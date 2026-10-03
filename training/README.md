# BVS training recipe

Trains, exports and evaluates the fighter policies of Bro vs Sis. A policy is a small MLP; the game plays it with its own GDScript ONNX interpreter, so the Python side only produces a model file and numbers.

## Constraints you must respect

- **MLP only.** The exported graph may use `Gemm`, `MatMul`, `Add`, `Mul`, `Relu`, `Tanh`, `Sigmoid`, `Clip`, `Identity`, `Flatten`, `Reshape`, `Squeeze`, `Unsqueeze`, `Concat` and `Constant` (opset 13 to 18, shipped at 17). Anything else (recurrent cells, convolutions, `Gather`, `Shape`, `ArgMax`...) is refused by `export.py` and by the game. No external data files, at most 16 MiB, 512 nodes, 250k multiply-adds.
- **Schema `bvs-schema-2` is frozen.** GDScript owns it (`game/ai/schema/bvs_schema_v2.gd`); Python never builds observations. `bvs_training/schema.py` only mirrors the constants so the trainer fails fast when Godot disagrees.

| Contract | Value |
|----------|-------|
| Observation | `[1, 102]` float32, "me first, opponent second", field names in `tests/fixtures/schema/v2_layout.json` |
| Action | `MultiDiscrete([3, 3, 2, 5, 2, 2, 2, 2])`, branches `a0_move`, `a1_vertical`, `a2_jump`, `a3_attack`, `a4_special`, `a5_throw`, `a6_block`, `a7_dash` |
| Model output | `logits` `[1, 21]`, argmax per branch (ties to the lowest index) |
| Decision rate | one decision per 4 physics frames (`action_repeat = 4`) |
| Sidecar | `bvs.json` (`format: bvs-model/1`) with `schema_version`, `obs_dim`, `action_branches`, `action_repeat`, `trained_on_commit`, `label`, optional `eval` |

Hub models are tagged `BVS` and `bvs-schema-2` (plus `reinforcement-learning`, `onnx`). The in-game picker lists tag `BVS` and marks `bvs-schema-2` as compatible.

## Setup

```sh
cd training
uv sync                      # Python 3.12; godot-rl 0.8.2, stable-baselines3 2.3.2, torch 2.14.1, onnx 1.23.1, onnxruntime 1.30.0
```

Godot 4.7.2 is found through `GODOT_BIN` (default: the Steam install on macOS). No other setup.

## Compatibility finding (godot-rl and the addon)

`godot-rl 0.8.2` speaks protocol 0.7, the same as `addons/godot_rl_agents/sync.gd`, and the handshake works against Godot 4.7.2 with Python 3.12 (`uv run python -m bvs_training.handshake`). It maps the all-discrete action dict to `MultiDiscrete([3, 3, 2, 5, 2, 2, 2, 2])` in insertion order. Two quirks are handled in the repo:

- On macOS godot-rl rewrites `env_path` `X` to `X.app/Contents/MacOS/X` and splits the command on spaces. `bin/bvs-godot.app/Contents/MacOS/bvs-godot` is a shim that execs the real launcher `bin/bvs-godot`, and `handshake.launcher_arg()` passes a relative path so no directory with a dot or a space is involved.
- `PPO(seed=...)` calls `env.seed()`, which godot-rl does not implement. `train.py` seeds Python, NumPy and torch itself and gives Godot `--env_seed`.

## Reproduce a run

```sh
cd training
uv run python -m bvs_training.handshake                          # optional protocol check
uv run python -m bvs_training.train --phase P1 --steps 4096 --seed 1   # smoke run (writes out/)
uv run python -m bvs_training.train --config configs/default.toml > out/train.log 2>&1   # full curriculum
uv run python -m bvs_training.export --checkpoint out/final.zip --out out/bvs_default/model.onnx
uv run python -m bvs_training.evaluate --model out/bvs_default/model.onnx --level easy --level normal --matches 20 --min-win-rate 0.60
uv run python -m bvs_training.golden --model out/bvs_default/model.onnx --obs-dump out/obs.json --out ../tests/fixtures/onnx/bvs_default_golden.json
```

