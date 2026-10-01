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
| S-A | Stage, camera, hitboxes, visuals (inserted after the S1 playtest, runs before S2) | ~700 incl. smoke harness | Yes (`size:exception`) |
| S2 | Movement feel, hit rules (F4, F5); punch fix moved to S-A | ~200 | No |
| S3 | Scripted CPU, difficulty presets, controller select UI | ~300 | No |
| S4 | Match flow, F2/F3/F8, SFX pitch, typo | ~250 | No |
| S5a | Moved to S-A (match camera, snapshot camera field, shake offset reset) | 0 | No |
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
| S5a | Moved to S-A | PR 5 (base PR 4) | N/A. Static: clamp math walk-through in 5a.4 | Editor: camera checklist (user) | `game/camera/match_camera.gd`, `Camera2D` script attach in `game.tscn`, Game snapshot `camera` key, `hurt.gd` offset reset |
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

## Phase S-A: Stage, camera, hitboxes, visuals

Inserted after the S1 playtest ("looks terrible, all hitboxes buggy; one map, moving camera, no two heights, a table"). It runs BEFORE S2. Source of truth for the numbers: engram `sdd/fun-gameplay-overhaul/explore-stage-hitbox`. Ambiguities are resolved the way Super Smash Bros does. Specs: match-camera (revised for the 1176x902 world), combat-hits (hitbox), gameplay-state-snapshot (camera key). Design Decisions 20 and 21 are superseded by this phase (see deviations in apply-progress).

Verification model for this phase differs from the rest: the user authorized running Godot, so every task is proven by the smoke harness in `tests/smoke/` (`tests/smoke/run_all.sh`), plus screenshots reviewed by the apply agent.

- [x] A.1 Edit `game/game.tscn`: game-own `Backdrop` Sprite2D (`fondo_cocina_junto.png`, native scale 1, `centered = false`, mipmap filter); remove the shared `background` instance, `ColorRect`, tablecloth sprites, both platforms and their sprites. Single `StaticBody2D/Floor` (800x60 at (430,510), top y=480, x 30..830) so the node path survives; no walls (ring-out on both sides). Fighters spawn at (330,380) and (630,380).
- [x] A.2 Edit `game/game.gd`, `game/player/player.gd`, `game/food/food_spawner.gd`: blast zones become `Game` exports (L -100, R 1276, B 810, T -400) pushed into each fighter as `blast_zone`; the hardcoded `Fighter` constants are removed; `Backdrop` is freed when `training`; spawner uses local coordinates (`food.position`, range x 100..760 over the counter), which also resolves F2.
- [x] A.3 Create `game/camera/match_camera.gd` and attach it to `Camera2D`: midpoint follow of fighters with `stocks > 0`, distance-based zoom clamped to 0.75..1.15, exponential smoothing, y soft clamp 300..420, Camera2D limits 0..1176 x 0..902, view clamped inside the world, writes `position`/`zoom` only; no-op when the parent is `training`. (Moved from S5a 5a.1, 5a.2.)
- [x] A.4 Edit `game/game.gd`: snapshot `platforms` is `[]`, new `camera: {center, zoom}` key. (Moved from S5a 5a.2.)
- [x] A.5 Edit `hurt.gd`: reset the shake `offset` to ZERO at the end of the shake tween. (Moved from S5a 5a.3.)
- [x] A.6 Edit `game/player/player.tscn`: movement body shrinks to 56x150 at (0,19) (bottom y=94, feet on the floor); new `Hurtbox` Area2D 120x171 at (0,8) matching the art, and `Combat.apply_hit` resolves through it.
- [x] A.7 Edit `punch.gd`, `fighter_profile.gd`, `player.tscn`: single `PunchArea` shape (center `(75*facing, -10)`, 110x40) mirrored by the locked facing, monitoring only during the active window, hit-once set per swing, NO owner teleport (`move_punch_offset` removed, second shape and `punch_distance` removed, `train.tscn` overrides dropped). (Supersedes S2 2.6.)
- [x] A.8 Dedicated physics layers: world 1, fighter body 2 (mask world only), food pickups 3, hurtboxes 4. Fighters pass through each other with a soft horizontal push-apart (`Fighter._apply_soft_push`); no standing on heads; food is not solid to fighters; projectiles and punches detect hurtboxes. Layer names in `project.godot`. (Supersedes S4 4.5.)
- [x] A.9 Smash facing: `Fighter.facing` follows the move input (initially toward the enemy) and is locked during Punch, Shoot, Hurt, Protect, Defeated; sprite flip follows `facing`; throws go in the facing direction; the dash no longer re-flips the sprite. This is what makes "enemy behind" a real situation for the mirrored hitbox.
- [x] A.10 Visuals: mipmaps via `[importer_defaults]` in `project.godot` (new imports on a clean clone) plus `texture_filter = LINEAR_WITH_MIPMAPS_ANISOTROPIC` on fighter sprites, held food and backdrop; HUD gradient mirrored for the right side and labels inside their panels.
- [x] A.11 Edit `train.tscn`: respace `Game` instances to x spacing 1400 (columns -1400, 0, 1400, 2800, 4200, y spacing unchanged), retune the root `Camera2D`; drop the dead `punch_distance` overrides. Backdrop is freed when training. `train.tscn` must load without script errors.
- [x] A.12 Create `tests/smoke/` (`smoke_util.gd`, `stage_floor.gd`, `combat.gd`, `movement.gd`, `camera.gd`, `train_loads.gd`, `screenshots.gd`, `run_all.sh`): windowed SceneTree scripts that instantiate `game/game.tscn`, drive fighters through the controller intent seam, assert with PASS/FAIL and a non-zero exit, and save screenshots to `$SHOT_DIR` (not committed).
- [x] A.13 Run `tests/smoke/run_all.sh` and `--headless --check-only` on every changed script; all green.
- [ ] A.14 Manual playtest S-A [P] (user): one fixed-height counter, camera follows and zooms, punches hit what the art shows, fighters pass through each other, food never blocks, sprites are smooth, HUD readable.

