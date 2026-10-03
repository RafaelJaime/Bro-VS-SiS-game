# Design: Combat Depth (shield meter, food that matters, sudden-death bombs, schema 3)

Mirror of Engram `sdd/combat-depth/design`. Inputs: `proposal.md` (including Resolved Decisions), `explore.md`, and the delta specs under `specs/` (fighter-shield, sudden-death-hazards, food-fight-items, match-flow, combat-hits, fighter-movement, cpu-opponent, gameplay-state-snapshot, ai-schema, rl-training-pipeline, hub-model-distribution).

## Technical Approach

The change is split into four slices that each leave the branch green:

- **S1** changes gameplay only. Shield, dizzy, air dodge, food, bombs and the CPU change, but the observation schema does not, so the bundled schema-2 model keeps loading and playing.
- **S2** adds schema 3 *alongside* schema 2 and moves training onto it. The playable version (`BvsSchema.CURRENT_VERSION`) stays 2.
- **S3** retrains the default model. Only if every acceptance gate passes does it flip `CURRENT_VERSION` to 3 in the same commit as the new bundled model.
- **S4** holds only the gated remote operations.

Five patterns carry the design:

1. **One hit pipeline.** Every damage source (punch, ledge attack, thrown food, bomb) builds a `Hit` value object and calls `Combat.resolve(hit, target)`. Resolution follows the spec order: invulnerable or intangible, then unblockable, then dizzy, then shielded, then normal. It returns an `Outcome` and emits `Fighter.hit_received(hit, outcome)`. Rewards, eval metrics and the CPU all consume that signal and never read observations.
2. **The shield is a fighter-owned meter, not a state.** `ShieldMeter` (a RefCounted) lives on the `Fighter` and is ticked once per physics frame by `Fighter._physics_process`, so regeneration runs in every state. `Protect` only reads and drains it. A break moves the FSM to a new `Dizzy` state. Air block becomes a new `AirDodge` state.
3. **Gameplay timers count physics ticks.** `CombatClock` converts the profile's seconds to integer ticks at a fixed 60 ticks per game second. Hit-stop changes `Engine.time_scale`, which scales `delta` but not the tick count. Training speedup raises `physics_ticks_per_second` together with `time_scale` (`addons/godot_rl_agents/sync.gd:64`), so one tick is always 1/60 s of game time. The shield regen delay, dizzy, air dodge, the sudden-death grace and escalation, and the training safety cap all count ticks.
4. **Sudden-death hazards are a Game-local child node.** It follows the `FoodSpawner` pattern: `Game` owns a `SuddenDeathHazards` node, bombs are Game children with Game-local positions, and in training the node creates no VFX or SFX.
5. **Schemas are registered by version and selected by the model.** `PolicyController` picks the schema module and decoder from the model's sidecar `schema_version`. `PlayerAIController` uses the training config's `schema_version`. The picker and `ModelManager` accept only `CURRENT_VERSION`. This lets S2 train on v3 while the game still plays the v2 bundled model, and it lets S3 fall back cleanly if the gates fail.

## Architecture Decisions

### D1: `Hit` value object plus `Combat.resolve` (single resolution path)

**Choice**: `game/combat/hit.gd` (`class_name Hit`) carries the following fields:
- `attacker`: null for hazards.
- `damage` and `knockback`.
- `shield_damage`: below 0 means "derive from damage".
- `unblockable`.
- `source`: one of `PUNCH`, `LEDGE`, `FOOD`, `BOMB`.
- `source_position`: a global position. It decides the knockback x direction.
- `food_name`.

`Combat.resolve(hit, target) -> Outcome` (`IGNORED`, `FULL`, `BLOCKED`, `BROKE`) is the only resolver. `Combat.apply_hit(attacker, target, damage, knockback)` stays as a thin wrapper that builds a `PUNCH` hit, so call sites and tests that use it keep compiling. `Hurt` takes the knockback direction from `pending_source_x` instead of `owner.enemy`, because bombs have no attacker.

**Alternatives considered**: adding parameters to `apply_hit` (already four positional arguments, and bombs need a source position and flags); a per-source resolver (it would duplicate the shield order the spec fixes).

**Rationale**: One place enforces the spec's resolution order for punches, food and bombs. The outcome signal is the single source for the new reward terms and the eval metrics (the "signals, not observations" rule of `rl-training-pipeline`).

### D2: Shield meter on the Fighter, ticked in physics ticks

**Choice**: `game/combat/shield_meter.gd` (`class_name ShieldMeter`, RefCounted). `Fighter._physics_process` calls `shield.tick(holding = state == "Protect", suspended = state == "Dizzy")` once per frame. When holding, it drains `max / break_ticks` per tick. Regeneration starts `regen_delay_ticks` after release, at `max / regen_ticks` per tick. While dizzy it neither drains nor regenerates. If the hold drain empties it, `tick()` returns true and the Fighter calls `break_shield(null)`. A blocked hit drains through `Protect.absorb(hit)`. The meter also tracks `held_ticks` (continuous hold length) for the reward penalty and the HUD.

**Alternatives considered**:
- Meter inside the `Protect` state: there would be no regeneration outside Protect, and `Protect` is re-entered every time.
- Node `Timer`s: they scale with `time_scale` and break the "physics ticks" requirement.
- A per-row global clock: it is not needed, and it would be a shared object across training rows.

**Rationale**: Regeneration must run in every state, and the Fighter already owns per-frame bookkeeping (`_tick_movement`). A RefCounted is cheap in 25 training rows and easy to unit-test with synthetic ticks.

### D3: Tunables in `FighterProfile` groups (the kit seam), not a new resource

**Choice**: New groups `Shield`, `Air dodge` and `Pickup` in `game/player/fighter_profile.gd`. `AttackProfile` gains `shield_damage := -1.0`. The CPU values go into `CpuDifficulty`. The food values go into `FoodCatalog` constants (the existing pattern for food data).

**Alternatives considered**: a separate `ShieldProfile` resource (one more `.tres` seam with no second consumer yet); keeping the `Protect` node exports (`block_damage_reduction`, and so on), which the per-character kit cannot swap.

**Rationale**: The profile is documented as the single place to tune fighter feel, and no state may hardcode values. The `Protect` exports (`block_duration`, `block_damage_reduction`, `block_knockback_reduction`) are removed. No scene overrides them (verified: no `block_` keys in any `.tscn`).

### D4: Shield break enters a `Dizzy` FSM state; blocked hits never start hitstun

**Choice**: `game/player/StateMachine/PlayerStateMachine/States/dizzy.gd` (`class_name Dizzy`):
- `available_actions` is empty, so intent is ignored.
- `_enter`: counts `dizzy_ticks` down, applies a small upward pop (`shield_break_pop_velocity`), plays the `hurt` animation (the existing hitstun visuals), shows `DizzyStars`, adds a sprite wobble, and plays the `shield_break` SFX.
- `_update`: applies gravity and ground friction. When the count reaches 0 it calls `exit_to_neutral()`.
- `_exit`: sets the meter to `shield_break_recovery * max` and hides the cue.
- A hit on a dizzy fighter follows the `FULL` path into `Hurt`, which ends dizzy through the normal transition (`_exit` still restores the meter).

