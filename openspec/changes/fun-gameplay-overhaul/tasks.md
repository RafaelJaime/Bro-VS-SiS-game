# Tasks: Fun Gameplay Overhaul

Change: `fun-gameplay-overhaul` | Project: `bro-vs-sis-game` | Store: hybrid
Specs: `openspec/changes/fun-gameplay-overhaul/specs/*/spec.md` | Design: `design.md` | Proposal: `proposal.md`

Verification model (no test runner, `strict_tdd: false`, never run tests locally): every task is verified by (a) static review (`rg` audits and diff reading) and (b) the slice's manual playtest checklist in the Godot editor, run by the user. The `[S]` marker means static check, `[P]` means playtest item.

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~1,450-1,750 authored (additions + deletions) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 (S1) -> PR 2 (S2) -> PR 3 (S3) -> PR 4 (S4) -> PR 5 (S5a) -> PR 6 (S5b) |
| Delivery strategy | exception-ok (user, 2026-10-01): one PR with `size:exception`, one logical work-unit commit per slice/task group |
| Chain strategy | n/a (single PR) |

Decision needed before apply: Resolved — single PR with `size:exception`, multiple logical commits.
Chained PRs recommended: Yes (declined by user)
Chain strategy: n/a
400-line budget risk: High (accepted via `size:exception`)
Branch: `feat/fun-gameplay-overhaul` (based on `feat/kitchen-food-fight`)

The single-pr strategy requires `size:exception` approval before apply, or the user switches to chained PRs. Slices are written so either path works: each slice is an autonomous, playable, revertible unit; the slice boundary is a commit group or PR boundary.

### Per-slice line forecast

| Slice | Content | Est. lines | Over 400? |
|-------|---------|-----------|-----------|
| S1 | Controller seam, `FighterProfile` seam, snapshot accessor, print cleanup, ONNX fix | ~330 | No (tight) |
| S2 | Movement feel, punch fix, hit rules (F4, F5) | ~300 | No |
| S3 | Scripted CPU, difficulty presets, controller select UI | ~300 | No |
| S4 | Match flow, F2/F3/F8, SFX pitch, typo | ~250 | No |
| S5a | Match camera, snapshot camera field, shake offset reset | ~120 | No |
| S5b | Charge, directional punches, recovery, inputs, bot extension, instructions | ~280 | No |
| Total | | ~1,580 | 4x budget |

If S1 grows past 400 because of `FighterProfile`, split S1 into S1a (intent and controllers, ~250) and S1b (profile seam and snapshot, ~100). The honest-slicing pass is already done here; no code-golf to fit the budget.

### Suggested Work Units

PR base boundaries below apply to `feature-branch-chain` (PR 1 base = tracker branch, each later PR base = previous PR branch). For `stacked-to-main`, every PR bases on `master` after the previous one merges. Baseline for all: branch `feat/kitchen-food-fight` at `9d7bf0c`.

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| S1 | Intent seam, FighterProfile seam, snapshot, no ghost AI | PR 1 (base tracker/master) | N/A (no runner). Static: `rg` audits listed in 1.15 | Godot 4.6 editor: run `game.tscn` 2P, then `train.tscn` (user) | `game/player/controllers/*`, `game/player/fighter_profile.gd`, edits in `player.gd`, `motion.gd`, `state.gd`, States, `player_ai_controller.gd`, `game.gd`. Revert restores original input paths |
| S2 | Snappy movement, air actions, punch fix, hitstun, F4, F5 | PR 2 (base PR 1) | N/A. Static: `rg` audits in 2.13 | Editor: playtest checklist S2 (user) | S2 edits to `player.gd`, `fighter_profile.gd` additions, States, `combat.gd`, `player.tscn`. Reverting restores old feel on top of the seam |
| S3 | Playable single player vs CPU with difficulty select | PR 3 (base PR 2) | N/A. Static: `rg` audits in 3.9 | Editor: Human vs CPU Easy/Normal/Hard, no model (user) | `cpu_difficulty.gd`, `scripted_controller.gd`, character select edits, `scene_manager.gd` `play_game` change |
| S4 | Countdown, sudden death, rematch, pause toggle, F2/F3/F8, SFX bands | PR 4 (base PR 3) | N/A. Static: `rg` audits in 4.13 | Editor: playtest checklist S4 (user) | `game.gd`/`game.tscn` phase machine, `food_spawner.gd`, layer edits, `sfx.gd`, pause and game-over UI, `project.godot` layer names |
| S5a | Follow camera with dynamic zoom | PR 5 (base PR 4) | N/A. Static: clamp math walk-through in 5a.4 | Editor: camera checklist (user) | `game/camera/match_camera.gd`, `Camera2D` script attach in `game.tscn`, Game snapshot `camera` key, `hurt.gd` offset reset |
| S5b | Charge, directional punches, up-recovery, up/down inputs, bot extension | PR 6 (base PR 5) | N/A. Static: `rg` audits in 5b.14 | Editor: smash moves checklist (user) | `attack_profile.gd`, `recovery.gd`, `punch.gd` charge phases, `human_controller.gd` aim mapping, `project.godot` 4 input actions, `ChargeGlow`, bot S5 fields, instructions text |