## Phase S2: Movement feel, hit rules (F4, F5)

Specs: fighter-movement (all), combat-hits (hitstun, F4, F5; the hitbox requirement moved to S-A). Design Decisions 5-12.

Verification for S2 (user authorized running Godot): `tests/smoke/movement_feel.gd`, `hit_rules.gd`, `hud.gd`, `food_size.gd` (plus the S-A scripts) via `tests/smoke/run_all.sh`. Fast fall is not implemented (no down input exists until S5b; "Not planned here"). Being hit also refills the double jump and air dash (user request), implemented in `Hurt._enter`.

### S2 additions (user request, same slice)

- [x] 2.H1 Remove the top red/blue gradient bands and the damage progress bars from the fighter HUD (`player.tscn` PlayerUI subtree and its sub-resources). Verify: `hud.gd` finds no `ProgressBar` and no `GradientTexture1D`.
- [x] 2.H2 Rewrite `game/player/player_ui.gd` (`class_name FighterHud`, still a `CanvasLayer`, so camera zoom never affects it): bottom-of-screen panels (P1 left, P2 right) with face portrait, name and a BIG damage percent; the number color lerps white, yellow, red, dark red (`FighterHud.damage_color`); portrait comes from `CharacterUI.face_texture` or falls back to `assets/images/game/characters/{name}/face/{x}_014.png`. Signals `damage_changed` and `stocks_changed` keep their handlers. Hidden in training rows.
- [x] 2.H3 Hit "pop" on the damage number (scale and rotation tween owned by the HUD layer) and one mini face per stock (visible count equals stocks).
- [x] 2.H4 Small match timer at top-center (`game.tscn` `TimerLabel`: font 40, outline, top-wide anchors).
- [x] 2.H5 Smoke `tests/smoke/hud.gd` (18 checks): panel placement, no bars or bands, portrait and name, % text and color after hits, pop and settle, stock decrements, timer size and position; screenshots `s2_hud_after_damage`, `s2_hud_after_stock_loss`.
- [x] 2.F1 Food readable: pickups and projectiles scale 0.6 (about 58 px), held food 0.55 at y -115 (about 53 px), circle shapes radius 29 to match, mipmapped filter. Smoke `tests/smoke/food_size.gd` (5 checks over all 20 foods).
- [x] 2.T1 Smoke `movement_feel.gd` (19 checks: short vs full hop, double jump once and restored, coyote, expired coyote, buffer, dashes) and `hit_rules.gd` (25 checks: air punch, air block, air throw, hitstun scaling and action lock, post-hit invulnerability, F4 race, respawn blink, F5 hit-stop).

