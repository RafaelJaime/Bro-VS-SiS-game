# Proposal: Hugging Face AI Opponents (schema v2, GDScript ONNX, trained default model)

Mirror of Engram `sdd/hf-ai-opponents/proposal`. Builds on `explore.md` (written before the gameplay overhaul; findings re-checked against current code below).

## Intent

Hugging Face (HF) opponents do not work in a real match today, and no model trained on the current gameplay exists.

- **No inference in play.** `ControllerConfig.POLICY` sets `ONNX_INFERENCE` on `PlayerAIController`, but only `train.tscn` has a `Sync` node. A policy fighter therefore never receives actions. Inference is C#-only (`ONNXInference.cs`), so it can never run in the non-.NET GitHub Pages web build.
- **Obsolete contract.** `get_obs()` still returns the 13 pre-overhaul floats, which use `global_position` and are offset by the training rows. Actions are still 6 thresholded continuous values. The models see nothing of damage %, stocks, food, stage edges, cooldowns, jumps or state, and they cannot aim, dash or recover. `HubModel.BVS_SCHEMA_VERSION` is still `1`.
- **Broken training.** `game.gd` handles training defeat and timeout with `_reset_players_for_training()` and never calls `Fighter.game_over()`, so no `done` signal is sent. The reward comes only from hurt events: there is no KO, stock or win reward. The row spacing in `train.tscn` is inconsistent (Game3 is at -1400, the row offset is 2100, and some fighters keep stale StateMachine overrides).
- **Stale cache.** `ModelManager.download_model()` writes to `user://Agent{N}.onnx` and skips the download if that file exists. Picking a different model, or a newer revision, silently reuses the old file. That file lives in IndexedDB on the web build. If the file is missing, `ControllerConfig` silently falls back to the scripted CPU.

