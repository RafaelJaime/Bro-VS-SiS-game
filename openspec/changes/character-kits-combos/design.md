# Design: Character Kits and Combos (jab chains, frame data, combo safeguards, schema 4)

Mirror of Engram `sdd/character-kits-combos/design`. Inputs: `proposal.md` (authoritative, including the Resolved Decision), `explore.md`, `odd/tasks/shield-spam.md` (T4 merged here), the main specs under `openspec/specs/`, and the archived `combat-depth` design (schema, training and harness patterns D13-D16).

## Technical Approach

The change follows the proposal's Direction B in seven slices. Each slice leaves the branch green, and the existing smoke suite keeps running on the baseline `FighterProfile`.

1. **S1: timing on physics ticks.** `Punch` and `Hurt` drop their `Timer` nodes and count `CombatClock` ticks. The punch cooldown moves onto the `Fighter` as a tick counter, ticked in `_tick_combat`, so it keeps running after `Punch` exits. A per-fighter **attack buffer** records presses in actionable states and in `Punch`, and `Motion.handle_actions` reads it the same way it already reads the jump buffer. With the baseline profile, frame data comes from the legacy fields, so the timing matches today's within one tick.
2. **S2: frame data and jab chains.** `AttackProfile` gains frame data in ticks (startup, active, endlag, link window, hitstun base and growth, cooldown, hit-stop scale). A value of `-1` means "derive from the legacy profile fields". `FighterProfile` gains `jab_chain`, `air_jab_chain` and `neutral_single`. `Punch` runs a small chain state machine: a neutral press during a step queues the next step, which fires when the link window opens, and the finisher's data launches. `Hit` carries its `AttackProfile` and its hit-stop scale.
3. **S3: victim-side combo tracking and safeguards.** A new `ComboTracker` (RefCounted, owned by the victim `Fighter`, ticked like `ShieldMeter`) counts the hits that land while the victim is in `Hurt`. It returns a scaling record (knockback growth, hitstun decay, time-cap clamp, hard-cap launch plus invulnerability) that `Hurt._enter` applies. The victim emits `combo_updated` and `combo_ended`. The attacker's `FighterHud`, `MatchMetrics` and `RewardTracker` consume those signals. All numbers live in one `ComboRules` resource.
4. **S4: kits as data.** `rafael_profile.tres` and `matilde_profile.tres` live in `game/player/profiles/` and are resolved by a static `FighterKits` registry from `CharacterUI.name`. `Fighter` resolves its kit in `_enter_tree` (scene characters) and in the `character_ui` setter (`SceneManager.play_game`), through a new `set_profile()` that re-initializes the profile-derived state. The Matilde up-launcher into air jab is prototyped first with a probe. The CPU chains through an event-driven hook on the opponent's `hit_received`.
5. **S5: schema 4 next to schema 3.** `bvs_schema_v4.gd` is v3 plus 13 appended floats (149). `bvs_action_decoder_v4.gd` decodes exactly like v3. The registry gains version 4, but `CURRENT_VERSION` **stays 3 until S6** (combat-depth D13 precedent). This slice also adds the snapshot keys, kit randomization in `TrainArena`, the capped `combo_hit` reward and the `shield_raise` lever, the new `MatchMetrics` and harness fields and gates, the v4 fixtures, and the Python v4 constants. It ends with the **shield-raise baseline measurement**, which fixes the gate threshold before any retrain.
6. **S6: retrain, gates, flip.** Time-boxed retrain. Promotion and the `CURRENT_VERSION = 4` flip happen in one commit, together with the model, `bvs.json`, the default golden, the reports and `training/reports/bvs_default-replay.mp4`, and only when every gate passes. A gate failure follows the Resolved Decision.
7. **S7: gated remote.** The model card is updated, and `prepare_upload.py` stays print-only, with a separate confirmation for each destination.

## Architecture Decisions

### D1: Tick counters replace `Timer` nodes in `Punch` and `Hurt`; the cooldown moves to the `Fighter`

**Choice**:
- `Punch` counts `_tick` (ticks since the current step fired) and ends the swing at `startup + active + endlag`.
- `Hurt` counts `_ticks_left`, set from the computed hitstun, and calls `_on_hurt_finished()` when it reaches 0.
- The "next attack allowed" lockout becomes `Fighter.attack_cooldown_ticks`, decremented in `_tick_combat`, so it keeps running in `Idle`.
- `Punch.can_enter()` checks `attack_cooldown_ticks <= 0` (plus the existing air rule).
- `Fighter._cooldown_left("Punch")` asks the state through `cooldown_left()` when it has one. `Shoot` keeps its `Timer` and the current path.
- The snapshot's `cooldowns.punch` keeps its meaning (seconds until a punch can start). It is now `CombatClock.seconds(max(attack_cooldown_ticks, swing ticks left))`, so the frozen v3 feature `self_cd_punch` stays valid.

**Alternatives considered**:
- Keeping the `Timer` nodes and only adding frame data. Idle-process timers jitter by about one frame against physics ticks on a real display, and Timer time stretches under hit-stop, so 2-4 tick links would drift.
- Keeping the cooldown as a counter inside `Punch`. States only update while they are current, so it would freeze in `Idle`.

**Rationale**: This follows the repo convention (`CombatClock`, `ShieldDrop`, `Dizzy`). Hit-stop changes `Engine.time_scale`, not the tick count, so attacker and victim advance by the same number of ticks during a hit-stop, and frame advantage is unaffected. Training has no hit-stop.

**Legacy derivation (baseline profile, behavior-preserving)**:
- `D = ticks(punch_duration) = 18`.
- `startup = ceil(D * punch_active_start) - 1 = 3`.
- `active = ceil(D * punch_active_end) - ceil(D * punch_active_start) = 9`, so active ticks are 4..12, as `_elapsed` produces today.
- `endlag = D - startup - active = 6`.
- `cooldown = ticks(punch_cooldown) = 42` from the press.
- Hitstun is `ticks(clamp(base + |kb| * per_kb, min, max))`.

The node overrides (`punch_duration`, `punch_cooldown`, `hurt_duration`) keep working. Exact-frame expectations can shift by at most one tick, because the old Timer fired on the idle step. Those are updated honestly, as in shield-spam T1.

### D2: Post-hit invulnerability stays on the existing Fighter timer

**Choice**: `Fighter.grant_invulnerability()` and `_invuln_timer` stay unchanged. The post-hitstun 0.5 s grant still happens in `_on_hurt_finished`, now driven by the tick count. The combo hard cap reuses the same `grant_invulnerability(seconds)`.

**Alternatives considered**: Moving invulnerability to ticks as the proposal lists. `tests/smoke/ledge.gd` reads `_invuln_timer.time_left` directly (lines 55 and 156), and respawn, ledge and visibility tests depend on it. Invulnerability is never on the link path, because it starts only when hitstun ends.

**Rationale**: It keeps the regression surface small with no effect on combos. This is a deliberate narrowing of proposal S1 item 1. The spec phase should state "Punch and Hurt timers" and leave invulnerability as it is today (see Open Questions).

### D3: Attack input buffer on the `Fighter`, read by `Motion` like the jump buffer

**Choice**:
- `Fighter.attack_buffer_ticks: int` and `Fighter.buffered_attack_aim: FighterIntent.Aim`, handled in `_tick_attack_buffer()` (called from `_physics_process` before the state machine updates):
  - On `intent.attack_pressed` while the current state is in `ATTACK_BUFFER_STATES = ["Idle", "Run", "Jump", "Fall", "Punch"]`, the buffer is set to `profile.attack_buffer_ticks` (default **6**, the same 0.10 s as `jump_buffer`) and the aim is stored.
  - Otherwise a non-zero buffer is decremented.
- `Motion._is_requested("punch")` returns `owner.attack_buffer_ticks > 0`.
- `Punch._enter()` calls `owner.consume_attack_buffer()` and uses the buffered aim as `_start_aim`. On the press frame this equals `intent.aim`, as today.
- Any other transition emitted by `handle_actions` (recovery, dash, jump, protect, air_dodge, shoot) clears the attack buffer, so one press never yields two actions. This covers the recovery chord, which sets both `attack_pressed` and `special_pressed`.
- Presses in `Hurt`, `ShieldDrop`, `Protect`, `Dizzy`, `AirDodge`, `LedgeHang`, `Dash`, `Recovery` and `Helpless` are not buffered, as today. The shield-spam numbers from T1 do not move.
- Holding the key never re-arms the buffer, because only `attack_pressed` edges set it.

