# Exploration: fun-gameplay-overhaul

Mirror of Engram `sdd/fun-gameplay-overhaul/explore`. Constraint: existing assets only.

## Current State
- Assets: 2 characters (Rafael, Matilde), ~14 single frames each (idle x2, run x2, jump, fall, hurt, punch, protect, shoot, defeated, face + 2 illustrations); 20 food sprites; 4 kitchen/cloud backgrounds; 1 platform; 6 buttons and logos; fire/glow/noise/confetti textures; sounds `button.mp3`, `cartoonpunch.wav`, `fireball-explosion.wav`; 1 music track.
- Loop (branch `feat/kitchen-food-fight`): splash, main menu, character select (optional ONNX per player), game, game over. Damage %, 3 stocks, blast zone, 2 one-way platforms, 99s timer. Food spawns every 3-5s (max 4); shoot key picks up/throws. Punch and block exist.
- No offline CPU opponent: `PlayerAIController` falls back to HUMAN unless an ONNX model is downloaded (`model_manager.gd`).

## Gaps
- Movement: floaty jump (`JUMP_VELOCITY` -600, gravity 500, ~360px apex); Jump/Fall have empty `available_actions` (no air punch/throw/block, no double jump); dash only via double-tap in Idle; no coyote time or jump buffer.
- Combat: `punch.gd` teleports owner ±50px for hitbox placement; no post-hit invulnerability (stun-lock); food only differs by numbers; 2 SFX reused for everything.
- Pacing: single static stage, no hazards, no countdown, no sudden death, no camera zoom.
- Menus: Replay goes to character select (no instant rematch); Esc doesn't close pause; AI picker is a dev-style HuggingFace username box; "Intructions" typo.
- Known advisories: F2 spawner global coords; F3 `game.gd` null-deref in training; F4 invulnerability tween race; F5 hit-stop race; F8 resting `FoodPickup` blocks fighters.
- Hygiene: debug `print()` in hot paths; no tests.

## Affected Areas
- `scripts/AIController/player_ai_controller.gd`, `States/motion.gd`: scripted CPU.
- `game/player/player.tscn`, `States/*.gd`: air actions, jump tuning, dash, punch hitbox.
- `game/food/*`: item effects, F2, F8.
- `game/combat/combat.gd`, `game/game.gd`: hit rules, F3, F5, countdown, sudden death.
- `ui/character_select/*`, `game/ui/pause/*`, `game/ui/game_over/*`: mode/difficulty, pause, rematch.
- `game/audio/sfx.gd`: pitch-varied SFX reuse.
- `train.tscn`, `addons/godot_rl_agents/sync.gd`: ONNX/training compat.

## Approaches
1. CPU opponent + movement/air game + match flow and fixes. Highest fun per asset; medium effort; blind tuning; bot must coexist with `sync.gd` modes.
2. Deepen food fight (per-food effects, one hazard, SFX variants, hit VFX). Medium-high effort; pays off only on a solid core.
3. Mode variety (survival, timed, gauntlet). High effort, low value on a weak core.

## Recommendation
Approach 1 first, then a trimmed Approach 2 slice. Defer Approach 3.

## Risks
- No test runner; feel-tuning is manual playtest only.
- Scripted bot vs `sync.gd` control modes.
- ONNX models and `train.tscn` trained on old rules.
- 1-2 frames per animation: feel must come from physics and effects.
- Food PNGs and freesound files lack `.import` files (runtime `load()` only).