- [x] 2.1 Edit `game/player/fighter_profile.gd`: add movement and hit tuning from the design Tuning Defaults table (ground/air accel, gravity 1800, fall multiplier 1.2, max fall 1000, jump -850, double jump -750, jump_cut 0.45, coyote 0.10, buffer 0.10, max_air_jumps 1, dash ground/air durations, hitstun clamp params, hurt_gravity_scale 0.6, post_hit_invulnerability 0.5, respawn invulnerability 1.5, hit-stop). Changing profile defaults is the single place the new feel is tuned; keep both characters identical.
- [x] 2.2 Edit `game/player/player.gd`: add `jumps_left`, `air_dash_available`, `coyote_timer`, `jump_buffer_timer`, `_coyote_blocked`, `_tick_movement(delta)` (resets on landing, blocks triple jump), `resolve_jump() -> JumpKind` (Decision 6). Verify [S]: truth table for ground, coyote, air, buffer, coyote-expired matches the fighter-movement spec scenarios.
- [x] 2.3 Edit `player.gd`: `grant_invulnerability(duration, blink := true)` using a one-shot `_invuln_timer` child and a node-bound looping `_blink_tween` (F4); timeout clears the flag, kills the tween, restores sprite visibility; `reset_player()` stops both; `_respawn()` calls it with the respawn duration using `max(remaining, duration)`. Verify [S]: no `get_tree().create_tween()` or `await ...create_timer` left for invulnerability.
- [x] 2.4 Edit `motion.gd`: gravity from profile (fall multiplier, max fall speed), ground and air acceleration. Edit `jump.gd`: GROUND and AIR kinds, velocity by kind, short hop (`velocity.y *= jump_cut_multiplier` once when `!jump_held and velocity.y < 0`), air actions. Edit `fall.gd`, `idle.gd`, `run.gd`: `resolve_jump()`, landing to Idle, air actions.
- [x] 2.5 Edit `dash.gd`: dash from Idle, Run and air; air dash consumes `air_dash_available`, suspends gravity, shorter duration; `can_enter()` is `on_floor or air_dash_available`.
- [x] 2.6 **Moved to S-A (A.7).** Edit `punch.gd`: single mirrored hitbox from locked `facing` and `profile` offset, active-window polling of `punch_area.get_overlapping_bodies()` with a `_hit_targets` set, air punch applies gravity, delete `move_punch_offset` and `body_entered` connect churn. Edit `player.tscn`: delete `PunchArea/CollisionShape2D2`. Verify [S]: `rg move_punch_offset` returns nothing; owner `position` is never written in `punch.gd`.
- [x] 2.7 Edit `shoot.gd`, `protect.gd`: air variants, hold-to-block bounded by `block_duration`, gravity in air, `exit_to_neutral()`.
- [x] 2.8 Edit `hurt.gd`: hitstun scaled by knockback (`clamp(base + |kb| * per_kb, min, max)`), `hurt_gravity_scale`, keep x momentum, call `owner.grant_invulnerability(post_hit_invulnerability)` only in `_on_hurt_finished()`, connect the timer once. Verify [S]: Hurt-to-Hurt re-entry grants no invulnerability.
- [x] 2.9 Edit `game/combat/combat.gd`: `static var _hit_stop_token`, token-guarded restore of `Engine.time_scale`, `static func cancel_hit_stop()` (F5). Edit `game/game.gd`: `_exit_tree()` calls `Combat.cancel_hit_stop()` when not training. Verify [S]: training path never touches `time_scale`.
- [x] 2.10 Edit `game/player/player.tscn`: `available_actions` for Idle, Run, Jump, Fall set to `["dash","jump","punch","protect","shoot"]` (recovery added in S5b).
- [x] 2.11 Static logic review [S]: hit-stop overlap ends at 1.0; invulnerability extension logic; hitstun + post-hit invulnerability (0.8 s) exceeds punch cooldown (0.7 s); `train.tscn` overrides (`punch_distance`, `punch_duration`, `punch_cooldown`, `[]` available_actions) still resolve.
- [x] 2.12 Update comments and docs touched by the slice (no doc files created). Remove temporary code.
- [ ] 2.13 Manual playtest S2 [P] (user): jump apex visibly lower and shorter; short hop, coyote jump, buffered jump, double jump (no triple); air punch, throw, block; dash from Idle, Run, air (once per airtime); punch mirrored left/right and owner never moves; no stun-lock under repeated punches; two overlapping hits leave `Engine.time_scale == 1.0` (remote inspector); respawn blink ends cleanly and a second respawn restarts it.

## Phase S3: Scripted CPU and controller/difficulty select

Specs: cpu-opponent (behaviours, three levels, single-player), match-flow (controller select UI). Design Decisions 13, 14.

