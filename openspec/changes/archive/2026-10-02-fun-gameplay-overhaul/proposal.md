# Proposal: Fun Gameplay Overhaul

## Intent

The game plays poorly: the jump floats (~360 px apex with gravity 500), fighters have no air actions, the dash is hard to trigger, the punch teleports its owner, and hits can stun-lock a fighter. The match has no countdown, sudden death, or quick rematch. Single player also does not work. P2 is either a human or an ONNX model, and the ONNX path is broken: nothing feeds actions, so the fighter idles and ignores input.

The game identity is confirmed as **Super Smash Bros style** (ring-out food fight; alternative genres rejected, see `sdd/bro-vs-sis-game/game-identity`). With only 1–2 frames per animation, the fun has to come from knockback physics, ring-outs, items, platforms, and the air game, plus a few Smash signature mechanics that need no new frames.

This change makes the existing game fun and fully playable using **existing assets only** (no new art or audio). It also leaves the code ready for the later `hf-ai-opponents` change. The main single-player experience will eventually be a match against an AI picked from HuggingFace. To prepare for that, this change adds:

- a controller seam that separates where input comes from (Human / Scripted / external policy) from the fighter that acts on it;
- a scripted CPU bot, so single player works now;
- a read-only accessor for the gameplay state.

It does **not** define or freeze the AI observation/action schema. Per the recorded ordering decision (`sdd/bro-vs-sis-game/change-ordering`), the schema is frozen only after these mechanics settle.

**Why now:** the mechanics have to settle before the AI schema can be frozen. Each mechanic that changes after the freeze forces retraining and contract churn.

## Scope

### In Scope

1. **Controller seam.** Add a per-frame `FighterIntent` value with these fields: move_x, jump pressed/held, attack, throw, block, dash, plus the S5 fields: attack held/released (for charge), aim direction (neutral / up / down / side), and special/recovery pressed. S1 declares all fields; the S5 fields stay inert until S5.
   - The intent comes from a pluggable controller: `HumanController` (P1/P2 input actions), `ScriptedController` (CPU bot), or `PolicyController` (an adapter over the existing `PlayerAIController` action floats, so `sync.gd` TRAINING/ONNX modes keep working).
   - `Motion` and its states read only the intent. This replaces today's split between the event-driven human path and the polling AI path.
   - The controller kind is chosen explicitly. The game path no longer auto-switches to ONNX just because `user://Agent{N}.onnx` exists (this removes the ghost-AI idle).
2. **Scripted CPU opponent** with three difficulty levels (Easy / Normal / Hard). It approaches, punches, blocks, picks up and throws food, and recovers to the stage (double jump back toward the floor). Difficulty is set by tunable reaction delay, action accuracy, and block/throw probability.
   - After S5, minimal extension only: at Normal/Hard the bot may use directional punches and the up-recovery move. Easy stays unchanged. The bot does not charge smash attacks (deferred to a follow-up).
3. **Controller/difficulty selection** in character select, per player: Human, or CPU Easy / Normal / Hard. The existing ONNX/HF option stays where it is and routes through `PolicyController`. It stays functionally unchanged and is still non-functional until `hf-ai-opponents` lands.
4. **Movement feel:**
   - snappier jump (higher gravity and jump velocity, short hop when jump is released early);
   - coyote time (~0.1 s) and a jump buffer (~0.1 s);
   - one double jump;
   - air punch, air throw, and air block (Jump and Fall get `available_actions`);
   - dash usable from Idle, Run, and air (one air dash per airtime). The double-tap trigger stays; no new input binding.
5. **Punch hitbox fix.** The hitbox moves or flips relative to facing, and the owner is never teleported (`punch.gd` `move_punch_offset` is removed).
6. **Hit rules:**
   - a short hitstun followed by a brief post-hit invulnerability window, so stun-locks end;
   - F4: invulnerability tween/timer race (bound tween, a new respawn cancels the previous one);
   - F5: hit-stop serialized, so overlapping hits never leave `Engine.time_scale` wrong.
7. **Match flow:**
   - pre-match countdown "3-2-1-GO" (existing `Label`/fonts);
   - sudden death on a timeout tie (both set to 1 stock, timer off);
   - instant rematch from game over with the same characters and controllers (character select stays reachable);
   - pause toggles with Esc;
   - the "Intructions" typo is fixed.