When a blocked hit empties the meter, the target takes chip damage, gets no pushback, and goes straight to `Dizzy` (outcome `BROKE`). Blocked hits apply pushback velocity but never enter `Hurt`. That matches the existing `Protect.receive_blocked_damage` behavior, which keeps the post-hit invulnerability logic unchanged.

**Alternatives considered**: reusing `Hurt` with a long stun (it would grant post-hit invulnerability on exit, so the fighter would not be "fully punishable"); a flag on the Fighter with no state (every state would need to gate its input).

**Rationale**: The FSM already gates input through `available_actions`, so an empty list delivers the spec's "ignores input" for free. A named state shows up in the snapshot and in the v3 state one-hot.

### D5: Ground-only shield; air block becomes an `AirDodge` state with tick-counted intangibility

**Choice**:
- `Motion.ACTION_PRIORITY` gains `"air_dodge"`. In `player.tscn`, the Jump and Fall `available_actions` swap `"protect"` for `"air_dodge"`. Idle and Run keep `"protect"`. `_is_requested("air_dodge")` is `intent.block_pressed`.
- `Protect.can_enter()` requires the fighter to be on the floor, the meter above 0, and the fighter not dizzy. `Protect._update` exits to Fall when the fighter leaves the floor and to neutral on release. The old 1 s `block_duration` timer is removed, so the meter is the limit.
- `game/player/StateMachine/PlayerStateMachine/States/air_dodge.gd`:
  - `can_enter`: airborne, `owner.air_dodge_available`, and `owner.air_dodge_cooldown_left == 0`.
  - `_enter`: spends the allowance and starts the cooldown counter (`air_dodge_cooldown` ticks, counted by the Fighter).
  - The fighter is intangible for `air_dodge_invuln` ticks, then has `air_dodge_endlag` ticks of no actions, then goes to Fall (or Idle on landing).
  - Momentum: the x velocity is scaled by `air_dodge_drift`, and gravity is scaled by `air_dodge_gravity_scale`.
- `Fighter.is_intangible()` is true only during the window. `Combat.resolve` treats it like `is_invulnerable`.
- The cue is a translucent status tint (D11). The allowance resets in `Fighter.restore_air_actions()`, which landing, `Hurt`, `LedgeHang`, respawn and sudden death already call. `"AirDodge"` is added to `LEDGE_GRAB_STATES` and to `TURN_LOCKED_STATES`, and `"Dizzy"` is added to `TURN_LOCKED_STATES`.

**Alternatives considered**:
- Reusing `"protect"` in the air states and branching inside `Protect`: one state with two unrelated behaviors and no clean `can_enter`.
- `grant_invulnerability(seconds, false)`: it uses a time-scaled `Timer`, which violates the tick rule, and it would show in the snapshot as `is_invulnerable`, mixing dodge with the respawn and ledge grants.

**Rationale**: Each state has one responsibility. Intangibility counted in ticks satisfies `combat-hits` "Timers independent of time scale". Resetting through `restore_air_actions` reuses the one existing hook for "landing, ledge or hit".

### D6: Throw priority is a held-food priority list in `Motion`

**Choice**: There are two constant lists:
- `ACTION_PRIORITY = [recovery, dash, jump, punch, protect, air_dodge, shoot]`
- `ACTION_PRIORITY_HOLDING = [recovery, dash, jump, shoot, punch, protect, air_dodge]`

`handle_actions()` uses the second list while `owner.is_holding_food()`. Empty-handed priority (pickup included) is unchanged, as the spec's "No food, no change" requires.

**Alternatives considered**: a priority field on each `State` (it spreads one rule across nodes); fixing the conflict only in the v3 decoder (humans would still lose throws to "punch + throw", and the CPU and the v2 model would stay masked).

**Rationale**: This fixes all controllers at once, including the bundled v2 model in the S1 interim, with a change of about 10 lines.

### D7: Food rebalance and identity effects as catalog data

**Choice**:
- `FoodCatalog.WEIGHT_STATS` gains `shield_damage` and new values (table below).
- `FoodCatalog.TAGS` maps a food name to tags, and `TAG_EFFECTS` maps a tag to multipliers. There are exactly **two** effects:
  - `hot` (coffee, soup, stew): knockback ×1.25, a fire trail on the projectile, and a fire puff on impact.
  - `hard` (cheese, steak, grill): shield damage ×1.4, and the projectile spins.
- `FoodProjectile` builds a `FOOD` `Hit` from the catalog helpers (`get_hit_knockback`, `get_shield_damage`).
- The pickup area becomes a `RectangleShape2D`. Its size is `(2 * pickup_reach_x, pickup_reach_height)` and it is centered near the feet. `Fighter._ready` builds it per fighter from the profile, duplicating the shape as `Punch` does.
- `Shoot._try_pickup` takes the nearest overlapping food instead of the first.
- Spawner defaults: 1.8 to 3.0 s, `max_alive` 5.

**Alternatives considered**: a third effect such as "zippy" (light speed ×1.25) or "sticky"; extra item behaviors such as bounce or stun. Rejected to keep the scope to the spec minimum. Each tag only scales existing numbers and reuses existing art.

**Rationale**: It reverses "food ≈ punch" (explore cause 3) and the narrow reach (cause 4) with data only. One invariant protects the spec's "full shield survives one heavy hit": `max_tag_multiplier × heavy.shield_damage < shield_max` (1.4 × 55 = 77 < 100). The smoke test asserts it.

### D8: Sudden-death hazards node with an escalating, tick-scheduled spawner

**Choice**: `game/hazards/sudden_death_hazards.gd` (`class_name SuddenDeathHazards`, Node2D at the Game origin, added to `game.tscn` as `SuddenDeathHazards`) and `game/hazards/bomb.tscn` with `bomb.gd` (`class_name Bomb`, Area2D).

Lifecycle and schedule:
- `begin()` is called when sudden death is released and resets the counters. `stop_and_clear()` frees every bomb.
- `_physics_process` advances `elapsed_ticks` only while active.
- Grace lasts `grace_ticks` (1200, which is 20 s). After it, the n-th spawn waits `max(floor_ticks, round(start_ticks * decay^n))`, with `start_ticks` 120, `decay` 0.88 and `floor_ticks` 24. At most `max_alive` (6) bombs exist at once.

Spawn position:
- The spawn x is the current x of a target fighter (round-robin) ± a jitter of 60 px, with probability `target_chance` (0.6). Otherwise it is uniform over the stage. It is clamped to the stage.
- The spawn y is `stage.top - fall_height` (760 px).
- The fall is constant at `fall_speed` (420 px/s), so the telegraph lasts about 1.8 s, above the spec's tunable minimum (default 1.0 s). A shadow sprite sits at stage-top y under the bomb and grows as the bomb falls.

Explosion:
- A bomb explodes on its first contact with a fighter hurtbox (`area_entered`) or the floor (`body_entered` StaticBody2D). It is freed silently below the blast bottom.
- On explosion it checks each Game fighter once: hurtbox center within `explosion_radius` (90) plus the hurtbox half-extent. Each fighter hit gets `Combat.resolve` with `damage` 12, `knockback` (120, -560) and `unblockable = true`. The x direction points away from the bomb center, and away from the stage center when |dx| < 4.
- At 300%, `get_knockback_scale()` = 7, so the launch is (840, -3920). That passes the top blast zone in about 0.25 s. This is lethal and holds even through a shield.
- Respawn and dodge invulnerability are respected by `resolve` (spec).

