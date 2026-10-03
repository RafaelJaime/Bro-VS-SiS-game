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
- [x] T1 Lingering transparency fix + regression smoke check — route: delegated (diagnosis spans player/state files)
- [x] T2 Results portraits lowered + layout check — route: delegated (same writer)
- [x] T3 Results buttons + back arrow + navigation checks — route: delegated (same writer)

## Delivery
Small branch `fix/playtest-results-transparency`, one commit per task, PR to master.

## Progress / Evidence

- T1 (691beb7, fix(player)): root cause: `Fighter.grant_invulnerability(duration, blink=false)` (ledge grab, ledge climb) killed the running blink tween (`_blink_tween.kill()`) while it could be in its hidden half (`visible=false`), and nothing restored it, so the sprite stayed invisible for the whole grab (up to `ledge_invuln_first` 1.0 s, plus the climb) after any respawn (1.5 s) or post-hit (0.5 s) blink. Reproduced first in `tests/smoke/visibility.gd` (2 FAIL: "a non-blinking grant never leaves the sprite hidden", "a ledge grab made in the hidden half of the blink shows the sprite"). Fix: no tween; blink is state (`_blinking`, `_blink_clock`) and `_apply_visibility()` is the only code that sets the sprite visibility (also called on grant and stop). Check: visibility.gd 9/9 (adds a mixed run of respawn, hits during invulnerability, hit-stop, charge: vulnerable implies visible and opaque every frame; longest invulnerability 1.17 s <= 1.5 s max), added to run_all.sh. ledge, hit_rules, combat pass. Route: delegated direct (single writer).
- T2 (d446f7a, fix(ui)): the strip was the 9 px bottom band drawn over the art plus the art ending at the panel edge. Art lowered `ResultsPanel.ART_DROP` = 12 px (clamped so the art bottom never leaves the panel) and the band removed; art drawn right under the outline. results_screen.gd checks, per panel (winner and loser, both winners): art bottom >= panel bottom, art lowered, rendered pixels just above the border are art, not background. Screenshots reviewed visually (Rafael and Matilde).
- T3 (5bcaa40, fix(ui)): results keep only the leftmost button (button5 art, caption Characters, goes to the character select) and the standard BackButton scene (bottom left, same as credits/character select; goes to the main menu through SceneManager.go_back). Focus starts on the main button. Esc: no other screen binds Esc to Back, so none added. Character select Back already always goes to the main menu (navigation.gd covers it from the menu, after results, after a restarted match). Smoke updated, not deleted: results_screen.gd (single button, art, caption, Back arrow scene/position, focus), navigation.gd (one-button row, Back arrow click -> main menu and unpaused, restarted-match flow via SceneManager.rematch()), match_flow.gd, match_e2e.gd, keyboard_playtest.gd (rematch now via `paused = false; SceneManager.rematch()`, the API kept, since no UI reaches it).
