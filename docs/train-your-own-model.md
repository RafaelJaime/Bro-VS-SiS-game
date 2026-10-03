# Train and publish your own BVS opponent

Train a fighter policy with PPO, export it as a small ONNX file, publish it on Hugging Face, and fight it in the game by typing your username in the model picker. A reference model is published at <https://huggingface.co/RafaelJaime/BVS-default>.

Technical reference for every script: [`training/README.md`](../training/README.md).

## Quick path

```sh
cd training
uv sync
uv run python -m bvs_training.train --phase P1 --steps 4096 --seed 1                  # smoke run
mkdir -p out && uv run python -m bvs_training.train --config configs/default.toml > out/train.log 2>&1   # full run
uv run python -m bvs_training.export --checkpoint out/final.zip --out out/my_fighter/model.onnx
uv run python -m bvs_training.evaluate --model out/my_fighter/model.onnx --level easy --level normal --matches 20 --min-win-rate 0.60
```

Then [publish](#7-publish-to-hugging-face) the folder `out/my_fighter/` (`model.onnx` + `bvs.json` + `README.md`) with tags `BVS` and `bvs-schema-2`.

## Contents

1. [Prerequisites](#1-prerequisites)
2. [Setup and smoke run](#2-setup-and-smoke-run)
3. [Full training](#3-full-training)
4. [Export to ONNX](#4-export-to-onnx)
5. [Check it in Godot (golden parity)](#5-check-it-in-godot-golden-parity)
6. [Evaluate](#6-evaluate)
7. [Publish to Hugging Face](#7-publish-to-hugging-face)
8. [Play against it](#8-play-against-it)
9. [The model contract](#the-model-contract)
10. [Troubleshooting](#troubleshooting)

## 1. Prerequisites

| Need | Detail |
|------|--------|
| Godot **4.7.2** | Runs the headless training scene and the evaluation. Point `GODOT_BIN` at the executable. |
| [uv](https://docs.astral.sh/uv/) | Installs Python 3.12 and the pinned dependencies (the project requires `==3.12.*`). |
| A Hugging Face account | Only for publishing. |

`GODOT_BIN` defaults to the Steam install on macOS (`~/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot`). With any other install, export it first:

```sh
export GODOT_BIN=/path/to/Godot
```

**macOS note.** `godot-rl` rewrites an `env_path` `X` into `X.app/Contents/MacOS/X`. The repo ships `training/bin/bvs-godot.app/Contents/MacOS/bvs-godot`, a shim that execs the real launcher `training/bin/bvs-godot`, so training works without changes. You do not need to create it.

**Linux note.** The launcher and `GODOT_BIN` handling are plain shell, so setting `GODOT_BIN` should be enough. The training pipeline has been exercised on macOS (Apple M-series) only.

## 2. Setup and smoke run

```sh
cd training
uv sync
uv run python -m bvs_training.handshake
```

`HANDSHAKE OK` means Godot, `godot-rl` and the schema agree (observation `[102]`, action space `MultiDiscrete([3 3 2 5 2 2 2 2])`).

Then a short run to prove the whole loop works (it writes to `training/out/`):

```sh
uv run python -m bvs_training.train --phase P1 --steps 4096 --seed 1
```

Expect Godot lines such as `BVS_EPISODE {...}` (one per finished episode, with every reward term) and a final line naming `out/final.zip`.

## 3. Full training

```sh
mkdir -p out
uv run python -m bvs_training.train --config configs/default.toml > out/train.log 2>&1
```

Keep the terminal open (or use `tmux`). Follow progress with `tail -f out/train.log`.

### Curriculum (`configs/default.toml`)

| Phase | Agent steps | Opponents |
|-------|-------------|-----------|
| `P1` | 3,000,000 | 100% CPU Easy |
| `P2` | 3,000,000 | 50% CPU Easy, 50% CPU Normal |
| `P3` | 4,000,000 | 30% CPU Normal, 20% CPU Easy, 20% self-play, 30% frozen snapshots of earlier checkpoints |

Total: 10M agent steps. Each phase opens a fresh Godot environment, so the opponent mix changes without scene edits.

### Knobs

| Where | Setting | Default | Effect |
|-------|---------|---------|--------|
| `[run]` | `n_parallel` | 4 | Godot processes (8 rows each). More is faster until cores run out. |
| `[run]` | `speedup` | 8 | Physics speedup passed to Godot. |
| `[run]` | `time_box_hours` | 8.0 | Hard stop, checked at phase boundaries and after every rollout. |
| `[run]` | `checkpoint_every` | 250,000 | Agent steps between checkpoints. |
| `[run]` | `snapshot_opponents` | `true` | Lets P3 play frozen snapshots; when `false` (or none exist yet) that share goes to CPU Normal, with a printed warning. |
| `[ppo]` | `n_steps`, `batch_size`, `n_epochs`, `learning_rate`, `gamma`, `gae_lambda`, `ent_coef`, `clip_range` | see file | Standard PPO hyperparameters. |
| `[ppo]` | `net_arch_pi`, `net_arch_vf` | `[64, 64]` | Network size. Keep the exported graph inside the [limits](#the-model-contract). |
| `[reward]` | any `RewardConfig` field | empty | Overrides the defaults of `game/ai/training/reward_config.gd`. |
| `[[phase]]` | `name`, `steps`, `mix` | P1 to P3 | The curriculum itself. |

Copy the file (`cp configs/default.toml configs/mine.toml`) and pass `--config configs/mine.toml` to experiment.

### Command-line options

`train` accepts `--config`, `--phase` (`P1`, `P2`, `P3` or `all`), `--steps` (overrides every selected phase), `--seed`, `--n-parallel`, `--speedup`, `--out`, `--resume <zip>` and `--checkpoint-every`.

### Time and throughput

Measured on a 10-core Apple M-series, `action_repeat` 4, speedup 8:

| `n_parallel` | Agent steps per second |
|--------------|------------------------|
| 1 | about 1.2k |
| 2 | about 2.3k |
| 4 | about 4.6k |
| 8 | about 8.4k |

At 4 processes, the 10M-step curriculum is roughly 40 minutes of pure simulation. The published default model finished the whole curriculum in under one hour of wall time using `--n-parallel 8`. Your machine will differ.

### Stopping and resuming

- `touch training/out/STOP` ends the run cleanly after the current rollout; a model is still written.
- Outputs: `out/final.zip`, `out/checkpoints/step_*.zip`, `out/snapshots/step_*.onnx`, and one `out/train_config_<phase>.json` per phase.
- Resume with `--resume out/checkpoints/<file>.zip`, for example `--phase P3 --resume out/checkpoints/step_P2_final.zip`.

## 4. Export to ONNX

```sh
uv run python -m bvs_training.export --checkpoint out/final.zip --out out/my_fighter/model.onnx --label "My fighter"
```

`--label` is the name stored in the sidecar (default `BVS default`) and `--difficulty-hint` sets `difficulty_hint` (default `easy`).

The script exports the deterministic logits head with `torch.onnx.export(opset_version=17, dynamo=False, ...)`; you do not need to set any of that. Before writing anything it:

1. runs `onnx.checker`,
2. audits every op against the whitelist,
3. compares onnxruntime with torch on 256 observations (tolerance 1e-5).

If any step fails, **nothing is written**. On success you get `model.onnx` and `bvs.json` side by side.

To check the toolchain without a checkpoint: `uv run python -m bvs_training.export --self-test`.

### Why only MLPs

The game does not ship onnxruntime. It runs models with its own GDScript interpreter (`game/ai/onnx/`), so only a small set of operators exists:

| Constraint | Value |
|------------|-------|
| Allowed ops | `Gemm`, `MatMul`, `Add`, `Mul`, `Relu`, `Tanh`, `Sigmoid`, `Clip`, `Identity`, `Flatten`, `Reshape`, `Squeeze`, `Unsqueeze`, `Concat`, `Constant` |
| Opset | 13 to 18 (the exporter writes 17) |
| Size | at most 16 MiB, 512 nodes, 512 initializers, 4,194,304 elements per tensor |
| Compute | at most 250,000 multiply-adds per inference |
| External data | not allowed |

Recurrent cells, convolutions, `Gather`, `Shape`, `ArgMax` and similar ops are rejected. Stay with a plain MLP (`net_arch_pi` in the config).

## 5. Check it in Godot (golden parity)

This confirms the game's interpreter produces the same numbers as onnxruntime for your file.

```sh
uv run python -m bvs_training.evaluate --model out/my_fighter/model.onnx --level easy --matches 20 --obs-dump out/obs.json
uv run python -m bvs_training.golden --model out/my_fighter/model.onnx --obs-dump out/obs.json --out out/golden.json
```

From the repository root, run the check in Godot (use your Godot executable for `godot`):

```sh
BVS_GOLDEN_JSON=training/out/golden.json "$GODOT_BIN" --headless --path . --fixed-fps 60 --script res://tests/smoke/onnx_golden.gd
```

The golden file holds 32 seeded random observations plus up to 32 observations recorded in real matches. The shipped default matched onnxruntime within 1.4e-6 with identical argmax on 64 cases.

This step is optional but recommended; `evaluate` in the next section already runs your model through the same interpreter.

## 6. Evaluate

```sh
uv run python -m bvs_training.evaluate --model out/my_fighter/model.onnx --level easy --level normal --level hard --matches 20 --min-win-rate 0.60
```

Full non-training matches, sides alternating, using the interpreter players use. It writes `reports/<name>-eval.md` and `.json` and exits non-zero if the win rate versus CPU Easy is below `--min-win-rate`. At least 20 matches are required unless you pass `--smoke` (pipeline checks only).

### What good looks like

| Signal | Reference (`BVS-default`, 40 matches per level) |
|--------|--------------------------------------------------|
| Win rate vs Easy | 1.00 (gate: at least 0.60 over at least 20 matches) |
| Win rate vs Normal, Hard | 1.00 and 1.00 |
| Stocks lost | 0.00 against every level |
| Idle share | 0.03 |
| Self-KO share of stocks lost | 0.00 |
| Action entropy per branch | 0.70 to 1.51 bits (no branch collapsed to one action) |

A model that wins by timeout, idles most of the match, or loses stocks to its own falls is weaker than its win rate suggests: read the "Behavior indicators" and "Play quality" tables, not only the first one.

### Embed the results in the sidecar

```sh
uv run python -m bvs_training.sidecar --model-dir out/my_fighter --label "My fighter" --difficulty-hint hard --eval-report reports/my_fighter-eval.json
```

The report name follows the model folder, so `out/my_fighter/` gives `reports/my_fighter-eval.json`. Rewriting `bvs.json` is safe to repeat.

## 7. Publish to Hugging Face

Publishing is a remote action on your account. Nothing in this repo uploads for you: `prepare_upload` only stages files and prints the commands.

### Stage and render the model card

```sh
uv run python -m bvs_training.prepare_upload --repo <your-username>/<model-name> --license mit --confirm <your-username>/<model-name> --source out/my_fighter --allow-unbundled
```

- `--confirm` must repeat `--repo` exactly, otherwise the script exits with status 2.
- `--allow-unbundled` is needed because the default `--source` is the model bundled with the game.
- Choose the license you actually want (SPDX id).
- The result is `out/upload/<model-name>/` with `model.onnx`, `bvs.json` and a rendered `README.md` whose front matter carries the tags and your evaluation results.

### Upload

The script prints the exact commands. They have this shape:

```sh
uvx --from huggingface_hub hf repos create <your-username>/<model-name> --repo-type model --exist-ok
uvx --from huggingface_hub hf upload <your-username>/<model-name> out/upload/<model-name> . --repo-type model --commit-message "<message>"
```

Run the commands exactly as printed. They go through `uvx --from huggingface_hub` on purpose: a bare `hf` on your `PATH` may be a different program. You must be authenticated with your own Hugging Face account first (see the Hugging Face CLI documentation).

### Verify

Open `https://huggingface.co/api/models?author=<your-username>&filter=BVS` in a browser. Your repo should be listed with the tags `BVS` and `bvs-schema-2`.

## 8. Play against it

1. Start the game and open the character select screen.
2. For a player, press **Use AI**; the picker "Choose an AI model" opens. (The controller dropdown next to it offers Human, the CPU levels and "AI: BVS default".)
3. Type your Hugging Face username and press **Search** (leave it empty to list every model tagged `BVS`).
4. Your model appears with the **Compatible** badge. Select it; the game resolves the revision, downloads `bvs.json` and `model.onnx`, validates them and shows **Ready**.
5. Start the match.

Notes:

- The bundled **AI: BVS default** is always available offline from the controller dropdown.
- Downloads are cached per repo and revision under `user://models/`. Publishing a new revision downloads again.
- A model that fails never falls back silently to the scripted CPU; you see the reason instead.

## The model contract

A repo must contain exactly these for the game to use it.

| File | Purpose |
|------|---------|
| `model.onnx` | The policy: input `obs` `[1, 102]` float32, output `logits` `[1, 21]`. |
| `bvs.json` | The sidecar (`format: bvs-model/1`). Downloaded and validated first. |
| `README.md` | The model card. Its front matter carries the Hub tags. |

| Tag | Meaning |
|-----|---------|
| `BVS` | Makes the model discoverable by the picker. |
| `bvs-schema-2` | Marks it **Compatible** with this game. Without it, or with another number, the model is not selectable. |

Recommended extra tags: `reinforcement-learning`, `onnx`. The generated card sets all four.

### Sidecar fields

| Field | Value for schema 2 |
|-------|--------------------|
| `format` | `bvs-model/1` |
| `schema_version` | `2` |
| `obs_dim` | `102` |
| `action_branches` | `a0_move` 3, `a1_vertical` 3, `a2_jump` 2, `a3_attack` 5, `a4_special` 2, `a5_throw` 2, `a6_block` 2, `a7_dash` 2 (names and order must match) |
| `action_repeat` | `4` (one decision per 4 physics frames) |
| `onnx` | `{"file": "model.onnx", "input": "obs", "output": "logits", "opset": 17}` |
| `trained_on_commit` | Git commit of the game the model was trained on |
| `label`, `difficulty_hint` | Display name and hint |
| `eval` | Optional results block |

`export` and `sidecar` write all of this for you. Do not edit it by hand.

### Observation and action

- **Observation** (`[1, 102]`, built by the game, "me first, opponent second"): own state (35 values), opponent state (35), relative position and stage flags, the 2 nearest foods, the 2 nearest projectiles, timer and sudden death. Python never builds observations. The authoritative layout is `game/ai/schema/bvs_schema_v2.gd`.
- **Action**: `MultiDiscrete([3, 3, 2, 5, 2, 2, 2, 2])`, 21 logits. The game takes the argmax of each branch (ties go to the lowest index).
- The schema is frozen. A change would arrive as a new schema version with a new tag.

## Troubleshooting

### Picker badges

| Badge | Cause | Fix |
|-------|-------|-----|
| **Trained for an older version** | The model has no `bvs-schema-N` tag, or N is lower than the game's schema (2). | Retrain against schema 2 and add the tag `bvs-schema-2`. |
| **Needs a newer game** | N is higher than the game's schema. | Update the game, or tag the model correctly. |
| **Not a BVS model** | Listed as one of your other reinforcement-learning models because you have no `BVS`-tagged model. | Add the tag `BVS` (and `bvs-schema-2`) to the repo. |
| Model not listed | Wrong username, repo is private or gated, or the tag is missing. | Check `https://huggingface.co/api/models?author=<you>&filter=BVS`. |

Tags come from the `tags:` list in the front matter of the repo `README.md`.

### Selecting a model fails

| Message or cause | Meaning | Fix |
|------------------|---------|-----|
| "The repo is missing model.onnx and/or bvs.json" | A required file is not in the repo. | Upload both files at the repo root. |
| "bvs.json is not valid JSON" or "bvs.json is missing '...'" | Broken or incomplete sidecar. | Regenerate it with `export` or `sidecar`. |
| `schema_version`, `obs_dim`, `action_branches` or `action_repeat` mismatch | Sidecar does not match schema 2. | Regenerate it; do not hand-edit. |
| "unsupported operator ..." | The graph uses an op outside the whitelist. | Use a plain MLP; `export` would have refused it, so you probably produced the file another way. |
| "This model expects N inputs; this game provides 102" | The ONNX input size differs from the schema (sidecar and graph disagree). | Train and export through `bvs_training`; do not change the observation size. |
| "model.onnx is too large" or "needs N multiply-adds (limit 250000)" | Over the size or compute limit. | Use a smaller network (`net_arch_pi`). |
| "opset N is not supported (need 13 to 18)" | Exported with another opset. | Use `bvs_training.export`. |
| "was not found on Hugging Face" or "is private or gated" | Wrong id, or the repo is not public. | Check the owner/name and make the repo public. |
| HTTP 429 | Hugging Face rate limit. | Wait a minute and press Retry. |
| "Could not reach Hugging Face" | Offline. | Reconnect. A revision downloaded before still plays from the cache. |

### Training and tooling

| Symptom | Fix |
|---------|-----|
| `handshake` cannot start Godot | Set `GODOT_BIN` to a Godot 4.7.2 executable. |
| `export` fails with an unsupported op | The checkpoint network is not a plain MLP; use the default `net_arch_pi` and `net_arch_vf`. |
| `evaluate` exits non-zero | Win rate versus CPU Easy is below `--min-win-rate`. Train longer or adjust the curriculum. |
| `evaluate` refuses fewer than 20 matches | Raise `--matches`, or add `--smoke` for a pipeline check only. |
| A bare `hf` command does nothing useful | Use `uvx --from huggingface_hub hf ...` as printed by `prepare_upload`. |

## Next step

Share your repo link with the community, and open an issue if the picker rejects a model that follows this guide.
