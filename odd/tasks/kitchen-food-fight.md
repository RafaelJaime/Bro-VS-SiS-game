# Kitchen Food Fight (ring-out redesign)

## Objective
Replace the HP-based fighting mechanics with a Smash-style ring-out food fight in the kitchen.

## Problem / Why
User dislikes current fighting-game feel. Character art has only 1–2 frames per animation, so
depth must come from physics, items, and stage — not animation-heavy combos.

## Design (defaults, tweakable)
- **Damage %** replaces HP. Hits add %; knockback = base × (1 + percent / 50). No death by damage.
- **Stocks**: 3 each. Fall/get launched past blast zone → lose stock, respawn above stage with 1.5s blinking invulnerability.
- **Stage**: no side walls; main floor narrower than screen; 2 floating one-way platforms; kitchen background.
- **Food**: spawner drops random food (20 sprites, `assets/images/game/food/`) every 3–5s, max 4 alive.
  Shoot key: pick up food when empty-handed (overlapping), throw when holding. Held food shown above head.
  Weight classes: light (+6%, fast, low kb), medium (+10%), heavy (+16%, slow arc, high kb).
  - light: popcorn, nuggets, coffee, nachos, sandwich, bread, pancake
  - medium: pizza, noodles, hotdogs, sausage_plate, sausage_stick, salad, soup, cheese, steak
  - heavy: turkey, ham, grill, stew
- **Punch**: +8%, moderate kb. **Block**: halves % gained, 30% knockback (fixes unused `receive_blocked_damage`).
- **Win**: last with stocks. Timer end → more stocks wins; tie → lower %; else draw.
- **Juice**: hit-stop on hits, punch/explosion SFX (existing freesound files), in-game music.

## Scope / Constraints
- Godot 4.6, GL Compatibility, 800×600. Reuse existing FSM states and assets.
- Keep local 2P and AI controller working (fix `player_ai_controller.gd:100` protect→shoot mixup).
- Existing ONNX models were trained on old obs/rules; compat only, retraining out of scope.

## TDD / Checks
- TDD: Strict mode configured, but **no test runner exists** (no GUT/gdUnit addon, no `godot` CLI). User rule forbids running tests locally.
  → Checks are static review + manual playtest in editor by user. Disclosed.

## Tasks
- [x] T0 Slice food sheet into 20 transparent 96px PNGs (`assets/images/game/food/`) — route: inline (scripted, mechanical)
- [x] T1 Damage % + scaled knockback + block fix (replace HP)
- [ ] T2 Ring-out stage: remove walls, platforms, blast zone, stocks, respawn + invulnerability
- [ ] T3 Food items: catalog resource, spawner, pickup/hold/throw (replaces shoot)
- [ ] T4 HUD: % display + stock icons; game-over by stocks/timer
- [ ] T5 Juice: hit-stop, SFX, music
- [ ] T6 AI controller compat + protect action bug fix

## Delivery
Forecast ~700–1000 authored lines → exceeds ~400 budget. Strategy: ask-on-risk (ask chain strategy before PR).

## Progress / Evidence
- Branch `feat/kitchen-food-fight` created.
- T0 done; contact sheet visually verified.
- T1 done; commit `<T1_COMMIT_HASH>`.
  - `game/player/player.gd`: replaced `health`/`max_health` with `damage_percent` (float, starts 0, no cap), added `add_damage()`, `get_knockback_scale()` (`1 + percent/50`), `damage_changed` signal.
  - `game/combat/combat.gd` (new): `Combat.apply_hit(attacker, target, damage, knockback_base)` centralizes block/no-block resolution so punch and future thrown food share one path.
  - `game/player/StateMachine/PlayerStateMachine/States/hurt.gd`: reads `pending_damage`/`pending_knockback` set by the attacker, calls `owner.add_damage()`, scales knockback by `get_knockback_scale()`, no longer ends the match on 0 HP (no death by damage — ring-out/stocks come in T2). Blink-flash intensity now ramps with `damage_percent` (capped visually at 150%) instead of inverse health.
  - `game/player/StateMachine/PlayerStateMachine/States/protect.gd`: fixed the dead `receive_blocked_damage()` bug — `Combat.apply_hit` now actually calls it when the target is blocking (previously blocking gave full immunity). Halves % gained (`block_damage_reduction=0.5`), knockback = 30% of base (`block_knockback_reduction=0.3`, reinterpreted as "fraction retained" per design wording "30% knockback"), then scaled by `get_knockback_scale()`.
  - `game/player/StateMachine/PlayerStateMachine/States/punch.gd`: added `punch_damage=8.0`, `punch_knockback=Vector2(220,-120)` exports; `_on_punch_area_body_entered` now calls `Combat.apply_hit` instead of blindly forcing `Hurt` (which is what caused the block bug).
  - `game/player/player_ui.gd`, `game/player/player.tscn`: HUD rewired from the old `update_health`/Hurt-only signal to `Fighter.damage_changed` → `PlayerUI._on_damage_changed`. Progress bar now shows `damage_percent` against a visual-only 200 cap; full %/stock HUD redesign is T4's job.
  - `game/ui/game_over/game_over.gd`: timeout winner is interim "lower damage % wins" (final stocks-first rule lands with T2/T4).
  - Deviation: `train.tscn` (RL training rig, out of scope per design doc) still has two `Hurt` node overrides for the now-removed `knockback_force` export; Godot silently ignores orphaned property overrides on load (non-fatal), left untouched to avoid risking the generated multi-row training scene without being able to run the editor.
  - Deviation: `Hurt.player_defeated` signal kept declared-but-unemitted in T1 (game.tscn's existing connection stays structurally valid); T2 wires real elimination via blast-zone detection.

## Next step
T2: ring-out stage (remove walls, add platforms, blast-zone detection, stocks, respawn + invulnerability), then T3–T6.