Verification for S3 (user authorized running Godot): `tests/smoke/cpu_combat.gd`, `cpu_recovery.gd`, `cpu_match.gd`, `cpu_select.gd` (headless: they simulate minutes of game time) and `cpu_shots.gd` (windowed screenshots), all through `tests/smoke/run_all.sh`. Deviations from the design text: the bot also has `aggression` and `recovery_skill` fields (Smash-style CPU levels), and the RECOVER plan runs on a shorter reaction time than the other plans; `Game.get_state_snapshot()` gained a `blast_zone` key (additive).

- [x] 3.1 Create `game/player/controllers/cpu_difficulty.gd`: `CpuDifficulty extends Resource` with exported fields and `static func preset(level)` for Easy, Normal, Hard using the design preset table (S5 fields `use_directional`, `use_up_recovery` added in 5b.12). Verify [S]: Easy delay > Normal > Hard; accuracy ordered the other way. Smoke: `cpu_combat.gd` preset ordering checks.
- [x] 3.2 Create `game/player/controllers/scripted_controller.gd`: reaction-tick loop reading `game.get_state_snapshot()`; plan priority RECOVER, DEFEND, THROW, PICKUP, ATTACK, APPROACH (Decision 13); held flags persist between ticks; pressed flags are a one-frame pending-press latch with a release frame before the next press; never walks off the stage edge while grounded; `attack_held` always false. Verify [S]: emits only `FighterIntent`; reads stage rect from the snapshot, no hardcoded coordinates. Smoke: `cpu_combat.gd` (approach and hits, Easy vs Hard damage), `cpu_recovery.gd` (14 recovery scenarios), `cpu_match.gd` (no self-destruction over 85 s at Hard and Normal, full match to game over).
- [x] 3.3 Edit `game/player/controllers/controller_config.gd`: `build()` returns `ScriptedController` for CPU using the preset or the optional `difficulty_resource`. Remove the 1.8 placeholder. (Also: `Fighter.ControllerKind.CPU` builds a Normal bot; a Policy config whose model file is missing falls back to the CPU instead of an idle fighter.)
- [x] 3.4 Edit `scripts/SceneManager/scene_manager.gd`: `play_game(c1, c2, cfg1 := null, cfg2 := null)` calls `fighter.set_controller(cfg.build(fighter))` after `add_child`; store `last_match` (used by S4 rematch). Null cfg keeps the AUTO controller.
- [x] 3.5 Edit `ui/character_select/character_select.tscn`: add `ControllerOption` (OptionButton: Human, CPU Easy, CPU Normal, CPU Hard) in `ControlP1` and `ControlP2`, above the existing AI widgets. Defaults P1 Human, P2 CPU Normal (open question in design; flag for user).
- [x] 3.6 Edit `ui/character_select/ai_controller.gd`: option visibility in `initial_menu`; `get_controller_config(is_p2)`; a selected HF model takes precedence and yields a Policy config. Edit `ui/character_select/character_select.gd`: pass configs to `SceneManager.play_game`. Smoke: `cpu_select.gd` (29 checks).
- [x] 3.7 Static review [S]: `rg "ScriptedController|ControllerConfig"` call graph; HF/ONNX option stays functionally unchanged (ONNX turns on only through an explicit Policy config); `train.tscn` diff empty; `scripts/AIController/player_ai_controller.gd` untouched.
- [x] 3.8 Comments and docs on tunable difficulty fields (doc comments on every `CpuDifficulty` field).
- [ ] 3.9 Manual playtest S3 [P] (user): Human vs CPU Easy, Normal, Hard with no HF model; CPU approaches, punches, blocks, picks up and throws food, recovers to the stage from an edge; Easy is visibly slower and less accurate than Hard; CPU never idles at spawn; 2P Human vs Human still works (switch P2 to Human; P2 defaults to CPU Normal now).

## Phase S-T: Table stage and framing

User feedback after S3: "Right now they are floating in the air; let's put a table like this" (reference: rectangular table, red/white gingham cloth over the top and hanging over the front and sides, wooden legs below, standing in a room). Only existing assets are used (`assets/images/game/plataformacuadrados.png` for the cloth); legs, floor, shadows are drawn in code. The tabletop front edge is the fight floor, so the `StaticBody2D/Floor` collider is unchanged (top y=480, x 30..830).

Verification: `tests/smoke/table_stage.gd`, `hud_framing.gd` (CPU vs CPU, 30 s, sampled every 0.5 s), updated `stage_floor.gd`, `camera.gd`, `hud.gd`, plus every older script via `tests/smoke/run_all.sh`.