**Alternatives considered**:
- Buffering in every state, including out of hitstun. That changes the ShieldDrop contract from T1 ("attack inputs are edges and are not buffered"), lets mashing during hitstun fire at hitstun end, and perturbs the shield-spam measurements.
- A buffer inside `Punch` only. It cannot cover hit-stop and endlag presses that need to fire from `Idle`.

**Rationale**: It mirrors the existing jump-buffer pattern (`peek_jump` and `consume_jump`). The CPU (0.12-0.40 s decisions) and the policy (`ACTION_REPEAT` 4) can then land presses inside short windows.

### D4: Frame data in ticks on `AttackProfile`, `-1` meaning legacy

**Choice**: `AttackProfile` adds the fields below. Every attack, including directional ones, takes its timing from its own profile.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `startup_ticks` | int | -1 | Ticks before the first active tick |
| `active_ticks` | int | -1 | Active ticks (the hitbox is live on ticks `startup+1 .. startup+active`) |
| `endlag_ticks` | int | -1 | Ticks after the active window; the swing ends at `startup+active+endlag` |
| `cooldown_ticks` | int | -1 | Extra lockout from the press (`Fighter.attack_cooldown_ticks`); -1 means `ticks(profile.punch_cooldown)`, 0 means "actionable at swing end" |
| `link_window_ticks` | int | 0 | Chain steps only: a neutral press advances on ticks `startup+active+1 .. startup+active+link_window` |
| `hitstun_ticks` | int | -1 | Base hitstun; -1 means the global formula on the final knockback |
| `hitstun_kb_growth` | float | 0.0 | Extra hitstun ticks per px/s of final knockback (used only when `hitstun_ticks >= 0`) |
| `hitstop_scale` | float | 1.0 | Multiplies the FULL-hit hit-stop duration (jabs about 0.5) |

Any `-1` timing field derives from the profile's legacy `punch_duration`, `punch_active_start` and `punch_active_end` (D1). `AttackProfile.make()` keeps its signature. A new static `AttackProfile.frames(startup, active, endlag, ...)` helper sets the frame data for code-built attacks.

**Alternatives considered**:
- Seconds as floats. Rounding could move links by a tick, and the link math in D6 is in ticks.
- A separate `FrameData` resource. It adds a second resource per attack in every `.tres` for no gain.

**Rationale**: The defaults reproduce today's behavior, so S2 is invisible until a kit sets values. Ticks make the link math exact.

### D5: Jab chains as a step state machine inside `Punch`

**Choice**:
- `FighterProfile` adds:
  - `jab_chain: Array[AttackProfile]` (grounded neutral).
  - `air_jab_chain: Array[AttackProfile]` (airborne neutral).
  - `neutral_single: AttackProfile`: a grounded neutral charged past `tap_threshold`, or a kit with no chain. Null means the legacy neutral built from the `punch_*` fields.
  - The baseline profile has both chains empty and `neutral_single` null, which is exactly today's neutral punch.
- `_select_attack(aim)`:
  - A non-neutral aim picks the directional attack, as today.
  - A neutral aim picks `neutral_single` when the swing came out of a charge with `hold >= tap_threshold`.
  - Otherwise it picks step 0 of `jab_chain` on the ground or `air_jab_chain` in the air.
  - With both chains empty, it picks the legacy neutral.
- During a chain step, on each `_update`:
  1. If `owner.attack_buffer_ticks > 0` and the buffered aim is NEUTRAL, the step is not the last, and `_tick <= link_close`, then set `_chain_queued = true` and consume the buffer. A non-neutral press stays in the buffer and can fire a new attack after the swing.
  2. If `_chain_queued` and `link_open <= _tick <= link_close` and the medium (floor or air) is unchanged, advance: `_step += 1`, `_tick = 0`, clear `_hit_targets`, place the hitbox, and set `attack_cooldown_ticks`.
  3. Once `_tick >= startup + active + endlag`, `end_punch()`.
- Chains advance on a whiff (Smash jab behavior). One press means one step, so holding never chains.
- The finisher (last step) has `link_window_ticks = 0` and launch knockback. That is the **chain cap** (at most 3 steps; the schema normalizes by 3).
- Charge scaling still applies to whatever attack fires (`smash-moves`: "the charged smash keeps its charge scaling on top of kit values").

**Alternatives considered**:
- A separate state per chain step (`Jab1`, `Jab2`). It adds FSM nodes and one-hot slots, which breaks the frozen v3 state layout.
- Auto-chaining while the key is held. The proposal rules it out.
- Advancing only on hit. It is harder to read for players and the policy, and Smash advances on a whiff.

**Rationale**: It stays inside the existing single-hitbox `Punch` and touches no scene topology or v3 one-hot. `_chain_queued` lets an early press (CPU, policy) land without the 6-tick buffer having to bridge the startup.

### D6: Link math (verified by a frame-advantage probe)

Let a step fire at tick `P`, with startup `s`, active `a`, and hitstun `S` on the victim. The engine has a fixed detection latency δ: deferred `monitoring` plus the overlap update, about 2 ticks as measured in the explore. The first-active-tick hit lands at `H = P + s + δ`.

The victim leaves `Hurt` and becomes invulnerable at `H + S`. A true link therefore needs the next hit at `H2 <= H + S - 1`. That bound does not depend on the order in which the two fighters update.

The next step fires at the earliest at `A2 = P + s1 + a1 + 1` (link open) and hits at `A2 + s2 + δ`. δ cancels:

```
slack(step1 -> step2) = S1 - a1 - s2 - 2      (ticks; >= 0 means a true link at the earliest press)
```

Kit targets: slack 2 for Rafael (tight on purpose) and 3-5 for Matilde. A press later in the link window still chains, but it loses the true combo once it is later than `slack` ticks after the window opens. That is the timing skill.

The probe (`tests/smoke/frame_data.gd`) measures δ and the actual hit ticks headless and asserts:
- the advantage on hit for each step;
- the link at 0%;
- the whiff at 90% caused by knockback growth.

### D7: `ComboTracker` on the victim, with `ComboRules` as one tunable resource

**Choice**:
- `game/combat/combo_tracker.gd` (`class_name ComboTracker`, RefCounted) is held by `Fighter.combo`, created and set up in `_enter_tree` next to `shield`.
- `game/combat/combo_rules.gd` (`class_name ComboRules`, Resource) has its defaults in `game/combat/combo_rules.tres`. It is shared by both fighters for fairness. Tests may swap `fighter.combo.rules`.
- `Combat._apply_full(hit, target)` works in this order:
  1. Read `in_hitstun := target._state_name() == "Hurt"` **before** the state change.
  2. `var scale := target.combo.register(hit, in_hitstun)`.
  3. Set the Hurt pending fields (`pending_attack = hit.attack`, `pending_combo = scale`).
  4. `_change_state("Hurt")`.
- `register` rules:
  - `hit.attacker == null` (bomb): `reset()` silently, return the identity scale, and do not count the hit.
  - `in_hitstun` and active: `hits += 1`, `damage += hit.damage`.
  - Otherwise a new combo starts: `hits = 1`, `damage = hit.damage`, `elapsed_ticks = 0`, `attacker = hit.attacker`.
  - Food hits from an attacker count, because they are real hits during hitstun.
- Scaling record, applied in `Hurt._enter`:
  - `kb_mult = knockback_growth ^ (hits - 1)` (1.1).
  - `stun_mult = hitstun_decay ^ max(0, hits - (decay_from_hit - 1))`: 1.0 for hits 1-3, then 0.8 and 0.64.
  - `stun_cap_ticks = time_cap_ticks - elapsed_ticks` (90 - elapsed).
  - `capped = hits >= hard_cap_hits` (6), or `stun_cap_ticks <= min_combo_stun_ticks` (4).
- `Hurt._enter` applies the record:
  - `final_kb *= victim scale * kb_mult`.
  - `stun = clampi(roundi(base_stun * stun_mult), 1, max(1, stun_cap_ticks))`.
  - When `capped`: the knockback becomes the stronger of the hit's and `cap_launch_knockback` (both get the same victim scaling), and the victim gets `grant_invulnerability(seconds(stun) + post_hit_invulnerability)` at once, so the 6th hit launches and nothing else connects.
- Ending a combo:
  - `ComboTracker.tick(state_name)` runs in `Fighter._tick_combat`. While active it does `elapsed_ticks += 1`, and when the state is not `Hurt` it calls `end()`, which emits `combo_ended(hits, damage, attacker)` and resets.
  - A Hurt-to-Hurt re-entry happens within one tick, so the lazy check never ends a live combo.
  - Leaving `Hurt` through a KO, a respawn or a reset also ends the combo on the next tick.
  - `MatchMetrics.stop()` flushes an open combo.