Dependencies: S1 first. S2 depends on S1. S3 depends on S1 (controllers) and S2 (air actions for recovery behaviour). S4 depends on S1 (rematch needs `ControllerConfig`) and S3 (`play_game` signature). S5a depends on S4 (`Game` bounds and phase). S5b depends on S1 (intent fields) and S2 (punch rework). S5a and S5b are independent of each other once S4 lands, so they can be built in parallel in separate worktrees if chained PRs are used; otherwise sequentially.

Design deviation to confirm at apply: the design's `FighterTuning` resource is replaced by the user-requested `FighterProfile` (Task 1.2). `Fighter.tuning` in the design maps to `Fighter.profile`; S2 adds the movement and hit fields to `FighterProfile` instead of creating a second resource. No behavior difference.

---

## Phase S1: Controller seam, FighterProfile seam, snapshot accessor, print cleanup

Specs: fighter-control (all), gameplay-state-snapshot (Fighter, Game, unversioned). Design Decisions 1-5, 23.

- [x] 1.1 Create `game/player/controllers/fighter_intent.gd`: `FighterIntent extends RefCounted` with every field from the design contract (move_x, jump_pressed/held, attack_pressed/held/released, throw_pressed, block_pressed/held, dash_pressed, `Aim` enum + aim, special_pressed). All S5 fields declared but inert. Verify [S]: field names match design "Interfaces / Contracts"; all default neutral.
- [x] 1.2 Create `game/player/fighter_profile.gd`: `FighterProfile extends Resource` (user addition 1, Smash-style kits seam). Exported groups: movement (run_speed, jump_velocity, gravity, dash_speed, dash_duration), weight (`knockback_scale`/weight), punch (punch_damage, punch_knockback, punch_distance, punch_duration, punch_cooldown) and moveset flags (`can_double_jump`, `can_dash`, `can_air_punch`, `can_charge`, `can_recover`). Defaults reproduce current baseline constants exactly (run 300, jump -600, gravity 500, punch 8 dmg / kb (220,-120)). Add a doc comment: future per-character kits supply a different `FighterProfile`; no state code may hardcode these values. Verify [S]: defaults match the baseline values currently in `motion.gd`, `punch.gd`, `dash.gd`, `jump.gd`.
- [x] 1.3 Edit `game/player/player.gd`: add `@export var profile: FighterProfile`; in `_ready`, if null assign `FighterProfile.new()` so no `.tres` is required. Expose it as `owner.profile` for states. Both characters keep identical (default) values. Verify [S]: no `.tres` added; `train.tscn` untouched.
- [x] 1.4 Edit `motion.gd`, `jump.gd`, `dash.gd`, `punch.gd`, `hurt.gd` (under `game/player/StateMachine/PlayerStateMachine/States/`): replace hardcoded movement, weight, punch and dash constants with reads from `owner.profile`, keeping the existing `@export` names (`punch_distance`, `punch_duration`, `punch_cooldown`, which `train.tscn` overrides) as the node-level override. Rule: an unset node export falls back to the profile value. Verify [S]: `rg "const (RUN|JUMP|GRAVITY)"` in States shows no remaining hardcoded tuning; `train.tscn` overridden names still exist.
- [x] 1.5 Create `game/player/controllers/fighter_controller.gd`: base `FighterController extends RefCounted` with `bind`, `sample`, `kind_name`. Verify [S]: matches design contract.
- [x] 1.6 Create `game/player/controllers/human_controller.gd`: maps `P{N}_left/right/jump/protect/punch/shoot` to intent; owns double-tap dash detection (moved from `idle.gd`, 0.30 s window); aim stays NEUTRAL. Verify [S]: action names match `project.godot` `[input]`; P1/P2 prefix derived from the fighter.
- [x] 1.7 Create `game/player/controllers/policy_controller.gd`: adapter over `PlayerAIController` floats with level semantics and guards per Decision 4 (`jump_pressed = jump and (rising_edge or on_floor)`, `attack_held = false`, S5 fields neutral). Verify [S]: `get_obs()`/`get_action_space()` not touched.
- [x] 1.8 Create `game/player/controllers/controller_config.gd`: `ControllerConfig` resource (kind HUMAN/CPU/POLICY, difficulty, `difficulty_resource`, `onnx_model_path`) and `build(fighter)`. CPU case returns a Human controller placeholder with a TODO note until S3 (no stub files). Policy case sets `ai_controller_2d.control_mode = ONNX_INFERENCE` and the model path only when explicitly selected.
- [x] 1.9 Edit `game/player/player.gd`: add `controller_kind` (AUTO/HUMAN/CPU/POLICY, default AUTO), `controller`, `intent`, `controls_locked`, `facing`, `set_controller()`, AUTO resolution in `_ready` (Decision 3), single `intent = controller.sample(delta)` at the top of `_physics_process` (neutral intent while `controls_locked`). Remove the debug `print`. Verify [S]: exactly one `sample(` call site per frame.
- [x] 1.10 Edit `game/player/StateMachine/state.gd`: add `can_enter() -> bool` (default true). Edit `.../States/motion.gd`: delete `process_ai_transitions`, `set_ai_direction`, `set_manual_direction`, `_state_input`; add `handle_actions()` (priority `recovery, dash, jump, punch, protect, shoot`, filtered by `available_actions` and `can_enter()`), `move_axis()`, `set_direction()`, `exit_to_neutral()`; remove the `print` in `_enter`. Verify [S]: no `Input.` or `PlayerAIController` reference left in `States/*.gd`.
- [x] 1.11 Edit `idle.gd`, `run.gd`, `jump.gd`, `fall.gd`: use the Motion helpers; `idle.gd` loses `_state_input`. Edit `punch.gd`, `shoot.gd`, `dash.gd`: `can_enter()` for cooldown/availability, remove reject emits in `_enter`, remove the punch `print`. Edit `player_state_machine.gd` (remove `input_dir`) and `state_machine.gd` (drop `_input` dispatch).
- [x] 1.12 Edit `game/player/player.tscn`: add `"dash"` to Idle `available_actions` so baseline dash-from-Idle survives the new path. Verify [S]: `train.tscn` `available_actions = []` overrides still apply.
- [x] 1.13 Edit `scripts/AIController/player_ai_controller.gd`: `_ready` becomes `super._ready()` only; delete the auto-ONNX logic and prints. Verify [S]: `get_obs()`, `get_action_space()`, `set_action()` byte-identical to baseline (`git diff` shows no hunks there).
- [x] 1.14 Edit `game/game.gd`: add `get_state_snapshot()` (keys per design: phase placeholder, timer, stage/platform rects read from `$StaticBody2D/Floor` shapes at runtime, foods, projectiles, fighters) and `Fighter.get_state_snapshot()` in `player.gd` (position Game-local, velocity, facing, on_floor, damage_percent, stocks, held_food, state, cooldowns, jumps_left placeholder, is_invulnerable, controller). Add the "unversioned, not a schema" doc comment on both. Verify [S]: read-only, builds a new Dictionary, no version key.
- [x] 1.15 Slice audit [S]: `rg -n "print\(" game/player/player.gd game/player/StateMachine scripts/AIController/player_ai_controller.gd` returns nothing; `rg "Input\." game/player/StateMachine` returns nothing; `git diff -- train.tscn` empty; no files added under `assets/`.
- [ ] 1.16 Manual playtest S1 [P] (user, Godot 4.6): 2P keys unchanged and fully working; dash from Idle works; with a stale `user://Agent0.onnx` present and Human selected the fighter obeys input (no ghost AI); `train.tscn` opens with agents in `AGENT` and `control_mode` TRAINING, no script errors; both fighters feel identical to before (profile defaults equal baseline).

