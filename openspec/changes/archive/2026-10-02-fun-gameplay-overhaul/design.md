# Design: Fun Gameplay Overhaul

## Technical Approach

The work lands in five ordered slices (S1–S5), as the proposal describes. Each slice can be reverted on its own, from S5 down.

1. **S1 – Controller seam.** A per-frame `FighterIntent` value object separates where input comes from from how the fighter acts on it.
   - `Fighter` owns one `FighterController` (a `RefCounted`, not a node) and samples it exactly once at the top of `_physics_process`.
   - Every `Motion` state reads only `owner.intent`, through shared helpers. The duplicated human (`_state_input` events) and AI (`process_ai_transitions` polling) paths are deleted.
   - `PolicyController` adapts the existing `PlayerAIController` float fields. `sync.gd` and the `AIController2D` node stay exactly where they are, and `get_obs()` and `get_action_space()` are not touched.
2. **S2 – Movement and hit rules.** Movement and hit tuning move into one `FighterTuning` resource. The FSM gains:
   - jump kinds (ground, coyote, air), short hop, and a jump buffer;
   - air actions and air dash;
   - a punch hitbox that is placed by facing, so the owner is never teleported;
   - hitstun that scales with knockback, followed by post-hit invulnerability;
   - a timer-based invulnerability lifecycle (F4) and a token-serialized hit-stop (F5).
3. **S3 – CPU and selection.** A scripted CPU (`ScriptedController`) is a utility loop that reads the snapshot accessors and runs on a reaction-interval tick. Difficulty is a `CpuDifficulty` resource. Character select builds a `ControllerConfig` per player, and `SceneManager` keeps it for rematches.
4. **S4 – Match flow and fixes.** `game.gd` gets an explicit phase machine (countdown, then playing, then optional sudden death, then over). This slice also adds the pause toggle, instant rematch, and the fixes F2, F3, and F8 (dedicated collision layers), plus SFX event pitch bands.
5. **S5 – Smash moves and camera.**
   - `Punch` gains a charge phase and per-direction `AttackProfile`s.
   - A new `Recovery` air state is added.
   - A charge-glow `Sprite2D` uses the existing glow texture.
   - `P{N}_up`/`P{N}_down` input actions are added.
   - A `MatchCamera` script on the existing game `Camera2D` drives only `position`/`zoom`, with a manual clamp.
   - The bot gets a small extension.

The design follows the specs in `openspec/changes/fun-gameplay-overhaul/specs/*` (fighter-control, fighter-movement, combat-hits, cpu-opponent, match-flow, food-fight-items, gameplay-state-snapshot, smash-moves, match-camera).

### Baseline facts that drive the design (verified in code)

| Fact | Evidence | Consequence |
|------|----------|-------------|
| `PlayerAIController._ready()` overrides `control_mode` (ONNX if `user://Agent{N}.onnx` exists, else HUMAN) and does not call `super._ready()`. | `scripts/AIController/player_ai_controller.gd:11-22`; `AIController2D._ready` does `add_to_group("AGENT")` (`addons/godot_rl_agents/controller/ai_controller_2d.gd:36-37`). | In Godot 4 the parent `_ready` is not chained automatically, so agents never join `AGENT`, and `train.tscn`'s `control_mode = 2` is overwritten with HUMAN. **TRAINING is effectively broken at baseline.** S1 restores it as a side effect of removing the auto-ONNX override (see Decision 3). |
| Nodes run `_physics_process` parent-first. | Godot tree order: `Fighter` runs before its `StateMachine` child. | Intent sampled in `Fighter._physics_process` is visible to all states in the same frame. |
| `PunchArea` has two always-on shapes (left at x=45.5, right at x=-55). | `game/player/player.tscn:189-197` | Today a punch hits on both sides. The owner teleport (`move_punch_offset`) is redundant. Replace both with one mirrored shape. |
| `train.tscn` overrides `Punch.punch_distance/punch_duration/punch_cooldown`, `Hurt.knockback_force` (a property that does not exist), and sets `available_actions = []` on Jump/Fall/Punch/Hurt/Protect/Shoot. | `train.tscn:35-61` | Unknown overridden properties are tolerated (the `knockback_force` precedent), but we keep the `punch_distance` name anyway. The `[]` overrides keep TRAINING without air actions, which matches the baseline semantics. |
| The game `Camera2D` has `anchor_mode = 0` (top-left) at the origin. HUD lives in the `PlayerUI` CanvasLayer (inside `player.tscn`) and the `UI` CanvasLayer (layer 2). | `game/game.tscn:309-340`, `player.tscn:209` | Camera zoom never affects the HUD. The follow camera must switch to drag-center at runtime, and only outside training. |
| `Pause` already has `process_mode = 3` (ALWAYS). Its `_input` only ever sets `paused = true`. | `game/ui/pause/pause.tscn:7`, `pause.gd:9-12` | The Esc toggle is a logic fix only. |
| Stage geometry: floor shape center (397, 600), 500x66 → x 147..647, top y 567. Platforms are 150 wide, top y ≈ 420, centered at x 230 and 560. | `game/game.tscn:239-279` | The bot and the snapshot read the stage rect from the `Floor` shape at runtime. Nothing is hardcoded. |
| P1 = A/D/W/S/F/G and P2 = arrows/J/K. W and Up arrow are jump; S and Down arrow are protect. | `project.godot:56-115` | The new up/down actions need free keys (see Decision 17). |

## Architecture Decisions

### Decision 1: Intent as a `RefCounted` value, sampled once per physics frame by `Fighter`

**Choice**: `FighterIntent extends RefCounted` holds plain fields. `Fighter._physics_process` does `intent = controller.sample(delta)` (or `FighterIntent.new()` while `controls_locked`) before the movement bookkeeping and `move_and_slide()`. States read `owner.intent`.
**Alternatives considered**:
- Intent as a Dictionary: no typing, and typos fail silently.
- Controllers as Nodes in `player.tscn`: they would need scene edits that `train.tscn` inherits, plus `_process` ordering concerns.
- States polling `Input` directly: this is the current split we are removing.
**Rationale**: Typed fields are checked by the GDScript analyzer. Parent-first physics order guarantees a single sample per frame shared by every state (spec: "Single intent sample per frame"). A `RefCounted` controller needs no scene changes, so `train.tscn` is untouched.

### Decision 2: Fixed action priority in code, gated by the existing `available_actions`

**Choice**: `Motion.handle_actions()` walks the fixed priority `["recovery", "dash", "jump", "punch", "protect", "shoot"]`. It considers only the names present in the state's `available_actions`, and only those whose target state's `can_enter()` is true. It emits at most one transition and returns `true` if it did.
**Alternatives considered**:
- Iterating `available_actions` in array order: priority would depend on per-node scene data, and `train.tscn` overrides would reorder behavior.
- Hardcoding per-state transitions with no `available_actions`: this breaks the `train.tscn` `[]` overrides that keep training free of air actions.
**Rationale**: The relative order `jump > punch > protect > shoot` is exactly the baseline AI order (`process_ai_transitions` iterated `["jump","punch","protect","shoot"]`), so policy semantics are preserved. `available_actions` keeps working as the per-state, per-scene gate, so the `[]` overrides in `train.tscn` still mean "no actions here".

