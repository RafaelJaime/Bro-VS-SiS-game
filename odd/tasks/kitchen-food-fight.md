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
- [ ] T1 Damage % + scaled knockback + block fix (replace HP)
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

## Next step
T1–T6 delegated to one writer (2+ non-trivial files per task).