## Phase S2: Movement feel, punch fix, hit rules (F4, F5)

Specs: fighter-movement (all), combat-hits (hitbox, hitstun, F4, F5). Design Decisions 5-12.

- [ ] 2.1 Edit `game/player/fighter_profile.gd`: add movement and hit tuning from the design Tuning Defaults table (ground/air accel, gravity 1800, fall multiplier 1.2, max fall 1000, jump -850, double jump -750, jump_cut 0.45, coyote 0.10, buffer 0.10, max_air_jumps 1, dash ground/air durations, hitstun clamp params, hurt_gravity_scale 0.6, post_hit_invulnerability 0.5, respawn invulnerability 1.5, hit-stop). Changing profile defaults is the single place the new feel is tuned; keep both characters identical.
- [ ] 2.2 Edit `game/player/player.gd`: add `jumps_left`, `air_dash_available`, `coyote_timer`, `jump_buffer_timer`, `_coyote_blocked`, `_tick_movement(delta)` (resets on landing, blocks triple jump), `resolve_jump() -> JumpKind` (Decision 6). Verify [S]: truth table for ground, coyote, air, buffer, coyote-expired matches the fighter-movement spec scenarios.
- [ ] 2.3 Edit `player.gd`: `grant_invulnerability(duration, blink := true)` using a one-shot `_invuln_timer` child and a node-bound looping `_blink_tween` (F4); timeout clears the flag, kills the tween, restores sprite visibility; `reset_player()` stops both; `_respawn()` calls it with the respawn duration using `max(remaining, duration)`. Verify [S]: no `get_tree().create_tween()` or `await ...create_timer` left for invulnerability.
- [ ] 2.4 Edit `motion.gd`: gravity from profile (fall multiplier, max fall speed), ground and air acceleration. Edit `jump.gd`: GROUND and AIR kinds, velocity by kind, short hop (`velocity.y *= jump_cut_multiplier` once when `!jump_held and velocity.y < 0`), air actions. Edit `fall.gd`, `idle.gd`, `run.gd`: `resolve_jump()`, landing to Idle, air actions.
- [ ] 2.5 Edit `dash.gd`: dash from Idle, Run and air; air dash consumes `air_dash_available`, suspends gravity, shorter duration; `can_enter()` is `on_floor or air_dash_available`.
- [ ] 2.6 Edit `punch.gd`: single mirrored hitbox from locked `facing` and `profile` offset, active-window polling of `punch_area.get_overlapping_bodies()` with a `_hit_targets` set, air punch applies gravity, delete `move_punch_offset` and `body_entered` connect churn. Edit `player.tscn`: delete `PunchArea/CollisionShape2D2`. Verify [S]: `rg move_punch_offset` returns nothing; owner `position` is never written in `punch.gd`.
- [ ] 2.7 Edit `shoot.gd`, `protect.gd`: air variants, hold-to-block bounded by `block_duration`, gravity in air, `exit_to_neutral()`.
- [ ] 2.8 Edit `hurt.gd`: hitstun scaled by knockback (`clamp(base + |kb| * per_kb, min, max)`), `hurt_gravity_scale`, keep x momentum, call `owner.grant_invulnerability(post_hit_invulnerability)` only in `_on_hurt_finished()`, connect the timer once. Verify [S]: Hurt-to-Hurt re-entry grants no invulnerability.
- [ ] 2.9 Edit `game/combat/combat.gd`: `static var _hit_stop_token`, token-guarded restore of `Engine.time_scale`, `static func cancel_hit_stop()` (F5). Edit `game/game.gd`: `_exit_tree()` calls `Combat.cancel_hit_stop()` when not training. Verify [S]: training path never touches `time_scale`.
- [ ] 2.10 Edit `game/player/player.tscn`: `available_actions` for Idle, Run, Jump, Fall set to `["dash","jump","punch","protect","shoot"]` (recovery added in S5b).
- [ ] 2.11 Static logic review [S]: hit-stop overlap ends at 1.0; invulnerability extension logic; hitstun + post-hit invulnerability (0.8 s) exceeds punch cooldown (0.7 s); `train.tscn` overrides (`punch_distance`, `punch_duration`, `punch_cooldown`, `[]` available_actions) still resolve.
- [ ] 2.12 Update comments and docs touched by the slice (no doc files created). Remove temporary code.
- [ ] 2.13 Manual playtest S2 [P] (user): jump apex visibly lower and shorter; short hop, coyote jump, buffered jump, double jump (no triple); air punch, throw, block; dash from Idle, Run, air (once per airtime); punch mirrored left/right and owner never moves; no stun-lock under repeated punches; two overlapping hits leave `Engine.time_scale == 1.0` (remote inspector); respawn blink ends cleanly and a second respawn restarts it.

