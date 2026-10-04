# BVS training recipe

> New here? Start with the step-by-step guide: [docs/train-your-own-model.md](../docs/train-your-own-model.md). This file is the technical reference.

Trains, exports and evaluates the fighter policies of Bro vs Sis. A policy is a small MLP; the game plays it with its own GDScript ONNX interpreter, so the Python side only produces a model file and numbers.

## Constraints you must respect

- **MLP only.** The exported graph may use `Gemm`, `MatMul`, `Add`, `Mul`, `Relu`, `Tanh`, `Sigmoid`, `Clip`, `Identity`, `Flatten`, `Reshape`, `Squeeze`, `Unsqueeze`, `Concat` and `Constant` (opset 13 to 18, shipped at 17). Anything else (recurrent cells, convolutions, `Gather`, `Shape`, `ArgMax`...) is refused by `export.py` and by the game. No external data files, at most 16 MiB, 512 nodes, 250k multiply-adds.
- **Training targets `bvs-schema-4`; schemas 2 and 3 stay frozen next to it.** GDScript owns all three (`game/ai/schema/bvs_schema_v4.gd` with `bvs_action_decoder_v4.gd`, and the frozen v3 and v2 modules with their decoders); Python never builds observations. `bvs_training/schema.py` only mirrors the constants (`SCHEMAS[2]`, `SCHEMAS[3]`, `SCHEMAS[4]`, `TRAIN_VERSION = 4`) so the trainer fails fast when Godot disagrees, and checks the committed fixtures on import.
- **The freeze rule (amended).** The v2 and v3 modules, decoders and fixtures (`bvs_schema_v2.gd`, `bvs_schema_v3.gd`, their decoders, `tests/fixtures/schema/v2_*.json` and `v3_*.json`, the op fixtures) stay byte-identical. Only assertions about the *current* schema version or the *bundled* model move to the current schema (and the registry test stub of `schema_v2.gd` and `schema_v3.gd`, which registers a made-up version, moved from 4 to 5 once version 4 became real). A schema change is a new `bvs_schema_vN.gd` plus a registry entry, never an edit of an older version.
- **The playable version is a separate switch.** `BvsSchema.CURRENT_VERSION` (what the picker, the model manager and the bundled default accept) stays 3 until a retrained schema 4 model passes every acceptance gate; it flips to 4 in the same commit that bundles that model. Until then schema 4 is registered and trainable, and a schema 4 (or 3) model can still be evaluated and run through the harness (the model's own sidecar `schema_version` picks its schema).
- **Schema 4 = schema 3 plus 13 floats.** Indices 0-135 are the schema 3 vector byte for byte; 136-139 and 140-143 are the kit one-hots of me and the opponent (Rafael 0, Matilde 1, ids 2-3 reserved, a generic profile is all zeros), 144 is my jab chain step / 3, 145 is 1 while my link window is open, 146 is the opponent's hitstun left in seconds (clipped to 1), 147 is the combo I am dealing (opponent's combo hits / 6) and 148 the combo I am taking (my combo hits / 6). The action layout and the decoder behavior are unchanged.

| Contract | Value |
|----------|-------|
| Observation | `[1, 149]` float32, "me first, opponent second" (shield meter, dizzy, air dodge, food tags, nearest two bombs, sudden-death phase, plus kits, chain step, link window, opponent hitstun and combo), field names in `tests/fixtures/schema/v4_layout.json` (schema 3: `[1, 136]`, `v3_layout.json`; schema 2: `[1, 102]`, `v2_layout.json`) |
| Action | `MultiDiscrete([3, 3, 2, 5, 2, 2, 2, 2])`, branches `a0_move`, `a1_vertical`, `a2_jump`, `a3_attack`, `a4_special`, `a5_throw`, `a6_block`, `a7_dash` |
| Model output | `logits` `[1, 21]`, argmax per branch (ties to the lowest index) |
| Decision rate | one decision per 4 physics frames (`action_repeat = 4`) |
| Sidecar | `bvs.json` (`format: bvs-model/1`) with `schema_version`, `obs_dim`, `action_branches`, `action_repeat`, `trained_on_commit`, `label`, optional `eval` |