8. **Advisory fixes:**
   - F2: spawner uses coordinates local to the owning `Game`;
   - F3: `game.gd` null-guard in training rows;
   - F8: `FoodPickup` moves off the fighter collision layer, so it no longer blocks fighters or lands on heads.
9. **Hygiene:** remove debug `print()` calls from hot paths (`Motion._enter`, `PlayerAIController._ready`, `Fighter`).
10. **SFX pitch variation.** Random pitch on `Sfx` playback, with per-event pitch bands that reuse the existing 3 sounds, so pickup, throw, jump, and KO cues are distinguishable.
11. **Gameplay state accessor.** Read-only `get_state_snapshot()` methods on `Fighter` and `Game` that return plain dictionaries: position local to the owning Game, velocity, facing, on_floor, damage %, stocks, held food, FSM state, cooldowns, jumps left, food positions, timer.
    - The fields are documented as **unversioned and not a schema**.
    - The future schema module will read these dictionaries.
    - S5 adds: charge level (0..1), recovery available, last attack direction; and on `Game`, the camera center and zoom.
12. **Smash signature mechanics (slice S5, after S4, existing assets only).** All are driven by `FighterIntent`, so the CPU bot and future AI controllers can use them.
    - **Charged smash attack.** Holding punch charges up to ~1 s. While charging, the fighter glows using the existing glow texture (`assets/textures/2D Fire  - Tutorial/T_VFX_Glow_1.PNG`, already used in character select). On release, damage and knockback scale with the charge. A tap stays a normal punch. Charging is allowed only on the ground (air charge is deferred).
    - **Up-recovery move.** A special upward burst, usable once per airtime. It resets on landing and on being hit. It reuses the existing jump frame and the existing jump SFX with a pitch band.
    - **Camera follow and dynamic zoom.** The game `Camera2D` (`game/game.tscn`) tracks the midpoint between fighters and zooms out with their distance. Center and zoom are clamped so the view never shows past the stage/blast-zone bounds. The camera drives `position`/`zoom` only; the existing hurt shake keeps using `offset`. HUD stays on its `CanvasLayer`.
    - **Directional attacks.** Up / down / side punch variants with different knockback angles and tuning, reusing the existing punch frame. Input is the held direction plus punch.

### Out of Scope

- **AI obs/action schema definition or versioning, ONNX runtime work, the GDScript ONNX interpreter, HF discovery/browser, bundled models, training, reward changes, retraining.** All of this belongs to `hf-ai-opponents`. `PlayerAIController.get_obs()` and `get_action_space()` stay byte-compatible.
- **Per-food effects (heal, speed, stun, etc.) and stage hazards.** Deferred to a follow-up change. Rationale: they only pay off once the core feel is good, they push this change further past its budget, and the snapshot accessor is an open dictionary, so new food state can be added before the schema freeze without breaking this change.
- **New game modes** (survival, gauntlet, tournament), fast-fall, combos, air charge, and CPU use of charged smash attacks.
- **New input bindings**, unless the user resolves the S5 input decision below in favor of adding up/down actions.
- **Any new art or audio asset.**
- **Retuning `train.tscn`.** It must still load and run in TRAINING mode through `PolicyController`. It is not re-balanced.
- **Automated tests.** No runner exists (F6 stays open).

## Capabilities

`openspec/specs/` is empty, so every capability is new.

### New Capabilities
- `fighter-control`: per-frame intent contract (including charge, direction, and special/recovery fields); Human / Scripted / Policy controllers; explicit per-player controller selection; no implicit ONNX activation.
- `cpu-opponent`: scripted bot behaviours (approach, punch, block, food pickup/throw, edge recovery), the three difficulty levels, and directional/recovery use at Normal/Hard.
- `fighter-movement`: jump arc and short hop, coyote time, jump buffer, double jump, air actions, dash availability rules.
- `combat-hits`: punch hitbox placement without owner displacement; hitstun plus post-hit invulnerability; respawn invulnerability lifecycle (F4); serialized hit-stop (F5).
- `match-flow`: countdown, sudden death, instant rematch, pause toggle, controller/difficulty select UI.
- `food-fight-items`: spawn coordinates local to the owning Game (F2); pickup collision isolation from fighters (F8); event-specific SFX pitch variation.
- `gameplay-state-snapshot`: read-only, unversioned Fighter/Game state accessors, documented as an input for a future schema module.
- `smash-moves`: charged smash attack (charge window, glow feedback, scaled damage/knockback), up-recovery (once per airtime, reset rules), directional punch variants and their knockback angles.
- `match-camera`: camera follow, distance-based zoom, clamping to stage/blast-zone bounds, coexistence with hurt shake and HUD.