## Phase S3: Scripted CPU and controller/difficulty select

Specs: cpu-opponent (behaviours, three levels, single-player), match-flow (controller select UI). Design Decisions 13, 14.

- [ ] 3.1 Create `game/player/controllers/cpu_difficulty.gd`: `CpuDifficulty extends Resource` with exported fields and `static func preset(level)` for Easy, Normal, Hard using the design preset table (S5 fields `use_directional`, `use_up_recovery` added in 5b.12). Verify [S]: Easy delay > Normal > Hard; accuracy ordered the other way.
- [ ] 3.2 Create `game/player/controllers/scripted_controller.gd`: reaction-tick loop reading `game.get_state_snapshot()`; plan priority RECOVER, DEFEND, THROW, PICKUP, ATTACK, APPROACH (Decision 13); held flags persist between ticks; pressed flags are a one-frame pending-press latch with a release frame before the next press; never walks off the stage edge while grounded; `attack_held` always false. Verify [S]: emits only `FighterIntent`; reads stage rect from the snapshot, no hardcoded coordinates.
- [ ] 3.3 Edit `game/player/controllers/controller_config.gd`: `build()` returns `ScriptedController` for CPU using the preset or the optional `difficulty_resource`. Remove the 1.8 placeholder.
- [ ] 3.4 Edit `scripts/SceneManager/scene_manager.gd`: `play_game(c1, c2, cfg1 := null, cfg2 := null)` calls `fighter.set_controller(cfg.build(fighter))` after `add_child`; store `last_match` (used by S4 rematch). Null cfg keeps the AUTO controller.
- [ ] 3.5 Edit `ui/character_select/character_select.tscn`: add `ControllerOption` (OptionButton: Human, CPU Easy, CPU Normal, CPU Hard) in `ControlP1` and `ControlP2`, above the existing AI widgets. Defaults P1 Human, P2 CPU Normal (open question in design; flag for user).
- [ ] 3.6 Edit `ui/character_select/ai_controller.gd`: option visibility in `initial_menu`; `get_controller_config(is_p2)`; a selected HF model takes precedence and yields a Policy config. Edit `ui/character_select/character_select.gd`: pass configs to `SceneManager.play_game`.
- [ ] 3.7 Static review [S]: `rg "ScriptedController|ControllerConfig"` call graph; HF/ONNX option stays functionally unchanged; `train.tscn` diff empty.
- [ ] 3.8 Comments and docs on tunable difficulty fields.
- [ ] 3.9 Manual playtest S3 [P] (user): Human vs CPU Easy, Normal, Hard with no HF model; CPU approaches, punches, blocks, picks up and throws food, recovers to the stage from an edge; Easy is visibly slower and less accurate than Hard; CPU never idles at spawn; 2P Human vs Human still works.

