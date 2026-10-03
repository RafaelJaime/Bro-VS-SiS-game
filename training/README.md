# BVS training recipe

> New here? Start with the step-by-step guide: [docs/train-your-own-model.md](../docs/train-your-own-model.md). This file is the technical reference.

Trains, exports and evaluates the fighter policies of Bro vs Sis. A policy is a small MLP; the game plays it with its own GDScript ONNX interpreter, so the Python side only produces a model file and numbers.

## Constraints you must respect

- **MLP only.** The exported graph may use `Gemm`, `MatMul`, `Add`, `Mul`, `Relu`, `Tanh`, `Sigmoid`, `Clip`, `Identity`, `Flatten`, `Reshape`, `Squeeze`, `Unsqueeze`, `Concat` and `Constant` (opset 13 to 18, shipped at 17). Anything else (recurrent cells, convolutions, `Gather`, `Shape`, `ArgMax`...) is refused by `export.py` and by the game. No external data files, at most 16 MiB, 512 nodes, 250k multiply-adds.
- **Training targets `bvs-schema-3`; `bvs-schema-2` stays frozen next to it.** GDScript owns both (`game/ai/schema/bvs_schema_v3.gd` with `bvs_action_decoder_v3.gd`, and the frozen `bvs_schema_v2.gd` with `bvs_action_decoder_v2.gd`); Python never builds observations. `bvs_training/schema.py` only mirrors the constants (`SCHEMAS[2]`, `SCHEMAS[3]`, `TRAIN_VERSION = 3`) so the trainer fails fast when Godot disagrees, and checks the committed fixtures on import.
- **The v2 freeze rule (amended).** The v2 module, decoder and fixtures (`bvs_schema_v2.gd`, `bvs_action_decoder_v2.gd`, `tests/fixtures/schema/v2_layout.json`, `v2_obs_golden.json`, the op fixtures) stay byte-identical. Only assertions about the *current* schema version or the *bundled* model move to the current schema. A schema change is a new `bvs_schema_vN.gd` plus a registry entry, never an edit of an older version.
- **The playable version is a separate switch.** `BvsSchema.CURRENT_VERSION` (what the picker, the model manager and the bundled default accept) stays 2 until a retrained schema 3 model passes every acceptance gate; it flips to 3 in the same commit that bundles that model. Until then schema 3 is registered and trainable, and a schema 3 model can still be evaluated and run through the harness (the model's own sidecar `schema_version` picks its schema).

| Contract | Value |
|----------|-------|
| Observation | `[1, 136]` float32, "me first, opponent second" (shield meter, dizzy, air dodge, food tags, nearest two bombs, sudden-death phase), field names in `tests/fixtures/schema/v3_layout.json` (schema 2: `[1, 102]`, `v2_layout.json`) |
| Action | `MultiDiscrete([3, 3, 2, 5, 2, 2, 2, 2])`, branches `a0_move`, `a1_vertical`, `a2_jump`, `a3_attack`, `a4_special`, `a5_throw`, `a6_block`, `a7_dash` |
| Model output | `logits` `[1, 21]`, argmax per branch (ties to the lowest index) |
| Decision rate | one decision per 4 physics frames (`action_repeat = 4`) |
| Sidecar | `bvs.json` (`format: bvs-model/1`) with `schema_version`, `obs_dim`, `action_branches`, `action_repeat`, `trained_on_commit`, `label`, optional `eval` |

A schema 3 model is tagged `BVS` and `bvs-schema-3` (plus `reinforcement-learning`, `onnx`; `schema.SCHEMA_TAG`). The in-game picker lists tag `BVS` and marks the tag of the game's *current* schema as compatible (`bvs-schema-2` today; a `bvs-schema-3` model shows "Needs a newer game" until the switch flips). In the air, `a6_block` becomes the air dodge; `a5_throw` is exclusive while holding food (a punch and a throw never fire together).

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
uv run python -m bvs_training.handshake                          # optional protocol check (schema 3 env, a sudden-death-start row)
uv run python -m bvs_training.train --phase P1 --steps 4096 --seed 1   # smoke run (writes out/)
uv run python -m bvs_training.train --config configs/default.toml > out/train.log 2>&1   # full curriculum
uv run python -m bvs_training.export --checkpoint out/final.zip --out out/bvs_default/model.onnx
uv run python -m bvs_training.evaluate --model out/bvs_default/model.onnx --level easy --level normal --matches 20 --min-win-rate 0.60
uv run python -m bvs_training.golden --model out/bvs_default/model.onnx --obs-dump out/obs.json --out ../tests/fixtures/onnx/bvs_default_golden.json
uv run python -m bvs_training.harness --model out/bvs_default/model.onnx   # combat-depth acceptance gates
```

- `configs/default.toml` is all data: PPO hyperparameters, the `[match]` block, `[reward]` overrides (fields of `game/ai/training/reward_config.gd`), the curriculum phases (`P1` all CPU Easy, `P2` Easy and Normal, `P3` mixed with self-play and, once enabled, frozen snapshots), the `[acceptance]` gates and the time box.
- Each phase writes `out/train_config_<phase>.json` (the `BVS_TRAIN_CONFIG` read by `game/ai/training/train_arena.gd`: `schema_version`, `rows`, `match`, `reward`) and opens a fresh env, so the opponent mix changes without scene edits.
- **Sudden-death episodes.** `[match] sudden_death = true` sends a tied timer expiry into sudden death (300% and one stock, then escalating bombs after a grace period) instead of a draw, so the sudden-death slots of the observation are not always 0. `sd_safety_cap` (60 s) truncates a sudden death that never produced a KO: the episode ends as a draw with reason `sd_cap` and `"truncated": true` in its `BVS_EPISODE` line, and earns no win, loss or timeout reward. A phase's `sd_start` share (P2 0.125, P3 0.25) makes that share of its rows start every episode in sudden death (row key `"start": "sudden_death"`; they re-enter it after each reset).
- **Combat rewards** (all driven by fighter signals, never by observations): `pickup` (per food picked up, at most `pickup_cap` per episode), `food_hit` (my thrown food reaching the opponent, blocked or not), `shield_break_dealt` / `shield_break_taken` (a shield broken by my hit / mine broken), and `shield_hold` (per decision once my shield has been held longer than `shield_hold_threshold` seconds). `reward_config.gd` accepts the two parameters next to the terms.
- Godot prints one `BVS_EPISODE {json}` line per finished episode with every reward term, so KO, stock and win rewards are visible in the log. Redirect the output to a file for long runs.
- **Time box and stop file:** `run.time_box_hours` (default 8) is checked at phase boundaries and after every rollout. `touch training/out/STOP` ends the run cleanly after the current rollout; a model is still written (`out/final.zip`, `out/checkpoints/step_*.zip`, `out/snapshots/step_*.onnx`).
- Checkpoints are written every `checkpoint_every` agent steps and at the end of each phase.
- `--resume <zip>` continues from a checkpoint; `--n-parallel` and `--speedup` override the config.
- `snapshot_opponents = true` lets `TrainArena` run frozen snapshot ONNX files (`out/snapshots/step_*.onnx`) as P3 opponents through the in-game `PolicyController`. While no snapshot has been exported yet, or when the flag is `false`, the snapshot share is given to `cpu_normal` with a printed warning. A snapshot that is missing or does not fit the run's schema (3) is an error naming its row, never a silent substitute.

Throughput on a 10-core Apple M-series (8 rows per Godot process, speedup 8, `action_repeat` 4): 1 process 1.2k agent steps per second, 2 processes 2.3k, 4 processes 4.6k, 8 processes 8.4k (`n_parallel` in the config; default 4).

## Export, golden vectors, evaluation

- `export.py` wraps the policy trunk and action head (`PolicyLogits`), exports with `torch.onnx.export(opset_version=17, dynamo=False, do_constant_folding=True)`, runs `onnx.checker`, audits the ops against `onnx_ops.WHITELIST`, and checks onnxruntime against torch on 256 observations within 1e-5. It fails and writes nothing when an op is unsupported. `--self-test` exports a random-init policy to a temp dir; `--random-init --out <file>` writes a random-weight model for fixtures. It also writes `bvs.json` next to the model (`model.onnx` pairs with `bvs.json`, any other name with `<stem>.bvs.json`).
- `golden.py --check-schema` checks the committed schema fixtures against the Python mirror (name count, the self/opponent block order, every recorded golden observation finite, inside the clip range and `obs_dim` wide). The schema 3 fixtures (`tests/fixtures/schema/v3_layout.json`, `v3_obs_golden.json`) are generated by `tests/tools/gen_schema_v3_fixtures.gd`; the smoke test `tests/smoke/schema_v3.gd` fails when the layout or normalization drifts without them being regenerated (`"$GODOT" --headless --path . --fixed-fps 60 --script res://tests/tools/gen_schema_v3_fixtures.gd`).
- `golden.py --check-ops` regenerates the per-op fixtures under `tests/fixtures/onnx/ops/` and fails on any git difference. `golden.py --model` writes onnxruntime vectors (32 seeded random plus up to 32 recorded observations) with the model sha256; check them in Godot with `BVS_GOLDEN_JSON=<golden.json> godot --headless --path . --fixed-fps 60 --script res://tests/smoke/onnx_golden.gd` (the schema is the one that has the golden's `obs_dim`; the gate is max abs diff <= 1e-4 and exact argmax, run **before** a model is committed).
- `evaluate.py` runs `tests/smoke/policy_eval.gd` (full non-training matches, sides alternating, the model through the shipped interpreter) and writes `reports/<name>-eval.md` and `.json` with win rate, stocks taken, approach, attacks, recoveries, self-KO share, idle share and the combat-depth table (sudden-death length, pickups and throws per fighter-minute, blocked share, damage by source, shield breaks). It exits non-zero below `--min-win-rate` versus CPU Easy. At least 20 matches are required unless `--smoke` is given.
- `sidecar.py --model-dir <dir> --eval-report <json>` rewrites `bvs.json` with the evaluation block.
- `harness.py --model <model.onnx>` is the committed acceptance harness. It launches `tests/smoke/combat_harness.gd` twice (full matches `mvm`, `m_vs_cpu_easy`, `m_vs_cpu_normal` and the CPU-only reference `cpu_hard_vs_cpu_hard`; then the same with forced sudden death), renders `reports/<name>-harness.md` and `.json`, applies the `[acceptance]` gates and exits non-zero when one fails. The gates (`configs/default.toml`): forced-SD `mvm` mean sudden death at most 45 s, pickups per fighter-minute above 1.0 and blocked share at most 0.70 in every regulation matchup with the model, KO win rate versus CPU Easy at least 0.60, and at least 20 matches per matchup (`--smoke` skips that last one for pipeline checks). The Godot side can be driven by hand with `BVS_HARNESS_MODEL`, `BVS_HARNESS_MATCHUPS` (`mvm`, `m_vs_cpu_<easy|normal|hard>`, `cpu_<lvl>_vs_cpu_<lvl>`), `BVS_HARNESS_MATCHES`, `BVS_HARNESS_SEED`, `BVS_HARNESS_FORCE_SD` and `BVS_HARNESS_OUT`; the same seed and build give identical numbers (the documented tolerance for engine-version drift is 5% on the rate metrics).
- Tests: `cd training && uv run pytest -q` (schema mirror and fixtures, sidecar and export for schema 3, phase configs, the combat table of `evaluate.py`, and the harness gates with synthetic metrics).

## Upload gate

Publishing to Hugging Face is a remote operation. **Nothing in this repo uploads.** `prepare_upload.py --repo <owner>/<name> --license <spdx> --confirm <owner>/<name>` stages `out/upload/<name>/` (`model.onnx`, `bvs.json`, a rendered model card), verifies the staged sha256 against the bundled copies under `game/ai/models/bvs_default/`, and only prints the `uvx --from huggingface_hub hf repos create ... --exist-ok` and `uvx --from huggingface_hub hf upload ...` commands. They go through `uvx` because a bare `hf` can be a different program on `PATH` (for example the Higgsfield CLI), and the current Hugging Face CLI spells the subcommand `repos create` (`hf upload` also creates a missing repo). Without `--confirm` carrying the same repo id it exits with status 2 before doing anything. It never contacts the network, reads credentials or imports a Hub client. Run the printed commands only after the destination, the operation and the credential were explicitly confirmed, then check `https://huggingface.co/api/models?filter=BVS` read-only. The default model is published at https://huggingface.co/RafaelJaime/BVS-default (commit `8229490c7c1b5925b8353a80ae0295eda25fa589`).
