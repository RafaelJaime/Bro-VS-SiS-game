# Playtest fixes: lingering transparency, results screen

## Objective
Fix three issues reported by the user after playing the published build.

## Problem / Why
1. Fighters sometimes stay transparent (semi-invisible) for a long time.
2. Results screen: both portraits (winner bust, loser face) leave a visible strip of the panel's halftone/stripe background between the character art and the panel's bottom border.
3. Results screen has too many buttons.

## Scope
- T1 Find and fix the lingering transparency (invulnerability blink / ledge invuln / respawn / charge flash / hit-stop interplay); fighter visuals must always return to fully opaque when no invulnerability is active.
- T2 Lower the character art a few pixels in both results panels so it touches/overlaps the bottom border (no strip).
- T3 Results buttons: keep only the leftmost button, which goes to character select; add the standard back arrow (same as other screens) that goes to the main menu. Character select Back always goes to the main menu (verify).

## Constraints
- Existing assets only. Godot 4.7.2. Smoke harness `tests/smoke/run_all.sh` (running authorized).
- Do not stage the user's editor normalizations in `project.godot`, `game/game.tscn`, `game/ui/game_over/confetti.tres` unless a task needs those files.

## TDD / Checks
- TDD: strict_tdd=false (no unit runner); smoke checks written first where feasible.
- Each task: focused smoke check + full suite SMOKE PASSED at the end.

## Tasks
- [ ] T1 Lingering transparency fix + regression smoke check — route: delegated (diagnosis spans player/state files)
- [ ] T2 Results portraits lowered + layout check — route: delegated (same writer)
- [ ] T3 Results buttons + back arrow + navigation checks — route: delegated (same writer)

## Delivery
Small branch `fix/playtest-results-transparency`, one commit per task, PR to master.

## Progress / Evidence