### Modified Capabilities
None. No existing specs.

## Approach

This follows exploration Approach 1, plus the SFX-pitch part of Approach 2 (the cheapest part). Food effects and hazards are dropped.

- **Seam first.** Add a `FighterController` base, a `FighterIntent` data class, and three implementations. `Fighter` holds one controller and samples its intent once per physics frame. States consume it through `Motion` helpers (`wants_jump()`, `move_axis()`, ...), so the duplicated human/AI branches in `motion.gd` collapse into one path.
  - `PolicyController` wraps `PlayerAIController`, so `sync.gd` keeps owning TRAINING/ONNX control modes and `train.tscn` keeps working.
  - Later, an ONNX or GDScript-interpreter policy only needs a new controller, with no FSM changes. This is the scalability the user asked for.
- **Movement and combat** are tuned through exported constants. Every number is flagged for manual playtest.
- **CPU bot** is a small utility/heuristic decision loop over the snapshot accessor (so the bot proves the accessor is useful). It emits `FighterIntent`, and difficulty parameters live in a `Resource`.
- **Match flow** goes into `game.gd`, the game-over screen, the pause screen, and character select. Rematch reuses the stored selections.
- **Advisories** are fixed in place, as their notes in `odd/tasks/kitchen-food-fight.md` describe.
- **S5 Smash moves** extend the `Punch` state with a charge phase and direction-dependent knockback vectors (exported per direction), and add a `Recovery` air state gated by a per-airtime flag. The glow is a `Sprite2D` child on the fighter, shown and scaled with charge. The camera is a small script on the existing `Camera2D` that reads both fighters' Game-local positions and the Game's blast-zone bounds. All new numbers are exported constants flagged for playtest.
- **Input map (checked in `project.godot`).** Each player has only `left`, `right`, `jump`, `protect`, `punch`, `shoot`. Pickup and throw are both on `shoot`, so holding `punch` to charge does **not** conflict with pickup/throw. There is no `up`/`down` action and no special key, so directional attacks and recovery need an input mapping decision (see below).

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `game/player/controllers/` (new) | New | `fighter_controller.gd`, `fighter_intent.gd`, `human_controller.gd`, `policy_controller.gd`, `scripted_controller.gd`, difficulty `Resource`s |
| `game/player/player.gd`, `player.tscn` | Modified | controller ownership, intent sampling, jumps/dash counters, snapshot, F4, print cleanup |
| `game/player/StateMachine/PlayerStateMachine/States/*.gd` | Modified | intent-driven transitions, jump feel, coyote/buffer, double jump, air actions, dash, punch hitbox, hitstun/invulnerability |
| `scripts/AIController/player_ai_controller.gd` | Modified | no auto-ONNX in game path, prints removed; obs/action API unchanged |
| `game/combat/combat.gd` | Modified | post-hit invulnerability, serialized hit-stop (F5) |
| `game/game.gd`, `game/game.tscn` | Modified | countdown, sudden death, rematch hook, F3 guard, Game snapshot |
| `game/food/food_spawner.gd`, `food_pickup.tscn` | Modified | F2 local coordinates, F8 collision layers |
| `game/audio/sfx.gd` | Modified | pitch variation per event |
| `ui/character_select/*` | Modified | per-player controller/difficulty choice |
| `game/ui/pause/*`, `game/ui/game_over/*` | Modified | Esc toggle, instant rematch |
| `ui/instructions/*`, main menu label | Modified | typo fix, controls text (double jump, air actions) |
| `game/player/StateMachine/PlayerStateMachine/States/punch.gd`, new `recovery.gd` | Modified/New (S5) | charge phase, directional knockback vectors, up-recovery state |
| `game/player/player.gd`, `player.tscn` | Modified (S5) | glow `Sprite2D` child (existing texture), recovery-available flag, snapshot fields |
| `game/combat/combat.gd` | Modified (S5) | knockback scaled by charge and direction angle |
| `game/camera/match_camera.gd` (new), `game/game.tscn` | New/Modified (S5) | follow/zoom script on the existing `Camera2D`, clamped to blast-zone bounds |
| `game/player/StateMachine/PlayerStateMachine/States/hurt.gd` | Modified (S5) | shake stays on `offset`, verified not to fight the follow camera |
| `game/player/controllers/scripted_controller.gd` | Modified (S5) | directional/recovery use at Normal/Hard |
| `project.godot` `[input]` | Possibly modified (S5) | only if the input decision adds up/down actions |
| `ui/instructions/*` | Modified (S5) | controls text for charge, directional attacks, recovery |
| `train.tscn` | Unchanged (verify) | must still load; per-node overrides checked statically; its own `Camera2D` gets no follow script |