Visuals and audio (existing assets only, CPU particles for the web):
- Body: `T_Gradient_circle22.jpg` tinted dark, with an additive `T_VFX_Glow_1.PNG` fuse glow and a `CPUParticles2D` spark trail using `T_LeLuStar11.jpg`.
- Explosion: a one-shot `CPUParticles2D` burst with `T_VFX_Glow_1.PNG` (additive, white to yellow to orange to transparent), plus a flash sprite scale tween.
- SFX: a `bomb` event on `fireball-explosion`.
- In training, the node spawns bombs with no visuals or SFX (`game.training`).

Training safety cap: in training only, when `elapsed_ticks >= training_cap_ticks` (3600) the node emits `training_cap_reached` once.

**Alternatives considered**:
- Bombs as `FoodProjectile` variants: the hit, telegraph and lifetime rules all differ.
- Timer-based scheduling: time-scaled.
- Purely random x: idle fighters might take minutes to get hit, failing "20/20 forced SD end" in bounded time.
- An `Area2D` overlap query for the explosion: it is reported a frame late, so its timing is nondeterministic.

**Rationale**: The proposal's Resolved Decision 1 says real matches have no cap, so the spawner itself must guarantee that a KO comes. A targeted share makes the KO quick (seconds after bombs start) for idle fighters and still dodgeable for active ones. The deterministic distance check plus one explosion per bomb gives "one hit per bomb per fighter". A per-node `RandomNumberGenerator` seeded from `GameRng.next_seed()` keeps tests reproducible.

### D9: Match flow: double KO restarts SD; training enters SD on a tie; safety cap only in training

**Choice** (`game/game.gd`):
- `_start_sudden_death()` calls `hazards.stop_and_clear()` and prepares the fighters. After the intro (`sudden_death_intro`, or `training_sd_intro` = 0 in training), `_release_sudden_death()` calls `hazards.begin()`.
- `_resolve_defeat()` already calls `_start_sudden_death()` on a simultaneous KO. In sudden death that now restarts the grace period and escalation (spec double-KO rule).
- `_end_match()` calls `hazards.stop_and_clear()`.
- Training changes:
  - On timer expiry with a tie and `training_sudden_death` set (default true, overridable from `BVS_TRAIN_CONFIG.match.sudden_death`), the row enters sudden death and sends no `done`.
  - `_resolve_training_defeat()` restarts sudden death on a double KO in sudden death.
  - `hazards.training_cap_reached` ends the episode as a draw with reason `&"sd_cap"`.
  - `_end_training_episode(winner, reason)` resets `phase = PLAYING`, clears the hazards, and records `last_episode_end_reason` before emitting the unchanged `training_episode_ended(winner)` signal.
  - `training_start_in_sudden_death` rows wait for both fighters' new `reset_done` signal, then call `force_sudden_death()`.
- `force_sudden_death()` is public, for tests and the harness.

**Alternatives considered**:
- Adding a `reason` parameter to `training_episode_ended`: the existing one-argument lambdas in `tests/smoke/train_loads.gd:177,212` and `RewardTracker` would fail at emit time.
- Starting sudden death in the same frame as the episode end: `Fighter.reset_player()` runs on the fighter's next frame and would overwrite 300% and 1 stock with 0% and 3 stocks.

**Rationale**: It is minimal and reuses the existing phase machine, with backward-compatible signals. The new `reason` field is how the spec's "truncated" flag reaches the logs. godot_rl's sync only carries `done`, so truncation is recorded in the `BVS_EPISODE` record (`"truncated": true`) and the draw gives no win, loss or timeout reward.

### D10: Shield HUD: bubble on the fighter plus a bar on the HUD card

**Choice**:
- `ShieldBubble` is a Sprite2D child in `player.tscn`. It reuses the existing `T_VFX_Glow_1.PNG` ext_resource with an additive material and is driven by `game/player/shield_bubble.gd`. It is visible only while the state is `Protect`. Its scale is `lerp(0.12, 0.30, ratio)`, and its color goes from the character color to red as the ratio drops.
- `DizzyStars` is a Node2D with three additive `T_LeLuStar11.jpg` sprites orbiting above the head, driven by `game/player/dizzy_stars.gd` and visible only in `Dizzy`.
- `FighterHud` (`player_ui.gd`) adds a 6 px shield bar (`StyleBoxFlat`, no assets) under the percent label, filled by `ratio` every `_process`. A red pulsing "BREAK!" label shows while the fighter is dizzy. Both stay idle at full meter.
- In training, the bubble, the stars and the bar are hidden with processing off.

**Alternatives considered**: only a HUD bar (players watch the fighter, not the corner); only a bubble (no readable value during play, and the spec allows either).

**Rationale**: It is Smash-faithful (the bubble), readable for spectators (the bar), and uses existing textures only. Neither element touches `animated_sprite_2d.visible`, which keeps the single-owner visibility rule in `Fighter._apply_visibility`.

### D11: Sprite tint has one owner (`status_tint`)

**Choice**: `Fighter.status_tint: Color` is set by `AirDodge` (translucent white) and `Dizzy` (a pale yellow flash). `set_charge_visual(-1)` restores `modulate` to `status_tint` instead of `Color.WHITE`. Charge writes `modulate` only while charging, and charging cannot overlap AirDodge or Dizzy.

**Alternatives considered**: each state writing `modulate` directly (a stale tint after an interrupted state, the same failure class that the single visibility owner already fixed for blinking).

**Rationale**: It follows the existing single-owner pattern.

### D12: CPU respects the shield and gains three plans, all driven by data

**Choice**: `CpuDifficulty` gains the fields below (preset defaults Easy / Normal / Hard):
- `shield_release_ratio`: 0.45 / 0.35 / 0.25, with 0.15 hysteresis.
- `punish_dizzy_chance`: 0.0 / 0.7 / 1.0.
- `food_pressure_chance`: 0.0 / 0.5 / 0.9.
- `turtle_time`: 1.5 s.
- `bomb_dodge`: false / false / true.
- `bomb_lookahead`: 0.9 s.
- `bomb_margin`: 40 px.

`ScriptedController`:
- The plan order becomes LEDGE, RECOVER, DODGE_BOMB (if `bomb_dodge`), PUNISH (the enemy is `Dizzy`, the roll succeeds, then approach and attack), DEFEND (only while the meter is above the release ratio), THROW, PICKUP, ATTACK, APPROACH.
- THROW uses `max(throw_chance, food_pressure_chance)` while the enemy is in `Protect`.
- PICKUP doubles `pickup_seek_distance` once the enemy has shielded for `turtle_time` and the pressure roll succeeds.
- `_fill_intent` drops `block_held` when the meter reaches the release ratio.
- `"Dizzy"` joins `NO_ACTION_STATES`.
- A block press is emitted when the state accepts `"protect"` or `"air_dodge"`, so an airborne CPU air-dodges threats.
- `_pickup_reach` reads `profile.pickup_reach_x * 0.8`.
- Easy keeps `use_directional = false`, so the PUNISH and DODGE_BOMB paths use the neutral aim and never press special.