- The 0.5 s post-hitstun invulnerability is kept (granted only at the natural hitstun end, as today).

**Alternatives considered**:
- Combo state inside `Hurt` (the proposal sketch). `Hurt` is re-entered for each hit and only updates while current. Snapshot, HUD and metrics readers would also have to reach into the state node. A tracker object matches the `ShieldMeter` pattern.
- An attacker-side counter. It cannot see hits from food, cannot apply the victim's scaling, and does not reset on the victim's hitstun.
- Per-profile combo rules. Asymmetric anti-infinite rules invite balance exploits.

**Rationale**:
- With the time-cap clamp, no victim stays in `Hurt` for more than 90 consecutive ticks (1.5 s), given that a single hit's hitstun is at most 54 ticks (formula maximum 0.9 s) or 33 ticks (launcher).
- The hard cap bounds the hit count at 6.
- The knockback growth pushes jab chains out of reach at high %.
- The infinite probe from the explore (zero knockback, mashing) ends by hit 6 at the latest.

### D8: Combo signals and the attacker HUD counter

**Choice**:
- `Fighter` (as victim) adds:
  - `signal combo_updated(hits: int, damage: float, attacker: Fighter)`, emitted on every counted hit.
  - `signal combo_ended(hits: int, damage: float, attacker: Fighter)`.
- `FighterHud` connects in `_ready` to `owner.enemy.combo_updated` and `combo_ended` and filters on `attacker == owner`. This is not done in training, where the HUD is already hidden and stops processing.
- It builds a `ComboLabel`: 22 px, white with a black outline, placed above the card on the card's side.
- With `hits >= 2`, the label shows `"%d HIT COMBO  %d%%" % [hits, round(damage)]` at alpha 1, with a pop tween (as `_pop`).
- On `combo_ended` with `hits >= 2`, the label is held for 0.35 s and then fades to alpha 0 over 0.65 s (about 1 s total). A newer combo kills the fade tween.
- An optional small `T_LeLuStar11` additive icon (existing asset, `assets/textures/2D Fire  - Tutorial/T_LeLuStar11.jpg`) can sit in front of the text. No new assets.

**Alternatives considered**:
- Polling the opponent's snapshot every frame. It is wasteful, and the signal already carries the damage.
- Showing the counter on the victim's card. The proposal and Smash both use the attacker's side.

**Rationale**: It follows the signal-driven pattern used for damage and stocks, and nothing new is needed for training.

### D9: Kits resolved from `CharacterUI.name` through a static `FighterKits` registry

**Choice**:
- `game/player/profiles/fighter_kits.gd` (`class_name FighterKits`) provides:
  - `const PATHS := {&"rafael": "res://game/player/profiles/rafael_profile.tres", &"matilde": "res://game/player/profiles/matilde_profile.tres"}`.
  - `static func for_character(ui: CharacterUI) -> FighterProfile` (lower-cased name; unknown or null gives `FighterProfile.new()`).
  - `static func by_id(kit_id: int) -> FighterProfile`.
  - `static func ids() -> PackedInt32Array` (`[0, 1]`).
  - `static func random(rng: RandomNumberGenerator) -> FighterProfile`.
  - Loaded `.tres` files are cached and handed out by reference. Profiles are read-only at run time, so sharing them is safe.
- `FighterProfile` adds `kit_id: int = -1` (generic) and `kit_name: StringName = &"default"`. Rafael is 0 and Matilde is 1; ids 2 and 3 are reserved.
- `Fighter`:
  - `@export var kit_from_character := true`.
  - `_enter_tree`: when `profile == null`, use `FighterKits.for_character(character_ui)` if `kit_from_character`, else `FighterProfile.new()`.
  - The `character_ui` setter calls `set_profile(FighterKits.for_character(value))` when `is_inside_tree() and kit_from_character`. That is the `SceneManager.play_game` path, which assigns characters after `add_child`. `SceneManager` itself needs no code change.
  - `set_profile(p)` does `profile = p; shield.setup(p); shield.refill(); restore_air_actions(); _build_pickup_area()` (when ready). `Punch` reads `owner.profile` on every swing, so nothing else caches it.
- Smoke compatibility: `Smoke.spawn_game(p1_x, p2_x, with_countdown, kits := false)`. When false, it assigns `FighterProfile.new()` to both fighters before `add_child`, so the existing suite keeps testing the baseline numbers. Kit, harness, eval and reel scripts pass `kits = true`.

**Alternatives considered**:
- A `kit` export on `CharacterUI`. The character select builds its own `CharacterUI` resources, and `game.tscn` uses embedded sub-resources, so the kit would be duplicated in several places.
- Assigning the kit in `SceneManager.play_game`. It misses `game.tscn` and training rows, which never go through `play_game`.

**Rationale**: There is one source of truth for the mapping, and it covers the real match, `game.tscn` defaults, training rows (Fighter1 Rafael, Fighter2 Matilde) and the harness. Kits stay data (`.tres`).

### D10: Initial kit data (tunable) and the Matilde launcher prototype first

Frame data is in ticks (60/s). Damage is in %. Knockback is base px/s before the victim's `knockback_scale * (1 + %/50)`.

| Attack | Rafael | Matilde |
|---|---|---|
| Movement | run 270, jump -820, double -720, `knockback_scale` 0.9, recovery -900 / drift 220 | run 340, jump -900, double -780, `knockback_scale` 1.1, recovery -1050 / drift 290 (longer recovery) |
| Jab 1 | 4 dmg, kb (70,-30), s4 a2 e10, link 10, stun 11, hit-stop 0.6 | 2.5, (50,-20), s3 a2 e9, link 9, stun 11, hit-stop 0.5 |
| Jab 2 | **finisher** 8, (260,-180), s5 a3 e16, stun formula, hit-stop 1.0 | 2.5, (50,-20), s3 a2 e9, link 9, stun 11, hit-stop 0.5 |
| Jab 3 | (none) | **finisher** 4, (240,-200), s4 a3 e14, stun formula |
| Neutral single (charged / no chain) | 10, (260,-140), s6 a4 e16 | 6, (200,-120), s4 a3 e12 |
| Up | heavy launcher 9, (40,-520), s6 a4 e33 (0.55 s), stun formula | combo launcher 6, (20,-430), s4 a3 e18 (0.30 s), stun **33** fixed (0.55 s) |
| Side | 13, (360,-90), s7 a4 e20 | 8, (260,-90), s5 a3 e14 |
| Down (ground) | 8, (160,-240), s5 a3 e16 | 6, (130,-220), s4 a3 e12 |
| Down air (spike) | 11, (40,460), s6 a4 e16 | 7, (30,380), s5 a3 e14 |
| Air jab | single: 5, (120,-120), s4 a3 e12 | A1 3, (40,-40), s3 a2 e8, link 8, stun 12; A2 4, (180,-160), s3 a3 e12, stun formula |
| `launcher_followup` (CPU hint) | `&"none"` | `&"air_jab"` |

All kit attacks use `cooldown_ticks = 0` (actionable at swing end) and `attack_buffer_ticks = 6`.

Link slack from D6:
- Rafael J1→J2: 11 - 2 - 5 - 2 = **2**.
- Matilde J1→J2: 11 - 2 - 3 - 2 = **4**.
- Matilde J2→J3: 11 - 2 - 4 - 2 = **3**.
- Matilde A1→A2: 12 - 2 - 3 - 2 = **5**.

**Matilde launcher → air jab, worked at 20% on a Rafael victim.** Victim scale: 0.9 × 1.4 = 1.26.
- Launch: vy = -542 px/s, with Hurt gravity 1800 × 0.6 = 1080 px/s².
- Launch hit at about P+7. Victim hitstun ends at about P+40.
- Matilde is actionable at P+25, with a buffered jump at -900.
- An air jab (A1, s3) pressed at about P+27 hits at about P+33. That is 26 ticks after the launch, with the victim about 133 px up and Matilde about 81 px up: a 52 px gap, inside the A1 hitbox (offset (55,-60), size (110,90)). Slack about 6 ticks.
- At 60% (scale 1.98) the gap grows to about 186 px and the follow-up whiffs, which is the intended %-window.