## Size Forecast vs 400-line Budget

| Slice | Content | Est. authored lines |
|-------|---------|---------------------|
| S1 | Controller seam + snapshot accessor + print cleanup | ~250 |
| S2 | Movement feel + punch fix + hit rules (F4, F5) | ~300 |
| S3 | Scripted CPU + controller/difficulty select UI | ~300 |
| S4 | Match flow + F2/F3/F8 + SFX pitch + typo | ~250 |
| S5 | Smash moves (charge, up-recovery, directional attacks) + match camera + bot extension + snapshot fields + controls text | ~300–400 |
| **Total** | | **~1,300–1,600** |

**The forecast exceeds the 400-line review budget about 3.3–4x under the current `single-pr` strategy.** S5 alone sits at the budget ceiling; if it runs over, it splits cleanly into S5a (camera) and S5b (moves + bot).

Decision needed before apply (still pending): Yes. The orchestrator must ask the user to choose one of:
- switch to chained PRs, using S1–S5 as the slices; each slice is independently playable and revertible, S1 must land first, and S5 depends on S1 (intent fields) and S2 (punch/knockback rework);
- accept a `size:exception` single PR.

Trimming further, for example dropping the CPU bot, would break the single-player requirement, so it is not recommended. Deferring S5 to its own follow-up change is possible but contradicts the user's request to include it here.

## Resolved Product Decision: S5 Input Mapping

**Decision (user, 2026-10-01): Option B.** Add `P{N}_up` / `P{N}_down` actions (4 new bindings); this overrides the earlier "no new input bindings" exclusion for these two actions only. The exact recovery chord (`up` + `shoot` vs `up` + `punch` while airborne) is left to design.

Original options considered:

| Option | Directional attacks | Up-recovery | Tradeoff |
|--------|---------------------|-------------|----------|
| A. Reuse existing keys | up = `jump` held + `punch`, down = `protect` held + `punch`, side = `left`/`right` + `punch` | `jump` + `punch` while airborne | No new bindings; chords overlap with jump/block, so up-punch on the ground also jumps, down-punch must bypass block, and in the air up-punch and recovery share the same chord (one must win) |
| B. Add `P{N}_up` / `P{N}_down` actions | held direction + `punch` (Smash-like) | `up` + `shoot` while airborne (or `up` + `punch` in air) | Cleanest and closest to Smash; adds 4 bindings and touches `project.godot`, instructions, and the `HumanController`; on keyboard 2P the extra keys must fit both players |

The `FighterIntent` shape (direction + special field) is the same under both options; only `HumanController` mapping differs.

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Feel tuning is blind (no runner, no CLI). | High | Exported constants, documented defaults, a manual playtest checklist per slice |
| Seam refactor regresses human input or `sync.gd` TRAINING mode. | Med | `PolicyController` reads the same `PlayerAIController` fields; static grep of `train.tscn` overrides; S1 makes no behavior change |
| Removing ONNX auto-activation changes the behavior of an existing cached model. | Low | That path is already broken (fighter idles). Explicit selection keeps the ONNX option available |
| Existing ONNX model and `train.tscn` trained on old rules play worse. | Med | Accepted. Retraining is deferred to `hf-ai-opponents` |
| CPU bot is too strong or too weak, or gets stuck at edges. | Med | Difficulty is data-driven; edge-recovery behavior is in the spec; tuned in playtest |
| Snapshot accessor gets treated as a de facto schema too early. | Low | Documented as unversioned; schema freeze is explicitly owned by `hf-ai-opponents` |
| Only 1–2 animation frames, so air actions look stiff. | Med | Reuse the existing jump/fall/punch/protect frames; feel comes from physics and hit-stop |
| PR size exceeds the review budget. | High | Chained S1–S5 slices (decision above); S5 can split into S5a/S5b |
| Camera zoom vs the 800x600 viewport: zooming out shows past the kitchen background, zooming in crops platforms; screen shake fights the follow. | Med | Godot `Camera2D.zoom` clamped to >= 1.0, so the widest view is today's full 800x600 framing and the camera only zooms in when fighters are close; center clamped to bounds (design to confirm); follow drives `position`/`zoom`, shake keeps `offset`; HUD is on a `CanvasLayer`, so zoom does not affect it |
| Up-recovery is too strong (no ring-outs) or too weak (useless). | Med | Once per airtime, resets only on landing/hit, exported height/velocity, no hitbox; playtest checklist includes "ring-out still possible at high damage" |
| Charge input conflicts with tap punch or other keys. | Low | Verified: pickup/throw are on `shoot`, not `punch`. A short tap threshold keeps taps as normal punches; charge is ground-only |
| Directional/recovery chords conflict with jump/block (if input Option A). | Med | Resolved by the open input decision; Option B removes the overlap |
| Charge/direction intent changes leak into `PlayerAIController` obs/action API. | Low | New fields live on `FighterIntent` only; `PolicyController` leaves them neutral; `get_obs()`/`get_action_space()` stay byte-compatible |