**Alternatives considered**: a utility-scoring AI (a rewrite, outside the "fun against humans, not tuned against the model" goal); tuning the CPU against the model (explicitly out of scope).

**Rationale**: It extends the existing priority planner with data-only knobs. Difficulty ordering stays a property of the presets, which the smoke tests check.

### D13: Schema 3 alongside schema 2; the version flip is deferred to S3

**Choice**:
- `bvs_schema_v3.gd` and `bvs_action_decoder_v3.gd` are new, self-contained modules: the v2 code is copied and extended, and nothing calls into v2.
- The `BvsSchema` registry holds `{2: [BvsSchemaV2, BvsActionDecoderV2], 3: [BvsSchemaV3, BvsActionDecoderV3]}` and exposes `get_schema(v)`, `new_decoder(v)`, `current()` and `is_builtin(v)`.
- `validate_sidecar()` validates against `get_schema(CURRENT_VERSION)` instead of the hardcoded `BvsSchemaV2`. `unregister_test_stub` refuses built-in versions.
- **`CURRENT_VERSION` stays 2 through S2 and becomes 3 in the S3 commit that swaps the bundled model.** If the S3 gates fail, it stays 2: schema 3 remains registered and trainable, the v2 default keeps shipping, and the branch stays consistent.
- `PolicyController` resolves the schema and decoder from `model.schema_version()` (new `OnnxPolicyModel` accessor over the sidecar) and rejects unregistered versions. `PlayerAIController.schema_version` is set by `TrainArena` from `BVS_TRAIN_CONFIG.schema_version`, defaulting to `CURRENT_VERSION`. `TrainArena` snapshot rows validate against that version.
- `ModelManager` validates downloaded and bundled models with `BvsSchema.current()`.
- `HubModel` already compares the tag with `CURRENT_VERSION`, so the picker's "current playable schema" rule needs no code change, only test updates.

**Alternatives considered**:
- Bumping `CURRENT_VERSION` in S2 as the proposal sketched: the S2 commit would reject the still-bundled v2 model (`ModelManager` validation), so the branch would be broken until S3, and a gate failure would leave no consistent state.
- A shared base class for v2 and v3: it touches frozen v2.
- A v3 that delegates to v2 helpers: it couples the frozen code to the new code.

**Rationale**: Every commit stays green, the S3 fallback in `rl-training-pipeline` ("keep old bundled model") is a real state, and v2 remains byte-identical.

### D14: v3 observation layout (136 floats), v2 action nvec kept, exclusive throw decode

**Choice**:
- The layout and normalization are defined in the Interfaces section. The fighter block grows to 43:
  - two held-food tag flags (`hot`, `hard`);
  - shield ratio;
  - dizzy flag;
  - dizzy time left;
  - air-dodge availability;
  - a 16-slot state one-hot (adds `Dizzy` and `AirDodge`);
  - the `invulnerable` slot now means "cannot be hit" (invulnerable or intangible).
- Food slots gain the tag flags (stride 8).
- Two bomb slots are added (present, dx, dy, vx, vy, time to impact).
- Match slots: timer, sudden death, SD phase / 2, SD elapsed / 60.
- Absent slots are all zeros with `present = 0` (the v2 sentinel convention).
- The action nvec stays `[3,3,2,5,2,2,2,2]`. In the air, a6 block = 1 produces `block_pressed`, which the game resolves to an air dodge.
- The v3 decoder differs from v2 only in this: on the first frame of a window with `a5_throw = 1` **while holding food**, `throw_pressed = true` and `attack_pressed = false`. With no food held, throw decodes as in v2 (spec).

**Alternatives considered**:
- A dedicated pickup branch or new action sizes: it changes nvec, and the current export head and Python constants all assume eight branches. Not needed now that motion priority and the decoder fix the masking.
- Appending only the new features after v2's 102: the state one-hot and the food tags would then live far from their entity blocks, making the layout harder to audit.

**Rationale**: It covers every spec feature with bounded, Game-local, self-relative values and keeps the policy head and export unchanged.

### D15: Rewards from signals, a training SD curriculum, and a committed harness with gates

**Choice**:
- `RewardConfig.TERMS` adds `pickup` (0.05), `food_hit` (0.15), `shield_break_dealt` (0.4), `shield_break_taken` (-0.4) and `shield_hold` (-0.003 per decision past the threshold). New non-term `PARAMS` (`shield_hold_threshold` 1.5 s, `pickup_cap` 20 per episode) are accepted by `from_dict`.
- `RewardTracker` connects to:
  - `food_picked_up`: pickup term.
  - The foe's `hit_received` with `source == FOOD`, the attacker equal to me, and an outcome other than `IGNORED`: food_hit term.
  - `shield_broken(cause)`: dealt only when `cause.attacker == me`; taken always.
  - `shield.held_ticks`: read per decision.
  - Episode reason `sd_cap`: outcome `"draw"` with `"truncated": true`.
- `game/ai/training/match_metrics.gd` (`class_name MatchMetrics`) aggregates the same signals for `tests/smoke/policy_eval.gd` and the new `tests/smoke/combat_harness.gd`.
- Python:
  - `training/bvs_training/harness.py` runs the harness and applies the gates from `[acceptance]` in `training/configs/default.toml`.
  - `evaluate.py` renders the new metrics.
  - `train.py` writes `schema_version = 3`, the `match` block and `sd_start` rows into `BVS_TRAIN_CONFIG`.

**Alternatives considered**: rewards from observation deltas (forbidden by the spec); a Python-side metrics recomputation (GDScript is the source of truth, and the signals exist only in Godot); keeping the explore harness in the scratchpad (the spec requires it committed and repeatable).

**Rationale**: This removes explore cause 2 (no food reward), puts sudden death into training (observation 101 was always 0), and makes acceptance measurable and reproducible.

### D16: Remote gate stays print-only and per-destination

**Choice**: `prepare_upload.py` keeps the gate:
- It refuses to run without `--confirm-repo RafaelJaime/BVS-default`.
- It only *prints* the `hf upload` commands, with tags `BVS` and `bvs-schema-3`.
- A separate `--space` mode requires `--confirm-space RafaelJaime/BroVSister` and prints the Space deploy steps without running them.
- There is no auth probing and no network call in the tooling.

**Alternatives considered**: a script that uploads directly (forbidden without explicit authorization); one confirmation covering both destinations (the spec requires separate confirmation).

**Rationale**: It matches `rl-training-pipeline` "Remote operation authorization gate" and the session's remote-authorization contract.

## Data Flow

Hit resolution (all sources):

```
Punch / LedgeHang / FoodProjectile / Bomb
        │  Hit{damage, knockback, shield_damage, unblockable, source, source_position}
        ▼
Combat.resolve(hit, target) ─ invulnerable|intangible? ─► IGNORED
        │ unblockable or state != Protect (incl. Dizzy)
        ├──────────────► Hurt (pending dmg/kb/source_x) ─► FULL
        │ state == Protect
        └─► Protect.absorb(hit) ─► ShieldMeter.absorb ─► empty? ─► Fighter.break_shield ─► Dizzy ─► BROKE
                                              └─► chip + pushback ─► BLOCKED
        │
        ▼
target.hit_received(hit, outcome) ─► RewardTracker / MatchMetrics / (juice: hit-stop + Sfx unless training)
```