**Prototype order (S4 first task)**: `tests/smoke/kits.gd::_probe_matilde_launcher` scripts launcher, jump and A1 headless at 0/20/40/60% and records the hit tick and the gap. If it does not connect at 0-30%, tune as data only, in this order: launcher `knockback.y`, then `hitstun_ticks`, then A1 hitbox offset and size, then Matilde `air_acceleration`/`jump_velocity`. If it is still unreliable, **fall back to a jab-chain-only identity**: Matilde keeps the 3-hit jab and the 2-hit air jab, the up becomes a plain launcher, and `launcher_followup = &"none"`. Report this before tuning the rest of the kits.

### D11: CPU combos driven by events, gated by difficulty

**Choice**: `CpuDifficulty` adds the fields below.

| Field | Easy | Normal | Hard |
|---|---|---|---|
| `chain_chance` | 0.0 | 0.75 | 0.95 |
| `chain_press_delay` (s) | n/a | 0.05 | 0.017 |
| `launcher_followup_chance` | 0.0 | 0.0 | 0.8 |

`ScriptedController.bind()` connects to `fighter.enemy.hit_received`. On a FULL `PUNCH` hit with `attacker == fighter`:
- **Chain**: if the fighter is in `Punch` on a chain step that is not the last (`Punch.chain_step()` and `chain_length()`), roll `chain_chance` and schedule a neutral press after `chain_press_delay`. `_want_attack` with aim NEUTRAL is not tied to the decision tick.
- **Follow-up**: if `hit.attack.direction == &"up"` and the profile's `launcher_followup == &"air_jab"`, roll `launcher_followup_chance` and enter `Plan.FOLLOWUP`. The plan presses jump in the last 6 ticks of the endlag (jump buffer), then a neutral attack when the enemy is within a dy/dx window above, with a 0.7 s timeout.

`_accepts("punch")` also returns true while the state is `Punch` and `Punch.accepts_chain_press()` is true. The press is then consumed by the `_chain_queued` path.
- Easy keeps `use_directional = false` and never chains, so it throws single jabs only.
- The CPU still never charges (`attack_held` false).
- The difficulty ordering stays Easy ≤ Normal ≤ Hard.

**Alternatives considered**:
- Lowering `decision_interval`. It changes every other plan and the difficulty feel.
- Reading `chain_step` from the snapshot at decision time. A 0.22-0.40 s decision interval misses 9-10 tick windows.

**Rationale**: This is the same event pattern as the reward tracker. Chains then work at every decision interval, and Easy's restrictions hold structurally.

### D12: Schema 4 = v3 + 13 appended floats; the decoder is a v3 copy; the flip waits for S6

**Choice**:
- `bvs_schema_v4.gd` is a self-contained copy of v3 (nothing calls into v3) with `VERSION 4` and `OBS_DIM 149`.
- **Indices 0-135 are byte-identical to v3**. `[136, 149)` is appended:

| Index | Field | Value |
|---|---|---|
| 136-139 | `self_kit_0..3` | one-hot of `kit_id` (Rafael 0, Matilde 1, 2-3 reserved); `kit_id < 0` or `>= 4` is all zeros |
| 140-143 | `opp_kit_0..3` | the same for the opponent |
| 144 | `self_chain_step` | `chain_step / 3`, clipped to [0,1] (0 outside a chain step; 1..3 for steps) |
| 145 | `self_link_open` | 1 while `link_open <= tick <= link_close` on a non-final chain step |
| 146 | `opp_hitstun_left` | opponent `hitstun_left` seconds / 1.0, clipped to [0,1] |
| 147 | `self_combo_dealt` | **opponent's** `combo_hits` / 6, clipped to [0,1] (the combo I am dealing) |
| 148 | `self_combo_taken` | my `combo_hits` / 6, clipped to [0,1] |

- `FIGHTER_KEYS` v4 = the v3 keys plus `kit_id`, `chain_step`, `link_open`, `hitstun_left`, `combo_hits`. A missing key gives an error naming it and an all-zero vector, as in v3.
- `bvs_action_decoder_v4.gd` is a renamed copy of the v3 decoder that checks against `BvsSchemaV4.BRANCHES`. Decoding is identical, and `[3,3,2,5,2,2,2,2]` is unchanged.
- `BvsSchema._registry` and `_decoders` gain `4`. **`CURRENT_VERSION` stays 3 through S5** and becomes 4 in the S6 commit that bundles the gated model. `HubModel.BVS_SCHEMA_VERSION` derives from it.
- Training targets v4 through `BVS_TRAIN_CONFIG.schema_version = 4`, which `TrainArena`, `PlayerAIController` and `PolicyController` already support.