- [x] T.1 Create `game/stage/table_stage.gd` (`TableStage`) and `fighter_shadows.gd`; add `TableStage` to `game/game.tscn` between `Backdrop` and the fighters: room floor and baseboard, contact shadow, shaded underside, 4 wooden legs with dark outline, gingham front drape (wavy darker hem, fold lines), side flaps at both ends, perspective tabletop band using the gingham texture, thick red-brown outline. Ground shadow under each fighter that shrinks with height. Freed when `training`.
- [x] T.2 Edit `game/game.tscn`, `game/game.gd`: `Backdrop` shifted to x=-158 and dimmed (modulate) so the 800px table is centered on the 1176px art; blast zones retuned (-230..1090); free `TableStage` in training. Spawns and spawner range stay on the table.
- [x] T.3 Edit `game/camera/match_camera.gd`: world rect `Rect2(-158, 0, 1176, 902)`, bottom `hud_reserve` (130 px) so the tabletop sits above the HUD band at every zoom, wider horizontal margin so the whole table fits at the start.
- [x] T.4 Edit `game/player/player_ui.gd`: compact panels (about 232x100, lighter background).
- [x] T.5 Tests: `stage_floor.gd` (shifted backdrop, table spans the floor, feet within 4 px), `camera.gd` (shifted limits), `hud.gd` (compact panel), new `table_stage.gd` and `hud_framing.gd`; register in `run_all.sh`.
- [x] T.6 Screenshots reviewed (start, zoomed-in fight, zoomed-out, fall off the table end) and tuned.
- [ ] T.7 Manual playtest S-T [P] (user): the table reads as ground, HUD never hides a fighter, the cloth matches the kitchen art.

## Phase S4: Match flow, F2/F3/F8, SFX pitch, typo

Specs: match-flow (countdown, sudden death, rematch, pause, instructions), food-fight-items (F2, F3, F8, SFX pitch). Design Decisions 15, 16, 21, 22.

- [x] 4.1 Edit `game/player/player.gd`: `set_stocks(n)` emits `stocks_changed`.
- [x] 4.2 Edit `game/game.gd` and `game/game.tscn`: `Phase` enum (COUNTDOWN, PLAYING, SUDDEN_DEATH, OVER); `Timer.autostart = false`; `UI/CountdownLabel` (centered, font size 96); countdown "3-2-1-GO" with pausable timers (`create_timer(step, false)`); lock and unlock fighters; training path starts immediately as today. Update the Game snapshot `phase`, `sudden_death`, `timer_running`.
- [x] 4.3 Edit `game/game.gd`: timeout logic (unequal stocks, equal stocks to sudden death with both at 1 stock, timer off, `TimerLabel` hidden, "SUDDEN DEATH" shown 1 s), `phase != OVER` guard in `_on_player_defeated`, null-guard `game_over` in training rows (F3). Edit `ui/global/timer_label.gd`: show `wait_time` while stopped.
- [x] 4.4 Edit `game/food/food_spawner.gd`: `start()` instead of self-start. (The F2 part, `food.position` instead of `global_position`, is done in S-A A.2.)
- [x] 4.5 **Moved to S-A (A.8).** Superseded layer plan: world 1, fighter body 2 (mask world), food 3, hurtbox 4. Original text: Edit `game/food/food_pickup.tscn`, `food_projectile.tscn`, `game/player/player.tscn`, `project.godot`: layers per Decision 21 (fighters on layer 2, food on layer 3, masks per table) and `[layer_names]`. Verify [S]: table in design matches every node's `collision_layer`/`collision_mask`; `train.tscn` inherits without edits.
- [x] 4.6 Edit `game/audio/sfx.gd`: `EVENTS` table with the design bands, `play_event()`, `is_training()` (moved from `Combat`), keep `play()`. Edit `game/combat/combat.gd`, `shoot.gd`, `jump.gd`, `player.gd`: call `play_event` for hit, heavy_hit, block, pickup, throw, jump, double_jump, ko. Verify [S]: bands do not overlap per source sound.
- [x] 4.7 Edit `game/ui/pause/pause.gd`: Esc toggles pause and unpause, `set_input_as_handled()`, ignored while game over is visible.
- [x] 4.8 Edit `scripts/SceneManager/scene_manager.gd`: `rematch()` replays `last_match`. Edit `game/ui/game_over/game_over.gd` and `game_over.tscn`: Replay calls `SceneManager.rematch()`, new "Characters" button opens character select; both unpause first.
- [x] 4.9 Fix the typo: `ui/instructions/instructions.tscn` title; rename `IntructionsButton` and `_on_intructions_button_pressed` in `ui/main_menu/main_menu.tscn` and `ui/main_menu/main_menu_buttons.gd`; add instruction lines for double jump, dash (double-tap), air actions. Verify [S]: `rg -i "Intructions"` returns nothing anywhere.
- [x] 4.10 Static review [S]: hit-stop and invulnerability untouched; training path equals baseline behavior.
- [x] 4.11 Remove temporary code and finalize comments.
- [x] 4.12 Static audit: no `print(` in per-frame paths; no new files under `assets/`.
- [ ] 4.13 Manual playtest S4 [P] (user): every match starts 3-2-1-GO with fighters locked; pause during countdown freezes digits; timeout tie goes to sudden death; double KO ends once; rematch keeps characters and controllers; "Characters" returns to select; Esc opens and closes pause; food passes through fighters and does not ride heads; pitch bands audibly different per event; food spawns in the correct place inside a train row (F2).