### Decision 3: Explicit controller kind, and `PlayerAIController` no longer touches `control_mode`

**Choice**:
- `PlayerAIController._ready()` becomes `super._ready()` only. The auto-ONNX logic and the prints are removed.
- `Fighter` exports `controller_kind: AUTO | HUMAN | CPU | POLICY`, default `AUTO`. `AUTO` resolves in `Fighter._ready()`:
  - if `ai_controller_2d.control_mode` is `TRAINING`, `ONNX_INFERENCE`, or `INHERIT_FROM_SYNC`, use a `PolicyController`;
  - otherwise use a `HumanController`.
- `SceneManager.play_game(c1, c2, cfg1, cfg2)` overrides this after `add_child` with `fighter.set_controller(cfg.build(fighter))`. For the HF option, `cfg.build` also sets `ai_controller_2d.control_mode = ONNX_INFERENCE` and `onnx_model_path`, which is what the old auto path did, but now only when it is explicitly selected.

**Alternatives considered**:
- Adding a `SCRIPTED` value to `sync.gd`'s `ControlModes`: this edits a vendored addon, and Sync is absent from `game.tscn` anyway.
- Keeping auto-ONNX but gating it on a flag: the ghost-AI bug would survive in any path that forgets the flag.

**Rationale**:
- `player.tscn` sets `control_mode = 1` (HUMAN), so `game.tscn` resolves to Human, which fixes the ghost AI.
- `train.tscn` sets `control_mode = 2`, which now survives `_ready` and resolves to Policy.
- With `super._ready()`, agents join `AGENT`, so `sync.gd` actually finds the training agents. This restores TRAINING; it is flagged under Risks for an editor check.
- Joining `AGENT` in `game.tscn` is harmless because there is no Sync node there.

### Decision 4: `PolicyController` keeps level-triggered semantics, with two guards

**Choice**: Each value is thresholded at `> 0.5`:
- `move_x = right - left`;
- `attack_pressed = attack`, `attack_held = false` (an instant tap, so the S5 charge never triggers);
- `throw_pressed = shoot`;
- `block_pressed = block_held = protect`;
- `dash_pressed = false`, `aim = NEUTRAL`, `special_pressed = false`;
- `jump_held = jump`;
- `jump_pressed = jump and (rising_edge or fighter.is_on_floor())`.

**Alternatives considered**:
- Pure level for `jump_pressed`: a held jump would fire the double jump on the frame after the ground jump.
- Pure edge: this changes the baseline "hold jump = re-jump on landing" behavior that the existing model was trained on.

**Rationale**: This preserves baseline policy behavior on the ground and prevents an accidental instant double jump. The S5 fields stay neutral (spec: "Policy controller adapter").

### Decision 5: Movement bookkeeping lives on `Fighter`; tuning lives in `FighterTuning`

**Choice**:
- `Fighter` owns `jumps_left`, `air_dash_available`, `recovery_available` (S5), `coyote_timer`, `jump_buffer_timer`, and `_coyote_blocked`. It ticks them in `_tick_movement(delta)` from `is_on_floor()`, which is the result of the previous `move_and_slide`.
- Landing resets jumps, air dash, recovery, and coyote. A ground jump sets `coyote_timer = 0` and `_coyote_blocked = true` until the fighter is seen airborne. This prevents a ground jump plus a coyote jump plus a double jump (a triple jump).
- All numbers live in `FighterTuning extends Resource`, with script defaults. `Fighter` has `@export var tuning: FighterTuning`. If it is null, `_ready` assigns `FighterTuning.new()`, so no `.tres` file is required.

**Alternatives considered**:
- Constants on `Motion`: these are duplicated per state node and are not inspector-tunable as one set.
- Counters in `PlayerStateMachine`: this works, but the snapshot accessor and the bot already read `Fighter`.

**Rationale**: There is one tunable place, the snapshot reads its fields directly, and `train.tscn` needs no edits.

### Decision 6: Jump resolution as a single `Fighter.resolve_jump()` query

**Choice**: Steps:
- `jump_buffer_timer` is refreshed on `intent.jump_pressed`.
- Ground states call `resolve_jump()`. It returns `GROUND` if `buffer > 0` and (`on_floor` or `coyote > 0`), consuming the buffer and the coyote time.
- Air states (Jump, Fall, Dash-air) return `GROUND` when coyote is still alive. Otherwise they return `AIR` only on a fresh `intent.jump_pressed` with `jumps_left > 0`, decrementing it.
- The buffer otherwise survives, so it fires on landing.
- `Jump._enter()` applies `jump_velocity` or `double_jump_velocity` by kind.
- Short hop: in `Jump._update`, the first frame with `!intent.jump_held and velocity.y < 0` multiplies `velocity.y *= jump_cut_multiplier` once.

**Alternatives considered**: Two separate states (`Jump` and `DoubleJump`) duplicate code and animation wiring.
**Rationale**: This satisfies the coyote, coyote-expired, buffered, and double-jump scenarios with one rule set.

### Decision 7: Punch hitbox placed by locked facing, active-window polling, one hit per target

