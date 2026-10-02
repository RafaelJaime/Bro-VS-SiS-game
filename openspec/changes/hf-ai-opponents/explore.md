# Exploration: hf-ai-opponents

Mirror of Engram `sdd/hf-ai-opponents/explore`. Related: `fun-gameplay-overhaul`.

## Current Pipeline
1. `scripts/model_manager.gd`: `GET /api/models?author=<user>`, keeps models tagged `BVS`; UI is a free-text username box (`ui/character_select/ai_controller.gd`).
2. `download_model()` fetches `<id>/resolve/main/model.onnx` to `user://Agent{0|1}.onnx`; skips if the file exists.
3. `PlayerAIController._ready()` sets `ONNX_INFERENCE` if that file exists, else `HUMAN`.
4. `addons/godot_rl_agents/sync.gd` would run `ONNXModel.run_inference` every 8 physics ticks.
5. `Motion.process_ai_transitions` reads `*_action > 0.5`.
6. `train.tscn`: Sync node + 25 `Game` instances (`training=true`).

Contract: obs = 13 floats (own/opponent pos, vel, on_floor; relative pos; distance). Actions = 6 continuous (left, right, jump, attack, shoot, protect). ONNX inputs `obs[1,N]`, `state_ins[1]`; outputs `output`, `state_outs`; opset 17.

## Findings
- **F1 HF AI non-functional in play.** No Sync node in `game/game.tscn` or `main.tscn` (only `train.tscn`). AI fighter idles and ignores human input. `user://Agent{N}.onnx` cached forever (IndexedDB on web): ghost AI across sessions; stale model reused.
- **F2 Inference is C# only.** `addons/godot_rl_agents/onnx/csharp/ONNXInference.cs` (Microsoft.ML.OnnxRuntime); no `.csproj`; Pages export uses non-.NET Godot; Godot 4 C# web export unavailable. Models cannot run in the web build.
- **F3 Training defects.** `Fighter.game_over()` never called (no `done`); reward only per hurt (no stock/KO/win); obs uses `global_position` with offset training rows; obs lacks damage %, stocks, food, platforms, facing, state; continuous thresholded actions.
- **F4 Hub.** Only `RafaelJaime/BVS_SB3` tagged BVS (`BVS`, `BVS.1`). `filter=BVS` works server-side. Anonymous limits: 500 API / 3000 resolver req per 5 min per IP.
- **F5 Training pipeline.** No Python scripts, model card template or train export preset; README `gdrl` command unverified.
- **F6 UX.** Username-only discovery; no cards, difficulty, version, offline fallback or bundled default; non-array 200 response hangs UI; errors only `print()`ed; `is_p2` bool passed as `player_id`.

## Compatibility With New Gameplay
Old models cannot see new state nor use new actions; dim changes fail. Proposed contract: tags `BVS` + `bvs-schema-N`; sidecar `bvs.json` (`obs_dim`, action names/order, `action_repeat`, `trained_on_commit`, optional difficulty/Elo); validate ONNX input dim before play; schema v1 models = legacy/unsupported.

## Approaches
| # | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| A | Desktop-only ONNX via .NET; scripted CPU on web | Smallest delta | No HF on web (shipped target); .NET CI | Medium |
| B | Pure-GDScript ONNX MLP interpreter + Policy abstraction | All platforms incl. web; no C#/GDExtension/JS; small MLPs cheap | Minimal protobuf parser + op whitelist; MLP-only; golden-vector validation | Medium-High |
| C | `onnxruntime-web` via JavaScriptBridge + C# desktop | Full op coverage on web | Two codepaths, async interop, MBs of wasm | High |
| D | GDExtension ONNX | No C# | Web unlikely; immature; per-platform builds | High, risky |

Scripted CPU (3 difficulty levels, same Policy interface) is required under every approach.

## Recommendation
B + scripted bot:
1. Policy abstraction (Human, Scripted, OnnxMlp) ticked by `PlayerAIController`; Sync only for training; in-memory per-match selection; cache keyed by repo+revision.
2. Single versioned obs/action schema module shared by training and inference (local coords, new state, discrete actions).
3. Training fixes (`done` on stock loss/match end, stock/win rewards) + documented recipe (export preset, SB3 script, upload script, model card, self-play vs bot).
4. Discovery UI by tag (`filter=BVS&sort=downloads`), cards with compatibility, retry/offline states, bundled default.
5. Slices: (a) Policy + bot + Sync decoupling; (b) GDScript ONNX interpreter + golden tests; (c) schema/training fixes + HF contract + discovery UI.

## Open Questions
1. Accept MLP-only constraint and document it for community trainers?
2. Land gameplay overhaul first and freeze schema v2, or build contract now and bump versions?
3. Ship a trained default model, or only the scripted bot with HF as opt-in advanced?

## Risks
- Interpreter unproven on real SB3/CleanRL exports.
- Schema must freeze after gameplay settles.
- Hub ecosystem is a single author.
- Unverified: deploy workflow Godot 4.5 vs `project.godot` 4.6.