**Alternatives considered**:
- Interleaving the features into the fighter blocks (the combat-depth D14 style). It breaks the "v4[0:136] == v3" parity check, which is the cheapest guard on the frozen layout.
- Flipping `CURRENT_VERSION` in S5 (the proposal's wording). `ModelManager` would reject the still-bundled v3 model, and branch commits between S5 and S6 would be red. A gate failure that ends in choice (c) would also leave no consistent state.
- Adding the opponent's chain step and link state. The 13-float budget was agreed, and the opponent's `Punch` one-hot plus `opp_cd_punch` already signal a threat.

**Rationale**: It keeps every commit green, makes the Resolved Decision's fallbacks real states, and reduces the v4 audit to 13 documented floats.

### D13: The frozen v2/v3 registry checks move their test stub from version 4 to version 5

**Choice**:
- `tests/smoke/schema_v2.gd::_check_registry` (lines 346-354) and `tests/smoke/schema_v3.gd::_check_registry` (lines 457 and 484-494) register a test stub **as version 4**. `register_test_stub` refuses built-in versions, so these checks fail once v4 is registered.
- Only those stub lines change: the stub becomes version 5, and `not is_builtin(4)` becomes `not is_builtin(5)`.
- The layout, observation, decode and fixture checks of both files stay **unedited**.
- The full registry coverage for 2, 3 and 4 moves to `schema_v4.gd`.

**Alternatives considered**:
- Leaving them unedited. They would fail.
- Removing the stub checks. That loses the extensibility guard.

**Rationale**: combat-depth set the same precedent (its stub moved from 3 to 4). The spec phase should word "frozen checks unedited" as "frozen layout/obs/decode checks unedited; registry stub version may move" (Open Questions).

### D14: Rewards from signals: a capped `combo_hit` and a `shield_raise` lever

**Choice**: `RewardConfig.TERMS` adds two terms and `PARAMS` adds two parameters.

| Key | Kind | Default in `RewardConfig` | `default.toml` start | Meaning |
|---|---|---|---|---|
| `combo_hit` | term | 0.02 | 0.02 | Per extra hit (hits ≥ 2) of a combo I deal (foe's `combo_updated` with `attacker == me`) |
| `combo_hit_cap` | param | 4 | 4 | Extra hits rewarded per combo (at most 0.08 per combo at the defaults) |
| `combo_episode_cap` | param | 1.0 | 1.0 | Total `combo_hit` reward per episode |
| `shield_raise` | term | 0.0 | -0.002 | Per shield raise (`Fighter.shield_raises` delta, read per decision) |

**Alternatives considered**:
- Rewarding combo length from observations. The spec forbids it (rewards come from signals).
- An uncapped combo reward. It invites farming jab restarts.
- Only gating shield raises without a reward lever. T1 recorded that "the training signal has to do the rest".

**Rationale**: The combo bonus is small next to `damage_dealt` (0.01 per %), so it shapes rather than dominates. `shield_raise` defaults to 0 in code, so behavior is unchanged without the config, and it is the main iteration lever for the shield gate.

### D15: Shield-raise gate threshold from a measured baseline, recorded before the retrain

**Choice**: The procedure runs at the end of S5 with the final gameplay and kits, before R1:
1. Run the harness at seed 1 with `BVS_HARNESS_KITS=rm`:
   - `cpu_hard_vs_cpu_hard` (40 matches) gives `R_cpu`, the shield raises per fighter-minute.
   - The **current bundled schema-3 model**, which still runs because v3 is registered, in `mvm` and `m_vs_cpu_hard` (24 matches each) gives `R_old`, the spam baseline, as the maximum of the two.
2. Compute `T = min(0.5 * R_old, max(1.5 * R_cpu, R_cpu + 2.0))`. If `0.5 * R_old < R_cpu` (the old model is not spammy on the new rules), use `T = max(1.5 * R_cpu, R_cpu + 2.0)` and note it.
3. Write `training/reports/shield-baseline.{json,md}` with `R_cpu`, `R_old` and `T`, and set `[acceptance] max_shield_raises_per_fighter_minute = T` in `default.toml`. This is committed before R1, and the gate cannot be changed afterwards except by a re-measurement that the report explains.
4. The gate applies to the retrained model in `mvm` and `m_vs_cpu_hard`.

**Alternatives considered**:
- A fixed number picked now. No baseline exists on the new rules (drop lag, raise cost, kits).
- Comparing only with the old model. A model can halve an absurd rate and still spam.

**Rationale**: The threshold is anchored to a non-spamming reference (CPU Hard respects the meter by design) and requires a real improvement over the published behavior that prompted T4.

### D16: Metrics and harness additions; gates as data

**Choice**:
- `MatchMetrics` adds:
  - `shield_raises[2]` (a `Fighter.shield_raises` delta between `setup` and `stop`).
  - `combos: Array` of `{hits, damage, attacker_kit, victim_index}` from each victim's `combo_ended` (single hits are counted as length 1).
  - Per-fighter `hurt_run` and `max_hurt_ticks`, tracked in `_on_physics_frame` (consecutive ticks in `Hurt`).
  - `kits[2]` (`profile.kit_name`).
- `aggregate()` adds:
  - `shield_raises_per_fighter_minute`;
  - `combo_histogram` (`"1".."6"`, `"7+"`);
  - `max_combo`;
  - `multi_hit_combos` (hits ≥ 2);
  - `max_hurt_seconds`;
  - `hurt_over_cap` (runs longer than 90 ticks);
  - `combo_damage_by_kit` (the mean damage of multi-hit combos per attacker kit);
  - `damage_by_kit`.
- `combat_harness.gd` adds `BVS_HARNESS_KITS`:
  - `character`: the scene default, Fighter1 Rafael and Fighter2 Matilde.
  - `rm` (default for gates): the kit pair cycles with `(index / 2) % 2` while sides alternate with `index % 2`, so each controller plays each kit on each side.
  - `rotate4`: RM, MR, RR, MM.
  - Per match it records `winner_kit` and `winner_side`. Per matchup it reports `kit_win_share` (Rafael wins / decided matches with different kits) and `side_win_share`.
  - `spawn_game(..., kits = true)` plus `fighter.set_profile(FighterKits.by_id(...))`.
- `harness.py` reads the new `[acceptance]` keys.

| Gate key | Value | Matchups |
|---|---|---|
| existing: `max_mean_sd_seconds` 45, `min_pickups_per_fighter_minute` 1.0, `max_blocked_share` 0.70, `min_ko_win_rate_easy` 0.60 | unchanged | as today |
| `min_matches` | 24 (40 for the share matchups) | all |
| `max_shield_raises_per_fighter_minute` | `T` from D15 | mvm, m_vs_cpu_hard |
| `max_combo` | 6 | all |
| `max_hurt_seconds` | 1.5 | all |
| `min_multi_hit_combos` | 5 per matchup | mvm, cpu_normal_vs_cpu_normal, cpu_hard_vs_cpu_hard |
| `kit_win_share_min` / `kit_win_share_max` | 0.40 / 0.60 | cpu_hard_vs_cpu_hard (40), mvm (40) |
| `max_combo_damage_gap` | 0.20 (`abs(R - M) / max(R, M)` of the mean multi-hit combo damage) | all model and CPU matchups pooled |

The gate run covers mvm 40, cpu_hard_vs_cpu_hard 40, m_vs_cpu_easy 24, m_vs_cpu_hard 24, cpu_normal_vs_cpu_normal 24, and a forced-SD mvm 20: 172 matches, both kits, both sides.

`evaluate.py` and `policy_eval.gd` render the same new fields (kits by character for the eval).

**Alternatives considered**:
- Recomputing metrics in Python. GDScript signals are the only source of truth (combat-depth D15).
- 20-match share gates. ±11% sampling noise at n=20 makes a 40-60% band meaningless, so the share matchups use 40.

**Rationale**: Acceptance stays reproducible from the seed, and every success criterion in the proposal maps to a named gate.

### D17: Training: kits randomized per side per episode, seeded per row

**Choice**:
- `BVS_TRAIN_CONFIG.kits = {"mode": "random" | "character", "seed": int}` (from `[kits]` in `default.toml`, `mode = "random"`).
- `TrainArena._build_row` creates a per-row `RandomNumberGenerator` (seed = kits seed × 1009 + row index).
  - In `random` mode it assigns `set_profile(FighterKits.random(rng))` to each side independently at build time, and again on `game.training_episode_ended`, before the fighters reset on their next physics frame. RR, MM, RM and MR then all occur.
  - In `character` mode it keeps the scene kits.
- `train.py` writes `schema_version: 4` and the `kits` block. `handshake.py` checks obs 149.
- `[reward]` gains `combo_hit`, `combo_hit_cap`, `combo_episode_cap` and `shield_raise`.

**Alternatives considered**:
- Fixed kits per row. The agent would learn kit-specific play only on one side.
- Per-step randomization. That is nonsense mid-episode.

**Rationale**: One model covers both kits in both seats, and the kit one-hot is learnable. The randomness stays seeded, as with the CPU opponents.

### D18: Retrain plan, time box and gate-failure flow (Resolved Decision)

**Choice**:
- **R0 sanity**: P1-P3 at 100k steps each, `--n-parallel 4` (about 3 min). Check the `BVS_EPISODE` lines carry `combo_hit`/`shield_raise`, every kit pair appears in the row logs, and there is no `SCRIPT ERROR`.
- **Baseline**: D15, committed.
- **R1**: the full `default.toml` curriculum (10M steps, `--n-parallel 8`, about 50 min based on the 2817 s r1 of combat-depth). Then golden parity, `evaluate.py` and `harness.py`.
- **R2-R4 (only on failure)**, one lever group per run:
  - reward weights (`shield_raise`, `shield_hold`, `combo_hit`);
  - curriculum (P3 `cpu_hard` share up to 0.15, `sd_start`);
  - steps (up to 14M);
  - kit data, only for the balance gates, followed by a rerun of the S4 kit and CPU smoke tests. A kit-data change after the baseline requires re-running D15, and the report says so.
- **Time box**: 4 full runs or 4 h of cumulative training wall time, whichever comes first (`time_box_hours` per run stays as the hard cap).
- **Gate failure at the time box**: STOP and ask the user to choose (b) merge the best candidate with the failed gate reported, or (c) merge S1-S4 on schema 3 and move S5-S6 to a follow-up. Under (c), S5 can stay merged registered-but-not-current, because v4 is not current until S6. Nothing is merged before a decision.
- **Promotion (all gates pass)**: one commit containing:
  - `model.onnx` and `bvs.json` (schema 4);
  - `CURRENT_VERSION := 4`;
  - the regenerated `tests/fixtures/onnx/bvs_default_golden.json`;
  - the current-version test migrations;
  - the reports and the replay.
- **Replay**: `policy_reel.gd -- model=... opponent=model kits=rm seconds=45 --write-movie` produces an AVI, converted by a documented manual `ffmpeg` command into `training/reports/bvs_default-replay.mp4`. It is not placed under `game/`, so the web export never ships it. `prepare_upload.py --replay` stages it as `replay.mp4`.

**Rationale**: It applies the Resolved Decision literally, keeps the iteration bounded, and leaves an auditable report trail.

### D19: Remote stays print-only and per destination

**Choice**:
- `prepare_upload.py` keeps `--confirm <repo>`. Tags become `BVS` and `bvs-schema-4` (through `schema.SCHEMA_TAG`), plus `reinforcement-learning`, and `replay.mp4` is staged from `--replay`.
- `--space` requires `--confirm-space RafaelJaime/BroVSister` and prints the deploy steps.
- There is no network code and no auth probing. S7 runs only after the PR merges and the user explicitly confirms each destination.

**Rationale**: This is unchanged from combat-depth D16. It matches the remote-authorization contract.

## Data Flow

Press to hit to combo (one tick, parent-first order):

```
Fighter._physics_process
  intent = controller.sample()
  _tick_attack_buffer()        press in ATTACK_BUFFER_STATES -> attack_buffer_ticks = 6, buffered_aim
  _tick_combat()               shield.tick, attack_cooldown_ticks--, combo.tick(state) -> end? -> combo_ended
StateMachine._physics_process -> state._update
  Idle/Run/Jump/Fall: handle_actions -> "punch" if buffer > 0 and Punch.can_enter (cooldown == 0)
  Punch: _tick++ ; active? -> overlaps -> Hit.punch(+attack, +hitstop_scale)
         chain step: neutral buffer -> _chain_queued ; link open -> _advance() ; end at s+a+e
                                   |
                                   v
Combat.resolve(hit, target) --invuln--> IGNORED
   | not shielding
   v
_apply_full: in_hitstun = (state == "Hurt")
             scale = target.combo.register(hit, in_hitstun) --> combo_updated(hits, dmg, attacker)
             Hurt.pending_{damage, knockback, source_x, attack, combo} ; change_state("Hurt")
   v
Hurt._enter: kb * victim scale * kb_mult ; stun = base(attack|formula) * stun_mult, clamp to time cap
             capped? -> launch kb >= cap_launch_kb, grant_invulnerability(stun + 0.5 s)
Hurt._update: _ticks_left-- -> 0 -> grant 0.5 s invuln, exit_to_neutral
   v
target.hit_received(hit, outcome) -> RewardTracker / MatchMetrics / CPU (chain + follow-up hooks)
_play_juice: hit-stop 0.08 * hit.hitstop_scale (never in training)
```

Combo consumers:

```
victim.combo_updated --> attacker FighterHud (hits >= 2: show "N HIT COMBO  D%")
                     --> RewardTracker(attacker) combo_hit (capped per combo / episode)
victim.combo_ended   --> FighterHud fade (0.35 s hold + 0.65 s fade)
                     --> MatchMetrics.combos (histogram, max, damage by attacker kit)
```

Kit resolution:

```
game.tscn (Rafael/Matilde CharacterUI) --_enter_tree--> FighterKits.for_character -> profile
SceneManager.play_game --character_ui setter--> set_profile(FighterKits.for_character)
TrainArena (kits.mode = random) --build + training_episode_ended--> set_profile(FighterKits.random(row rng))
Smoke.spawn_game(kits=false) --> FighterProfile.new() (baseline, legacy numbers)
combat_harness (BVS_HARNESS_KITS=rm) --> set_profile(FighterKits.by_id(pair[side]))
```

Schema selection (unchanged mechanism, version 4 added):

```
S5:  registry {2, 3, 4}; CURRENT_VERSION = 3; training uses schema_version 4 via BVS_TRAIN_CONFIG
S6:  gates pass -> CURRENT_VERSION = 4 + bundled v4 model (one commit)
picker: HubModel tag bvs-schema-4 == CURRENT ? Compatible : "Trained for an older version"
```

## File Changes

Authored-line forecast per slice (generated fixtures, binaries and video excluded): S1 ~250, S2 ~350, S3 ~300, S4 ~380, S5 ~550, S6 ~80, S7 ~30. Delivery is a single PR with `size:exception`, with one or a few work-unit commits per slice. Never stage `project.godot`, `odd/tasks/kitchen-food-fight.md` or `game/ui/game_over/confetti.tres` (the user's local edits).

### S1: tick timers and attack buffer

| File | Action | Description |
|---|---|---|
| `game/player/StateMachine/PlayerStateMachine/States/punch.gd` | Modify | Remove `punch_timer`/`cooldown_timer`; `_tick` swing counter; legacy frame derivation (D1); `cooldown_left()`; `_enter` consumes the attack buffer and uses the buffered aim |
| `game/player/StateMachine/PlayerStateMachine/States/hurt.gd` | Modify | Remove `timer`; `_ticks_left` from `_hitstun_for` in ticks; `ticks_left()` accessor |
| `game/player/StateMachine/PlayerStateMachine/States/motion.gd` | Modify | `_is_requested("punch")` reads `owner.attack_buffer_ticks`; non-punch transitions clear the buffer |
| `game/player/player.gd` | Modify | `attack_cooldown_ticks`, `attack_buffer_ticks`, `buffered_attack_aim`, `ATTACK_BUFFER_STATES`, `_tick_attack_buffer()`, `consume_attack_buffer()`, `_cooldown_left` via `cooldown_left()`; reset clears the buffer and cooldown |
| `game/player/fighter_profile.gd` | Modify | `attack_buffer_ticks: int = 6` (Punch group) |
| `game/player/controllers/scripted_controller.gd` | Modify (small) | none needed in S1 (still uses `cooldowns.punch`); listed for awareness |
| `tests/smoke/attack_timing.gd` | Create | Buffer fires on the first actionable tick; expires after 6 ticks; not recorded in Hurt/ShieldDrop/Protect; hold never re-presses; one press means one action (jump+attack same frame → jump only); swing and hitstun tick counts are equal with `Engine.time_scale` 0.3 and 1.0; baseline hit/Idle/cooldown ticks within ±1 of today's |
| `tests/smoke/run_all.sh` | Modify | Add `attack_timing` |
| Existing smoke (`hit_rules`, `combat`, `shield_spam`, `air_punch`, `shield`) | Modify only if needed | Honest ±1-tick updates only, each documented in the ODD/SDD evidence |

### S2: frame data and jab chains

| File | Action | Description |
|---|---|---|
| `game/combat/attack_profile.gd` | Modify | Frame-data fields (D4), `frames()` helper, `resolved_frames(profile, override_duration) -> Dictionary` (startup, active, endlag, cooldown) |
| `game/player/fighter_profile.gd` | Modify | `jab_chain`, `air_jab_chain`, `neutral_single`, `kit_id`, `kit_name`, `launcher_followup` |
| `game/player/StateMachine/PlayerStateMachine/States/punch.gd` | Modify | Chain step machine (D5), `chain_step()`, `chain_length()`, `link_open()`, `accepts_chain_press()`, per-step `_hit_targets` reset, frame data per attack |
| `game/combat/hit.gd` | Modify | `attack: AttackProfile`, `hitstop_scale: float = 1.0` |
| `game/combat/combat.gd` | Modify | FULL hit-stop duration × `hit.hitstop_scale` |
| `game/player/StateMachine/PlayerStateMachine/States/hurt.gd` | Modify | `pending_attack`; hitstun from `attack.hitstun_ticks` (+ growth) or the formula |
| `tests/smoke/frame_data.gd` | Create | Baseline reproduces legacy ticks; a test chain profile: one press per step, hold never chains, an early press queues, a late press after `link_close` does not chain, the finisher launches (vy < 0 above threshold), the jab hit-stop scale is on the Hit; frame-advantage probe that reports δ and the per-step advantage |

### S3: combo tracking, safeguards, HUD

| File | Action | Description |
|---|---|---|
| `game/combat/combo_rules.gd` | Create | `ComboRules` resource (D7 defaults) |
| `game/combat/combo_rules.tres` | Create | Shared defaults |
| `game/combat/combo_tracker.gd` | Create | `register`, `tick`, `end`, `reset`, `Scale` record |
| `game/combat/combat.gd` | Modify | `_apply_full` reads `in_hitstun`, registers the combo, passes the scale |
| `game/player/StateMachine/PlayerStateMachine/States/hurt.gd` | Modify | Applies `kb_mult`, `stun_mult`, the time-cap clamp, the hard-cap launch and immediate invulnerability |
| `game/player/player.gd` | Modify | `combo` field, `combo_updated`/`combo_ended` signals, `combo.tick` in `_tick_combat`, reset on `reset_player`/`_respawn`/`prepare_sudden_death` |
| `game/player/player_ui.gd` | Modify | `ComboLabel`, enemy signal hookup, show/fade (D8) |
| `tests/smoke/combo_safeguards.gd` | Create | Infinite probe (zero-kb test chain, mashing) ends at hit ≤ 6 and Hurt ≤ 90 consecutive ticks; decay from hit 4; kb growth ×1.1; cap grants invulnerability and launches; post-hit 0.5 s invulnerability kept; a bomb resets the combo; a Hurt→Hurt re-entry keeps it alive; `combo_ended` fires one tick after hitstun ends |
| `tests/smoke/hud.gd` | Modify | Combo label hidden at 1 hit, shown at 2+ with damage, fades within about 1.1 s, absent in training |

### S4: kits, prototype, CPU combos

| File | Action | Description |
|---|---|---|
| `game/player/profiles/fighter_kits.gd` | Create | Registry (D9) |
| `game/player/profiles/rafael_profile.tres` | Create | Rafael kit (D10) |
| `game/player/profiles/matilde_profile.tres` | Create | Matilde kit (D10) |
| `game/player/player.gd` | Modify | `kit_from_character`, kit resolution in `_enter_tree` and the setter, `set_profile()` |
| `game/player/controllers/cpu_difficulty.gd` | Modify | `chain_chance`, `chain_press_delay`, `launcher_followup_chance` + presets |
| `game/player/controllers/scripted_controller.gd` | Modify | `hit_received` hook, scheduled chain press, `Plan.FOLLOWUP`, `_accepts("punch")` during chain steps |
| `tests/smoke/smoke_util.gd` | Modify | `spawn_game(..., kits := false)` |
| `tests/smoke/kits.gd` | Create | **Matilde launcher probe first**; assignment by character (scene, `play_game`, setter), `set_profile` refresh (shield, jumps, pickup); per-kit run speed and jump apex; Rafael 2-hit and Matilde 3-hit link at 0%; chains whiff at 90%; Matilde 2-hit air jab; recovery height Matilde > Rafael |
| `tests/smoke/cpu_combos.gd` | Create | Multi-hit combo rate Easy = 0 ≤ Normal ≤ Hard over seeded matches; Hard follow-ups > 0 with Matilde; Easy no directional, no chain, no charge |
| `tests/smoke/run_all.sh` | Modify | Add `frame_data`, `combo_safeguards`, `kits`, `cpu_combos` |

### S5: schema 4, training, metrics, baseline

| File | Action | Description |
|---|---|---|
| `game/ai/schema/bvs_schema_v4.gd` | Create | D12 layout, keys, `build_obs`, `validate_snapshot`, helpers, `sidecar_template` (v4) |
| `game/ai/schema/bvs_action_decoder_v4.gd` | Create | v3 decode, v4 branches |
| `game/ai/schema/bvs_schema.gd` | Modify | Register 4; `CURRENT_VERSION` stays 3; comment update |
| `game/player/player.gd` | Modify | Snapshot keys `kit_id`, `chain_step`, `link_open`, `hitstun_left`, `combo_hits`, `combo_damage` |
| `game/ai/training/reward_config.gd` | Modify | `combo_hit`, `shield_raise`, `combo_hit_cap`, `combo_episode_cap` |
| `game/ai/training/reward_tracker.gd` | Modify | Foe `combo_updated` → capped `combo_hit`; per-decision `shield_raises` delta → `shield_raise` |
| `game/ai/training/train_arena.gd` | Modify | `kits` config, per-row RNG, assignment at build and on episode end |
| `game/ai/training/match_metrics.gd` | Modify | D16 fields and aggregate |
| `tests/fixtures/schema/v4_layout.json`, `v4_obs_golden.json` | Create (generated) | v4 freeze; cases: both kits, generic kit, mid-chain with the link open, hitstun, combo dealt/taken, P2 view, bombs |
| `tests/tools/gen_schema_v4_fixtures.gd` | Create | Generator |
| `tests/smoke/schema_v4.gd` | Create | Dimension 149; `v4[0:136] == v3` on the same snapshots; one-hot (−1, 0, 1, 4 → zeros); bounds and finiteness; missing keys named; decode parity v3 == v4 over random vectors; registry 2/3/4 built in, stub 5, 99 unsupported; current still 3; fixture parity ≤ 1e-6; real-game snapshot carries the v4 keys |
| `tests/smoke/schema_v2.gd`, `schema_v3.gd` | Modify (registry stub lines only) | Stub version 4 → 5 (D13) |
| `tests/smoke/train_loads.gd` | Modify | `schema_version` 4 rows build; random kits differ across episodes and cover mirrors; `character` mode keeps scene kits; reward terms present |
| `tests/smoke/combat_harness.gd` | Modify | `BVS_HARNESS_KITS`, kit and side win share, new metrics |
| `tests/smoke/policy_eval.gd`, `policy_reel.gd` | Modify | `kits` argument; new metrics in the JSON |
| `training/bvs_training/schema.py` | Modify | `SCHEMAS[4]` (obs 149, fields from `v4_layout.json`), `TRAIN_VERSION = 4`, `SCHEMA_TAG` for 4 |
| `training/bvs_training/train.py`, `handshake.py` | Modify | `schema_version` 4, `kits` block, obs check |
| `training/bvs_training/export.py`, `sidecar.py`, `golden.py` | Modify | v4 obs_dim, sidecar, tags, golden length |
| `training/bvs_training/evaluate.py` | Modify | New metrics table |
| `training/bvs_training/harness.py` | Modify | New gates; per-matchup match counts; `--baseline` mode writing `reports/shield-baseline.{json,md}` |
| `training/configs/default.toml` | Modify | `[kits]`, `[reward]` new keys, `[acceptance]` new keys (`max_shield_raises_per_fighter_minute` filled from the baseline) |
| `training/reports/shield-baseline.json`, `.md` | Create | D15 measurement (committed before R1) |
| `training/README.md` | Modify | Schema 4 contract, kits, combo reward, gates, baseline, replay recipe |
| `odd/tasks/shield-spam.md` | Modify | T4 marked "moved into SDD change character-kits-combos" |

### S6: retrain, gates, flip

| File | Action | Description |
|---|---|---|
| `game/ai/models/bvs_default/model.onnx`, `bvs.json` | Replace | Gated v4 model and sidecar |
| `game/ai/schema/bvs_schema.gd` | Modify | `CURRENT_VERSION := 4` |
| `tests/fixtures/onnx/bvs_default_golden.json` | Regenerate | Default-model parity |
| `tests/smoke/hf_picker.gd`, `onnx_golden.gd`, `policy_match.gd`, `cpu_select.gd` | Modify | Current schema 4; schema 3 shows "Trained for an older version" |
| `training/reports/bvs_default-{eval,harness,training}.{md,json}` | Replace | Evidence, including every run of the time box |
| `training/reports/bvs_default-replay.mp4` | Create (binary) | 45 s model-vs-model replay, both kits |

On a gate failure at the time box, only the reports (marked FAIL) are committed and the user decides (D18).

### S7: gated remote

| File | Action | Description |
|---|---|---|
| `training/bvs_training/prepare_upload.py` | Modify | `--replay`, tags `bvs-schema-4`, `--space --confirm-space` (print-only) |
| `training/templates/model_card.md` | Modify | Schema 4 contract, kits, harness results |

## Interfaces / Contracts

```gdscript
# game/combat/attack_profile.gd (additions)
@export var startup_ticks: int = -1
@export var active_ticks: int = -1
@export var endlag_ticks: int = -1
@export var cooldown_ticks: int = -1        # -1: ticks(profile.punch_cooldown); 0: actionable at swing end
@export var link_window_ticks: int = 0      # chain steps only
@export var hitstun_ticks: int = -1         # -1: global formula on the final knockback
@export var hitstun_kb_growth: float = 0.0  # ticks per px/s of final knockback (with hitstun_ticks >= 0)
@export var hitstop_scale: float = 1.0
## {startup, active, endlag, cooldown} in ticks; -1 fields derive from the legacy profile timing.
func resolved_frames(profile: FighterProfile, duration_override: float = -1.0) -> Dictionary

# game/player/fighter_profile.gd (additions)
@export var kit_id: int = -1                 # -1 generic, 0 Rafael, 1 Matilde, 2-3 reserved
@export var kit_name: StringName = &"default"
@export var jab_chain: Array[AttackProfile] = []
@export var air_jab_chain: Array[AttackProfile] = []
@export var neutral_single: AttackProfile    # null: legacy neutral from punch_* fields
@export var attack_buffer_ticks: int = 6
@export var launcher_followup: StringName = &"none"   # CPU hint: &"none" | &"air_jab"

# game/combat/hit.gd (additions)
var attack: AttackProfile                    # null for food, bomb, ledge
var hitstop_scale: float = 1.0

# game/combat/combo_rules.gd
class_name ComboRules extends Resource
@export var hard_cap_hits: int = 6
@export var decay_from_hit: int = 4
@export var hitstun_decay: float = 0.8
@export var knockback_growth: float = 1.1
@export var time_cap: float = 1.5            # seconds (90 ticks)
@export var min_combo_stun_ticks: int = 4
@export var cap_launch_knockback: Vector2 = Vector2(260.0, -360.0)

# game/combat/combo_tracker.gd
class_name ComboTracker extends RefCounted
class Scale:
	var hits: int = 0
	var kb_mult: float = 1.0
	var stun_mult: float = 1.0
	var stun_cap_ticks: int = 1 << 30
	var capped: bool = false
var rules: ComboRules
var hits: int
var damage: float
var elapsed_ticks: int
var attacker: Fighter
func setup(owner_fighter: Fighter, combo_rules: ComboRules = null) -> void
func register(hit: Hit, in_hitstun: bool) -> Scale   # emits owner.combo_updated when counted
func tick(state_name: String) -> void                # elapsed++, ends when state != "Hurt"
func end() -> void                                   # emits owner.combo_ended(hits, damage, attacker) when hits > 0
func reset() -> void                                 # silent
func is_active() -> bool

# game/player/player.gd (additions)
signal combo_updated(hits: int, damage: float, attacker: Fighter)
signal combo_ended(hits: int, damage: float, attacker: Fighter)
const ATTACK_BUFFER_STATES: Array[String] = ["Idle", "Run", "Jump", "Fall", "Punch"]
@export var kit_from_character: bool = true
var combo: ComboTracker
var attack_cooldown_ticks: int = 0
var attack_buffer_ticks: int = 0
var buffered_attack_aim: FighterIntent.Aim = FighterIntent.Aim.NEUTRAL
func set_profile(p: FighterProfile) -> void
func consume_attack_buffer() -> FighterIntent.Aim
# Snapshot additions (fighter): kit_id:int, chain_step:int, link_open:bool,
#   hitstun_left:float (s), combo_hits:int (as victim), combo_damage:float

# Punch state (additions)
func cooldown_left() -> float               # seconds until a punch may start
func chain_step() -> int                    # 0 outside a chain, 1..N during step N
func chain_length() -> int
func link_open() -> bool
func accepts_chain_press() -> bool          # non-final chain step and tick <= link_close

# Hurt state (additions)
var pending_attack: AttackProfile
var pending_combo: ComboTracker.Scale
func ticks_left() -> int

# game/player/profiles/fighter_kits.gd
class_name FighterKits extends RefCounted
const PATHS := {&"rafael": "res://game/player/profiles/rafael_profile.tres",
		&"matilde": "res://game/player/profiles/matilde_profile.tres"}
static func for_character(ui: CharacterUI) -> FighterProfile
static func by_id(kit_id: int) -> FighterProfile
static func ids() -> PackedInt32Array
static func random(rng: RandomNumberGenerator) -> FighterProfile

# game/player/controllers/cpu_difficulty.gd (additions)
@export_range(0.0, 1.0) var chain_chance: float = 0.75
@export var chain_press_delay: float = 0.05
@export_range(0.0, 1.0) var launcher_followup_chance: float = 0.0

# game/ai/schema/bvs_schema_v4.gd
class_name BvsSchemaV4
const VERSION := 4
const OBS_DIM := 149
const ACTION_REPEAT := 4
const LOGITS := 21
const KIT_SLOTS := 4
const MAX_CHAIN := 3
const COMBO_SCALE := 6.0
const HITSTUN_SCALE := 1.0
const KIT_OFFSET := 136           # self 136-139, opponent 140-143
const CHAIN_OFFSET := 144
const LINK_OFFSET := 145
const OPP_HITSTUN_OFFSET := 146
const COMBO_DEALT_OFFSET := 147
const COMBO_TAKEN_OFFSET := 148
```

Train config contract (`BVS_TRAIN_CONFIG`) additions: `"schema_version": 4` and `"kits": {"mode": "random", "seed": 1}`.

Harness contract additions:
- Environment: `BVS_HARNESS_KITS` (`character` | `rm` | `rotate4`, default `rm`).
- Per-matchup JSON adds: `shield_raises_per_fighter_minute`, `combo_histogram`, `max_combo`, `multi_hit_combos`, `max_hurt_seconds`, `hurt_over_cap`, `combo_damage_by_kit`, `damage_by_kit`, `kit_win_share`, `side_win_share`.

## Testing Strategy

| Layer | What to Test | Approach |
|---|---|---|
| Unit (synthetic) | `ComboTracker` scaling (decay, growth, time cap, hard cap, bomb reset); `AttackProfile.resolved_frames` legacy derivation; v4 `build_obs` layout, bounds, one-hot, v3 prefix parity; v4 decode parity; registry | `combo_safeguards.gd`, `frame_data.gd`, `schema_v4.gd` over synthetic profiles and snapshots |
| Integration (real `game.tscn`) | Buffer and tick timers; chains (one press per step, hold, early or late press); frame-advantage probe; infinite probe; HUD counter; kit assignment and `set_profile`; Matilde launcher prototype; CPU chain rates; training kit randomization | `attack_timing.gd`, `frame_data.gd`, `combo_safeguards.gd`, `hud.gd`, `kits.gd`, `cpu_combos.gd`, `train_loads.gd`, scripted through `smoke_util.IntentController` |
| Time-scale independence | Swing and hitstun tick counts with `Engine.time_scale` 0.3 vs 1.0 | `attack_timing.gd`, counting `Engine.get_physics_frames()` deltas |
| Regression | Existing suite on the baseline profile (`spawn_game(kits=false)`): `hit_rules`, `combat`, `smash_moves`, `shield*`, `air_punch`, `match_flow`, `cpu_*`, `keyboard_playtest`, `match_e2e`, `schema_v2`/`schema_v3` (frozen parts unedited), `onnx_golden`, `policy_match`, `hf_picker` | Updated only where behavior intentionally changes (±1 tick, registry stub, S6 current-version flip) |
| Parity | v4 obs fixture ≤ 1e-6; v4 default-model ONNX golden ≤ 1e-4 with exact argmax | `schema_v4.gd`, `onnx_golden.gd`, `golden.py` |
| Acceptance | Baseline (D15), eval, harness gates (D16), 172 matches, both kits, both sides | `harness.py --baseline`, `evaluate.py`, `harness.py` |

`openspec/config.yaml` has `strict_tdd: false` and no workspace runner. Running Godot, the smoke suite and training is authorized for this change (proposal), and execution belongs to apply and verify. The user's global rule against running test suites locally still applies to phases without that authorization.

## Threat Matrix

| Boundary | Applicability | Design response | Planned RED tests |
|---|---|---|---|
| Documentation-like paths | N/A: no executable classification of files is added | - | - |
| Git repository selection | N/A: no git automation is added | - | - |
| Commit state | N/A: no tooling commits | - | - |
| Push state | N/A: no tooling pushes | - | - |
| PR commands | N/A: no PR automation | - | - |

Process note, outside the matrix:
- `harness.py` keeps its existing list-form `subprocess.run` launch of Godot (no shell, fixed flags). The only new inputs are environment variables (`BVS_HARNESS_KITS`) and a `--baseline` output path.
- The MP4 conversion is a documented manual `ffmpeg` command, not tooling code.
- Remote operations stay print-only behind per-destination confirmation (D19).

## Migration / Rollout

- **S1-S4 interim**: the bundled v3 model still loads and plays. It sees kits only through changed dynamics. `self_cd_punch` keeps its meaning (D1). This is accepted on the branch.
- **S5**: v4 is registered but not current. Training targets v4 through config. The picker is unchanged (schema 3 is still current).
- **S6 flip** (one commit): model, `bvs.json`, default golden, `CURRENT_VERSION = 4`, test migrations, reports and replay. After the flip, `bvs-schema-3` Hub models show "Trained for an older version" (accepted).
- **Gate failure at the time box**: STOP and ask (b) or (c), per the Resolved Decision. (c) is consistent because S5 does not flip.
- **Rollback**:
  - Revert S6 to return to the v3 model on top of S1-S5.
  - Revert S5 together with S6.
  - S3 must not be reverted without S2 and S4 (chains without safeguards are infinite).
  - Balance problems are fixed with data (`.tres`, `combo_rules.tres`).
- **Remote** (S7): only after merge and explicit user confirmation for each destination. The previous HF revisions remain in the repo history.

## Open Questions

- [ ] **Invulnerability timer scope (D2)**: the proposal lists post-hitstun invulnerability among the timers moving to ticks. The design keeps the existing Fighter timer, because it is off the link path and `ledge.gd` reads `_invuln_timer`. The spec should say "Punch and Hurt timers are tick-based" without the invulnerability timer. Confirm, or accept a two-line `ledge.gd` update if ticks are required.
- [ ] **Frozen-check wording (D13)**: `schema_v2.gd`/`schema_v3.gd` register a stub as version 4. The spec should allow the stub version to move to 5 while the layout, obs, decode and fixture checks stay unedited.
- [ ] **`CURRENT_VERSION` timing (D12)**: the proposal says `BVS_SCHEMA_VERSION` becomes 4 in S5. The design flips it in S6 with the bundled model, so commits stay green and fallback (c) stays real. The spec should phrase the requirement on the final state.
- [ ] **"Neutral single" meaning (D5)**: interpreted as the grounded neutral charged past the tap threshold, and the neutral of a kit without a chain. Policies and the CPU never charge, so only humans reach it. Confirm in spec.
- [ ] **Kit balance numbers (D10)**: initial values are tunable data. Link slack and the launcher window are verified by probes, not by this document.