Gameplay is now frozen (PR #10 merged), so the obs/action contract can be frozen as **`bvs-schema-2`**. Success means the following:
- An HF model trained on the current game is discovered in the existing picker, downloaded, validated, and played on desktop and on the web build.
- The project ships the first such model, trained by the agent and published under the BVS tags.

## Scope

### In Scope
1. **Versioned schema module (`bvs-schema-2`).** One GDScript module shared by training (`PlayerAIController`) and inference (`PolicyController`). It defines the observation layout, which is built from `get_state_snapshot()`: Game-local and self-relative coordinates, normalized, with a fixed order and an explicit `obs_dim`. It also defines the discrete action layout and its decode into `FighterIntent`, plus `action_repeat` and the schema version constant. The module is extensible: a future v3 adds a new layout without breaking how v2 decodes. `HubModel.BVS_SCHEMA_VERSION` changes to `2`.
2. **MultiDiscrete actions.** The planned branches are move {left, none, right}, jump, attack with aim {none, neutral, up, down, side}, throw, block, dash and special. The exact branches are fixed in the spec/design, after checking what godot_rl_agents and SB3 support for discrete actions and how they export them.
3. **Training environment fixes.**
   - Episode `done` on match end: elimination, timer or sudden-death resolution, sent through `Fighter.game_over()`.
   - Rewards for damage dealt and taken, KO given and taken, stock lost, and win or loss, with small shaping terms. All of these are tunable data.
   - `train.tscn` rows with consistent spacing and no stale overrides.
   - Opponent mode per Game row: self-play policy or scripted CPU at a given difficulty, used for the curriculum.
4. **Pure-GDScript ONNX MLP interpreter** (Approach B).
   - A minimal protobuf reader for `ModelProto`, `GraphProto`, `NodeProto`, initializers (`TensorProto` float32 raw/float data) and inputs/outputs.
   - An op whitelist covering what the export emits at opset 17: `Gemm`, `MatMul`, `Add`, `Relu`, `Tanh`, `Sigmoid`, `Identity`, `Constant`, `Flatten`, `Reshape`, `Concat`, `Slice`, `Squeeze`, `Unsqueeze`, and `ArgMax` if it is emitted. The final list is fixed in the design, against a real export.
   - Rejection with a clear error for any other op, or for dims that do not match.
   - Works the same on every platform, including the web build.
5. **Golden-vector validation.** A Python script runs the exported model in `onnxruntime` on fixed and recorded observations and writes committed JSON fixtures. A GDScript smoke test (`tests/smoke/onnx_golden.gd`) checks that the interpreter matches them within a tolerance (about 1e-4).
6. **Inference integration.**
   - `PolicyController` builds the schema-2 observation, runs the interpreter every `action_repeat` physics ticks, holds the decoded intent in between, and needs no `Sync` node in the game.
   - `PlayerAIController` and `sync.gd` are used only for training.
7. **Hub contract and cache.**
   - Tags: `BVS` and `bvs-schema-2`.
   - A `bvs.json` sidecar with `schema_version`, `obs_dim`, the action layout, `action_repeat`, `trained_on_commit`, and an optional difficulty or label.
   - The cache is keyed by repo id and revision sha (`user://models/<owner>__<name>/<sha>/`), replacing `user://Agent{N}.onnx`. The old files are ignored or cleaned up.
   - Before play, the ONNX input dim and the sidecar are checked against the schema. A model that fails this check is rejected with a visible reason.
8. **Download UX.** The first download shows a loading/waiting state with a cancel option and a visible error on failure. Silent fallback to the CPU is removed. The existing picker (username/tag search, compatibility badges) works with schema 2.
9. **Python training pipeline**, kept in the repo under `training/`.
   - A uv-managed Python 3.12 project with pinned `godot-rl`, `stable-baselines3` and `torch` (exact package, CLI and Godot 4.7 compatibility to be verified).
   - Scripts:
     - Train: PPO, Godot headless running `train.tscn`, curriculum vs scripted CPU Easy, then Normal, then mixed self-play.
     - Export: clean MLP ONNX at opset 17, with constant folding and the `obs`/`state_ins` interface preserved or simplified as the design decides.
     - Golden fixtures: generate the committed fixtures used by item 5.
     - Evaluation: model vs CPU matches.
     - Upload: gated, see item 11.
   - Also: a model card template, and trainer docs (MLP-only constraint, schema contract, tags).
10. **Train the default model** locally (Apple M5, 10 cores, 24 GB RAM; time-boxed), evaluate it, and commit its artifacts: the ONNX file, `bvs.json`, the golden fixtures and the evaluation report.
11. **Remote upload gate.** Publishing to HF is performed only after explicit user authorization (see "Remote Operation Authorization Gate").

### Out of Scope
- Desktop C#/.NET ONNX runtime, `onnxruntime-web` through the JavaScript bridge, and a GDExtension runtime (Approaches A, C and D).
- Recurrent, attention or convolutional policies. Schema 2 supports MLPs only, and this is documented.
- Support for schema-1 models: they appear only as "Trained for an older version".
- An online leaderboard, Elo, or ranking of community models.
- Gameplay changes: gameplay is frozen. Observation needs are met through the snapshot accessors.
- New CI jobs (the existing CI deploys only). Tests run locally under this session's authorization.
- Charged smash attacks for the policy: `attack_held` stays false in v2 (same rule as the CPU). This is extensible in a later schema.

## Capabilities

### New Capabilities
- `ai-schema`: the versioned obs/action schema module (v2 layout, normalization, discrete action decode into `FighterIntent`, `obs_dim`, `action_repeat`, version constant, extension rules), shared by training and inference.
- `onnx-mlp-inference`: the pure-GDScript ONNX reader and MLP interpreter (protobuf subset, op whitelist, shape checks, error reporting) and its golden-vector contract.
- `rl-training-pipeline`: the training environment (done boundaries, rewards, per-row opponent mode, `train.tscn` layout), the Python recipe (train, export, golden, eval), the model card and sidecar production, and the upload procedure with its authorization gate.
- `hub-model-distribution`: the Hub tag contract (`BVS`, `bvs-schema-N`), the `bvs.json` sidecar, the repo+revision cache, pre-play validation, and the download/loading/error UX.

### Modified Capabilities
- `fighter-control`: the Policy controller requirement changes. `get_obs()` and `get_action_space()` are no longer frozen at the legacy layout but defined by `ai-schema`. In-game inference runs in `PolicyController` without `Sync`. A missing model no longer falls back silently to the CPU.
- `gameplay-state-snapshot`: the "get_obs/get_action_space MUST remain unchanged" clause is removed. The snapshot stays unversioned, and the schema module is its versioned consumer. Any snapshot keys the schema needs, such as stage edges, become required keys.
- `match-flow`: the ONNX/HF option at character select waits for a pending download (loading state) and reports validation or download failures before the match starts.

## Approach

Approach B from the exploration, re-checked against the code after the overhaul.

1. **Schema first.** Freeze `bvs-schema-2` in one module (proposed: `game/ai/schema/bvs_schema_v2.gd` plus a version registry). It reads only `get_state_snapshot()` (Fighter and Game), so training and inference cannot drift apart. `PlayerAIController.get_obs()`, `get_action_space()` and `set_action()` delegate to it, and so does `PolicyController`.
2. **Training env.**
   - In training mode, `game.gd` ends an episode on match resolution and calls `game_over()` on both fighters before resetting.
   - A reward component in `PlayerAIController` listens to the damage, stock and match signals.
   - Each `train.tscn` row selects its opponent: TRAINING (self-play, with a shared policy across agents) or a CPU `ScriptedController` at a given difficulty.
3. **Interpreter.**
   - A small varint/length-delimited protobuf decoder builds a graph of whitelisted nodes. Weights are held in `PackedFloat32Array`, and a topological evaluator runs on them.
   - The policy is a small MLP (for example 2×64), so one forward pass costs about 10k multiply-adds. That is negligible every 4–8 ticks, even in web GDScript.
   - We control the export: the export script produces a clean graph (constant folding, plus `onnx-simplifier` if needed) that stays inside the whitelist.
4. **Validation loop.** Train, export, then build the onnxruntime golden fixtures. The GDScript smoke test checks parity, and the evaluation smoke test runs the model vs CPU Easy and Normal for N matches. The model is published only after parity passes and the evaluation meets the success criteria.
5. **Integration.**
   - `ControllerConfig.POLICY` carries a loaded model handle (repo, revision, parsed graph, sidecar), not a path.
   - `ModelManager` resolves the revision sha, downloads `model.onnx` and `bvs.json` from `resolve/<sha>/`, and caches them by repo+sha. It validates the files before reporting ready.
   - Character select waits on that ready signal.
6. **Delivery.** One PR with `size:exception` and logical commits, one per slice below (the same delivery as the previous change).

### Slices (authored-line forecast; generated fixtures and binaries excluded)

| # | Slice | Forecast |
|---|-------|----------|
| S1 | `ai-schema` v2 module, `PlayerAIController` delegation, `HubModel` bump, training env fixes (done, rewards, row opponent mode, `train.tscn` spacing), smoke updates | ~450 |
| S2 | GDScript protobuf reader, MLP interpreter, op whitelist, golden smoke test | ~600 |
| S3 | `training/` uv project: train, export, golden, eval and upload scripts, model card template, trainer docs | ~500 |
| S4 | Inference integration: `PolicyController` tick/decode, `ControllerConfig`, `ModelManager` repo+revision cache, sidecar validation, loading UX, picker compat | ~450 |
| S5 | Training run, committed artifacts (default model, `bvs.json`, fixtures, eval report) | ~100 + binaries |
| S6 | Gated HF upload (no code beyond S3 scripts) | ~0 |

Total: about 2,100 authored lines. The user chose single PR delivery with `size:exception`.

## Remote Operation Authorization Gate

The upload to Hugging Face is a remote operation. Running local training and Godot does not authorize it.
- **Stop before upload.** After S5, stop and present the following:
  - The destination repo id (proposed: `RafaelJaime/BVS-<name>`).
  - The operation: create the repo if it is missing, then upload `model.onnx`, `bvs.json` and `README.md` (the model card). Tags: `BVS`, `bvs-schema-2`, `reinforcement-learning`. Visibility: public.
  - The credential: the user's `hf` CLI login at `/usr/local/bin/hf`.
  - The evaluation results.
- **Proceed only on confirmation.** The upload runs only after the user explicitly confirms all three: destination, operation and credential.
- **No probing.** The agent does not inspect the ambient HF auth state (for example `hf auth whoami`) before that confirmation.
- **Verify read-only.** After the upload, a read-only listing check confirms that the model appears under `filter=BVS` with `bvs-schema-2`. The read-only Hub API used by the game remains allowed.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `game/ai/schema/` (new) | New | Versioned schema module and registry |
| `game/ai/onnx/` (new) | New | Protobuf reader, MLP interpreter, model resource |
| `scripts/AIController/player_ai_controller.gd` | Modified | Delegates obs/actions to the schema; reward/done wiring |
| `game/player/controllers/policy_controller.gd` | Modified | Runs the interpreter every `action_repeat` ticks; discrete decode |
| `game/player/controllers/controller_config.gd` | Modified | Loaded model handle; no silent CPU fallback |
| `game/game.gd`, `game/player/player.gd` | Modified | Training-mode episode end through `game_over()`; reward signals |
| `train.tscn` | Modified | Row spacing, per-row opponent mode, stale overrides removed |
| `scripts/model_manager.gd`, `scripts/hub_model.gd` | Modified | Repo+revision cache, sidecar, validation, schema 2 |
| `ui/character_select/*` | Modified | Loading/wait/error states for the HF option |
| `addons/godot_rl_agents/` | Unchanged/limited | Kept for training only; C# path no longer used in game |
| `training/` (new) | New | uv project, scripts, model card template, docs |
| `tests/smoke/` | New/Modified | `onnx_golden.gd`, schema, policy match, `train_loads.gd`, `hf_picker.gd` updates |
| `tests/fixtures/onnx/` (new) | New | Golden vectors, default model test copy |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `godot-rl` Python package or protocol is incompatible with Godot 4.7.2 or the addon version in the repo | Med | Verify the package version and handshake first. Pin versions. If needed, update the addon within training-only files. |
| SB3 MultiDiscrete export emits ops outside the whitelist (Shape, Gather, Where, etc.) | Med | Use our own export wrapper (deterministic logits/argmax head), constant folding and `onnx-simplifier`. Grow the whitelist only with golden coverage. |
| Training time or quality: the policy degenerates (camping, self-KO) or does not beat CPU Easy within the time box | High | Curriculum vs CPU Easy, reward shaping, episode cap, checkpoints with periodic evaluation. Time-box each run. Success is "beats CPU Easy and plays non-trivially", not dominance. |
| GDScript interpreter is too slow on web | Low | Small MLP, inference only every `action_repeat` ticks, Packed arrays. Measure frame cost in the web build. |
| Numerical drift between onnxruntime and GDScript (float32 vs GDScript float64) | Low | Golden tolerance about 1e-4. Argmax actions must match exactly on the fixtures. |
| A hand-written protobuf parser fails on unusual encodings (external data, float_data vs raw_data) | Low-Med | Support both encodings and reject external data with a clear error. The fixtures cover the real export. |
| Schema v2 misses a feature the policy needs | Med | The registry allows schema 3 without breaking v2. Feature choices are reviewed against the scripted CPU's inputs. |
| Revision sha lookup adds API calls (anonymous rate limits) | Low | One metadata call per selected model, cached by sha. |
| Large binary or fixture churn in git | Low | One small ONNX file (KB range). Fixtures are compact JSON. |

## Rollback Plan

- Each slice is one logical commit, so any slice can be reverted on its own. S4 can be reverted alone, leaving the schema, interpreter and training pipeline inert.
- Reverting the PR restores schema 1, `user://Agent{N}.onnx`, and the non-functional HF option. The scripted CPU is unaffected throughout (cpu-opponent spec unchanged).
- The HF upload is reversible by the user only. It can be made private or deleted through the Hub. The agent does no remote cleanup without separate authorization.
- Cached `user://models/` entries can be cleared safely. Legacy `user://Agent*.onnx` files are ignored.

## Dependencies

- uv, a Python 3.12 venv, `godot-rl`, `stable-baselines3`, `torch`, `onnx`, `onnxruntime` and optionally `onnx-simplifier`. Exact versions are verified in the design.
- Steam Godot 4.7.2 headless binary. Note: `openspec/config.yaml` says 4.6, so the project and export versions need a check.
- The `hf` CLI, authenticated by the user, needed only at the gated upload step.
- This session's user authorization to run Godot, tests and training locally (it overrides the default no-local-tests rule for this change only).

## Success Criteria

- [ ] `bvs-schema-2` is frozen in one module. Training and inference use the same module, and `HubModel.BVS_SCHEMA_VERSION == 2`.
- [ ] `train.tscn` runs headless with the Python trainer. Episodes end on match resolution, and the KO, stock and win rewards are observable in the logs.
- [ ] The GDScript interpreter matches the onnxruntime golden outputs within 1e-4, and the argmax actions match exactly on every fixture.
- [ ] The default model wins at least 60% of N≥20 headless matches vs CPU Easy. It plays non-trivially: it approaches, attacks, recovers to the stage, and does not idle or self-KO in the majority of stocks lost. The evaluation report is committed.
- [ ] An HF model selected in the picker downloads once per revision, is validated, and plays a full match on desktop and in the web export without a `Sync` node.
- [ ] A model whose schema or input dim does not match is rejected with a visible reason. A missing download shows loading/error states, never a silent CPU swap.
- [ ] After explicit authorization, the default model is published with the `BVS` and `bvs-schema-2` tags, a model card and `bvs.json`, and it appears as "Compatible" in the in-game picker.

## Open Questions (product decisions for the orchestrator)

1. **Resolved (user, 2026-10-02): bundle it.** The default model ships in the build (`res://`) as an offline "BVS default" opponent selectable in character select without network (also on web), in addition to being published on the Hub.
2. Open until the upload gate: which **HF repo id/name** and **license** should the published default model use (for example `RafaelJaime/BVS-<name>`, MIT)?