A schema 4 model is tagged `BVS` and `bvs-schema-4` (plus `reinforcement-learning`, `onnx`; `schema.SCHEMA_TAG`). The in-game picker lists tag `BVS` and marks the tag of the game's *current* schema as compatible (`bvs-schema-3` today; a `bvs-schema-4` model shows "Needs a newer game" until the switch flips). In the air, `a6_block` becomes the air dodge; `a5_throw` is exclusive while holding food (a punch and a throw never fire together).

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
uv run python -m bvs_training.handshake                          # optional protocol check (schema 4 env, random kits, a sudden-death-start row)
uv run python -m bvs_training.train --phase P1 --steps 4096 --seed 1   # smoke run (writes out/)
uv run python -m bvs_training.train --config configs/default.toml > out/train.log 2>&1   # full curriculum
uv run python -m bvs_training.export --checkpoint out/final.zip --out out/bvs_default/model.onnx
uv run python -m bvs_training.evaluate --model out/bvs_default/model.onnx --level easy --level normal --matches 20 --min-win-rate 0.60
uv run python -m bvs_training.golden --model out/bvs_default/model.onnx --obs-dump out/obs.json --out ../tests/fixtures/onnx/bvs_default_golden.json
uv run python -m bvs_training.harness --model out/bvs_default/model.onnx   # acceptance gates (172 matches, both kits on both sides)
uv run python -m bvs_training.harness --baseline                            # shield-raise baseline (writes reports/shield-baseline.{json,md})
```

- `configs/default.toml` is all data: PPO hyperparameters, the `[match]` block, `[reward]` overrides (fields of `game/ai/training/reward_config.gd`), the curriculum phases (`P1` all CPU Easy, `P2` Easy and Normal, `P3` mixed with self-play and, once enabled, frozen snapshots), the `[acceptance]` gates and the time box.
- Each phase writes `out/train_config_<phase>.json` (the `BVS_TRAIN_CONFIG` read by `game/ai/training/train_arena.gd`: `schema_version`, `rows`, `match`, `kits`, `reward`) and opens a fresh env, so the opponent mix changes without scene edits.
- **Sudden-death episodes.** `[match] sudden_death = true` sends a tied timer expiry into sudden death (300% and one stock, then escalating bombs after a grace period) instead of a draw, so the sudden-death slots of the observation are not always 0. `sd_safety_cap` (60 s) truncates a sudden death that never produced a KO: the episode ends as a draw with reason `sd_cap` and `"truncated": true` in its `BVS_EPISODE` line, and earns no win, loss or timeout reward. A phase's `sd_start` share (P2 0.125, P3 0.25) makes that share of its rows start every episode in sudden death (row key `"start": "sudden_death"`; they re-enter it after each reset).
- **Combat rewards** (all driven by fighter signals, never by observations): `pickup` (per food picked up, at most `pickup_cap` per episode), `food_hit` (my thrown food reaching the opponent, blocked or not), `shield_break_dealt` / `shield_break_taken` (a shield broken by my hit / mine broken), and `shield_hold` (per decision once my shield has been held longer than `shield_hold_threshold` seconds). `reward_config.gd` accepts the two parameters next to the terms.
- **Kits.** `[kits] mode = "random"` (the default) draws a kit, Rafael or Matilde, for each side of each row when the row is built and again at the end of every episode, from a per-row generator seeded `kits.seed * 1009 + row index` (`kits.seed` defaults to `run.seed`), so both kits appear on both sides, mirrors included, and the draw is reproducible. `mode = "character"` keeps the scene kits (Fighter1 Rafael, Fighter2 Matilde). The kit one-hot of the observation is what lets one policy play both.
- **Combo and shield rewards** (signal driven): `combo_hit` (0.02 per extra hit of a combo I deal, from the foe's `combo_updated` with me as the attacker; at most `combo_hit_cap` = 4 extra hits per combo and `combo_episode_cap` = 1.0 per episode, so jab restarts are not farmed) and `shield_raise` (per `Fighter.shield_raises` delta per decision; 0.0 in `reward_config.gd`, -0.002 in `default.toml`; the main lever against shield spam).
- Godot prints one `BVS_EPISODE {json}` line per finished episode with every reward term, so KO, stock and win rewards are visible in the log. Redirect the output to a file for long runs.
- **Time box and stop file:** `run.time_box_hours` (default 8) is checked at phase boundaries and after every rollout. `touch training/out/STOP` ends the run cleanly after the current rollout; a model is still written (`out/final.zip`, `out/checkpoints/step_*.zip`, `out/snapshots/step_*.onnx`).
- Checkpoints are written every `checkpoint_every` agent steps and at the end of each phase.
- `--resume <zip>` continues from a checkpoint; `--n-parallel` and `--speedup` override the config.
- `snapshot_opponents = true` lets `TrainArena` run frozen snapshot ONNX files (`out/snapshots/step_*.onnx`) as P3 opponents through the in-game `PolicyController`. While no snapshot has been exported yet, or when the flag is `false`, the snapshot share is given to `cpu_normal` with a printed warning. A snapshot that is missing or does not fit the run's schema (4) is an error naming its row, never a silent substitute.

Throughput on a 10-core Apple M-series (8 rows per Godot process, speedup 8, `action_repeat` 4): 1 process 1.2k agent steps per second, 2 processes 2.3k, 4 processes 4.6k, 8 processes 8.4k (`n_parallel` in the config; default 4).

## Export, golden vectors, evaluation

- `export.py` wraps the policy trunk and action head (`PolicyLogits`), exports with `torch.onnx.export(opset_version=17, dynamo=False, do_constant_folding=True)`, runs `onnx.checker`, audits the ops against `onnx_ops.WHITELIST`, and checks onnxruntime against torch on 256 observations within 1e-5. It fails and writes nothing when an op is unsupported. `--self-test` exports a random-init policy to a temp dir; `--random-init --out <file>` writes a random-weight model for fixtures. It also writes `bvs.json` next to the model (`model.onnx` pairs with `bvs.json`, any other name with `<stem>.bvs.json`).
- `golden.py --check-schema` checks the committed schema fixtures against the Python mirror (name count, the self/opponent block order, every recorded golden observation finite, inside the clip range and `obs_dim` wide). The schema 4 fixtures (`tests/fixtures/schema/v4_layout.json`, `v4_obs_golden.json`) are generated by `tests/tools/gen_schema_v4_fixtures.gd`; the smoke test `tests/smoke/schema_v4.gd` fails when the layout or normalization drifts without them being regenerated (`"$GODOT" --headless --path . --fixed-fps 60 --script res://tests/tools/gen_schema_v4_fixtures.gd`). It also checks that `v4[0:136]` equals the schema 3 vector on the same snapshots. The schema 3 fixtures (`v3_*.json`, `tests/tools/gen_schema_v3_fixtures.gd`) stay frozen.
- `golden.py --check-ops` regenerates the per-op fixtures under `tests/fixtures/onnx/ops/` and fails on any git difference. `golden.py --model` writes onnxruntime vectors (32 seeded random plus up to 32 recorded observations) with the model sha256; check them in Godot with `BVS_GOLDEN_JSON=<golden.json> godot --headless --path . --fixed-fps 60 --script res://tests/smoke/onnx_golden.gd` (the schema is the one that has the golden's `obs_dim`; the gate is max abs diff <= 1e-4 and exact argmax, run **before** a model is committed).
- `evaluate.py` runs `tests/smoke/policy_eval.gd` (full non-training matches, sides alternating, the model through the shipped interpreter) and writes `reports/<name>-eval.md` and `.json` with win rate, stocks taken, approach, attacks, recoveries, self-KO share, idle share and the combat-depth table (sudden-death length, pickups and throws per fighter-minute, blocked share, damage by source, shield breaks) and a kits table (shield raises per fighter-minute, combo histogram and maximum, longest Hurt, combo damage by kit, and the model's wins by the kit it played; `--kits rm` by default, `--kits character` for the scene kits). It exits non-zero below `--min-win-rate` versus CPU Easy. At least 20 matches are required unless `--smoke` is given.
- `sidecar.py --model-dir <dir> --eval-report <json>` rewrites `bvs.json` with the evaluation block.
- `harness.py --model <model.onnx>` is the committed acceptance harness. It launches `tests/smoke/combat_harness.gd` once per group of matchups that share a match count (kits `rm`: the first controller plays Rafael on matches 0-1 and Matilde on 2-3 (mod 4) while sides alternate, so each controller plays each kit on each side): `mvm` and `cpu_hard_vs_cpu_hard` with 40 matches, `m_vs_cpu_easy`, `m_vs_cpu_hard` and `cpu_normal_vs_cpu_normal` with 24, then a forced sudden-death `mvm` with 20 (172 matches). It renders `reports/<name>-harness.md` and `.json`, applies the `[acceptance]` gates and exits non-zero when one fails. The gates (`configs/default.toml`):

  | Gate | Measured on | Threshold |
  |------|-------------|-----------|
  | sudden death ends | forced-SD `mvm` mean sudden death | at most 45 s |
  | food is picked up | every regulation matchup with the model | above 1.0 pickups per fighter-minute |
  | blocking is not the plan | every regulation matchup with the model | blocked share at most 0.70 |
  | it wins by KO | `m_vs_cpu_easy` | KO win rate at least 0.60 |
  | shields are not spammed | `mvm`, `m_vs_cpu_hard` | at most `max_shield_raises_per_fighter_minute` (recorded by `--baseline`; the gate fails while no value is recorded) |
  | shields are not tapped | every regulation matchup with the model | share of shield holds shorter than 15 ticks (0.25 s) at most `max_shield_tap_share` (0.5); CPU Hard's share is reported for information |
  | combos stay short | every matchup | longest combo at most 6 hits |
  | no long stun | every matchup | longest continuous Hurt at most 1.5 s |
  | combos happen | `mvm`, `cpu_normal_vs_cpu_normal`, `cpu_hard_vs_cpu_hard` | at least 5 combos of 2+ hits each |
  | kits are balanced | `mvm`, `cpu_hard_vs_cpu_hard` | Rafael's win share between 0.40 and 0.60 |
  | combo damage is balanced | all regulation matchups pooled | mean multi-hit combo damage differs by at most 20% between kits |
  | enough matches | every matchup | 24 (40 for `mvm` and `cpu_hard_vs_cpu_hard`, 20 for forced SD); `--smoke` skips this for pipeline checks |

  The Godot side can be driven by hand with `BVS_HARNESS_MODEL`, `BVS_HARNESS_MATCHUPS` (`mvm`, `m_vs_cpu_<easy|normal|hard>`, `cpu_<lvl>_vs_cpu_<lvl>`), `BVS_HARNESS_MATCHES`, `BVS_HARNESS_SEED`, `BVS_HARNESS_FORCE_SD`, `BVS_HARNESS_KITS` (`character`, `rm`, `rotate4`) and `BVS_HARNESS_OUT`; the same seed and build give identical numbers (the documented tolerance for engine-version drift is 5% on the rate metrics). Every matchup reports shield raises per fighter-minute, the combo histogram (1 to 6, 7+), the maximum combo, the longest Hurt, Rafael's win share and Fighter1's win share, and the mean multi-hit combo damage by kit.
- **Shield-raise baseline (design D15).** `harness.py --baseline` measures `R_cpu` (CPU Hard against itself, 40 matches, kits `rm`, seed 1) and `R_old` (the bundled model, or `--model`, in `mvm` and `m_vs_cpu_hard`, 24 matches each, the maximum of the two) and writes `reports/shield-baseline.json` and `.md` with the threshold `T = min(0.5 * R_old, max(1.5 * R_cpu, R_cpu + 2.0))` (when `0.5 * R_old < R_cpu` the old model does not spam on the new rules and `T = max(1.5 * R_cpu, R_cpu + 2.0)`). `T` is copied to `[acceptance] max_shield_raises_per_fighter_minute` and committed before the retrain; it only changes through a new measurement that the report explains (for example after a kit-data change).
- **Replay.** The 45 s model-vs-model replay of a candidate: `godot --path . --resolution 800x600 --fixed-fps 60 --write-movie out/replay.avi --script res://tests/smoke/policy_reel.gd -- model=<model.onnx> opponent=model kits=rm seconds=45 out=out/reel`, then a manual conversion (not in the repo toolchain): `ffmpeg -i out/replay.avi -c:v libx264 -pix_fmt yuv420p -crf 23 -an reports/bvs_default-replay.mp4`. The file lives under `training/reports/`, never under `game/`, so the web export does not ship it; `prepare_upload.py` stages a `replay.mp4` found next to the model.
- Tests: `cd training && uv run pytest -q` (schema mirror and fixtures for schemas 3 and 4, sidecar and export for schema 4, phase configs and the kits block, the combat and kits tables of `evaluate.py`, and the harness gates and the baseline with synthetic metrics).

## Upload gate

Publishing to Hugging Face is a remote operation. **Nothing in this repo uploads.** `prepare_upload.py --repo <owner>/<name> --license <spdx> --confirm <owner>/<name>` stages `out/upload/<name>/` (`model.onnx`, `bvs.json`, a rendered model card), verifies the staged sha256 against the bundled copies under `game/ai/models/bvs_default/`, and only prints the `uvx --from huggingface_hub hf repos create ... --exist-ok` and `uvx --from huggingface_hub hf upload ...` commands. They go through `uvx` because a bare `hf` can be a different program on `PATH` (for example the Higgsfield CLI), and the current Hugging Face CLI spells the subcommand `repos create` (`hf upload` also creates a missing repo). Without `--confirm` carrying the same repo id it exits with status 2 before doing anything. It never contacts the network, reads credentials or imports a Hub client. Run the printed commands only after the destination, the operation and the credential were explicitly confirmed, then check `https://huggingface.co/api/models?filter=BVS` read-only. The default model is published at https://huggingface.co/RafaelJaime/BVS-default (commit `8229490c7c1b5925b8353a80ae0295eda25fa589`).