## Phase S4: Match flow, F2/F3/F8, SFX pitch, typo

Specs: match-flow (countdown, sudden death, rematch, pause, instructions), food-fight-items (F2, F3, F8, SFX pitch). Design Decisions 15, 16, 21, 22.

- [ ] 4.1 Edit `game/player/player.gd`: `set_stocks(n)` emits `stocks_changed`.
- [ ] 4.2 Edit `game/game.gd` and `game/game.tscn`: `Phase` enum (COUNTDOWN, PLAYING, SUDDEN_DEATH, OVER); `Timer.autostart = false`; `UI/CountdownLabel` (centered, font size 96); countdown "3-2-1-GO" with pausable timers (`create_timer(step, false)`); lock and unlock fighters; training path starts immediately as today. Update the Game snapshot `phase`, `sudden_death`, `timer_running`.
- [ ] 4.3 Edit `game/game.gd`: timeout logic (unequal stocks, equal stocks to sudden death with both at 1 stock, timer off, `TimerLabel` hidden, "SUDDEN DEATH" shown 1 s), `phase != OVER` guard in `_on_player_defeated`, null-guard `game_over` in training rows (F3). Edit `ui/global/timer_label.gd`: show `wait_time` while stopped.
- [ ] 4.4 Edit `game/food/food_spawner.gd`: `start()` instead of self-start, use `food.position` not `global_position` (F2).
- [ ] 4.5 Edit `game/food/food_pickup.tscn`, `food_projectile.tscn`, `game/player/player.tscn`, `project.godot`: layers per Decision 21 (fighters on layer 2, food on layer 3, masks per table) and `[layer_names]`. Verify [S]: table in design matches every node's `collision_layer`/`collision_mask`; `train.tscn` inherits without edits.
- [ ] 4.6 Edit `game/audio/sfx.gd`: `EVENTS` table with the design bands, `play_event()`, `is_training()` (moved from `Combat`), keep `play()`. Edit `game/combat/combat.gd`, `shoot.gd`, `jump.gd`, `player.gd`: call `play_event` for hit, heavy_hit, block, pickup, throw, jump, double_jump, ko. Verify [S]: bands do not overlap per source sound.
- [ ] 4.7 Edit `game/ui/pause/pause.gd`: Esc toggles pause and unpause, `set_input_as_handled()`, ignored while game over is visible.
- [ ] 4.8 Edit `scripts/SceneManager/scene_manager.gd`: `rematch()` replays `last_match`. Edit `game/ui/game_over/game_over.gd` and `game_over.tscn`: Replay calls `SceneManager.rematch()`, new "Characters" button opens character select; both unpause first.
- [ ] 4.9 Fix the typo: `ui/instructions/instructions.tscn` title; rename `IntructionsButton` and `_on_intructions_button_pressed` in `ui/main_menu/main_menu.tscn` and `ui/main_menu/main_menu_buttons.gd`; add instruction lines for double jump, dash (double-tap), air actions. Verify [S]: `rg -i "Intructions"` returns nothing anywhere.
- [ ] 4.10 Static review [S]: hit-stop and invulnerability untouched; training path equals baseline behavior.
- [ ] 4.11 Remove temporary code and finalize comments.
- [ ] 4.12 Static audit: no `print(` in per-frame paths; no new files under `assets/`.
- [ ] 4.13 Manual playtest S4 [P] (user): every match starts 3-2-1-GO with fighters locked; pause during countdown freezes digits; timeout tie goes to sudden death; double KO ends once; rematch keeps characters and controllers; "Characters" returns to select; Esc opens and closes pause; food passes through fighters and does not ride heads; pitch bands audibly different per event; food spawns in the correct place inside a train row (F2).