Per-frame tick order (parent first):

```
Fighter._physics_process
  intent = controller.sample()
  shield.tick(holding=Protect, suspended=Dizzy) ──► hold-drain empty ─► break_shield(null)
  air_dodge_cooldown_left -= 1
  _tick_movement / move_and_slide / ledge / blast zone
StateMachine._physics_process ─► current_state._update  (Dizzy/AirDodge count their own ticks)
```

Sudden death:

```
timer tie ─► Game._start_sudden_death ─► hazards.stop_and_clear, fighters 300%/1 stock
   └─(intro)─► _release_sudden_death ─► hazards.begin()
hazards._physics_process: elapsed_ticks++ ─► grace ─► spawn schedule (targeted/random) ─► Bomb
Bomb falls ─► hurtbox/floor contact ─► explode ─► Combat.resolve(unblockable) per fighter (once)
KO ─► _resolve_defeat ─► one alive: _end_match ; both: _start_sudden_death (restart)
training only: elapsed >= cap ─► training_cap_reached ─► _end_training_episode(null, &"sd_cap")
```

Schema selection:

```
play:     ModelManager (validate vs BvsSchema.current()) ─► PolicyController(model)
                  └─ schema = BvsSchema.get_schema(model.schema_version()); decoder = new_decoder(v)
training: TrainArena(BVS_TRAIN_CONFIG.schema_version) ─► PlayerAIController.schema_version
                  └─ get_obs / action_space / decoder via the same registry
picker:   HubModel.schema (bvs-schema-N tag) == CURRENT_VERSION ? Compatible : Older/Newer
```

## File Changes

Authored-line forecast per slice (generated fixtures and binaries excluded): S1 about 900, S2 about 650, S3 about 120, S4 about 40. Delivery is a single PR with `size:exception` (preflight `single-pr`), one or more work-unit commits per slice.

### S1: gameplay (no schema change)

| File | Action | Description |
|------|--------|-------------|
| `game/combat/combat_clock.gd` | Create | `TICKS_PER_SECOND = 60`, `ticks(seconds)`, `seconds(ticks)` |
| `game/combat/hit.gd` | Create | `Hit` value object (D1), factories `punch()`, `food()`, `bomb()` |
| `game/combat/shield_meter.gd` | Create | `ShieldMeter` (D2) |
| `game/combat/combat.gd` | Modify | `Outcome` enum, `resolve(hit, target)`, `apply_hit` wrapper, juice per outcome (break uses a longer hit-stop), `hit_received` emit |
| `game/combat/attack_profile.gd` | Modify | `shield_damage := -1.0` (+ `make()` optional argument) |
| `game/player/fighter_profile.gd` | Modify | `Shield`, `Air dodge` and `Pickup` groups (tuning table) |
| `game/player/player.gd` | Modify | `shield`, signals (`hit_received`, `shield_broken`, `food_picked_up`, `food_thrown`, `reset_done`), `air_dodge_available` + cooldown, `break_shield`, `is_dizzy`, `is_intangible`, `status_tint`, pickup shape build, snapshot keys, refill on respawn/reset/sudden death (refill **after** the state change so `Dizzy._exit` cannot overwrite it), `TURN_LOCKED_STATES`/`LEDGE_GRAB_STATES` additions |
| `game/player/StateMachine/PlayerStateMachine/States/motion.gd` | Modify | `air_dodge` action, `ACTION_PRIORITY_HOLDING` (D6) |
| `game/player/StateMachine/PlayerStateMachine/States/protect.gd` | Modify | Ground-only `can_enter`, no timer, `absorb(hit) -> bool` replaces `receive_blocked_damage` |
| `game/player/StateMachine/PlayerStateMachine/States/dizzy.gd` | Create | `Dizzy` state (D4) |
| `game/player/StateMachine/PlayerStateMachine/States/air_dodge.gd` | Create | `AirDodge` state (D5) |
| `game/player/StateMachine/PlayerStateMachine/States/hurt.gd` | Modify | `pending_source_x` direction (falls back to `owner.enemy` when unset) |
| `game/player/StateMachine/PlayerStateMachine/States/punch.gd` | Modify | Builds a `PUNCH` hit with `_attack.shield_damage` (scaled by the charge damage multiplier when ≥ 0) |
| `game/player/StateMachine/PlayerStateMachine/States/ledge_hang.gd` | Modify | Climb attack resolves a `LEDGE` hit |
| `game/player/StateMachine/PlayerStateMachine/States/shoot.gd` | Modify | Nearest-food pickup; emit `food_thrown` |
| `game/player/player.tscn` | Modify | `Dizzy`, `AirDodge` nodes; Jump/Fall `available_actions` `protect` → `air_dodge`; `PickupArea` rectangle shape; `ShieldBubble`, `DizzyStars` nodes |
| `game/player/shield_bubble.gd` | Create | Bubble driver (D10) |
| `game/player/dizzy_stars.gd` | Create | Star orbit + wobble cue (D10) |
| `game/player/player_ui.gd` | Modify | Shield bar + "BREAK!" label |
| `game/food/food_catalog.gd` | Modify | New stats, `shield_damage`, `TAGS`, `TAG_EFFECTS`, helpers (D7) |
| `game/food/food_projectile.gd` | Modify | Builds a `FOOD` hit; `hot` trail/impact puff (CPUParticles2D, `T_VFX_Glow_1`), `hard` spin; no VFX in training |
| `game/food/food_spawner.gd` | Modify | Defaults 1.8–3.0 s, `max_alive` 5 |
| `game/hazards/sudden_death_hazards.gd` | Create | Spawner, schedule, cap signal, snapshot list (D8) |
| `game/hazards/bomb.gd`, `game/hazards/bomb.tscn` | Create | Bomb (fall, shadow, explosion, CPU particles) |
| `game/game.gd` | Modify | Hazards wiring, double-KO restart in SD, training SD + cap + reason, `force_sudden_death`, `reset_done` wait, snapshot keys (D9) |
| `game/game.tscn` | Modify | `SuddenDeathHazards` node (bomb scene export) |
| `game/audio/sfx.gd` | Modify | `bomb` [EXPLOSION 0.78–0.90], `shield_break` [EXPLOSION 1.20–1.32] (no overlap with `ko` 0.60–0.72 or `heavy_hit` 0.96–1.10) |
| `game/player/controllers/cpu_difficulty.gd` | Modify | New fields + presets (D12) |
| `game/player/controllers/scripted_controller.gd` | Modify | Release threshold, PUNISH, DODGE_BOMB, pressure THROW/PICKUP, air-dodge acceptance, `Dizzy` lock, reach from profile |
| `tests/smoke/shield.gd` | Create | Meter drain/regen/break timing in ticks, chip, override, unblockable, dizzy input lock/punish/timeout, respawn refill, hit-stop independence, air dodge window/once/reset, no air shield, snapshot keys |
| `tests/smoke/hazards.gd` | Create | Grace, start, monotonic interval + floor, cap, telegraph time, unblockable, lethal 300%, one hit per bomb, respawn invulnerability, two Games / offset invariance, cleanup, 20 forced idle SD end in KO, turtle KO, double-KO restart, real match no cap (bomb damage zeroed via test hook) |
| `tests/smoke/food_balance.gd` | Create | Beats punch, shield damage ordering + heavy break + full-survives with tag multiplier invariant, reach 100/40/out, throw priority (5 spec scenarios), spawner faster + cap, hot/hard effects |
| `tests/smoke/cpu_shield.gd` | Create | Release threshold, 20 s no self-break, punish rates (E ≤ N ≤ H), pressure throw, fetch vs turtle, Hard bomb dodge + survival vs Easy, Easy no aim/special, taps only, ordering |
| `tests/smoke/hit_rules.gd` | Modify | "air block enters Protect" → air dodge assertions |
| `tests/smoke/keyboard_playtest.gd` | Modify | "block halves damage" → chip fraction + meter drain |
| `tests/smoke/match_flow.gd`, `tests/smoke/hud.gd`, `tests/smoke/cpu_combat.gd` | Modify | SD escalation hook, shield bar presence, CPU still blocks within the meter |