## Rollback Plan

- The work lands on its own branch, cut from `feat/kitchen-food-fight` (or chained slice branches). Rollback is `git revert` of the merge or slice commits. No data migration and no save format are involved.
- Slices are ordered so each can be reverted from the top down:
  - reverting S5 restores the static camera and the single punch; the S5 intent fields are inert without S5, so S1–S4 keep working;
  - reverting S4 or S3 leaves a playable 2P game with the new movement;
  - reverting S2 restores the old feel on top of the seam;
  - reverting S1 restores the original input paths.
- `PlayerAIController`'s obs/action API is unchanged, so no ONNX model or HF contract has to be rolled back.
- `train.tscn` is not edited, so training needs no rollback.

## Dependencies

- Baseline: branch `feat/kitchen-food-fight` (T0–T6 plus fixes, up to `9d7bf0c`) must be the base. F2–F5 and F8 refer to its code.
- Godot 4.6 editor, for the manual playtest by the user.
- Downstream: `hf-ai-opponents` depends on this change's `fighter-control` seam and `gameplay-state-snapshot`.

## Success Criteria

- [ ] One player can start a match vs CPU (Easy/Normal/Hard) from character select with no HF model present, and the CPU moves, punches, blocks, throws food, and recovers to the stage.
- [ ] Local 2P still works with the same existing key bindings (plus any up/down actions added only if input Option B is chosen).
- [ ] With a stale `user://Agent{N}.onnx` present and Human selected, the fighter obeys human input (no ghost AI).
- [ ] Jump apex and hang time are visibly shorter. Double jump, short hop, coyote jump, and buffered jump all work. Punch, throw, and block work in the air. Dash triggers from Idle, Run, and air.
- [ ] Punch never moves its owner. A fighter cannot be hit again during the post-hit invulnerability window. Overlapping hits leave `Engine.time_scale == 1.0`.
- [ ] Every match starts with a 3-2-1-GO countdown. A timeout tie goes to sudden death. Game over offers an instant rematch. Esc both opens and closes pause. The "Intructions" typo is gone.
- [ ] F2, F3, F4, F5, and F8 are marked resolved in review. No `print()` calls remain in per-frame paths.
- [ ] Sound cues differ audibly by pitch per event.
- [ ] `Fighter.get_state_snapshot()` and `Game.get_state_snapshot()` return the documented fields. `PlayerAIController.get_obs()` and `get_action_space()` are unchanged.
- [ ] `train.tscn` still opens and runs in TRAINING mode (static check plus user editor check).
- [ ] Holding punch for up to ~1 s makes the fighter glow (existing glow texture) and, on release, deals visibly more damage and knockback than a tap; a tap is still a normal punch.
- [ ] The up-recovery burst works once per airtime, resets on landing or being hit, and lets a fighter return from off-stage, while ring-outs still happen at high damage.
- [ ] Up, down, and side punches send the target at clearly different angles using the existing punch frame.
- [ ] The camera follows both fighters and zooms out as they separate, never shows past the stage/blast-zone bounds, and the HUD stays fixed and readable at 800x600.
- [ ] At Normal/Hard, the CPU uses directional punches and the up-recovery; Easy is unchanged.
- [ ] Fighter snapshot includes charge level, recovery available, and last attack direction; Game snapshot includes camera center and zoom.
- [ ] No new files under `assets/`.
