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
- [x] T2 Ring-out stage: remove walls, platforms, blast zone, stocks, respawn + invulnerability
- [x] T3 Food items: catalog resource, spawner, pickup/hold/throw (replaces shoot)
- [x] T4 HUD: % display + stock icons; game-over by stocks/timer
- [x] T5 Juice: hit-stop, SFX, music
- [x] T6 AI controller compat + protect action bug fix

## Delivery
Forecast ~700–1000 authored lines → exceeds ~400 budget. Strategy: ask-on-risk (ask chain strategy before PR).

## Progress / Evidence
- Branch `feat/kitchen-food-fight` created.
- T0 done; contact sheet visually verified.
- T1 done; commit `2983964`.
  - `game/player/player.gd`: replaced `health`/`max_health` with `damage_percent` (float, starts 0, no cap), added `add_damage()`, `get_knockback_scale()` (`1 + percent/50`), `damage_changed` signal.
  - `game/combat/combat.gd` (new): `Combat.apply_hit(attacker, target, damage, knockback_base)` centralizes block/no-block resolution so punch and future thrown food share one path.
  - `game/player/StateMachine/PlayerStateMachine/States/hurt.gd`: reads `pending_damage`/`pending_knockback` set by the attacker, calls `owner.add_damage()`, scales knockback by `get_knockback_scale()`, no longer ends the match on 0 HP (no death by damage — ring-out/stocks come in T2). Blink-flash intensity now ramps with `damage_percent` (capped visually at 150%) instead of inverse health.
  - `game/player/StateMachine/PlayerStateMachine/States/protect.gd`: fixed the dead `receive_blocked_damage()` bug — `Combat.apply_hit` now actually calls it when the target is blocking (previously blocking gave full immunity). Halves % gained (`block_damage_reduction=0.5`), knockback = 30% of base (`block_knockback_reduction=0.3`, reinterpreted as "fraction retained" per design wording "30% knockback"), then scaled by `get_knockback_scale()`.
  - `game/player/StateMachine/PlayerStateMachine/States/punch.gd`: added `punch_damage=8.0`, `punch_knockback=Vector2(220,-120)` exports; `_on_punch_area_body_entered` now calls `Combat.apply_hit` instead of blindly forcing `Hurt` (which is what caused the block bug).
  - `game/player/player_ui.gd`, `game/player/player.tscn`: HUD rewired from the old `update_health`/Hurt-only signal to `Fighter.damage_changed` → `PlayerUI._on_damage_changed`. Progress bar now shows `damage_percent` against a visual-only 200 cap; full %/stock HUD redesign is T4's job.
  - `game/ui/game_over/game_over.gd`: timeout winner is interim "lower damage % wins" (final stocks-first rule lands with T2/T4).
  - Deviation: `train.tscn` (RL training rig, out of scope per design doc) still has two `Hurt` node overrides for the now-removed `knockback_force` export; Godot silently ignores orphaned property overrides on load (non-fatal), left untouched to avoid risking the generated multi-row training scene without being able to run the editor.
  - Deviation: `Hurt.player_defeated` signal kept declared-but-unemitted in T1 (game.tscn's existing connection stays structurally valid); T2 wires real elimination via blast-zone detection.
- T2 done; commit `dbb395d`.
  - `game/player/player.gd`: added `stocks` (3), `is_invulnerable`, blast-zone constants (`BLAST_LEFT=-150`, `BLAST_RIGHT=950`, `BLAST_BOTTOM=750`, world-space, tunable), `_check_blast_zone()` called after `move_and_slide()` each physics frame. `_lose_stock()`: decrements stocks, `stock_lost` signal; at 0 stocks transitions to `Defeated` and emits `player_defeated` (moved here from Hurt, since elimination is now blast-zone driven, not damage-driven); otherwise `_respawn()` resets `damage_percent` to 0, teleports to `initial_position + (0,-250)`, forces `Fall` state, and starts a 1.5s `_start_invulnerability()` (looped `Tween` toggling `animated_sprite_2d.visible` every 0.15s + a parallel timer as the source of truth for `is_invulnerable`).
  - `game/combat/combat.gd`: `apply_hit` now no-ops when `target.is_invulnerable` (so Hurt/Protect are both correctly skipped during the respawn window).
  - `game/game.tscn`: removed `WallLeft`/`WallRight` (collision + their plain white `ColorRect` visuals — the only "wall art" that existed) and their now-orphaned `RectangleShape2D_80nbo` sub_resource. Narrowed `Floor`'s collision+visual from 912px to 500px (centered, same position), moved the two existing `Plataformacuadrados` decorative sprites to the new edges. Added `PlatformLeft`/`PlatformRight` (`CollisionShape2D`, `one_way_collision=true`, 150×20, floating at y=430, i.e. ~137px above the floor) reusing the `plataformacuadrados` texture for visual consistency with the floor decorations. Repositioned `Fighter1` (142→230) and `Fighter2` (601→570) so both start safely inside the narrower floor span (world x [147,647]) instead of near/past its new edge. `load_steps` updated 40→41 (31 ext + 9 sub + 1).
  - `game/game.gd`, `game/player/StateMachine/PlayerStateMachine/States/hurt.gd`: removed the now-dead `Hurt.player_defeated` signal; `player_defeated` connection in `game.tscn` moved from `FighterN/StateMachine/Hurt` to `FighterN` directly (`Fighter.player_defeated`). Renamed handler `_on_hurt_player_defeated` → `_on_player_defeated` for accuracy.
  - Bug fix found during static review (not pre-existing-documented, discovered while wiring `Defeated`): the `Defeated` state node in `game/player/player.tscn` never had `state_machine` wired via `node_paths`/`NodePath("..")` like every sibling state — any AI-controlled fighter entering `Defeated` would have null-deref'd in `Motion._update() → process_ai_transitions()`. Fixed by adding the same `node_paths=PackedStringArray("state_machine")` + `state_machine = NodePath("..")` pattern used by all other states. This was latent before (Defeated was barely reachable) and became load-bearing once T2 made elimination routine.
  - `game/ui/game_over/game_over.gd`, `game/game.gd`: added `GameOver.forced_winner` / `set_forced_winner()`. `_on_player_defeated` now sets the forced winner to the defeated player's enemy before showing game-over (fixes a real bug T2 would otherwise introduce: the old "lower % wins" interim rule from T1 is actively wrong on an elimination, since the eliminated player can have *lower* % than the survivor). Timeout still clears the forced winner and falls back to the T1 interim "lower % wins" rule; full stocks-first win rule is still T4's job.
  - Deviation: respawn invulnerability duration/blink cadence, blast-zone margins, platform size/height, and the narrowed-floor/platform coordinates are first-pass numeric defaults (documented above) chosen from static geometry math only (no CLI/editor render available) — flagged for playtest tuning.
  - `train.tscn` needed no changes (no per-instance overrides of the removed Wall nodes, Floor shape, Fighter positions, or the renamed connection/method — verified by grep).
- T3 done; commit `a004c57`.
  - `game/food/food_catalog.gd` (new, `class_name FoodCatalog`): static `FOOD_ITEMS` dict mapping all 20 sprite names to a `WeightClass` (7 light/9 medium/4 heavy, matching the design doc exactly) and `WEIGHT_STATS` (damage %, throw speed, knockback, arc gravity_scale) per class — light 6%/fast/flat, medium 10%, heavy 16%/slow-arc. Textures loaded via `load()` at runtime only (never preload/ext_resource), per T0's note that the food PNGs have no `.import` files yet.
  - `game/food/food_pickup.gd` + `.tscn` (new): `FoodPickup` (`CharacterBody2D`) falls under gravity and lands on the floor/platforms using the project's existing default collision layer (same as Fighter). Not auto-picked-up on touch.
  - `game/food/food_projectile.gd` + `.tscn` (new): `FoodProjectile` (`Area2D`) is the thrown-food flying object — direction/speed/arc from `FoodCatalog`, hits go through `Combat.apply_hit` (so blocking/invulnerability both apply correctly to thrown food, not just punches). Not a reuse of `game/projectile/projectile.tscn`'s fire-VFX scene (judgment call: that scene's particle/shader setup is thematically a fireball and not worth retrofitting per-food-color; the *pattern* — Area2D + direction*speed + body_entered — is reused, just not the literal asset). `game/projectile/` (now fully unreferenced) deleted.
  - `game/food/food_spawner.gd` (new, `class_name FoodSpawner`): Timer-driven, `randf_range(3,5)`s between drops, caps at 4 alive (`max_alive`), spawns above the stage at a random x within the T2 floor/platform span. Added as a plain `Node2D` child of `Game` in `game/game.tscn` with `food_pickup_scene` wired to the new `food_pickup.tscn`.
  - `game/player/player.gd`: added `pickup_area`/`held_food_sprite` onready refs, `held_food: String`, `is_holding_food()`, `pick_up_food(pickup)`, `clear_held_food()` (also called from `reset_player()`/`_respawn()` so food is dropped on reset/KO).
  - `game/player/StateMachine/PlayerStateMachine/States/shoot.gd`: fully rewritten. Node/class name kept as `Shoot` (avoids churning the node tree + the already-wired `shoot` input action), but it no longer fires a free projectile — on press it throws held food if holding, else attempts a pickup via `owner.pickup_area.get_overlapping_bodies()`. Exported var names (`shoot_duration`/`shoot_cooldown`) kept unchanged so `train.tscn`'s existing per-node overrides stay meaningfully wired instead of becoming orphaned.
  - `game/player/player.tscn`: added `PickupArea` (Area2D, 70px radius circle) and `HeldFoodSprite` (Sprite2D, hidden by default, positioned above the head at local y=-110) as new Fighter children; replaced the `projectile_scene` export wiring on the `Shoot` node with `food_projectile_scene`. Also wired `Shoot.right_mark`/`left_mark` to the existing `RightMark`/`LeftMark` Marker2D siblings — discovered via static review that these exports existed since before T0 but were **never wired** in the scene (same latent-wiring-bug pattern as T2's `Defeated.state_machine`), so thrown food now spawns from a fixed hand-height point instead of a computed offset from the fighter's origin.
  - `ui/instructions/instructions.tscn`: updated the two "G/K (Shoot)" control-hint labels to "G/K (Pick up / Throw)" since the key's behavior changed.
  - Deviation: spawn x-range (180-620), spawn height, platform/pickup/projectile collision radii, and throw speed/arc numbers are first-pass defaults from the design doc's qualitative guidance (static review only, no editor render) — flagged for playtest tuning, same as T2's geometry.

- T4 done; commit `fb17d67`.
  - `game/player/player.gd`: renamed `stock_lost` → `stocks_changed` (not yet wired anywhere when T2 added it, so free to rename) and now also emitted from `reset_player()`, not just `_lose_stock()`, so the HUD refreshes stock icons on a full reset too.
  - `game/player/player_ui.gd`: `set_ui()` now also tints/initializes a percent `Label` and a row of `ColorRect` "pip" stock icons (tinted with `character_ui.color`, not `face_texture`, since the in-game `CharacterUI` resources for Rafael/Matilde don't set `face_texture` — verified by reading `game/game.tscn`'s `Resource_vktc5`/`Resource_kaw54`). `update_damage()` updates the percent label text (`"%d%%"`) alongside the existing bar; new `_on_stocks_changed()` toggles pip visibility (`i < stocks_left`).
  - `game/player/player.tscn`: added `LeftPercentLabel`/`RightPercentLabel` and `LeftStockIcons`/`RightStockIcons` (`HBoxContainer` of 3 `ColorRect`, 16×16) under each side's existing `VBoxContainer`; wired all four as new `PlayerUI` node_paths; added the `Fighter.stocks_changed → PlayerUI._on_stocks_changed` connection.
  - `game/ui/game_over/game_over.gd`: implemented the full design-doc timeout rule via `_resolve_timeout_winner()` — more stocks wins; tied stocks → lower % wins; both tied → draw. `forced_winner` (set by `game.gd` on an actual elimination) still takes priority and skips this comparison entirely, since an eliminated player can have a lower % than the stock-having survivor.
  - Deviation: stock icons are plain colored squares, not character art — no suitable small icon/portrait asset exists yet (`CharacterUI.face_texture` is unpopulated for both playable characters). Flagged for a future art pass; functionally correct and visually legible in the meantime.
  - Deviation: percent label format is a plain `"NN%"` integer (rounded); no color-ramping by percent (e.g. Smash's white→red) — not in the design doc's explicit scope, left for a later juice pass if wanted.

- T5 done; commit `d737739`.
  - `game/audio/sfx.gd` (new, `class_name Sfx`): one-shot SFX playback with no persistent node required (spawns a temporary `AudioStreamPlayer` under the tree root, frees itself on `finished`). Streams loaded via `load()` at runtime only (freesound assets have no `.import` files yet, same caveat as T0/T3).
  - `game/combat/combat.gd`: `apply_hit` now triggers hit-stop (`Engine.time_scale` dipped to 0.05 for 0.08s on an unblocked hit, 0.3 for 0.04s on a blocked one, restored via an `ignore_time_scale` `SceneTreeTimer` so the restore timer itself isn't affected by the freeze it created) and picks punch vs explosion SFX by a damage threshold (`>= 16.0`, i.e. heavy food only) — so punches and light/medium food play `cartoonpunch.wav`, heavy food plays `fireball-explosion.wav`. Both are skipped during AI training (new `_is_training()` check via the Fighter's parent `Game.training` flag) because `Engine.time_scale` is a single global property and `train.tscn` runs dozens of `Game` rows in parallel — one row's hit would otherwise stutter every other row.
  - `game/player/player.gd`: `_lose_stock()` plays the explosion SFX on every stock loss (same training guard).
  - `game/game.gd`, `game/game.tscn`: added a `MusicPlayer` `AudioStreamPlayer` node; `_ready()` loads `run-cinematic-music.mp3` via `load()`, sets `.loop = true`, and plays it — but only when `training == false` (same reasoning: ~50 training instances all playing music would be noise). Stopped in `_game_over()`'s non-training branch.
  - Deviation: no distinct "food throw" SFX exists as an asset (only punch + explosion), so light/medium food impacts reuse the punch sound and heavy food uses the explosion sound; this was already the plan going into T5, not a new deviation discovered mid-task.
  - Deviation: hit-stop/SFX duration and scale values (0.04-0.08s, 0.05-0.3 scale) are first-pass defaults, same playtest-tuning caveat as T2/T3's numeric defaults.

- T6 done; commit `d983f0c`.
  - `scripts/AIController/player_ai_controller.gd:100`: fixed the protect→shoot mixup — `set_action()`'s last line wrote `shoot_action = clamp(action["protect_action"][0], ...)` (overwriting the just-set `shoot_action` with the protect output, and leaving `protect_action` permanently 0). Changed to `protect_action = clamp(action["protect_action"][0], ...)`. Before this fix an AI-controlled fighter could never block (`protect_action` was always 0, and whatever the model decided for "shoot" was discarded).
  - AI obs/action-space compat: verified `get_obs()` (13 floats: own pos/vel/on-floor, opponent pos/vel/on-floor, relative pos, distance) and `get_action_space()` never referenced `health` in the first place — confirmed by a repo-wide grep before and after T1-T5, zero hits outside the fix above. So no observation-vector changes were needed to keep existing ONNX models loadable/inferable; "adapt to percent/stocks" from the design doc turned out to already be satisfied (position/velocity obs are valid under the new mechanics as-is). Retraining/reward retuning for the new food/stock mechanics stays explicitly out of scope per the design doc.
  - Final repo-wide verification: no remaining references anywhere to the removed `health`/`max_health`/`update_health`/`knockback_force`/`stock_lost`/`_on_hurt_player_defeated`/`game/projectile` APIs outside the two already-documented harmless `train.tscn` orphaned `knockback_force` overrides.

All T0-T6 tasks complete. See the per-task entries above for every file touched, every deviation, and every value flagged for playtest tuning.

## Next step
Feature complete. Remaining work is manual playtest/tuning in the editor (see each task's "Deviation" notes for specific numeric values to check) — no further tasks planned.

## Review (RDD)
- Range 4558c37..946a2d2 assessed medium (slice budget reached). User granted review.
- 1 CRITICAL fixed in bounded correction `342e205`: blast zone used global_position (broke offset train.tscn rows) → now local `position`.
- Approved + acknowledged (lineage review-ddb37be4be02cdd8).
- Advisory follow-ups (not blocking):
  - [x] F1 FoodProjectile has no lifetime/bounds → missed light throws fly forever (node leak). `food_projectile.gd:39-41`
  - [ ] F2 FoodSpawner uses absolute global coords → wrong in offset train rows. `food_spawner.gd:48-49`
  - [ ] F3 game.gd calls game_over.set_forced_winner() before training check → null deref if training row has no GameOver. `game.gd:34-41`
  - [ ] F4 Invulnerability tween unbound + overlapping respawns clear invuln early. `player.gd:128-139`
  - [ ] F5 Overlapping hit-stops race on Engine.time_scale. `combat.gd:55-64`
  - [ ] F6 No automated tests (no GUT); rules are static-checked only.
- Full-branch review (ef6f2ad..b3d4911, lineage review-f31d474e226eab95): user granted; approved with no blocking findings; acknowledged. Same advisories as above plus:
  - [x] F7 Thrown food is freed when it touches the one-way platforms (Area2D body_entered ignores one_way_collision). `food_projectile.gd:52-53`
  - F1 + F7 fixed: 3s MAX_LIFETIME; body_shape_entered skips one-way platform shapes; double-hit guard.