- `configs/default.toml` is all data: PPO hyperparameters, `[reward]` overrides (fields of `game/ai/training/reward_config.gd`), the curriculum phases (`P1` all CPU Easy, `P2` Easy and Normal, `P3` mixed with self-play and, once enabled, frozen snapshots) and the time box.
- Each phase writes `out/train_config_<phase>.json` (the `BVS_TRAIN_CONFIG` read by `game/ai/training/train_arena.gd`) and opens a fresh env, so the opponent mix changes without scene edits.
- Godot prints one `BVS_EPISODE {json}` line per finished episode with every reward term, so KO, stock and win rewards are visible in the log. Redirect the output to a file for long runs.
- **Time box and stop file:** `run.time_box_hours` (default 8) is checked at phase boundaries and after every rollout. `touch training/out/STOP` ends the run cleanly after the current rollout; a model is still written (`out/final.zip`, `out/checkpoints/step_*.zip`, `out/snapshots/step_*.onnx`).
- Checkpoints are written every `checkpoint_every` agent steps and at the end of each phase.
- `--resume <zip>` continues from a checkpoint; `--n-parallel` and `--speedup` override the config.
- `snapshot_opponents = true` lets `TrainArena` run frozen snapshot ONNX files (`out/snapshots/step_*.onnx`) as P3 opponents through the in-game `PolicyController`. While no snapshot has been exported yet, or when the flag is `false`, the snapshot share is given to `cpu_normal` with a printed warning. A snapshot that is missing or does not fit schema 2 is an error naming its row, never a silent substitute.

Throughput on a 10-core Apple M-series (8 rows per Godot process, speedup 8, `action_repeat` 4): 1 process 1.2k agent steps per second, 2 processes 2.3k, 4 processes 4.6k, 8 processes 8.4k (`n_parallel` in the config; default 4).

## Export, golden vectors, evaluation

- `export.py` wraps the policy trunk and action head (`PolicyLogits`), exports with `torch.onnx.export(opset_version=17, dynamo=False, do_constant_folding=True)`, runs `onnx.checker`, audits the ops against `onnx_ops.WHITELIST`, and checks onnxruntime against torch on 256 observations within 1e-5. It fails and writes nothing when an op is unsupported. `--self-test` exports a random-init policy to a temp dir; `--random-init --out <file>` writes a random-weight model for fixtures. It also writes `bvs.json` next to the model (`model.onnx` pairs with `bvs.json`, any other name with `<stem>.bvs.json`).
- `golden.py --check-ops` regenerates the per-op fixtures under `tests/fixtures/onnx/ops/` and fails on any git difference. `golden.py --model` writes onnxruntime vectors (32 seeded random plus up to 32 recorded observations) with the model sha256; check them in Godot with `BVS_GOLDEN_JSON=<golden.json> godot --headless --path . --fixed-fps 60 --script res://tests/smoke/onnx_golden.gd`.
- `evaluate.py` runs `tests/smoke/policy_eval.gd` (full non-training matches, sides alternating, the model through the shipped interpreter) and writes `reports/<name>-eval.md` and `.json` with win rate, stocks taken, approach, attacks, recoveries, self-KO share and idle share. It exits non-zero below `--min-win-rate` versus CPU Easy. At least 20 matches are required unless `--smoke` is given.
- `sidecar.py --model-dir <dir> --eval-report <json>` rewrites `bvs.json` with the evaluation block.

## Upload gate

Publishing to Hugging Face is a remote operation. **Nothing in this repo uploads.** `prepare_upload.py --repo <owner>/<name> --license <spdx> --confirm <owner>/<name>` stages `out/upload/<name>/` (`model.onnx`, `bvs.json`, a rendered model card), verifies the staged sha256 against the bundled copies under `game/ai/models/bvs_default/`, and only prints the `uvx --from huggingface_hub hf repos create ... --exist-ok` and `uvx --from huggingface_hub hf upload ...` commands. They go through `uvx` because a bare `hf` can be a different program on `PATH` (for example the Higgsfield CLI), and the current Hugging Face CLI spells the subcommand `repos create` (`hf upload` also creates a missing repo). Without `--confirm` carrying the same repo id it exits with status 2 before doing anything. It never contacts the network, reads credentials or imports a Hub client. Run the printed commands only after the destination, the operation and the credential were explicitly confirmed, then check `https://huggingface.co/api/models?filter=BVS` read-only. The default model is published at https://huggingface.co/RafaelJaime/BVS-default (commit `8229490c7c1b5925b8353a80ae0295eda25fa589`).
