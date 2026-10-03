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
- [x] T1 Shield drop lag + minimum hold (+ CPU respects it) with smoke checks — route: delegated
- [x] T2 Aerial punch keeps jump momentum with smoke checks — route: delegated (same writer)
- [x] T3 Shield bubble uses the player's color — route: delegated (same writer)
- [~] T4 Harness metric + gate: shield raises per fighter-minute; retrain default model; gates; bundle — route: delegated. FOLDED into SDD change `character-kits-combos` (slice S6: single retrain covering shield fixes and kits; baseline measurement in S5)
- [ ] T5 PR; after merge and user confirmation: upload model (replay.mp4) and Space

## Progress / Evidence

### T1-T3 (delegated writer, direct route, strict_tdd=false)
- T1 `a5e7b8b`: new `ShieldDrop` state (11 ticks, no actions, planted, bubble shrinks), `shield_min_hold` 4 ticks, `shield_raise_cost` 4 meter, jump out of shield allowed (Smash; skips the lag), CPU treats ShieldDrop as a no-action state. A hit during the lag is a normal hit (not Protect). Checks: `tests/smoke/shield_spam.gd` (18).
  - Raises/s for punch/block alternating every 4 ticks over 10 s: before 4.90, after 2.90 (every 2 ticks: 8.00 -> 2.00; every 8 ticks: 2.40 -> 2.90). The lag bounds mashing at about 3.75 raises/s; the training signal (T4) has to do the rest.
  - Honest test updates (intentional rule change): `shield.gd` released state is now ShieldDrop then Idle, bubble near-full tolerance 0.03 and hides after the lag; `food_balance.gd` meter expectation shifts by the raise cost; `match_reel.gd` accepts a launched fighter that left hitstun into Fall while still flying up (camera bubble already shown) because the new CPU timing changed the seeded match trajectory.
- T2 `ccf2005`: root cause was `Punch._update` planting every punch (`calculate_velocity(0, ZERO)`), braking the horizontal speed in the air (dx 278 vs 360 px, 77%). Vertical velocity was never zeroed (apex identical before and after). Airborne punches now use Jump/Fall air control. `tests/smoke/air_punch.gd` (5): apex and dx within 5%, the punch still hits.
- T3 `5606ce5`: bubble hue = `CharacterUI.color` (HUD source), weak meter fades and pulses instead of turning red. `tests/smoke/shield_look.gd` (11). Screenshots in the session scratchpad `shield_fix/`.
- Risk for T4: the bundled schema-3 model was trained without drop lag/raise cost (state ShieldDrop lands in the one-hot "other" slot); retrain needed.