## Phase S5a: Match camera

Specs: match-camera (all), gameplay-state-snapshot (S5 camera). Design Decision 20.

- [ ] 5a.1 Create `game/camera/match_camera.gd`: follow midpoint of fighters with `stocks > 0`, distance-based zoom clamped to `[1.0, 1.4]`, exponential smoothing, manual clamp to `Rect2(0,0,800,600)` bounds with `half = viewport / (2 * zoom)`, writes `position` and `zoom` only; no-ops when parent `training`.
- [ ] 5a.2 Edit `game/game.tscn`: attach `match_camera.gd` to the existing `Camera2D`. Switch to drag-center only at runtime outside training. Edit `game/game.gd`: Game snapshot `camera: {center, zoom}`.
- [ ] 5a.3 Edit `game/player/StateMachine/PlayerStateMachine/States/hurt.gd`: reset shake `offset = Vector2.ZERO` at the end of the shake tween. Shake keeps using `offset`.
- [ ] 5a.4 Static review [S]: clamp math at zoom 1.0 (view equals today's framing) and 1.4 near all four corners; `train.tscn` root `Camera2D` has no script; HUD is on a `CanvasLayer`.
- [ ] 5a.5 Manual playtest camera [P] (user): follows both fighters; zooms out as they separate and never beyond 1.0; never shows past the background; HUD fixed and readable at 800x600; hurt shake still visible and leaves no residual offset; `train.tscn` cameras unchanged.

## Phase S5b: Smash moves and bot extension

Specs: smash-moves (charge, recovery, directional), combat-hits (knockback by charge and direction), cpu-opponent (directional/recovery use), fighter-control (up/down inputs), gameplay-state-snapshot (S5 fields). Design Decisions 17-19.

- [ ] 5b.1 Edit `project.godot` `[input]`: add `P1_up` (E), `P1_down` (C), `P2_up` (I), `P2_down` (Comma). Verify [S]: none duplicates an existing binding or `ui_*` default.
- [ ] 5b.2 Edit `game/player/controllers/human_controller.gd`: aim mapping (UP, DOWN, SIDE when `move_x != 0`, else NEUTRAL) and `special_pressed = attack_pressed and aim == UP`; `attack_held`/`attack_released` populated. Verify [S]: no change to `PolicyController` (S5 fields stay neutral).
- [ ] 5b.3 Create `game/combat/attack_profile.gd`: `AttackProfile extends Resource` (damage, knockback, hitbox_offset).
- [ ] 5b.4 Edit `.../States/punch.gd`: five profiles with the design values (neutral built from `punch_damage`, `punch_knockback`, `punch_distance` so `train.tscn` overrides keep working), phases WINDUP, CHARGING, ACTIVE, RECOVERY, `tap_threshold` 0.15 s, charge capped at 1.0, fire on release, air or non-held-at-entry fires immediately, damage and knockback scaled by `lerp(1, max, charge)`, sets `last_attack_direction`, `_exit` hides glow.
- [ ] 5b.5 Edit `game/combat/combat.gd`: knockback scaled by charge and direction angle. Edit `.../States/hurt.gd`: `owner.recovery_available = true` on hit.
- [ ] 5b.6 Edit `game/player/player.gd`: `recovery_available`, `charge_level`, `last_attack_direction`, `set_charge_visual(charge)` (< 0 hides), reset `recovery_available` on landing, S5 snapshot keys. Edit `game/player/player.tscn`: `ChargeGlow` Sprite2D using the existing texture `res://assets/textures/2D Fire  - Tutorial/T_VFX_Glow_1.PNG` (uid `uid://dmybar0g2nd2a`), additive material, hidden, modulate by character color. Verify [S]: no new files under `assets/`.
- [ ] 5b.7 Create `.../States/recovery.gd`: `Recovery extends Motion` per Decision 19 (velocity -950, drift 250, gravity and reduced air control, to Fall when `velocity.y >= 0`, `available_actions = []`, existing jump frame, `play_event(&"recovery")`). Edit `player.tscn`: add `Recovery` state node and `"recovery"` to Jump and Fall `available_actions`; `Recovery.can_enter()` returns `owner.recovery_available`. Respect `profile.can_recover` flag (from 1.2).
- [ ] 5b.8 Edit `.../States/motion.gd`: in air, `special_pressed` with recovery available goes to Recovery; otherwise falls through to a normal air punch. Ground `special_pressed` ignored; ground up-aim punch is an up-punch.
- [ ] 5b.9 Edit `game/audio/sfx.gd`: `&"recovery"` band 1.18-1.28.
- [ ] 5b.10 Honor `FighterProfile` moveset flags (`can_charge`, `can_recover`, `can_air_punch`) in `can_enter()` checks, all true for both characters now.
- [ ] 5b.11 Edit `ui/instructions/instructions.tscn`: charge, directional attacks, recovery chord (`up` + punch in air), up/down keys.
- [ ] 5b.12 Edit `cpu_difficulty.gd` (`use_directional`, `use_up_recovery`: Easy false, Normal and Hard true) and `scripted_controller.gd` (aim UP when enemy above, DOWN in air above the enemy, SIDE near edge with damage above 60%, `special_pressed` in RECOVER when no jumps left and recovery available). Easy preset behavior unchanged; bot never charges.
- [ ] 5b.13 Static review [S]: intent S5 fields never leak into `PlayerAIController`; `get_obs()`/`get_action_space()` byte-identical; `train.tscn` diff empty; slices of `punch.gd` honor tap vs charge.
- [ ] 5b.14 Static audit: `rg -n "Input\." game/player/StateMachine` empty; four new bindings unique; no new files under `assets/`; no `print(` in touched files.
- [ ] 5b.15 Manual playtest smash moves [P] (user): tap is a normal punch; holding up to ~1 s glows and the release hits harder and farther; hold of 3 s gives the same as 1 s; up, down and side punches send targets at clearly different angles; recovery once per airtime, resets on landing and on being hit, returns a fighter from off-stage, ring-out still possible at 150%+ damage; Normal and Hard CPU use directional punches and recovery, Easy does not; E/C and I/Comma keys are comfortable on a shared keyboard.

---

## Final integration

- [ ] F.1 After the last slice: full-branch static audit (`rg` for `print(`, `Intructions`, `move_punch_offset`, `Input.` in States), and mark F2, F3, F4, F5, F8 resolved in `odd/tasks/kitchen-food-fight.md` advisories.
- [ ] F.2 User confirmation items from the design open questions: default P2 controller (CPU Normal), key choice, TRAINING restoration in `train.tscn`, input behavior during hit-stop.

## Future / Backlog (not in this change)

- Unique per-character moves and traits (Smash-style kits): supply a distinct `FighterProfile` per character, plus per-character `AttackProfile` sets and moveset flags. The seam is created in S1 (Task 1.2); this change keeps both characters identical.
- Publish the new web build to the HuggingFace Space `RafaelJaime/BroVSister`. This is a remote operation: it needs explicit user authorization of the destination, operation and credentials at that time; do not probe or reuse ambient sessions.
- Align Godot versions: local Steam editor 4.7.2 (`~/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app`), `project.godot` 4.6, `.github/workflows/deploy-pages.yml` CI 4.5.
- Follow-up change `hf-ai-opponents`: schema freeze (obs/action), GDScript ONNX MLP interpreter, HuggingFace model discovery, bundled models. It builds on this change's `FighterController` seam and `gameplay-state-snapshot`.
- Per-food effects (heal, speed, stun) and stage hazards.
- Optional automated test runner (GUT or gdUnit4) now that a Godot CLI exists locally; would close F6.
- Not planned here: CPU charge-smash use, air charge, fast-fall, new game modes.