## Phase S5a: Match camera (moved to S-A)

Specs: match-camera (all), gameplay-state-snapshot (S5 camera). Design Decision 20 (superseded: Camera2D limits plus a script clamp, world 1176x902, zoom 0.75..1.15). Every item below is done in S-A A.3-A.5, with the camera checks covered by `tests/smoke/camera.gd`.

- [x] 5a.1 (S-A A.3) Create `game/camera/match_camera.gd`: follow midpoint of fighters with `stocks > 0`, distance-based zoom clamped to `[1.0, 1.4]`, exponential smoothing, manual clamp to `Rect2(0,0,800,600)` bounds with `half = viewport / (2 * zoom)`, writes `position` and `zoom` only; no-ops when parent `training`.
- [x] 5a.2 (S-A A.3, A.4) Edit `game/game.tscn`: attach `match_camera.gd` to the existing `Camera2D`. Switch to drag-center only at runtime outside training. Edit `game/game.gd`: Game snapshot `camera: {center, zoom}`.
- [x] 5a.3 (S-A A.5) Edit `game/player/StateMachine/PlayerStateMachine/States/hurt.gd`: reset shake `offset = Vector2.ZERO` at the end of the shake tween. Shake keeps using `offset`.
- [x] 5a.4 (smoke `camera.gd`) Static review [S]: clamp math at zoom 1.0 (view equals today's framing) and 1.4 near all four corners; `train.tscn` root `Camera2D` has no script; HUD is on a `CanvasLayer`.
- [ ] 5a.5 (folded into A.14) Manual playtest camera [P] (user): follows both fighters; zooms out as they separate and never beyond 1.0; never shows past the background; HUD fixed and readable at 800x600; hurt shake still visible and leaves no residual offset; `train.tscn` cameras unchanged.

## Phase S5b: Smash moves and bot extension

Specs: smash-moves (charge, recovery, directional), combat-hits (knockback by charge and direction), cpu-opponent (directional/recovery use), fighter-control (up/down inputs), gameplay-state-snapshot (S5 fields). Design Decisions 17-19.

- [x] 5b.1 Edit `project.godot` `[input]`: add `P1_up` (E), `P1_down` (C), `P2_up` (I), `P2_down` (Comma). Verify [S]: none duplicates an existing binding or `ui_*` default.
- [x] 5b.2 Edit `game/player/controllers/human_controller.gd`: aim mapping (UP, DOWN, SIDE when `move_x != 0`, else NEUTRAL) and `special_pressed = attack_pressed and aim == UP`; `attack_held`/`attack_released` populated. Verify [S]: no change to `PolicyController` (S5 fields stay neutral).
- [x] 5b.3 Create `game/combat/attack_profile.gd`: `AttackProfile extends Resource` (damage, knockback, hitbox_offset).
- [x] 5b.4 Edit `.../States/punch.gd`: five profiles with the design values (neutral built from `punch_damage`, `punch_knockback`, `punch_distance` so `train.tscn` overrides keep working), phases WINDUP, CHARGING, ACTIVE, RECOVERY, `tap_threshold` 0.15 s, charge capped at 1.0, fire on release, air or non-held-at-entry fires immediately, damage and knockback scaled by `lerp(1, max, charge)`, sets `last_attack_direction`, `_exit` hides glow.
- [x] 5b.5 Edit `game/combat/combat.gd`: knockback scaled by charge and direction angle. Edit `.../States/hurt.gd`: `owner.recovery_available = true` on hit.
- [x] 5b.6 Edit `game/player/player.gd`: `recovery_available`, `charge_level`, `last_attack_direction`, `set_charge_visual(charge)` (< 0 hides), reset `recovery_available` on landing, S5 snapshot keys. Edit `game/player/player.tscn`: `ChargeGlow` Sprite2D using the existing texture `res://assets/textures/2D Fire  - Tutorial/T_VFX_Glow_1.PNG` (uid `uid://dmybar0g2nd2a`), additive material, hidden, modulate by character color. Verify [S]: no new files under `assets/`.
- [x] 5b.7 Create `.../States/recovery.gd`: `Recovery extends Motion` per Decision 19 (velocity -950, drift 250, gravity and reduced air control, to Fall when `velocity.y >= 0`, `available_actions = []`, existing jump frame, `play_event(&"recovery")`). Edit `player.tscn`: add `Recovery` state node and `"recovery"` to Jump and Fall `available_actions`; `Recovery.can_enter()` returns `owner.recovery_available`. Respect `profile.can_recover` flag (from 1.2).
- [x] 5b.8 Edit `.../States/motion.gd`: in air, `special_pressed` with recovery available goes to Recovery; otherwise falls through to a normal air punch. Ground `special_pressed` ignored; ground up-aim punch is an up-punch.
- [x] 5b.9 Edit `game/audio/sfx.gd`: `&"recovery"` band 1.18-1.28.
- [x] 5b.10 Honor `FighterProfile` moveset flags (`can_charge`, `can_recover`, `can_air_punch`) in `can_enter()` checks, all true for both characters now.
- [x] 5b.11 Edit `ui/instructions/instructions.tscn`: charge, directional attacks, recovery chord (`up` + punch in air), up/down keys.
- [x] 5b.12 Edit `cpu_difficulty.gd` (`use_directional`, `use_up_recovery`: Easy false, Normal and Hard true) and `scripted_controller.gd` (aim UP when enemy above, DOWN in air above the enemy, SIDE near edge with damage above 60%, `special_pressed` in RECOVER when no jumps left and recovery available). Easy preset behavior unchanged; bot never charges.
- [x] 5b.13 Static review [S]: intent S5 fields never leak into `PlayerAIController`; `get_obs()`/`get_action_space()` byte-identical; `train.tscn` diff empty; slices of `punch.gd` honor tap vs charge.
- [x] 5b.14 Static audit: `rg -n "Input\." game/player/StateMachine` empty; four new bindings unique; no new files under `assets/`; no `print(` in touched files.
- [ ] 5b.15 Manual playtest smash moves [P] (user): tap is a normal punch; holding up to ~1 s glows and the release hits harder and farther; hold of 3 s gives the same as 1 s; up, down and side punches send targets at clearly different angles; recovery once per airtime, resets on landing and on being hit, returns a fighter from off-stage, ring-out still possible at 150%+ damage; Normal and Hard CPU use directional punches and recovery, Easy does not; E/C and I/Comma keys are comfortable on a shared keyboard.

---

### S5b additions (user request, same slice; verified by `tests/smoke/smash_moves.gd`, `ledge.gd`, `cpu_smash.gd`)

Deviations from the task text: the recovery SFX band is 1.12-1.20 (1.18-1.28 would overlap the pickup band 1.22-1.32; the match_flow audit forbids overlaps); the ledge SFX band is 1.58-1.65; the side punch is used by the bot (damaged opponent near a table end) as well as up and down; the human chord is `up` + `punch` (Decision 17); a ledge jump is on `jump` (Smash) and `up` or pushing toward the table climbs; fast fall is a new `FighterProfile` group (Fall state, down held after the apex); walking off a table end now grabs the leg unless the fighter holds away from the table or down (movement and movement_feel tests adapted).

- [x] 5b.F1 Fast fall: `Fall` snaps `velocity.y` to `fast_fall_start_speed` when down is held while falling and `Motion.calculate_gravity` raises the cap to `fast_fall_speed` until landing or another action.
- [x] 5b.H1 Helpless fall: `Helpless` state after `Recovery` (drift only, no actions) until landing, a ledge grab or a hit.
- [x] 5b.L1 Table: outer legs flush with the table ends (`TableStage.LEG_OVERHANG`), `Game.get_ledges()` (grab zones tabletop to leg bottom, empty in training), snapshot `ledges`.
- [x] 5b.L2 `LedgeHang` state: snap to the leg, face the table, refill air actions and recovery, invulnerability 1.0 s decaying 0.3 s per grab since the ground or a hit, max hang 4 s, drop (down or away), climb (up or toward), ledge jump (jump, keeps the air jump), climb attack (punch), `Fighter._try_ledge_grab` rules (rising, away, down, lockout 0.6 s), trump.
- [x] 5b.L3 CPU: plan LEDGE (wait, then climb, ledge jump or climb attack) and a ledge-aware RECOVER (steers to the nearest leg when the stage is out of reach, uses the up-recovery after the double jump).
- [x] 5b.L4 Tests: `ledge.gd` (30 checks), `cpu_smash.gd` (19 checks: 20-trial recovery rates, up-recovery use, directional punches, Easy plain, 60 s bot fights with 0 self-destructs), `smash_moves.gd` (37 checks), all in `run_all.sh`.
- [x] 5b.P1 Polish: damage % outline 12 plus shadow and a lighter dark-red end stop; results screen hides the timer and fighter panels, "<NAME> WINS!" with clear Rematch / Characters / Main Menu buttons.
- [x] 5b.P2 Fix: `Fighter._respawn` and `prepare_sudden_death` clear the state machine velocity (stale knockback carried a respawned fighter out again).

## Final integration

- [x] F.1 Full-branch static audit: `rg` finds no `print(` in `game/`, `ui/`, `scripts/`; no `Intructions` outside the openspec text that describes the fix; no `move_punch_offset` outside the openspec text; no `Input.` in `game/player/StateMachine`. The advisories F2 (food spawner uses local coordinates), F3 (`game_over` null-guarded before `set_forced_winner`), F4 (node-owned invulnerability timer), F5 (token-serialized hit-stop) and F8 (food on layer 3 with mask 1, fighters mask 1: no body collision) are verified fixed in code; they are marked resolved in the working copy of `odd/tasks/kitchen-food-fight.md`, which stays uncommitted by instruction.
- [x] F.2 Open questions, resolved the Smash way. Default controllers: P1 Human, P2 CPU Normal for single player; a local two-player match picks Human for P2 in the select (kept). Keys `E`/`C` and `I`/`Comma` stay (rebindable in Project Settings; the on-screen instructions list them). TRAINING restoration: `train_loads.gd` now asserts all 50 fighters keep `control_mode` TRAINING and are policy-driven, so the Python server connection is the only part left to the editor. Inputs during hit-stop: the stop lasts 80 ms and the jump buffer (0.1 s) covers jumps; a punch tap shorter than the stop is the only theoretical miss, accepted and left to the playtest.
- [x] F.3 Final polish from the orchestrator review of the screenshots: the charge glow keeps the fighter's colors (bright flash 10-15 Hz that speeds up with the charge, small additive glow at the fist, tiny shake); the camera world grows to (-300, -300)-(1160, 902) with `BackdropExtension` filling the wall around the art, follows a high fighter (look-ahead, fast catch-up) and zooms out to 0.58 to keep it in view while the table stays above the HUD band; results confetti is scaled up so it reads as confetti, not as stray pixels; `tests/smoke/match_reel.gd` plays a full CPU Hard vs CPU Normal match from the character select and saves a frame every 2 game seconds.

## Future / Backlog (not in this change)

- Unique per-character moves and traits (Smash-style kits): supply a distinct `FighterProfile` per character, plus per-character `AttackProfile` sets and moveset flags. The seam is created in S1 (Task 1.2); this change keeps both characters identical.
- Publish the new web build to the HuggingFace Space `RafaelJaime/BroVSister`. This is a remote operation: it needs explicit user authorization of the destination, operation and credentials at that time; do not probe or reuse ambient sessions.
- Align Godot versions: local Steam editor 4.7.2 (`~/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app`), `project.godot` 4.6, `.github/workflows/deploy-pages.yml` CI 4.5.
- Follow-up change `hf-ai-opponents`: schema freeze (obs/action), GDScript ONNX MLP interpreter, HuggingFace model discovery, bundled models. It builds on this change's `FighterController` seam and `gameplay-state-snapshot`.
- Per-food effects (heal, speed, stun) and stage hazards.
- Optional automated test runner (GUT or gdUnit4) now that a Godot CLI exists locally; would close F6.
- Not planned here: CPU charge-smash use, air charge, fast-fall, new game modes.