### S2: schema 3 and training (CURRENT_VERSION stays 2)

| File | Action | Description |
|------|--------|-------------|
| `game/ai/schema/bvs_schema_v3.gd` | Create | Layout, keys, `build_obs`, `validate_snapshot`, action helpers, `sidecar_template` (version 3) |
| `game/ai/schema/bvs_action_decoder_v3.gd` | Create | v2 rules + exclusive throw while holding food |
| `game/ai/schema/bvs_schema.gd` | Modify | Version → [schema, decoder] registry, `new_decoder`, `current`, `is_builtin`, generic `validate_sidecar`, built-in-safe stub removal |
| `game/ai/onnx/onnx_policy_model.gd` | Modify | `schema_version()` from the sidecar (default `CURRENT_VERSION`) |
| `game/player/controllers/policy_controller.gd` | Modify | Schema/decoder from the model or the training agent; no hardcoded V2 |
| `game/ai/player_ai_controller.gd` | Modify | `schema_version` field; obs/action space/action parsing via the registry |
| `game/ai/training/train_arena.gd` | Modify | Reads `schema_version`, `match` (`sudden_death`, `sd_safety_cap`), row `start: "sudden_death"`; snapshot validation vs the training schema |
| `game/ai/training/reward_config.gd` | Modify | New terms + `PARAMS` (D15) |
| `game/ai/training/reward_tracker.gd` | Modify | Signal-driven terms, `sd_cap` draw + `truncated` in `BVS_EPISODE` |
| `game/ai/training/match_metrics.gd` | Create | Shared metrics aggregator |
| `autoload/model_manager.gd` | Modify | Validate with `BvsSchema.current()` instead of `BvsSchemaV2` (lines 479/504) |
| `tests/fixtures/schema/v3_layout.json`, `v3_obs_golden.json` | Create (generated) | v3 freeze + recorded snapshot cases (shield, dizzy, 0/1/3 bombs, P2 view) |
| `tests/tools/gen_schema_v3_fixtures.gd` | Create | One-off generator for the two fixtures |
| `tests/smoke/schema_v3.gd` | Create | Dimension, bounds/finite (999%, far off-stage, many bombs), sentinels, nearest-bomb order, offset invariance, read-only, training == inference, decode (exclusive throw, pulse once, invalid vectors), missing-key errors, registry (2 and 3, stub v4, 99 unsupported), fixture parity |
| `tests/smoke/combat_harness.gd` | Create | Env-driven harness: matchups `mvm`, `m_vs_cpu_<lvl>`, `cpu_<lvl>_vs_cpu_<lvl>`, `force_sd`, seed, JSON out |
| `tests/smoke/policy_eval.gd` | Modify | Adds `MatchMetrics` fields to its JSON |
| `tests/smoke/train_loads.gd` | Modify | Tie → SD (no `done` at expiry), SD cap draw, `schema_version` 3 rows, SD-start row |
| `training/bvs_training/schema.py` | Modify | Versioned constants (`SCHEMAS[2]`, `SCHEMAS[3]`), `TRAIN_VERSION = 3`, v3 layout fixture check |
| `training/bvs_training/train.py`, `handshake.py` | Modify | Writes `schema_version`, `match`, SD rows; checks the v3 env |
| `training/bvs_training/export.py`, `sidecar.py`, `golden.py` | Modify | v3 obs_dim/sidecar/tags `bvs-schema-3`; golden checks the v3 fixture length/order |
| `training/bvs_training/evaluate.py` | Modify | Combat-depth metrics table |
| `training/bvs_training/harness.py` | Create | Runs the harness (list-form subprocess), renders `reports/<name>-harness.{json,md}`, applies the gates, exits non-zero on failure |
| `training/configs/default.toml` | Modify | `[match]`, `[acceptance]`, reward keys, `sd_start` share in P2/P3 |
| `training/README.md` | Modify | Schema 3 contract, tags, SD episodes, harness |

### S3: retrain, gate, flip (only if all gates pass)

| File | Action | Description |
|------|--------|-------------|
| `game/ai/models/bvs_default/model.onnx`, `bvs.json` | Replace | Retrained v3 model + sidecar |
| `game/ai/schema/bvs_schema.gd` | Modify | `CURRENT_VERSION := 3` |
| `tests/fixtures/onnx/bvs_default_golden.json` | Regenerate | Default-model parity for the v3 model (it is a default-model fixture, regenerated on every retrain) |
| `tests/smoke/onnx_golden.gd`, `policy_match.gd`, `cpu_select.gd`, `hf_picker.gd` | Modify | Bundled/current-model assertions use `BvsSchema.current()`; picker expects schema 2 = "Trained for an older version" |
| `tests/smoke/schema_v2.gd` | Modify (one function) | `_check_registry` (asserts current == 2 and registers a v3 stub) moves to `schema_v3.gd`; the frozen-v2 checks stay untouched (see Open Questions) |
| `training/reports/bvs_default-eval.md/.json`, `bvs_default-harness.md/.json` | Create | Committed evidence |

If any gate fails, S3 commits only the reports (marked FAIL) and keeps `CURRENT_VERSION = 2` and the v2 bundled model.

### S4: gated remote (no code beyond the card)

| File | Action | Description |
|------|--------|-------------|
| `training/bvs_training/prepare_upload.py` | Modify | `--confirm-repo` (existing) + `--space --confirm-space`, print-only, tags `BVS`/`bvs-schema-3` |
| Model card (generated by `sidecar.py`) | Modify | Schema 3 contract, harness results |

## Interfaces / Contracts

