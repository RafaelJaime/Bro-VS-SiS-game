# Shield spam, jump cancel and shield color

## Objective
Stop the shield from being tapped between every other action, keep jump momentum when attacking in the air, and tint each shield with its player's color; retrain the default model on the fixed rules.

## Problem / Why
User playtest of the published build (schema-3 default model):
1. The model interleaves shield with every input (punch, shield, move, shield, attack, shield…). Raising/dropping the shield is free, so it costs nothing to sprinkle it between actions.
2. Pressing punch during a jump cancels the jump.
3. Shield bubble color should be the selected player's primary color (as in the HUD panel).

## Design (Smash-faithful defaults, tunable)
- Shield drop lag: releasing the shield leaves the fighter unable to act for ~11 frames (Smash), shown as the shield shrinking away; minimum shield hold so a 1-frame tap still pays the drop lag. Possible small activation cost on the meter. Out-of-shield jump allowed (Smash) — decide by playtest numbers.
- Aerial punch keeps the jump's vertical/horizontal momentum (no stop on attack in the air).
- Shield bubble tinted with the fighter's player color (P1 blue / P2 red, same source as HUD).
- Schema stays `bvs-schema-3` (obs/action contract unchanged); retrain the default model; add a harness metric and gate for shield toggles per minute.

## Scope / Constraints
- Godot 4.7.2, existing assets only, smoke harness `tests/smoke/run_all.sh` (running authorized), training under `training/` (authorized).
- HF uploads (model + Space) only after PR merge and explicit user confirmation.
- Never stage the user's local edits: `project.godot`, `odd/tasks/kitchen-food-fight.md`, `game/ui/game_over/confetti.tres`.

## TDD / Checks
strict_tdd=false; smoke checks first where feasible; full suite green per task.

## Tasks
- [ ] T1 Shield drop lag + minimum hold (+ CPU respects it) with smoke checks — route: delegated
- [ ] T2 Aerial punch keeps jump momentum with smoke checks — route: delegated (same writer)
- [ ] T3 Shield bubble uses the player's color — route: delegated (same writer)
- [ ] T4 Harness metric + gate: shield raises per fighter-minute; retrain default model; gates; bundle — route: delegated
- [ ] T5 PR; after merge and user confirmation: upload model (replay.mp4) and Space

## Progress / Evidence