**Choice**:
- `PunchArea` keeps a single `CollisionShape2D`; `CollisionShape2D2` is deleted.
- On punch fire, `Punch` locks `_facing = owner.facing`, which is the sign toward the enemy (the same rule as today's `flip_h`). It sets `shape.position = Vector2(profile.hitbox_offset.x * _facing, profile.hitbox_offset.y)`.
- During `punch_active_time`, it polls `punch_area.get_overlapping_bodies()` in `_update` and calls `Combat.apply_hit` once per `Fighter` in a `_hit_targets` set.
- The `body_entered` connect/disconnect churn and `move_punch_offset` are removed.
- The `punch_distance` export is kept and reused as the neutral hitbox reach, because `train.tscn` overrides it.

**Alternatives considered**:
- Negative `scale.x` on the Area2D: Godot discourages negative scale on collision objects.
- Keeping two shapes and toggling `disabled`: this works, but needs two shapes per direction once S5 adds profiles.
- A `PhysicsDirectSpaceState2D.intersect_shape` query: more code, and it bypasses the editor-visible area.

**Rationale**: Moving a shape takes effect at the next physics step, so polling over a short active window is correct where an immediate `get_overlapping_bodies()` would be stale. The `_hit_targets` set prevents multi-hits. The owner's position is only changed by physics (spec: "No teleport").

### Decision 8: Hitstun scales with knockback; post-hit invulnerability is granted only when hitstun ends naturally

**Choice**:
- `Hurt` computes the final knockback as it does today (sign from relative position, times `get_knockback_scale()`).
- It sets `hitstun = clamp(hitstun_base + |kb| * hitstun_per_knockback, hitstun_min, hitstun_max)`.
- It applies `gravity * hurt_gravity_scale` and keeps x momentum (no air control).
- In `_on_hurt_finished()` it calls `owner.grant_invulnerability(post_hit_invulnerability)` and then `exit_to_neutral()`.
- Re-entering Hurt (a hit during hitstun) goes through `_exit` and `_enter`, but does not grant invulnerability, so combos inside hitstun remain possible.
- `Hurt._enter` also sets `owner.recovery_available = true` (S5). `Punch._exit` hides the glow (S5).

**Alternatives considered**:
- A fixed 0.5 s hitstun: ring-outs would not scale with %.
- Granting invulnerability in `_exit`: a Hurt to Hurt re-entry would start invulnerability mid-combo, and the second hit's stun would outlive it.
- Invulnerability during hitstun: this removes all combos.

**Rationale**: Hitstun plus invulnerability (0.3 + 0.5 = 0.8 s) exceeds the punch cooldown (0.7 s), so a stun-lock by repeated punches is impossible. Hitstun reaches about 0.7 s at 200%, which keeps ring-outs at high damage.

### Decision 9: Invulnerability lifecycle on a `Timer` node child plus a node-bound tween (F4)

**Choice**:
- `Fighter._ready` creates `_invuln_timer` (a one-shot `Timer` child).
- `grant_invulnerability(duration, blink := true)` sets `is_invulnerable = true` and calls `_invuln_timer.start(max(remaining, duration))`. If `blink` is set, it kills `_blink_tween` and recreates it with `create_tween()` (bound to the Fighter, looping).
- The timer's `timeout` sets `is_invulnerable = false`, kills the tween, and sets `animated_sprite_2d.visible = true`.
- `reset_player()` stops both.
- `_respawn()` calls `grant_invulnerability(RESPAWN_INVULNERABILITY)`.

**Alternatives considered**:
- Keeping `await get_tree().create_timer()` with a generation counter: still an unbound coroutine that ignores pause.
- Keeping `get_tree().create_tween()`: unbound, and it survives the node being freed.

**Rationale**: A node-owned timer and tween pause with the game and die with the node. `max(remaining, duration)` makes a new respawn honor its full duration and means an old timer can never end invulnerability early (spec F4 scenarios).

### Decision 10: Token-serialized hit-stop (F5)

**Choice**: `Combat` gets `static var _hit_stop_token := 0`.
- `_trigger_hit_stop(duration, scale)` increments the token, captures it in a local, sets `Engine.time_scale = scale`, and starts the existing real-time timer. That timer's callback restores `Engine.time_scale = 1.0` only if `Combat._hit_stop_token == captured`.
- `Combat.cancel_hit_stop()` increments the token and restores 1.0. `Game._exit_tree()` calls it when not training.

**Alternatives considered**:
- A max-end timestamp with periodic checks: more state.
- A hit-stop autoload node: a new autoload for about 10 lines.
- A reference count: one extra decrement bug and the scale is stuck.

**Rationale**: Exactly one pending callback can restore the time scale (the latest one), so overlapping stops always end at 1.0. Training still skips hit-stop entirely, so Sync's speed-up `time_scale` is never touched.

### Decision 11: Protect becomes hold-to-block (ground and air), capped by `block_duration`

**Choice**: Protect lasts while `intent.block_held` is true, up to `block_duration` (default 1.0 s, still overridden by `train.tscn`). It applies gravity in the air and ends with `exit_to_neutral()`.
**Alternatives considered**: A fixed 1 s block on press, as today. The spec requires "blocks until released" for air block, and splitting ground and air semantics would confuse players.
**Rationale**: This is consistent and spec-compliant. The policy level-semantics (`block_held = protect > 0.5`) reproduce the old behavior closely.

### Decision 12: `can_enter()` gate replaces the re-entrant cooldown emit

**Choice**: `State.can_enter() -> bool` defaults to `true`. `Punch` and `Shoot` return `cooldown_timer.is_stopped()`. `Dash` returns `on_floor or owner.air_dash_available`. `Recovery` returns `owner.recovery_available` (S5). `handle_actions()` checks it before emitting.
**Alternatives considered**: Keeping `finished.emit("Idle")` from inside `_enter`. That triggers a nested `_change_state` during `_enter`, and in the air it would wrongly go to Idle.
**Rationale**: No nested transitions, and an air action on cooldown simply does nothing.

### Decision 13: CPU as a reaction-tick utility loop over snapshots

**Choice**: `ScriptedController` accumulates `delta`. Every `difficulty.decision_interval` it reads `game.get_state_snapshot()` (which includes both fighters) and picks one plan by priority:

1. **RECOVER**: if off-stage (x outside the stage rect by more than 10 px, or y below the stage top while airborne), move toward the stage center. Use the double jump on a fresh press while falling. With S5, at Normal/Hard, if no jumps are left and recovery is available, emit `special_pressed`.
2. **DEFEND**: if the enemy is in `Punch` within range, or a projectile is closing within 160 px, roll `block_chance` once per threat and hold block for up to `block_hold`.
3. **THROW**: if holding food, roughly level with the enemy (|dy| < 80), and within `throw_range`, roll `throw_chance`.
4. **PICKUP**: if not holding food, a food item is within `pickup_seek_distance`, and it is closer than the enemy, walk to it and press throw when within 60 px.
5. **ATTACK**: if in punch range (|dx| < 90, |dy| < 60), roll `action_accuracy`. On success, tap punch. On failure, whiff by punching from 1.6x range on a later tick. With S5, at Normal/Hard, aim UP when the enemy is above, DOWN in the air above the enemy, and SIDE when the enemy is near an edge with damage above 60%.
6. **APPROACH**: walk toward the enemy and stop at `approach_stop_distance`. Full-hop when the enemy is on a platform above (dy < -100, |dx| < 160). Never walk past the stage edge while grounded.

Between ticks, held flags (`move_x`, `block_held`, `jump_held`) persist. Pressed flags are emitted for one frame only, through a pending-press latch, and are released for at least one frame before the next press. `attack_held` is always false (no charge).
**Alternatives considered**:
- A behavior tree or GOAP: over-engineered for six behaviors.
- Feeding `PlayerAIController` floats from a heuristic, as exploration suggested: this couples the bot to the RL action space we must not freeze.
- A reaction delay via a ring buffer of delayed snapshots: more realistic, but more code. The decision interval gives the same "slower Easy" feel.

**Rationale**: The bot emits only intent (spec), proves that the snapshot is useful, and its difficulty is pure data.

### Decision 14: Difficulty as a `CpuDifficulty` Resource with code presets

**Choice**: `CpuDifficulty extends Resource` holds exported fields and `static func preset(level) -> CpuDifficulty` for Easy, Normal, and Hard. `ControllerConfig.difficulty_resource` (optional) overrides the preset, so a designer can drop in a `.tres` with no script change.
**Alternatives considered**: Three hand-authored `.tres` files only. These are unverifiable statically without the editor, and their UIDs are created by the editor.
**Rationale**: The spec's "data-driven" requirement is met (resource fields, an optional `.tres` override), and the defaults are reviewable in code.

### Decision 15: Match phase machine in `game.gd`

**Choice**: `enum Phase { COUNTDOWN, PLAYING, SUDDEN_DEATH, OVER }`.
- `_ready`:
  - when training, start immediately (`timer.start()`, `food_spawner.start()`, no lock), keeping today's behavior;
  - otherwise lock both fighters and run the countdown: "3", "2", "1" for `countdown_step` each, then "GO!" for 0.5 s. It uses `get_tree().create_timer(step, false)` (`process_always = false`), so pausing freezes the countdown with no skipped digits.
- After GO, it unlocks the fighters, starts the timer, and starts the spawner.
- Timeout:
  - training: reset, as today;
  - stocks differ: the forced winner is the one with more stocks, then OVER;
  - equal stocks: SUDDEN_DEATH. Both fighters go to `set_stocks(1)`, the timer stops, `TimerLabel` is hidden, and "SUDDEN DEATH" shows on the countdown label for 1 s. Damage is unchanged.
- `_on_player_defeated` is guarded by `phase != OVER`, so a double KO on the same frame ends the match once.
- `game_over` access is null-guarded (F3).

**Alternatives considered**:
- Keeping the % tiebreak and entering sudden death only on equal stocks and equal %: equal % almost only happens at 0/0, so sudden death would be dead code. The spec defines the tie as equal stocks.
- A countdown driven by a tween: tweens are fine, but timers make the pause semantics explicit.

**Rationale**: One place owns match state, and the training path stays byte-for-byte equivalent in behavior.

### Decision 16: Rematch via a stored `last_match` in `SceneManager`

**Choice**: `play_game(c1, c2, cfg1 := null, cfg2 := null)` stores `last_match = {c1, c2, cfg1, cfg2}`. `rematch()` replays it. Game over's existing Replay icon button calls `SceneManager.rematch()`. A new text Button, "Characters", opens character select. Both unpause first.
**Alternatives considered**: Reloading the current scene. That loses the post-`add_child` character and controller injection.
**Rationale**: Same characters and controllers, through the same code path as a fresh match.

### Decision 17: S5 input bindings and the recovery chord = `up` + `punch` while airborne

**Choice**: New actions (physical keys):
- `P1_up = E` (69) and `P1_down = C` (67), above and below `D` in the WASD cluster;
- `P2_up = I` (73) and `P2_down = Comma` (44), above and below the J/K cluster.

None of these duplicate an existing binding (A, D, W, S, F, G, arrows, J, K) or a `ui_*` default. `HumanController` maps them as follows:
- `aim = UP` if up is held, `DOWN` if down is held, `SIDE` if `move_x != 0`, otherwise `NEUTRAL`.
- `special_pressed = attack_pressed and aim == UP`.

The FSM decides what the chord means:
- in air states, `special_pressed` with `recovery_available` gives Recovery;
- in air states without recovery available, the same input falls through to a normal air punch (never a dead input);
- on the ground, `special_pressed` is ignored and `attack_pressed` with `aim == UP` is an up-punch (which can be charged).

**Alternatives considered**:
- `up` + `shoot` while airborne (the other chord in the proposal): `shoot` is pickup and throw. An air throw of held food upward, or an air pickup near falling food, would collide with recovery, so one of two frequent actions would have to lose. It also splits the "attack family" across two buttons.
- `up` + `punch` with an up-air attack as well: one chord cannot mean both; recovery wins in the air, which matches the Smash up-special read.
- Remapping W/S as up/down and moving jump/protect: this breaks the spec "existing bindings preserved".

**Rationale**:
- `up + punch` never conflicts with food handling.
- It keeps every directional move on one button family (punch).
- The chord is resolved only in `HumanController`. The intent shape stays controller-agnostic, so the bot and policies set `special_pressed` directly.

The trade-off is that there is no up-air attack; that is accepted. Key ergonomics on a shared keyboard are flagged for playtest. The keys are Project Settings data, so they can be rebound with no code change.

### Decision 18: Charge as a phase of `Punch`, firing on release; the tap threshold decides tap vs smash

**Choice**: `Punch` phases are `WINDUP → (CHARGING) → ACTIVE → RECOVERY`.
- **Ground punch with `attack_held` at entry**: it waits in WINDUP or CHARGING with friction until `!intent.attack_held`.
  - If held for less than `tap_threshold` (0.15 s), charge = 0 and it is a normal punch.
  - Otherwise `charge = clamp((t - tap_threshold) / (max_charge_time - tap_threshold), 0, 1)`.
  - There is no auto-release; the charge caps at 1.0 (spec: a 3 s hold gives 1.0).
- **Air punch, or `attack_held == false` at entry** (policy or bot): it fires immediately.
- On fire:
  - the aim is sampled now;
  - the profile is chosen as up, down-ground, down-air, side, or neutral;
  - `damage = profile.damage * lerp(1, charge_damage_max, charge)`;
  - `kb = profile.knockback * lerp(1, charge_knockback_max, charge)`;
  - `owner.last_attack_direction` is set, and the cooldown starts.
- Glow: `owner.set_charge_visual(charge)` while charging; `_exit` always calls `set_charge_visual(-1)` to hide it.

**Alternatives considered**:
- Fire on press and add a separate smash input: there is no free key, and it is not in scope.
- An auto-fire at max charge: contradicts the spec's cap scenario.

**Rationale**: A tap costs only its physical hold time (under 0.15 s). Policy and bot paths stay instant, so training semantics and the "bot never charges" rule hold by construction.

### Decision 19: Recovery as its own air state

**Choice**: `Recovery extends Motion`.
- `_enter` sets `owner.recovery_available = false`, `velocity.y = recovery_velocity`, and `velocity.x = move_x * recovery_drift`. It emits animation `"jump"` explicitly and calls `Sfx.play_event(&"recovery")`.
- `_update` applies gravity and reduced air control, and switches to Fall when `velocity.y >= 0`.
- `available_actions = []`, so nothing interrupts the burst.
- It has no hitbox and is independent of the double jump.

**Alternatives considered**: Reusing `Jump` with a kind flag. Recovery has a distinct availability rule, distinct reset rules, and no actions during the rise.
**Rationale**: The rules (once per airtime, reset on landing or on hit) are expressed in exactly one place, `Fighter` plus `can_enter`.

### Decision 20: Follow camera with a manual clamp; never touch `offset`, never run in training

**Choice**: `game/camera/match_camera.gd` is attached to `game.tscn`'s `Camera2D`.
- `_ready`: if `get_parent().training`, call `set_process(false)` and return with no property changes. Otherwise set `anchor_mode = DRAG_CENTER` and `position = bounds.get_center()`.
- `_process`:
  1. Take the positions of fighters with `stocks > 0`, clamped into `bounds`.
  2. Compute their midpoint plus `vertical_bias`.
  3. Compute `extent = (max - min) + margin` and `target_zoom = clamp(min(bounds.size.x / extent.x, bounds.size.y / extent.y), min_zoom (1.0), max_zoom)`.
  4. Smooth exponentially: `1 - exp(-speed * delta)`.
  5. Clamp the center to `[bounds.position + half, bounds.end - half]` with `half = viewport_size / (2 * zoom)`.
  6. Write `position` and `zoom` only.
- `bounds` defaults to `Rect2(0, 0, 800, 600)`, the background/stage view and today's full framing, which lies inside the blast zone (-150..950 by ..750).
- Hurt's shake keeps writing `offset`. S5 adds a final `offset = Vector2.ZERO` reset at the end of the shake tween; today it leaves a residual offset.

**Alternatives considered**:
- The built-in `limit_*`: their interaction with `offset` and with smoothing is engine-version-sensitive, and could swallow the shake at zoom 1.0.
- `position_smoothing_enabled`: it smooths position but not zoom, and fights the manual clamp.
- Clamping to the blast zone: it would show past the background art (the spec says "never shows past bounds").

**Rationale**: The clamp is deterministic and statically reviewable. At zoom 1.0 the view is exactly today's framing. Shake and HUD are untouched. Train rows' cameras are left byte-identical at runtime.

### Decision 21: Dedicated physics layers (F8)

**Choice**: Layer 1 `world` (stage, unchanged), layer 2 `fighters`, layer 3 `food`.

| Node | collision_layer | collision_mask |
|------|-----------------|----------------|
| `Fighter` (CharacterBody2D) | 2 | 1 + 2 (stage and the other fighter, preserving body pushing) |
| `PunchArea` | 0 | 2 |
| `PickupArea` | 0 | 4 (layer 3) |
| `FoodPickup` | 4 | 1 |
| `FoodProjectile` (Area2D) | 0 | 1 + 2 |

Layer names are added under `project.godot [layer_names]`.
**Alternatives considered**:
- Only moving `FoodPickup` to its own layer: food would still collide with fighters through its own mask 1, because fighters are on layer 1.
- Making `FoodPickup` an `Area2D`: it would lose the floor and platform landing.

**Rationale**: Food lands on the stage only, fighters walk through it, and pickup and punch detection stay explicit.

### Decision 22: SFX event table with pitch bands on the three existing sounds

**Choice**: `Sfx.play_event(event: StringName, requester)` looks up `EVENTS[event] = [path, pitch_min, pitch_max]`, sets `pitch_scale = randf_range(min, max)`, and returns early under training (the helper moves from `Combat._is_training`). The existing `Sfx.play(path, requester)` stays for compatibility.
**Alternatives considered**: Per-call pitch arguments scattered across callers. The bands would drift.
**Rationale**: One reviewable table, and the bands never overlap per source sound (spec: "Distinct bands").

### Decision 23: Snapshots are plain, open, unversioned Dictionaries

**Choice**: `Fighter.get_state_snapshot()` and `Game.get_state_snapshot()` build a new Dictionary from current fields. They are read-only, carry no version key, and have a doc comment stating "unversioned, not a schema; future schema module (hf-ai-opponents) reads this". Positions are `Fighter.position` and children of `Game`, so they are Game-local by construction.
**Alternatives considered**: A typed snapshot class, which would freeze a shape too early.
**Rationale**: This matches the proposal and the ordering decision. Adding keys later breaks no consumer.

## Data Flow

```
               ┌──────────────── Fighter._physics_process (parent, runs first) ─────────────────┐
 Input ───▶ HumanController ─┐                                                                  │
 Game/Fighter snapshots ─▶ ScriptedController ─┼─▶ intent: FighterIntent ─▶ _tick_movement() ─▶ move_and_slide() ─▶ _check_blast_zone()
 Sync ─▶ PlayerAIController floats ─▶ PolicyController ─┘   (neutral while controls_locked)       │
               └──────────────────────────────────────────────────────────────────────────────────┘
                                         │ (same frame, child)
                                         ▼
 StateMachine._physics_process ─▶ current Motion._update(): handle_actions(intent ∩ available_actions ∩ can_enter)
                                         │                         └─▶ finished.emit(next) ─▶ _change_state
                                         ▼
                              state_machine.velocity ─▶ Fighter.velocity (used by next move_and_slide)

 Punch ACTIVE ─▶ PunchArea overlaps ─▶ Combat.apply_hit(attacker, target, dmg, kb)
        ├─ target.is_invulnerable? ─▶ drop
        ├─ target in Protect ─▶ receive_blocked_damage
        └─ else Hurt(pending dmg/kb) ─▶ hitstun ─▶ grant_invulnerability(post-hit) ─▶ Idle/Fall
        └─ (not training) ─▶ hit-stop(token) + Sfx.play_event

 Game phase: COUNTDOWN ─▶ PLAYING ─(timeout, equal stocks)─▶ SUDDEN_DEATH ─(KO)─▶ OVER ─▶ GameOver
                                  └─(timeout, unequal / KO)───────────────────────────▶ OVER
 GameOver ─ Replay ─▶ SceneManager.rematch() ─▶ play_game(last_match) ─▶ new Game (countdown again)

 MatchCamera._process ─▶ fighters' positions (Game-local) ─▶ position/zoom (clamped)   Hurt ─▶ camera.offset (shake)
```

## File Changes

### S1 – Controller seam, snapshot accessor, print cleanup (no gameplay change except removing the ghost AI)

| File | Action | Description |
|------|--------|-------------|
| `game/player/controllers/fighter_intent.gd` | Create | `FighterIntent` with all fields, including S5 (inert until S5) |
| `game/player/controllers/fighter_controller.gd` | Create | Base `FighterController` (`bind`, `sample`, `kind_name`) |
| `game/player/controllers/human_controller.gd` | Create | Maps `P{N}_*` actions. Double-tap dash detection moves here from `idle.gd`. Aim stays `NEUTRAL` until S5 |
| `game/player/controllers/policy_controller.gd` | Create | Adapter over `PlayerAIController` floats (Decision 4) |
| `game/player/controllers/controller_config.gd` | Create | `ControllerConfig` resource (kind, difficulty, optional difficulty resource, onnx path) plus `build(fighter)`. CPU is wired in S3 |
| `game/player/player.gd` | Modify | `controller_kind`, `controller`, `intent`, `controls_locked`, `facing`, `set_controller()`, AUTO resolution, `get_state_snapshot()`; remove `print` |
| `game/player/StateMachine/PlayerStateMachine/States/motion.gd` | Modify | Delete `process_ai_transitions`, `set_ai_direction`, `set_manual_direction`, and `_state_input`. Add `handle_actions()`, `move_axis()`, `set_direction()` from the intent, and `exit_to_neutral()`. Remove the `print` |
| `game/player/StateMachine/state.gd` | Modify | Add `can_enter() -> bool` |
| `.../States/idle.gd`, `run.gd`, `jump.gd`, `fall.gd` | Modify | Use the helpers. `idle.gd` loses its `_state_input` |
| `.../States/punch.gd`, `shoot.gd`, `dash.gd` | Modify | `can_enter()` checks cooldown and availability. Remove the reject emits in `_enter`. Remove the punch `print` |
| `.../PlayerStateMachine/player_state_machine.gd` | Modify | Remove `input_dir` |
| `game/player/StateMachine/state_machine.gd` | Modify | Drop `_input` dispatch (no state consumes events anymore) |
| `scripts/AIController/player_ai_controller.gd` | Modify | `_ready` is `super._ready()` only; obs, action, and set_action untouched |
| `game/game.gd` | Modify | `get_state_snapshot()`, stage rect read from `$StaticBody2D/Floor` and platform shapes |
| `game/player/player.tscn` | Modify | Add `"dash"` to Idle's `available_actions` (baseline dash from Idle preserved under the new path) |

### S2 – Movement feel, punch fix, hit rules (F4, F5)

| File | Action | Description |
|------|--------|-------------|
| `game/player/fighter_tuning.gd` | Create | `FighterTuning` resource with the movement and hit defaults (table below) |
| `game/player/player.gd` | Modify | `tuning`, `jumps_left`, `air_dash_available`, coyote, buffer, `_tick_movement()`, `resolve_jump()`, `grant_invulnerability()` with Timer and bound tween (F4) |
| `.../States/motion.gd` | Modify | Gravity from tuning (fall multiplier, max fall speed), ground and air acceleration |
| `.../States/jump.gd` | Modify | Ground and air kinds, short hop, air actions |
| `.../States/fall.gd`, `idle.gd`, `run.gd` | Modify | `resolve_jump`, landing to Idle, air actions |
| `.../States/dash.gd` | Modify | Dash from Idle, Run, and air. Air dash consumes the flag and suspends gravity |
| `.../States/punch.gd` | Modify | Single mirrored hitbox, active window polling, `_hit_targets`, air punch with gravity; remove `move_punch_offset` |
| `.../States/shoot.gd`, `protect.gd` | Modify | Air variants, hold-to-block, `exit_to_neutral()` |
| `.../States/hurt.gd` | Modify | Knockback-scaled hitstun, `hurt_gravity_scale`, post-hit invulnerability on natural end, connect the timer once |
| `game/combat/combat.gd` | Modify | Token hit-stop and `cancel_hit_stop()` (F5) |
| `game/game.gd` | Modify | `_exit_tree` calls `Combat.cancel_hit_stop()` (non-training) |
| `game/player/player.tscn` | Modify | Delete `PunchArea/CollisionShape2D2`. `available_actions`: Idle and Run get `["dash","jump","punch","protect","shoot"]`; Jump and Fall get the same |

### S3 – Scripted CPU and controller/difficulty select

| File | Action | Description |
|------|--------|-------------|
| `game/player/controllers/cpu_difficulty.gd` | Create | `CpuDifficulty` resource and `preset(level)` |
| `game/player/controllers/scripted_controller.gd` | Create | Utility loop (Decision 13) |
| `game/player/controllers/controller_config.gd` | Modify | Build CPU, and Policy with ONNX path |
| `ui/character_select/character_select.tscn` | Modify | `ControllerOption` (OptionButton: Human, CPU Easy, CPU Normal, CPU Hard) in `ControlP1` and `ControlP2`, above the existing AI widgets |
| `ui/character_select/ai_controller.gd` | Modify | Option visibility in `initial_menu`; `get_controller_config(is_p2)`. A selected HF model takes precedence and gives Policy |
| `ui/character_select/character_select.gd` | Modify | Pass configs to `SceneManager.play_game` |
| `scripts/SceneManager/scene_manager.gd` | Modify | `play_game(c1, c2, cfg1, cfg2)` with `set_controller`, store `last_match` |

### S4 – Match flow, F2/F3/F8, SFX pitch, typo

| File | Action | Description |
|------|--------|-------------|
| `game/game.gd` | Modify | Phase machine, countdown, sudden death, `phase != OVER` guard, null guards (F3), start the timer and spawner |
| `game/game.tscn` | Modify | `Timer.autostart = false`; `UI/CountdownLabel` (Label, centered, font size 96) |
| `game/food/food_spawner.gd` | Modify | `start()` (no self-start in `_ready`); `food.position` instead of `global_position` (F2) |
| `game/food/food_pickup.tscn`, `food_projectile.tscn`, `game/player/player.tscn` | Modify | Collision layers and masks (Decision 21, F8) |
| `project.godot` | Modify | `[layer_names] 2d_physics/layer_1..3` |
| `game/audio/sfx.gd` | Modify | `BUTTON` path, `EVENTS` table, `play_event()`, `is_training()` |
| `game/combat/combat.gd`, `.../shoot.gd`, `.../jump.gd`, `game/player/player.gd` | Modify | Call `play_event` (hit, heavy hit, block, pickup, throw, jump, double jump, KO) |
| `game/ui/pause/pause.gd` | Modify | Esc toggle, `set_input_as_handled()`, ignored when game over is visible |
| `game/ui/game_over/game_over.gd`, `game_over.tscn` | Modify | Replay calls `SceneManager.rematch()`; new "Characters" Button |
| `scripts/SceneManager/scene_manager.gd` | Modify | `rematch()` |
| `ui/global/timer_label.gd` | Modify | Show `wait_time` while the timer is stopped |
| `ui/instructions/instructions.tscn` | Modify | Fix the "Intructions" title. Add lines for double jump, dash (double-tap), and air actions |
| `ui/main_menu/main_menu.tscn`, `ui/main_menu/main_menu_buttons.gd` | Modify | Rename `IntructionsButton` and `_on_intructions_button_pressed` (the spec requires no "Intructions" matches anywhere) |
| `game/player/player.gd` | Modify | `set_stocks(n)` emits `stocks_changed` (sudden death) |

### S5 – Smash moves, camera, bot extension

| File | Action | Description |
|------|--------|-------------|
| `game/combat/attack_profile.gd` | Create | `AttackProfile` resource (damage, knockback, hitbox_offset) |
| `.../States/recovery.gd` | Create | Recovery state (Decision 19) |
| `game/camera/match_camera.gd` | Create | Follow and zoom (Decision 20) |
| `.../States/punch.gd` | Modify | Charge phases, five profiles (neutral built from `punch_damage`/`punch_knockback`/`punch_distance` for `train.tscn` compatibility), aim at release |
| `game/player/player.gd` | Modify | `recovery_available`, `charge_level`, `last_attack_direction`, `set_charge_visual()`, snapshot keys |
| `game/player/player.tscn` | Modify | `ChargeGlow` Sprite2D (texture `res://assets/textures/2D Fire  - Tutorial/T_VFX_Glow_1.PNG`, existing UID `uid://dmybar0g2nd2a`, `CanvasItemMaterial` additive, hidden); `Recovery` state node; `"recovery"` added to Jump and Fall `available_actions` |
| `.../States/hurt.gd` | Modify | Reset `recovery_available` on hit; reset shake `offset` at the end |
| `game/player/controllers/human_controller.gd` | Modify | Aim and `special_pressed` mapping (Decision 17) |
| `project.godot` | Modify | `P1_up` (E), `P1_down` (C), `P2_up` (I), `P2_down` (Comma) |
| `game/player/controllers/scripted_controller.gd`, `cpu_difficulty.gd` | Modify | `use_directional` and `use_up_recovery` for Normal and Hard; Easy preset untouched |
| `game/game.tscn` | Modify | Attach `match_camera.gd` to `Camera2D` |
| `game/game.gd` | Modify | Snapshot `camera: {center, zoom}` |
| `game/audio/sfx.gd` | Modify | `&"recovery"` band |
| `ui/instructions/instructions.tscn` | Modify | Charge, directional attacks, recovery chord, up/down keys |
| `train.tscn` | Unchanged | Verified statically: no new overrides needed. Its root `Camera2D` gets no script, and the row cameras' script no-ops in training |

## Interfaces / Contracts

```gdscript
# game/player/controllers/fighter_intent.gd
class_name FighterIntent extends RefCounted
enum Aim { NEUTRAL, UP, DOWN, SIDE }
var move_x: float = 0.0          # -1..1
var jump_pressed := false        # edge (Policy: see Decision 4)
var jump_held := false
var attack_pressed := false
var attack_held := false         # S5 charge; Policy/Scripted always false
var attack_released := false     # S5
var throw_pressed := false       # pickup or throw (shoot)
var block_pressed := false
var block_held := false
var dash_pressed := false        # Human: double-tap; uses move_x (or facing) as direction
var aim: Aim = Aim.NEUTRAL       # S5
var special_pressed := false     # S5 recovery request

# game/player/controllers/fighter_controller.gd
class_name FighterController extends RefCounted
var fighter: Fighter
func bind(f: Fighter) -> void: fighter = f
func sample(_delta: float) -> FighterIntent: return FighterIntent.new()
func kind_name() -> String: return "none"

# game/player/controllers/controller_config.gd
class_name ControllerConfig extends Resource
enum Kind { HUMAN, CPU, POLICY }
@export var kind: Kind = Kind.HUMAN
@export var difficulty: CpuDifficulty.Level = CpuDifficulty.Level.NORMAL
@export var difficulty_resource: CpuDifficulty   # optional override
@export var onnx_model_path: String = ""
func build(fighter: Fighter) -> FighterController

# Fighter additions
enum ControllerKind { AUTO, HUMAN, CPU, POLICY }
@export var controller_kind: ControllerKind = ControllerKind.AUTO
@export var tuning: FighterTuning
var intent: FighterIntent
var controls_locked := false
var facing: int = 1                       # +1 right, -1 left (toward enemy)
func set_controller(c: FighterController) -> void
func resolve_jump() -> int                # JumpKind.NONE / GROUND / AIR
func grant_invulnerability(duration: float, blink := true) -> void
func set_stocks(n: int) -> void
func set_charge_visual(charge: float) -> void   # S5; < 0 hides
func get_state_snapshot() -> Dictionary

# State / Motion additions
func can_enter() -> bool                  # State, default true
func handle_actions() -> bool             # Motion
func exit_to_neutral() -> void            # Motion: Idle if on floor else Fall

# Combat
static func cancel_hit_stop() -> void

# Sfx
static func play_event(event: StringName, requester: Node) -> void

# SceneManager
func play_game(c1: CharacterUI, c2: CharacterUI, cfg1: ControllerConfig = null, cfg2: ControllerConfig = null) -> void
func rematch() -> void
```

### Snapshot keys (unversioned, open, not a schema)

`Fighter.get_state_snapshot()` returns:
- `position: Vector2` (Game-local), `velocity: Vector2`, `facing: int`, `on_floor: bool`;
- `damage_percent: float`, `stocks: int`, `held_food: String`;
- `state: StringName`, `cooldowns: {punch: float, shoot: float}` (seconds left);
- `jumps_left: int`, `air_dash_available: bool`, `is_invulnerable: bool`, `controller: String`;
- S5: `charge_level: float`, `recovery_available: bool`, `last_attack_direction: String` (`neutral|up|down|side`).

`Game.get_state_snapshot()` returns:
- `phase: String`, `timer_left: float`, `timer_running: bool`, `sudden_death: bool`;
- `stage: {left, right, top}`, `platforms: [{left, right, top}]`;
- `foods: [{name, position}]`, `projectiles: [{position, velocity, shooter: int}]`;
- `fighters: [snapshot1, snapshot2]`;
- S5: `camera: {center: Vector2, zoom: float}`.

### SFX event bands

| Event | Sound | Pitch band |
|-------|-------|------------|
| `hit` | cartoonpunch | 0.92–1.08 |
| `block` | cartoonpunch | 0.60–0.70 |
| `throw` | cartoonpunch | 1.45–1.65 |
| `heavy_hit` | explosion | 1.00–1.15 |
| `ko` | explosion | 0.55–0.65 |
| `pickup` | button.mp3 | 1.35–1.50 |
| `jump` | button.mp3 | 0.80–0.90 |
| `double_jump` | button.mp3 | 1.00–1.10 |
| `recovery` (S5) | button.mp3 | 1.18–1.28 |

## Tuning Defaults (all exported, all flagged for manual playtest)

| Group | Parameter | Default | Baseline / note |
|-------|-----------|---------|-----------------|
| Movement | run_speed | 300 | unchanged |
| | ground_accel / air_accel | 2400 / 1400 | 1000 / 1000 |
| | gravity | 1800 | 500 |
| | fall_gravity_multiplier / max_fall_speed | 1.2 / 1000 | none |
| | jump_velocity | -850 (apex ≈ 200 px, ≈ 0.47 s up) | -600 (≈ 360 px, 1.2 s up) |
| | double_jump_velocity | -750 (≈ 156 px) | none |
| | jump_cut_multiplier | 0.45 | none |
| | coyote_time / jump_buffer | 0.10 s / 0.10 s | none |
| | max_air_jumps | 1 | 0 |
| | dash_speed / ground / air duration | 600 / 0.25 s / 0.18 s, air gravity scale 0 | 600 / 0.3 s |
| | double_tap_window (Human) | 0.30 s | 0.30 s |
| Hits | hitstun | clamp(0.2 + \|kb\| × 0.0004, 0.3, 0.9) s | 0.5 s fixed |
| | hurt_gravity_scale | 0.6 | 1.0 at g=500 |
| | post_hit_invulnerability | 0.5 s | none |
| | respawn invulnerability | 1.5 s | unchanged |
| | hit-stop | 0.08 s at 0.05 (block 0.04 s at 0.3) | unchanged |
| Punch | duration / active / cooldown | 0.30 / 0.15 / 0.70 s | 0.3 / – / 0.7 |
| | neutral | 8 dmg, kb (220,-120), hitbox (50,-10) | unchanged |
| | side (S5) | 10 dmg, kb (320,-90), hitbox (60,-10) | new |
| | up (S5) | 8 dmg, kb (30,-380), hitbox (0,-90) | new |
| | down ground (S5) | 7 dmg, kb (150,-230), hitbox (45,50) | new |
| | down air / spike (S5) | 9 dmg, kb (40,420), hitbox (0,80) | new |
| Charge (S5) | tap_threshold / max_charge_time | 0.15 s / 1.0 s | new |
| | damage / knockback multiplier at full | 1.6 / 1.5 | new |
| | glow scale / alpha | 0.3→0.9 / 0.25→0.9, modulate = character color | new |
| Recovery (S5) | recovery_velocity / drift | -950 (≈ 250 px) / 250 px/s | new |
| Match | countdown step / GO hold | 1.0 s / 0.5 s | none |
| | match time | 99 s | unchanged |
| | sudden death | 1 stock each, timer off, damage unchanged | draw |
| Camera (S5) | min/max zoom | 1.0 / 1.4 | static 1.0 |
| | margin / vertical_bias | (300, 220) / -40 | – |
| | follow / zoom speed | 5 / 3 (exponential) | – |

CPU presets (`CpuDifficulty.preset`):

| Field | Easy | Normal | Hard |
|-------|------|--------|------|
| decision_interval (reaction) | 0.40 s | 0.22 s | 0.12 s |
| action_accuracy | 0.55 | 0.80 | 0.95 |
| block_chance | 0.15 | 0.40 | 0.70 |
| throw_chance | 0.30 | 0.60 | 0.85 |
| pickup_seek_distance | 120 | 220 | 320 |
| approach_stop_distance | 75 | 60 | 55 |
| block_hold | 0.35 s | 0.45 s | 0.55 s |
| use_directional (S5) | false | true | true |
| use_up_recovery (S5) | false | true | true |

## Testing Strategy

There is no runner (`openspec/config.yaml`: `strict_tdd: false`, runner none). Automated tests are out of scope per the proposal (F6 stays open), and the user rule forbids running tests locally. Even though the orchestrator reports Strict TDD as enabled, the project config fails closed to no runner.

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Static (per slice) | No `print(` in `motion.gd`, `player.gd`, `player_ai_controller.gd`, `punch.gd`; `get_obs()`/`get_action_space()` byte-identical to baseline; no `Input.` or `PlayerAIController` reads in `States/*.gd`; no `move_punch_offset`; no "Intructions"; no new files under `assets/`; the 4 new bindings unique; `train.tscn` diff empty and its overridden property names still exist (`punch_distance`, `punch_duration`, `punch_cooldown`, `block_*`, `shoot_*`, `available_actions`) | `rg` audits and git diff review |
| Static (logic) | Hit-stop token restores to 1.0 under overlap; invulnerability `max(remaining, duration)`; `resolve_jump` truth table (ground, coyote, air, buffer); camera clamp math at zoom 1.0 and 1.4 near corners; CPU presets ordered (Easy > Normal > Hard delay, Easy < Normal < Hard accuracy) | Reviewer walk-through against spec scenarios |
| Manual playtest S1 | 2P keys unchanged; stale `user://Agent0.onnx` with Human means human control; dash from Idle | User in the Godot 4.6 editor |
| Manual playtest S2 | Jump arc, short hop, coyote, buffer, double jump; air punch, throw, and block; dash from Idle, Run, and air (once); punch mirrored with no teleport; no stun-lock; overlapping hits leave `Engine.time_scale` at 1 | Editor plus remote inspector |
| Manual playtest S3 | Human vs CPU Easy, Normal, Hard with no model; bot approaches, punches, blocks, picks up and throws food, recovers from the edges | Editor |
| Manual playtest S4 | Countdown, including pause during the countdown; sudden death; rematch keeps controllers; Esc toggles; food passes through fighters and does not ride heads; pitch bands audible | Editor |
| Manual playtest S5 | Tap vs charge, glow, cap; up, down, and side angles; recovery once per airtime, reset on landing and on hit; ring-out still possible at 150%+; camera follow, zoom, and clamp; HUD fixed; Normal and Hard use directional attacks and recovery | Editor |
| Training | `train.tscn` opens; agents in `AGENT` with `control_mode` TRAINING; no script errors | Static check plus user editor run |

## Threat Matrix

N/A: no routing, shell, subprocess, VCS/PR automation, executable-file classification, or process-integration boundary. The only network code (`ModelManager` HF requests) is unchanged.

## Migration / Rollout

No data migration. There are no save files or schema changes.
- **Rollout**: S1 through S5 in order. S5 depends on S1 (intent fields) and S2 (punch rework). If S5 exceeds the budget, it splits into S5a (camera) and S5b (moves plus bot).
- **Rollback**: `git revert` per slice from the top down. Reverting S5 leaves the S5 intent fields inert.
- **Delivery**: the proposal's pending decision (chained PRs versus a `size:exception` single PR) still applies before apply.

## Open Questions

- [ ] **Default controller per player in character select**: the design defaults to P1 = Human and P2 = CPU Normal, because single player is the primary experience. The baseline equivalent would be P2 = Human. This needs user confirmation; it is not blocking.
- [ ] **S5 key choice** (`E`/`C` for P1, `I`/`Comma` for P2): ergonomics on a shared keyboard are unverified. The keys can be rebound in Project Settings with no code impact. Not blocking.
- [ ] **TRAINING restoration**: adding `super._ready()` makes `sync.gd` discover agents and keep `control_mode = TRAINING` for the first time since the `_ready` override was added. The user must confirm in the editor that `train.tscn` runs (and connects to the Python server when available). Not blocking.
- [ ] **Inputs during hit-stop**: at `time_scale` 0.05, physics ticks are sparse, so a polled `just_pressed` could be missed during an 80 ms stop. The jump buffer mitigates this for jumps. Verify in playtest; if needed, latch presses in `HumanController` via `Input` state on the next tick. Not blocking.