```gdscript
# game/combat/combat_clock.gd
class_name CombatClock
const TICKS_PER_SECOND := 60   # game ticks per game second (training speedup keeps this)
static func ticks(seconds: float) -> int        # maxi(0, roundi(seconds * 60))
static func seconds(tick_count: int) -> float

# game/combat/hit.gd
class_name Hit extends RefCounted
enum Source { PUNCH, LEDGE, FOOD, BOMB }
var attacker: Fighter            # null for hazards
var damage: float
var knockback: Vector2           # base, before damage-% scaling
var shield_damage: float = -1.0  # < 0: damage * profile.shield_damage_scale
var unblockable: bool = false
var source: Source = Source.PUNCH
var source_position: Vector2     # global; knockback x points away from it
var food_name: String = ""
static func punch(attacker: Fighter, damage: float, knockback: Vector2, shield_damage := -1.0, source := Source.PUNCH) -> Hit
static func food(attacker: Fighter, food_name: String, at: Vector2) -> Hit   # reads FoodCatalog helpers
static func bomb(at: Vector2, damage: float, knockback: Vector2) -> Hit      # unblockable

# game/combat/combat.gd
enum Outcome { IGNORED, FULL, BLOCKED, BROKE }
static func resolve(hit: Hit, target: Fighter) -> Outcome
static func apply_hit(attacker: Fighter, target: Fighter, damage: float, knockback_base: Vector2) -> void  # wrapper

# game/combat/shield_meter.gd
class_name ShieldMeter extends RefCounted
var value: float
var max_value: float
var held_ticks: int              # continuous hold length, 0 when released
func setup(profile: FighterProfile) -> void
func tick(holding: bool, suspended: bool) -> bool   # true when the hold drain emptied it this tick
func absorb(amount: float) -> bool                 # true when emptied; restarts the regen delay
func refill() -> void
func set_ratio(ratio: float) -> void
func ratio() -> float
func is_empty() -> bool

# game/player/player.gd (additions)
signal hit_received(hit: Hit, outcome: int)
signal shield_broken(cause: Hit)          # cause null when the hold drain broke it
signal food_picked_up(food_name: String)
signal food_thrown(food_name: String)
signal reset_done
var shield: ShieldMeter
var air_dodge_available: bool = true
var air_dodge_cooldown_left: int = 0       # ticks
var status_tint: Color = Color.WHITE
func break_shield(cause: Hit) -> void      # -> Dizzy, emits shield_broken, Sfx shield_break
func is_dizzy() -> bool
func is_intangible() -> bool               # AirDodge invulnerability window
func dizzy_seconds_left() -> float
# Snapshot keys added (fighter): shield, shield_max, dizzy, dizzy_left (s), air_dodge_available, intangible

# game/game.gd (additions)
var last_episode_end_reason: StringName    # &"ko", &"timeout", &"sd_cap"
func force_sudden_death() -> void
# Snapshot keys added (game): sudden_death_phase (0 none, 1 grace, 2 bombs), sudden_death_elapsed (s),
#   bombs: [{position: Vector2 (Game-local), velocity: Vector2, radius: float}]

# game/hazards/sudden_death_hazards.gd
class_name SuddenDeathHazards extends Node2D
signal training_cap_reached
@export var bomb_scene: PackedScene
@export var grace_time := 20.0
@export var start_interval := 2.0
@export var interval_decay := 0.88
@export var min_interval := 0.4
@export var max_alive := 6
@export var target_chance := 0.6
@export var target_jitter := 60.0
@export var fall_height := 760.0
@export var fall_speed := 420.0
@export var min_telegraph := 1.0
@export var explosion_radius := 90.0
@export var bomb_damage := 12.0
@export var bomb_knockback := Vector2(120.0, -560.0)
@export var training_cap := 60.0
var elapsed_ticks: int
func begin() -> void
func stop_and_clear() -> void
func phase() -> int                         # 0, 1, 2
func snapshot_bombs() -> Array

# game/ai/schema/bvs_schema.gd
const CURRENT_VERSION := 2                  # 3 in S3, together with the bundled model
static func get_schema(version: int) -> Object
static func new_decoder(version: int) -> RefCounted   # null if unsupported
static func current() -> Object
static func is_builtin(version: int) -> bool          # 2 and 3
static func validate_sidecar(sidecar: Dictionary) -> String   # vs get_schema(CURRENT_VERSION)
```

### Tuning defaults (all data)

| Owner | Key | Default | Note |
|------|-----|---------|------|
| FighterProfile/Shield | `shield_max` | 100 | |
| | `shield_break_time` | 5.0 s | hold drain = 20/s (spec ~5 s) |
| | `shield_regen_delay` | 0.5 s | 30 ticks |
| | `shield_regen_time` | 6.0 s | empty → full |
| | `shield_damage_scale` | 1.5 | 8-damage punch = 12 shield damage |
| | `shield_chip_fraction` | 0.25 | was 0.5 |
| | `shield_knockback_fraction` | 0.3 | still multiplied by the damage-% scale (as today) |
| | `shield_break_recovery` | 0.5 | meter ratio after dizzy |
| | `dizzy_duration` | 2.0 s | 120 ticks |
| | `shield_break_pop_velocity` | -450 | |
| FighterProfile/Air dodge | `air_dodge_invuln` | 0.3 s | |
| | `air_dodge_endlag` | 0.15 s | |
| | `air_dodge_cooldown` | 0.6 s | from dodge start |
| | `air_dodge_drift` | 0.5 | x velocity multiplier |
| | `air_dodge_gravity_scale` | 0.5 | |
| FighterProfile/Pickup | `pickup_reach_x` | 105 px | half-width (was ±26..70) |
| | `pickup_reach_height` | 100 px | bottom at the feet |
| FoodCatalog LIGHT | damage / kb / speed / shield | 9 / (240,-110) / 560 / 20 | punch 8 / (220,-120) |
| FoodCatalog MEDIUM | | 13 / (290,-150) / 420 / 35 | |
| FoodCatalog HEAVY | | 18 / (360,-190) / 300 / 55 | 100 → 45 → break on the 2nd |
| FoodCatalog tags | `hot` | kb ×1.25 | coffee, soup, stew |
| | `hard` | shield ×1.4 | cheese, steak, grill (77 < 100) |
| FoodSpawner | interval / cap | 1.8–3.0 s / 5 | was 3–5 s / 4 |
| CpuDifficulty E/N/H | `shield_release_ratio` | 0.45 / 0.35 / 0.25 | |
| | `punish_dizzy_chance` | 0.0 / 0.7 / 1.0 | |
| | `food_pressure_chance` | 0.0 / 0.5 / 0.9 | |
| | `bomb_dodge` | no / no / yes | lookahead 0.9 s, margin 40 px |
| RewardConfig | pickup / food_hit / break dealt / break taken / shield_hold | 0.05 / 0.15 / 0.4 / -0.4 / -0.003 | threshold 1.5 s, pickup cap 20 |
| Game (training) | `training_sudden_death` / intro / cap | true / 0 s / 60 s | |

### bvs-schema-3 observation (OBS_DIM = 136)

Normalization constants are copied from v2: x and y over the stage half-width (HW), vx / 600, vy / 1300, clip ±5.

| Range | Content |
|-------|---------|
| [0, 43) | **me**: pos x/y, vel x/y, facing, on_floor, damage/100 [0,5], stocks/3, holding, weight one-hot (3), held_hot, held_hard, punch cd [0,1], shoot cd/2, jumps/2, air dash, recovery, cannot-be-hit (invulnerable or intangible), ledge side, fast falling, charge, shield ratio [0,1], dizzy, dizzy_left/2 [0,1], air_dodge_available, state one-hot 16 (`Idle, Run, Jump, Fall, Punch, Hurt, Protect, Shoot, Dash, Helpless, LedgeHang, Recovery, Defeated, Dizzy, AirDodge`, other) |
| [43, 86) | **opponent**: the same 43 |
| [86, 92) | rel dx, rel dy, opp in front, me off stage, ledge left occupied, ledge right occupied |
| [92, 108) | 2 nearest foods × 8: present, dx, dy, light, medium, heavy, hot, hard |
| [108, 120) | 2 nearest projectiles × 6: present, dx, dy, vx, vy, mine |
| [120, 132) | 2 nearest bombs × 6: present, dx, dy, vx, vy, time-to-impact/2 [0,1] (1 when not descending) |
| 132–135 | timer/99 [0,1], sudden death, SD phase/2 {0, 0.5, 1}, SD elapsed/60 [0,1] |

An absent slot is all zeros (`present = 0`). The action space is `[3,3,2,5,2,2,2,2]`, 21 logits, `ACTION_REPEAT` 4, format `bvs-model/1`, `schema_version` 3.

Required snapshot keys for v3 are the v2 keys plus:
- fighter: `shield`, `shield_max`, `dizzy`, `dizzy_left`, `air_dodge_available`, `intangible`;
- game: `sudden_death_phase`, `sudden_death_elapsed`, `bombs` (entries need `position` and `velocity`).

A missing key returns an error naming it and an all-zero vector, as in v2.

### Harness and acceptance contract

`combat_harness.gd` takes `BVS_HARNESS_MODEL`, `BVS_HARNESS_MATCHUPS` (comma list), `BVS_HARNESS_MATCHES`, `BVS_HARNESS_SEED`, `BVS_HARNESS_FORCE_SD` and `BVS_HARNESS_OUT`. Its JSON carries, per matchup:
- `matches`, `ko_results`, `mean_sd_seconds`, `max_sd_seconds`;
- `pickups_per_fighter_minute`, `throws_per_fighter_minute`;
- `blocked_share` (BLOCKED+BROKE over FULL+BLOCKED+BROKE, bombs excluded);
- `damage_by_source`, `shield_breaks`.

`harness.py` gates come from `[acceptance]`: `max_mean_sd_seconds = 45`, `min_pickups_per_fighter_minute = 1.0`, `max_blocked_share = 0.70`, `min_ko_win_rate_easy = 0.60`, `min_matches = 20`. Repeatability: with the same seed and build, the metrics match exactly. The documented tolerance is ±5% on rate metrics, to absorb engine-version physics drift.

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit (GDScript smoke, synthetic) | `ShieldMeter` drain/regen/delay/clamp in ticks; `Hit` factories; food stats/tag invariant; v3 `build_obs` layout, bounds, sentinels, ordering; v3 decoder edges; registry (2, 3, stub v4, 99) | `tests/smoke/shield.gd`, `food_balance.gd`, `schema_v3.gd` over synthetic profiles/snapshot dictionaries |
| Integration (real `game.tscn`) | Resolution order per source; dizzy punish/timeout; air dodge window and resets; pickup reach; throw priority; hazards schedule, lethality, cleanup, offsets; double-KO restart; training tie → SD and cap; CPU plans | `shield.gd`, `hazards.gd`, `food_balance.gd`, `cpu_shield.gd`, `train_loads.gd`, using `smoke_util` scripted intents and `force_sudden_death()` |
| Time-scale independence | Dizzy/regen/first-bomb tick counts with `Engine.time_scale = 0.3` forced for a stretch vs 1.0 | Same assertions in both runs, counting `Engine.get_physics_frames()` deltas |
| Regression | Existing suite (`hit_rules`, `combat`, `match_flow` SFX band audit, `cpu_*`, `hud`, `keyboard_playtest`, `match_e2e`, `schema_v2`, `onnx_golden`, `policy_match`) | Updated only where behavior intentionally changed (listed in File Changes) |
| Parity | v3 obs fixture rebuild ≤ 1e-6; v3 default-model ONNX golden ≤ 1e-4 with exact argmax | `schema_v3.gd`, `onnx_golden.gd`, `golden.py` |
| E2E / acceptance | Model vs Easy/Normal (≥ 20), harness matchups, forced SD | `evaluate.py`, `harness.py` (S3 gates) |

Strict TDD is not configured (`openspec/config.yaml` `strict_tdd: false`, no runner). The user's global rule forbids running test suites locally unless explicitly asked. Execution authority for Godot smoke runs belongs to the apply and verify phases.

## Threat Matrix

| Boundary | Applicability | Design response | Planned RED tests |
|---|---|---|---|
| Documentation-like paths | N/A: no executable classification of files is added | — | — |
| Git repository selection | N/A: no git automation is added | — | — |
| Commit state | N/A: no tooling commits | — | — |
| Push state | N/A: no tooling pushes | — | — |
| PR commands | N/A: no PR automation | — | — |

Process note, outside the matrix: `harness.py` launches Godot the same way `evaluate.py` already does. It uses a list-form `subprocess.run` with no shell, fixed flags, and inputs only through environment variables. Remote operations stay print-only behind per-destination confirmation (D16).

## Migration / Rollout

- **Interim S1 state**: the bundled v2 model still loads and plays. It sees `Dizzy` and `AirDodge` as "other" states, and its throws now execute (motion priority). This is accepted: the interim exists only on the branch.
- **S2**: no player-visible schema change. `CURRENT_VERSION` stays 2, and training targets v3 through `BVS_TRAIN_CONFIG.schema_version = 3`.
- **S3 flip** (single commit): new model + `bvs.json` + default golden + `CURRENT_VERSION = 3` + migration of the current-version test assertions. On gate failure there is no flip, and the reports are committed as FAIL.
- **Hub**: after the flip, `bvs-schema-2` models show "Trained for an older version" (expected, in scope). The previous HF revision stays in the repo history (user-reversible).
- **Rollback**: revert S3 to return to the v2 model and schema 2 on top of S1 and S2. Revert S1 to restore the unlimited shield, the old food values and the SD without hazards.

## Open Questions

- [ ] **Spec conflict (needs an orchestrator decision before tasks):** `ai-schema` "Schema 2 frozen" and `rl-training-pipeline` "v2 tests green... pass unedited" cannot both hold after the flip.
  - `tests/smoke/schema_v2.gd::_check_registry` asserts `CURRENT_VERSION == 2` (line 312), validates the v2 template as current (line 317, plus "provides 102" at line 326), and registers a test stub *as version 3* (lines 346–351), which collides with the real v3.
  - `onnx_golden.gd`, `policy_match.gd`, `cpu_select.gd`, `hf_picker.gd` and `train_loads.gd` validate the *bundled* model against `BvsSchemaV2`.
  - Proposed amendment: the v2 module, decoder and fixtures (`v2_layout.json`, `v2_obs_golden.json`, the op fixtures) stay byte-identical. Only assertions about the *current* version or the *bundled* model move to `BvsSchema.current()` or `schema_v3.gd`. `bvs_default_golden.json` is classified as a default-model fixture (regenerated on every retrain), not a v2 fixture.
- [ ] Confirm that deferring the `CURRENT_VERSION` bump from S2 (proposal) to S3 (D13) is acceptable. It keeps every commit green and makes the gate-failure fallback consistent.
- [ ] Confirm that two identity effects (`hot`, `hard`) are enough. The spec allows 2–3.
