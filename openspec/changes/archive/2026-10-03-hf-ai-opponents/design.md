# Design: Hugging Face AI Opponents (schema v2, GDScript ONNX, trained default model)

Mirror of Engram `sdd/hf-ai-opponents/design`. Inputs: `proposal.md` (authoritative), Engram `sdd/hf-ai-opponents/explore`, main specs `openspec/specs/*`, and the current code (read in this phase; file:line evidence inline).

## Technical Approach

Approach B from the proposal, in five parts that share one contract:

1. **One schema module** (`game/ai/schema/`) owns the `bvs-schema-2` observation vector, the MultiDiscrete action layout, the action decoder into `FighterIntent`, `action_repeat`, and the sidecar contract. Training (`PlayerAIController` through `sync.gd`) and play (`PolicyController`) both call it. Python never computes observations. It only learns `obs_dim` and the action `nvec` from Godot's `env_info` and checks them against its own constants.
2. **A pure-GDScript ONNX interpreter** (`game/ai/onnx/`): a bounded protobuf wire reader, a ModelProto/GraphProto subset parser, a load-time shape check, and a small op evaluator over `PackedFloat32Array`. It reads untrusted Hub bytes, so every limit is explicit.
3. **A training environment** that matches play: a runtime-built arena (`train.tscn` plus `TrainArena`) whose rows do not overlap and where ledges exist. Episodes end through `Fighter.game_over()`. Rewards come from signals. Each row picks its opponent (scripted CPU, live self-play, or a frozen ONNX snapshot run by the same interpreter).
4. **A Python recipe** under `training/` (uv, Python 3.12, pinned `godot-rl` and SB3 PPO). It launches Godot headless through a launcher script, runs a phased curriculum, and exports **only the deterministic logits head** to a clean ONNX graph. It generates onnxruntime golden vectors and evaluates **the shipped artifact inside Godot** with the GDScript interpreter.
5. **Distribution**: a bundled offline default model in `res://`, a Hub cache keyed by repo and revision, sidecar and graph validation before play, visible loading and failure states, and an upload step that only prints the commands and stops at the authorization gate.

## Architecture Decisions

### D1: Schema module and versioning

**Choice**:
- A registry `BvsSchema` (`game/ai/schema/bvs_schema.gd`) maps a version int to a schema class. `CURRENT_VERSION := 2`.
- `BvsSchemaV2` (`bvs_schema_v2.gd`) is frozen after merge. A committed layout fixture (`tests/fixtures/schema/v2_layout.json`, field names in order) and a smoke test guard the freeze.
- Schema 3 adds `bvs_schema_v3.gd` and a registry entry, and never edits v2.
- `HubModel.BVS_SCHEMA_VERSION` becomes `BvsSchema.CURRENT_VERSION`.

**Alternatives considered**:
- Constants spread across `PlayerAIController` and `PolicyController` (today's state): this is how training and play drifted.
- A Python-side observation builder: it would duplicate the layout in two languages.
- A JSON layout file interpreted at runtime: slower, and the code would still have to know what each feature means.

**Rationale**: one GDScript source of truth, used by both paths, cannot drift. A frozen file plus a fixture makes an accidental v2 edit fail a test, not silently break every published model.

### D2: Observation layout (obs_dim = 102)

**Choice**: every value is a float32 built only from `Game.get_state_snapshot()` (Game-local, so the arena rows' offsets do not matter). The order is "me first, opponent second" from the observing fighter's point of view.

**Normalization constants** (frozen in v2, not read from `FighterProfile`):
- The stage center is `cx = (stage.left + stage.right) / 2` and the half-width is `HW = (stage.right - stage.left) / 2` (400 today).
- Positions: `x_n = (x - cx) / HW` and `y_n = (y - stage.top) / HW` (positive below the tabletop).
- Velocities: `vx / 600` (dash speed) and `vy / 1300` (fast-fall speed).
- Every feature is clipped to [-5, 5] after normalization.

Fighter block (35 floats; self at `[0,35)`, opponent at `[35,70)`):

| Off | Feature | Encoding |
|-----|---------|----------|
| 0,1 | position | `x_n`, `y_n` |
| 2,3 | velocity | `vx/600`, `vy/1300` |
| 4 | facing | -1 / +1 |
| 5 | on_floor | 0/1 |
| 6 | damage_percent | `/100`, clip [0,5] |
| 7 | stocks | `/3` |
| 8 | holding food | 0/1 |
| 9-11 | held food weight | one-hot LIGHT/MEDIUM/HEAVY (`FoodCatalog.get_weight_class`), zeros when empty |
| 12 | punch cooldown | seconds, clip [0,1] |
| 13 | shoot cooldown | seconds `/2`, clip [0,1] |
| 14 | jumps_left | `/2`, clip [0,1] |
| 15 | air_dash_available | 0/1 |
| 16 | recovery_available | 0/1 |
| 17 | is_invulnerable | 0/1 |
| 18 | ledge_side | -1/0/+1 |
| 19 | fast_falling | 0/1 |
| 20 | charge_level | 0..1 |
| 21-34 | state one-hot | Idle, Run, Jump, Fall, Punch, Hurt, Protect, Shoot, Dash, Helpless, LedgeHang, Recovery, Defeated, other (the 13 states in `player.tscn` plus a catch-all) |

Shared blocks:

| Range | Feature | Encoding |
|-------|---------|----------|
| 70,71 | opponent relative to me | `(opp.x-me.x)/HW`, `(opp.y-me.y)/HW` |
| 72 | opponent in front | `sign(dx) * facing` (0 when dx == 0) |
| 73 | me off stage | airborne and (x outside [left,right] or below top), same test as `ScriptedController._is_off_stage` |
| 74,75 | ledge occupied (left, right) | 0/1 from `snapshot.ledges[*].occupied` |
| 76-87 | 2 nearest foods (by distance to me, stage-inside only) | per slot: present, dx, dy, weight one-hot (3) |
| 88-99 | 2 nearest projectiles | per slot: present, dx, dy, `vx/600`, `vy/1300`, mine (shooter == my number) |
| 100 | timer left | `/99`, clip [0,1] |
| 101 | sudden death | 0/1 |

**Alternatives considered**:
- Horizontal mirroring, so the agent always "faces right": it halves the state space, but every x feature and the move/side-aim decode must flip, and it is easy to get subtly wrong. Deferred to a possible v3.
- Raw `global_position` (today): breaks when rows are offset (`player_ai_controller.gd:21-45`).
- More food or projectile slots: the stage rarely holds more than 2 relevant items, and every extra slot adds input width.
- Raycast sensors: an MLP over a full snapshot is cheaper and deterministic.

**Rationale**: it covers everything the scripted CPU reads to beat the player (`scripted_controller.gd:169-230`): stage edges, ledges, foods, projectiles, cooldowns, jumps, recovery, and the opponent's state. Bounded, self-relative values train well with PPO and no `VecNormalize`. Fixed constants make the observation independent of profile tuning, which is frozen anyway.

### D3: Action layout (MultiDiscrete, nvec = [3,3,2,5,2,2,2,2], 21 logits)

**Choice**: eight discrete branches, named with ordering prefixes so that insertion order and alphabetical order agree whatever the Python side does with the dict:

| Branch | Size | Values | Decode |
|--------|------|--------|--------|
| `a0_move` | 3 | left, none, right | `move_x` -1/0/+1 (held) |
| `a1_vertical` | 3 | none, up, down | held `aim` UP/DOWN (fast fall, ledge drop) |
| `a2_jump` | 2 | release, hold | `jump_held`; `jump_pressed` on the window's first frame when the previous decision was "release" or the fighter is on the floor (today's guard, `policy_controller.gd:30`) |
| `a3_attack` | 5 | none, neutral, up, down, side | `attack_pressed` on the window's first frame; the aim of that frame is the attack aim |
| `a4_special` | 2 | no, yes | `special_pressed` and `aim = UP` on the first frame (the CPU's recovery chord, `scripted_controller.gd:594-597`); it overrides `a3_attack` |
| `a5_throw` | 2 | no, yes | `throw_pressed` on the first frame |
| `a6_block` | 2 | no, yes | `block_held` for the whole window; `block_pressed` on a rising edge |
| `a7_dash` | 2 | no, yes | `dash_pressed` on the first frame |

- `attack_held` and `attack_released` stay false (no charge in v2). `action_repeat = 4` (15 Hz decisions).
- `BvsActionDecoderV2` is stateful: `begin_window(indices: PackedInt32Array)`, then `frame(fighter) -> FighterIntent` on each physics frame.
- Pressed flags fire only on the first frame of a window. Held flags last for the whole window.
- Training and play use the same decoder instance type inside `PolicyController`, so the frame-level semantics are identical.

**Alternatives considered**:
- Six thresholded continuous floats (today): hard to explore, and they cannot aim, dash or recover.
- One flat `Discrete(N)` over every combination: 1,440 classes.
- Deriving the side aim from move plus punch, as the human controller does: a walking punch would always become a side punch.
- Holding presses until the state accepts them (the CPU's "patience"): it depends on `available_actions` and adds hidden state that the agent cannot see.

**Rationale**:
- MultiDiscrete is the space `godot_rl_agents` maps to SB3 for all-discrete dicts. The `_extract_action_dict` argmax path in `sync.gd:282-310` shows that discrete branches are argmax-per-branch over concatenated logits.
- A factorized layout keeps the logits small (21).
- First-frame presses are deterministic and observable: the state one-hot tells the agent when a press was swallowed, and it re-presses in the next window.

### D4: Decision timing parity

**Choice**:
- In training, `Sync` (the first child of `Train`) sets the action at the start of every 4th physics frame, before the fighters' `_physics_process` (`sync.gd:172-185`). `PlayerAIController.set_action` stores `latest_action: PackedInt32Array` and increments `action_seq`.
- `PolicyController.sample()` calls `decoder.begin_window()` when `action_seq` changes.
- In play, `PolicyController` counts its own sampled frames. On every frame where `(ticks + phase_offset) % 4 == 0`, it builds the observation from the snapshot, runs the model, takes the argmax per branch, and calls `begin_window()`.
- `phase_offset` is the fighter index, so two AI fighters never run inference on the same frame.

**Alternatives considered**:
- Adding a `Sync` node to `game.tscn` in ONNX mode: this needs the C# runtime (`ONNX_wrapper.gd:3`), which is not available on the web.
- Running inference every frame: 4x the cost, and it does not match training.

**Rationale**: in both paths the observation reflects the state after the previous frame, and the action is applied in the same frame with the same decoder. Locked frames (countdown, sudden-death intro) are not sampled (`player.gd:146`), so the counter resumes cleanly.

### D5: GDScript ONNX interpreter: parser subset and limits

**Choice**:
- `PbReader` (`protobuf_reader.gd`) decodes wire types 0, 1, 2 and 5 over a `PackedByteArray`, with explicit bounds. It rejects groups (wire types 3 and 4), varints longer than 10 bytes, and lengths beyond the remaining bytes.
- `OnnxModelParser` reads only these fields (numbers from `onnx.proto`, reference https://github.com/onnx/onnx/blob/main/onnx/onnx.proto) and skips unknown fields:
  - ModelProto: `ir_version`=1, `opset_import`=8 (`domain`=1, `version`=2), `graph`=7.
  - GraphProto: `node`=1, `initializer`=5, `input`=11, `output`=12. `sparse_initializer`=15 is rejected.
  - NodeProto: `input`=1, `output`=2, `op_type`=4, `attribute`=5, `domain`=7.
  - AttributeProto: `name`=1, `f`=2 (fixed32), `i`=3, `s`=4, `t`=5, `floats`=7, `ints`=8 (packed or unpacked), `type`=20. Graph-valued attributes (`g`=6, `graphs`=11) are rejected.
  - TensorProto: `dims`=1, `data_type`=2 (FLOAT=1, INT64=7 for shape and axes constants only), `float_data`=4, `int64_data`=7, `name`=8, `raw_data`=9 (little-endian; `PackedByteArray.to_float32_array()` / `decode_s64`). `external_data`=13 and `data_location`=14 (EXTERNAL) are rejected.
  - ValueInfoProto: `name`=1, `type`=2, then `tensor_type`=1, `elem_type`=1, `shape`=2, `dim`=1, `dim_value`=1 or `dim_param`=2.
- Accepted opsets: the default domain (`""` or `ai.onnx`), versions 13–18.
- Hard limits: file ≤ 16 MiB, ≤ 512 nodes, ≤ 512 initializers, each tensor ≤ 4M elements, total MACs ≤ 250k per inference.

**Alternatives considered**:
- A generated protobuf library: none exists for GDScript, and a port would be large.
- Converting to a custom JSON weights format at export: Hub models would no longer be standard ONNX, and the "trained with godot_rl" ecosystem would break.
- onnxruntime-web through the JavaScript bridge, or a GDExtension: out of scope (proposal).

**Rationale**: the subset is what a `torch.onnx.export` of an MLP emits. Rejecting external data, sparse tensors and subgraphs keeps the parser small. The limits turn a malicious or huge file into a clear error rather than a freeze or an out-of-memory crash, which matters because the bytes come from any Hub user.

### D6: Op whitelist and evaluation

**Choice**:
- Whitelist: `Gemm`, `MatMul`, `Add`, `Mul`, `Relu`, `Tanh`, `Sigmoid`, `Clip`, `Identity`, `Flatten`, `Reshape`, `Squeeze`, `Unsqueeze`, `Concat`, `Constant`.
- `Shape`, `Gather`, `Slice` and `ArgMax` are deliberately excluded. Dynamic-shape ops must be constant-folded away by the export, and argmax happens in GDScript per branch.
- Load-time compile:
  1. Topological sort (Kahn); reject cycles and unknown inputs.
  2. Shape inference with the model input bound to `[1, obs_dim]`.
  3. Pre-transpose constant Gemm weights to row-major `[N][K]`.
  4. Build a flat plan.
- Run: values are `OnnxTensor {shape: PackedInt32Array, data: PackedFloat32Array}`. Accumulation happens in GDScript float (64-bit) and is stored as float32 per op, which keeps the result close to onnxruntime's float32.
- Gemm supports `alpha`, `beta`, `transA`, `transB`, and a C broadcast of `[N]`, `[1,N]` or `[M,N]`.
- Elementwise broadcasting is limited to the same shape, a trailing vector, or a scalar.
- The same whitelist is a constant in Python (`training/bvs_training/onnx_ops.py`). The export fails if the graph uses anything else. A synthetic fixture covers every op.

**Alternatives considered**:
- A general n-dimensional broadcasting engine: unnecessary for MLPs.
- Including `ArgMax` in the graph: it hides the logits that the golden tolerance check needs.
- Growing the whitelist from whatever SB3 or godot_rl export emits (`Shape`/`Gather` from dynamic batch): it adds complexity for no gain.

**Rationale**: 15 ops cover our own export (`Gemm` and `Tanh` in practice) and the common variants (MatMul plus Add, Relu, Flatten, Reshape) of other trainers' MLP exports. Every op has a golden fixture, as the proposal requires.

### D7: Inference performance budget

**Choice**:
- The reference policy is `net_arch pi=[64,64]` with Tanh: 102×64 + 64×64 + 64×21 ≈ 12k MACs.
- Budget: ≤ 1 ms per inference on desktop and ≤ 3 ms on the web, once every 4 frames, staggered per fighter.
- The 250k-MAC load limit rejects models that are far too large.
- A perf check in `tests/smoke/onnx_golden.gd` measures the average time per inference with `Time.get_ticks_usec()` over 200 runs and prints it (fail above 2 ms on desktop). The web is checked manually in the exported build.

**Alternatives considered**:
- Packing weights into textures and computing in a shader: overkill, and it reads back from the GPU.
- Caching the snapshot between frames: the snapshot is only built on decision frames anyway.

**Rationale**: amortized, this is under 1 ms per frame even on the web, with headroom for two AI fighters.

### D8: Export only the deterministic logits head (our own script)

**Choice**: `training/bvs_training/export.py` wraps the trained SB3 PPO policy:

```python
class PolicyLogits(torch.nn.Module):
    def __init__(self, policy):
        super().__init__()
        self.pi = policy.mlp_extractor.policy_net   # Linear+Tanh stack
        self.head = policy.action_net               # Linear -> 21 logits
    def forward(self, obs):                         # obs: [1, 102]
        return self.head(self.pi(obs))
```

- Exported with `torch.onnx.export(..., opset_version=17, input_names=["obs"], output_names=["logits"], do_constant_folding=True, dynamo=False)`. There are no dynamic axes, so the batch is static at 1.
- The script then:
  1. Runs `onnx.checker`.
  2. Audits the ops against the whitelist.
  3. Asserts that onnxruntime matches the torch logits within 1e-5 on 256 random observations.
- Bypassing the feature extractor is valid because the observation space is `Dict{"obs": Box(102)}`. SB3's `CombinedExtractor` only flattens that key, so it is identity on `[1,102]`. No `VecNormalize` is used.
- The interpreter also accepts godot_rl-style exports: an extra `state_ins` input is fed `[0]`, and the output named in the sidecar (default: the first output) is used. If such an export stays inside the whitelist, it loads.

**Alternatives considered**:
- godot_rl's `export_model_as_onnx` (outputs `output` and `state_outs`, inputs `obs` and `state_ins`, through `OnnxableMultiInputPolicy`): it adds an unused recurrent-state interface, and with dynamic batch axes it can emit `Shape`/`Gather`. Reference: https://github.com/edbeeching/godot_rl_agents/blob/main/godot_rl/wrappers/onnx/stable_baselines_export.py (not fetched in this phase; verified at S3 start).
- The dynamo exporter: PyTorch made it the default in 2.9, and it targets opset 18 with a different op mix, so `dynamo=False` is pinned explicitly.

**Rationale**: the smallest possible graph, only whitelisted ops, the exact head that argmax-per-branch needs, and a deterministic policy, as the proposal states.

### D9: Training environment: runtime arena replaces the 25 hand-placed rows

**Choice**: `train.tscn` shrinks to `Train (Node2D, script train_arena.gd)` with children `Sync`, `Camera2D` and `CanvasLayer/Label`.

- `TrainArena._ready()` reads `BVS_TRAIN_CONFIG` (path to a JSON file; environment variable, inherited by the Godot process) or uses built-in defaults: 8 rows, 6 `cpu_easy`, 2 `self`.
- It instantiates `game/game.tscn` per row with `training = true`, on a grid with pitch `(2000, 1600)`. The blast zone is 1320 × 1210, so no body, area or projectile of one row can reach another.
- `Sync` collects agents only after `root.ready` (`sync.gd:53-56`), so rows built in `_ready` are seen.

Row opponent kinds (from config):
- `self`: both fighters are TRAINING agents with the shared policy.
- `cpu_easy` / `cpu_normal` / `cpu_hard`: one TRAINING agent. The other fighter has `AIController2D.control_mode = HUMAN` (so `Sync` treats it as heuristic, `sync.gd:336`) and a `ScriptedController` with a per-row seed.
- `snapshot:<path>`: the opponent is a `PolicyController` running a frozen ONNX through the S2 interpreter.
- The agent's side (Fighter1 or Fighter2) alternates per row, so it learns both spawns.

Training-mode `Game` fixes:
- `get_ledges()` no longer returns `[]` in training (`game.gd:183-185`). It uses `ledge_depth` (258, which equals the table leg bottom 738 minus the top 480) once `TableStage` is freed.
- `_on_player_defeated` and `_on_timer_timeout` in training call `_end_training_episode(winner_or_null)`:
  1. Emit a new `training_episode_ended(winner)` signal (rewards).
  2. Call `game_over()` on both fighters (sets `done` and `needs_reset`, `player.gd:402-404`).
  3. Free the stage foods and projectiles.
  4. Restart the timer and the food spawner.
- `Fighter.reset_player()` also resets the state machine velocity and changes the state to `Fall`. Today a defeated fighter stays in `Defeated` after the training reset (`player.gd:389-400` does not touch the state machine).
- Remove `hurt.gd:32-33`; reward moves to the tracker.
- `reset_after = 999999` (`player.tscn:187`) already prevents truncation. Episodes are bounded by the 99 s match timer, and a timer end is sent as `done` (terminal; documented simplification).

**Alternatives considered**:
- Hand-fixing the 580-line `train.tscn`: the stale overrides (`available_actions = []` on Row/Game, `train.tscn:35-60`) and the 600 px row pitch, which lets a jump reach the floor of the row above, are exactly the kind of drift a hand-edited scene accumulates.
- Physics layers per row: Godot has only 32 layers, and spacing is simpler.

**Rationale**:
- The arena is data-driven: the curriculum changes rows through config, not scene edits.
- Rows do not overlap.
- Training matches play (ledges, real rules, `done` on match end).

### D10: Rewards (tunable data)

**Choice**:
- A `RewardTracker` (RefCounted) is owned by `PlayerAIController` when its mode is TRAINING. It connects to `damage_changed` and `stocks_changed` on its fighter and the enemy, and to `Game.training_episode_ended`.
- Only increases in damage and decreases in stocks count, so resets and respawns are ignored.
- Weights live in `RewardConfig` (Resource, `game/ai/training/reward_config.gd`, defaults below) and can be overridden from `BVS_TRAIN_CONFIG.reward`.

| Term | Default |
|------|---------|
| damage dealt / taken | +0.01 / -0.01 per % |
| KO given / stock lost | +1.0 / -1.0 |
| win / loss | +3.0 / -3.0 |
| timeout | +0.5 × sign(stock difference) |
| time penalty | -0.001 per decision |
| off-stage penalty | -0.002 per decision while off stage |
| approach shaping (potential-based) | 0.02 × (prev \|dx\| - \|dx\|) / HW per decision |

- At each episode end, the tracker prints one line `BVS_EPISODE {json}` with the episode's totals per term, the winner and the length. This is how the "KO, stock and win rewards observable in logs" criterion is checked.

**Alternatives considered**:
- Rewards only from hurt events (today): sparse, and nothing rewards winning.
- Distance shaping that is not potential-based: it encourages hugging the opponent and changes the optimal policy.

**Rationale**: dense enough to learn from CPU Easy, dominated by the KO and win terms, and every weight can be tuned without a code change.

### D11: Python pipeline: godot-rl launcher, curriculum, PPO

**Choice**:
- `training/` is a uv project (`requires-python = "==3.12.*"`). Exact pins are verified at S3 start and locked in `uv.lock`: `godot-rl`, `stable-baselines3` 2.x, `torch` 2.x, `onnx`, `onnxruntime`, `numpy`, and `onnxsim` only if folding needs it.
- The environment is `godot_rl.wrappers.stable_baselines_wrapper.StableBaselinesGodotEnv`, with `env_path = training/bin/bvs-godot`, a launcher script:
  `exec "$GODOT_BIN" --headless --path "$REPO" res://train.tscn "$@"`.
  godot_rl binds the port before launching, then passes `--port`, `--env_seed`, `--speedup` and `--action_repeat=4`, which `sync.gd:425-456` already parses. `n_parallel` runs 2–4 Godot processes to use the M5's cores.
- Curriculum phases come from `training/configs/default.toml`. Each phase writes a `BVS_TRAIN_CONFIG` JSON, closes the previous env, opens a new env, and calls `model.set_env()`:
  - **P1**: rows 100% `cpu_easy` (about 3M steps).
  - **P2**: 50% `cpu_easy` / 50% `cpu_normal` (about 3M steps).
  - **P3**: 30% `cpu_normal`, 20% `cpu_easy`, 20% `self`, 30% `snapshot` from the pool exported at P1/P2 checkpoints (about 4M steps).
  - Time box: about 8 h wall-clock in total. The run can be cut at any phase boundary and still produce a model.
- PPO settings: `MultiInputPolicy`, `net_arch=dict(pi=[64,64], vf=[64,64])`, Tanh, `n_steps=512`, `batch_size=2048`, `n_epochs=4`, `lr=3e-4`, `gamma=0.995`, `gae_lambda=0.95`, `ent_coef=0.01`, `clip_range=0.2`, fixed seed, `VecMonitor`, and a checkpoint every 250k steps.
- At startup, `train.py` asserts that the `env_info` observation shape is `(102,)` and `nvec == [3,3,2,5,2,2,2,2]` against `bvs_training/schema.py`.

**Alternatives considered**:
- Our own Python implementation of the `sync.gd` JSON/TCP protocol (handshake, env_info, reset/step/action/close): fewer dependencies, but it reimplements the VecEnv. This is the **fallback** if the pinned `godot-rl` cannot handshake with addon protocol 0.7 (`sync.gd:16-17`) on Godot 4.7.2.
- `env_path=None` with our own `subprocess` launch: it races the server bind, because `sync.gd:407-422` gives up when the connection is refused.
- RLlib: heavier, and nothing here needs multiple policies.

**Rationale**:
- Everything stays inside the documented godot_rl path.
- The environment variable carries curriculum data without touching godot_rl's argument plumbing.
- The phases can be restarted and time-boxed.

### D12: Evaluation and golden vectors use the shipped artifact

**Choice**:
- `tests/smoke/policy_eval.gd` is a SceneTree script that runs headless with `--fixed-fps 60`. It reads `BVS_EVAL_MODEL`, `BVS_EVAL_LEVEL`, `BVS_EVAL_MATCHES` (≥ 20), `BVS_EVAL_OUT` and `BVS_EVAL_OBS_DUMP`.
- It plays full matches of `game.tscn` (not training mode): the model through `PolicyController` against a seeded `ScriptedController`, alternating sides.
- It reuses `smoke_util.MatchLog` and writes a JSON report with:
  - wins, losses and win rate
  - self-KOs (stock lost with no hit in the last 3 s)
  - damage dealt
  - attack presses
  - approach ratio (frames within 150 px)
  - recoveries (returned to the stage after leaving it)
  - idle ratio (neutral intent frames)
- It also dumps a sample of real observations.
- `training/bvs_training/evaluate.py` launches the script and renders `training/reports/<model>-eval.md`.
- `golden.py` runs onnxruntime on 32 seeded random observations (inside the clip ranges) plus 32 recorded ones. It writes `tests/fixtures/onnx/bvs_default_golden.json` (model path, sha256, tolerance 1e-4, cases with obs, logits and argmax per branch).
- It also builds one synthetic model per whitelisted op, plus raw_data and float_data variants, with `onnx.helper`, into `tests/fixtures/onnx/ops/`, each with its own golden values.

**Alternatives considered**: evaluating in Python with onnxruntime through godot_rl: it would test a different runtime than the one players use.

**Rationale**: the success criteria (≥ 60% vs CPU Easy, non-trivial play, parity ≤ 1e-4, exact argmax) are measured on exactly what ships.

### D13: In-game integration and Hub distribution

**Choice**:
- **`PolicyController.new(model: OnnxPolicyModel = null)`**:
  - With a model, it runs inference itself.
  - With `null` while the fighter's AI controller is TRAINING, it reads `PlayerAIController.latest_action`.
  - With `null` otherwise, it returns neutral intents and reports `push_error` once.
  - `kind_name()` stays `"policy"`.
- **`ControllerConfig`**: `onnx_model_path` is replaced by a non-exported `model: OnnxPolicyModel` (held in memory, kept for rematches). `build()` no longer falls back to the CPU and no longer touches `AIController2D.control_mode`.
- **Bundled default**:
  - Files: `res://game/ai/models/bvs_default/model.onnx`, `bvs.json` and `README.md`.
  - `export_presets.cfg` gets `include_filter="game/ai/models/*"`, because non-resource files are not exported by default.
  - A new `ControllerOption` entry "AI: BVS default", after CPU Hard, maps to `ControllerConfig.policy_model(ModelManager.bundled_default())`. It loads once, synchronously, from `res://`, and works offline and on the web.
- **`ModelManager.request_model(slot, repo_id)`** runs a per-slot state machine:
  1. RESOLVING: `GET https://huggingface.co/api/models/<repo>` gives `sha` and `siblings`; both `model.onnx` and `bvs.json` must be listed.
  2. Cache hit at `user://models/<owner>__<name>/<sha>/`: go to LOADING.
  3. Otherwise DOWNLOADING: `GET /<repo>/resolve/<sha>/bvs.json`, validate the sidecar, then `model.onnx` (size cap).
  4. VALIDATING: parse, compile, then check against the schema and the sidecar.
  5. Write each file as `.part`, then rename.
  6. Record `index.cfg` (repo → last sha).
  7. READY or FAILED(reason).
- Offline at RESOLVING with a cached sha: load it (READY with an "offline, cached" note).
- Signals: `model_state_changed(slot, state, detail)`, `model_ready(slot, model)` and `model_failed(slot, reason, message)`. `cancel(slot)` frees the HTTPRequest.
- The existing injectable `hub_transport` covers these calls in tests.
- On startup, legacy `user://Agent*.onnx` files are deleted (best effort).
- **Character select**:
  - Choosing a model in the picker starts `request_model` at once (prefetch).
  - The player's panel shows "Resolving… / Downloading N KB… / Checking model…" with Cancel.
  - Play is disabled while any selected model is not READY.
  - FAILED shows the reason, for example "This model expects 13 inputs; this game provides 102", "Missing bvs.json", or "Unsupported ONNX operation LSTM", with Back. There is no silent CPU swap.
- **Picker**: unchanged UI. A `bvs-schema-2` tag is "Compatible" and `bvs-schema-1` is "Trained for an older version", through `HubModel.BVS_SCHEMA_VERSION = 2`.

**Alternatives considered**:
- Downloading on Play (today, `ai_controller.gd:112-118`): this is the race that caused the silent CPU fallback.
- A cache keyed by player slot (today): picking a new model reuses the stale file.
- `resolve/main` without a sha: a moving target, and it cannot be cached safely.

**Rationale**: these choices satisfy the proposal's no-silent-fallback, per-revision cache and offline default requirements. Validation happens before the match exists, so a bad model can never reach a fighter.

### D14: Upload gate (no remote action by tooling)

**Choice**:
- `training/bvs_training/prepare_upload.py --repo <id> --license <spdx>` stages `training/out/upload/<name>/` with `model.onnx`, `bvs.json`, and `README.md` rendered from `training/templates/model_card.md`.
- The card's YAML front matter carries `license`, `tags: [BVS, bvs-schema-2, reinforcement-learning, onnx]`, `library_name: stable-baselines3`, and the eval results.
- The script verifies the sha256 of the staged files against the bundled copies.
- It **prints** the commands and exits without running them:
  - `hf repo create <id> --repo-type model --exist-ok` (if supported by the installed CLI)
  - `hf upload <id> training/out/upload/<name> . --repo-type model --commit-message "..."`
- It never reads HF auth state. After the user confirms the destination, operation and credential (proposal gate), the orchestrator runs the printed commands. Verification is read-only: `GET /api/models?author=<owner>&filter=BVS` and the in-game picker.

**Alternatives considered**: `huggingface_hub.upload_folder` inside the script: it would mean remote execution from tooling, and it breaks the gate.

**Rationale**: the gate becomes structural, because no code path can upload. The exact CLI syntax is checked locally with `hf upload --help` at gate time (local and read-only).

## Data Flow

Training (one Godot process, N rows; one decision every 4 physics frames):

```
SB3 PPO ──TCP JSON──> Sync._physics_process (first child of Train)
   ▲                     │ set_action(dict) per TRAINING agent
   │                     ▼
   │            PlayerAIController.latest_action / action_seq
   │                     │
   │   Fighter._physics_process → PolicyController.sample()
   │       (null model) → BvsActionDecoderV2.begin_window/frame → FighterIntent
   │                     │
   │   game state ── Game.get_state_snapshot() ── BvsSchemaV2.build_obs(snap, idx)
   │                     │                                  │
   │   RewardTracker ◄── damage/stock signals, training_episode_ended
   └──── obs, reward, done ◄──────────────────────────────────┘
```

Play (no Sync):

```
CharacterSelect ─pick─> ModelManager.request_model(slot, repo)
    RESOLVING (/api/models/<repo> → sha) → cache? → DOWNLOADING (resolve/<sha>/bvs.json, model.onnx)
    → VALIDATING (OnnxModelParser → OnnxGraph.compile([1,102]) + sidecar vs BvsSchemaV2) → READY(model)
ControllerConfig.policy_model(model) ─SceneManager─> Fighter.set_controller(PolicyController(model))
every 4th sampled frame: snapshot → build_obs → OnnxGraph.run → 21 logits → argmax per branch
    → decoder.begin_window ; every frame: decoder.frame → FighterIntent
```

Artifacts:

```
train.py ─checkpoints─> export.py (logits head, opset 17) ─> model.onnx
   golden.py (onnxruntime) ─> tests/fixtures/onnx/*.json ◄── onnx_golden.gd (GDScript parity)
   evaluate.py ─> Godot policy_eval.gd (shipped interpreter) ─> report.json/.md
   sidecar.py ─> bvs.json ; copy → res://game/ai/models/bvs_default/
   prepare_upload.py ─> staged dir + printed `hf` commands ── STOP (authorization gate)
```

## File Changes

Authored-line estimates exclude generated fixtures, `uv.lock` and binaries.

### S1: schema v2 and training environment (~450)

| File | Action | Description |
|------|--------|-------------|
| `game/ai/schema/bvs_schema.gd` | Create | Registry, `CURRENT_VERSION`, `get_schema(v)`, `validate_sidecar(d)` |
| `game/ai/schema/bvs_schema_v2.gd` | Create | Constants, `FIELD_NAMES`, `build_obs(snap, my_index)`, `action_space()`, `argmax_branches(logits)`, `sidecar_template()` |
| `game/ai/schema/bvs_action_decoder_v2.gd` | Create | Stateful decoder (D3) |
| `game/ai/training/reward_config.gd` | Create | RewardConfig resource and `from_dict` |
| `game/ai/training/reward_tracker.gd` | Create | Signal-driven reward terms and the `BVS_EPISODE` log |
| `game/ai/training/train_arena.gd` | Create | Builds rows from `BVS_TRAIN_CONFIG` or defaults, opponent kinds, side alternation |
| `train.tscn` | Modify (rewrite) | Train root with TrainArena, Sync, Camera2D and Label; the 25 hand rows and stale overrides are removed |
| `scripts/AIController/player_ai_controller.gd` | Modify | Delegates to the schema; `latest_action` and `action_seq`; RewardTracker; `get_reward` |
| `game/player/controllers/policy_controller.gd` | Modify | Decoder-based; training source (model path in S4) |
| `game/game.gd` | Modify | `training_episode_ended` signal, `_end_training_episode`, ledges in training |
| `game/player/player.gd` | Modify | `reset_player` resets the FSM to Fall and the state machine velocity |
| `game/player/StateMachine/PlayerStateMachine/States/hurt.gd` | Modify | Remove the reward lines |
| `scripts/hub_model.gd` | Modify | `BVS_SCHEMA_VERSION = BvsSchema.CURRENT_VERSION` |
| `openspec/specs/...` | — | (deltas come from sdd-spec) |
| `tests/fixtures/schema/v2_layout.json` | Create | Frozen field-name list (generated once from `FIELD_NAMES`, then committed) |
| `tests/smoke/schema_v2.gd` | Create | Obs length, indices, clipping, me-first for P2, food ordering, decoder edges, layout freeze |
| `tests/smoke/train_loads.gd` | Modify | Arena rows, spacing ≥ blast size, opponent kinds, ledges present, `done` on defeat |
| `tests/smoke/hf_picker.gd` | Modify | Schema-2 compat fixtures |

### S2: interpreter (~600)

| File | Action | Description |
|------|--------|-------------|
| `game/ai/onnx/protobuf_reader.gd` | Create | `PbReader` with bounds and limits |
| `game/ai/onnx/onnx_tensor.gd` | Create | Shape and float32 data |
| `game/ai/onnx/onnx_model_parser.gd` | Create | ModelProto/GraphProto/NodeProto/TensorProto/ValueInfo subset |
| `game/ai/onnx/onnx_graph.gd` | Create | Topological sort, shape inference, compile, run, 15 ops |
| `game/ai/onnx/onnx_policy_model.gd` | Create | Graph, sidecar and meta; `load_bytes`, `validate(schema)`, `infer(obs)` |
| `tests/smoke/onnx_golden.gd` | Create | Op fixtures, default-model parity (≤ 1e-4, exact argmax), rejection cases (bad op, dim mismatch, external data, truncated bytes), perf print |
| `tests/fixtures/onnx/ops/*` | Create (generated) | Per-op tiny models and goldens (from `golden.py`) |

S2's fixtures are produced by S3's `golden.py`. Task order: write the S3 `golden.py` op-fixture part first, or build those fixtures with a minimal one-off `onnx.helper` script that is committed in S3.

### S3: training recipe (~500)

| File | Action | Description |
|------|--------|-------------|
| `training/pyproject.toml`, `training/.python-version`, `training/uv.lock` | Create | uv project, Python 3.12, pins |
| `training/bin/bvs-godot` | Create | Launcher (`GODOT_BIN`, `--headless --path`, passes args through) |
| `training/configs/default.toml` | Create | Phases, rows, PPO, reward overrides, time box |
| `training/bvs_training/schema.py` | Create | `SCHEMA_VERSION`, `OBS_DIM`, `ACTION_NVEC`, branch names, `ACTION_REPEAT` |
| `training/bvs_training/onnx_ops.py` | Create | Whitelist (mirror of D6) and op audit |
| `training/bvs_training/train.py` | Create | Phased PPO, checkpoints, snapshot pool export |
| `training/bvs_training/export.py` | Create | Logits-head export, checker, audit, ORT-vs-torch check |
| `training/bvs_training/golden.py` | Create | Default-model and per-op goldens |
| `training/bvs_training/evaluate.py` | Create | Runs `policy_eval.gd`, renders the report |
| `training/bvs_training/sidecar.py` | Create | `bvs.json` (with `trained_on_commit` from `git rev-parse HEAD`) and model card |
| `training/bvs_training/prepare_upload.py` | Create | Staging and printed commands only |
| `training/templates/model_card.md` | Create | Card template with front matter |
| `training/README.md` | Create | Trainer docs: MLP only, schema contract, tags, sidecar, reproduction |
| `tests/smoke/policy_eval.gd` | Create | Godot evaluation script (D12) |
| `.gitignore` | Modify | `training/out/`, `training/.venv/` |

### S4: in-game integration (~450)

| File | Action | Description |
|------|--------|-------------|
| `game/player/controllers/policy_controller.gd` | Modify | Inference path, staggered ticks, error once on a missing model |
| `game/player/controllers/controller_config.gd` | Modify | `model` handle, `policy_model()`; no CPU fallback; no control_mode writes |
| `scripts/model_manager.gd` | Modify | Repo+sha cache, state machine, sidecar and graph validation, bundled default, legacy cleanup |
| `scripts/hub_model.gd` | Modify | `info_url(id)`, `file_url(id, sha, file)` |
| `ui/character_select/ai_controller.gd` | Modify | Prefetch on pick, status, cancel, Play gating, "AI: BVS default" option |
| `ui/character_select/character_select.gd` / `.tscn` | Modify | Play disabled while pending; status label per player |
| `export_presets.cfg` | Modify | `include_filter="game/ai/models/*"` |
| `tests/smoke/cpu_select.gd` | Modify | Replace path-fallback checks with model-handle and no-fallback checks |
| `tests/smoke/hf_picker.gd` | Modify | Fake transport for info and resolve; cache hit; failure reasons |
| `tests/smoke/policy_match.gd` | Create | Bundled default plays one match without Sync, attacks occur, no script errors |

### S5: trained default model (~100 plus binaries)

| File | Action | Description |
|------|--------|-------------|
| `game/ai/models/bvs_default/model.onnx` | Create (binary) | Default model (KB range) |
| `game/ai/models/bvs_default/bvs.json`, `README.md` | Create | Sidecar and card |
| `tests/fixtures/onnx/bvs_default_golden.json` | Create (generated) | Parity cases |
| `training/reports/bvs_default-eval.md` (+ `.json`) | Create | Evaluation report |

### S6: upload

No code; it runs S3's `prepare_upload.py` and stops at the gate.

## Interfaces / Contracts

```gdscript
# game/ai/schema/bvs_schema.gd
class_name BvsSchema
const CURRENT_VERSION := 2
static func get_schema(version: int) -> Object        # BvsSchemaV2 script or null
static func validate_sidecar(sidecar: Dictionary) -> String   # "" ok, else human reason

# game/ai/schema/bvs_schema_v2.gd
class_name BvsSchemaV2 extends RefCounted
const VERSION := 2
const OBS_DIM := 102
const ACTION_REPEAT := 4
const BRANCHES: Array[Dictionary] = [
    {"name": "a0_move", "size": 3}, {"name": "a1_vertical", "size": 3},
    {"name": "a2_jump", "size": 2}, {"name": "a3_attack", "size": 5},
    {"name": "a4_special", "size": 2}, {"name": "a5_throw", "size": 2},
    {"name": "a6_block", "size": 2}, {"name": "a7_dash", "size": 2}]
const LOGITS := 21
const FIELD_NAMES: PackedStringArray = [...]          # 102 names, frozen
static func build_obs(game_snapshot: Dictionary, my_index: int) -> PackedFloat32Array
static func action_space() -> Dictionary              # godot_rl format, all "discrete"
static func action_from_dict(action: Dictionary) -> PackedInt32Array
static func argmax_branches(logits: PackedFloat32Array) -> PackedInt32Array  # ties → lowest index
static func sidecar_template() -> Dictionary

# game/ai/schema/bvs_action_decoder_v2.gd
class_name BvsActionDecoderV2 extends RefCounted
func begin_window(indices: PackedInt32Array) -> void
func frame(fighter: Fighter) -> FighterIntent

# game/ai/onnx/onnx_policy_model.gd
class_name OnnxPolicyModel extends RefCounted
var repo_id: String; var revision: String; var sidecar: Dictionary; var label: String
static func load_bytes(onnx: PackedByteArray, sidecar: Dictionary) -> Dictionary  # {model, error}
static func load_res(dir: String) -> Dictionary                                  # bundled
func infer(obs: PackedFloat32Array) -> PackedFloat32Array                        # 21 logits

# scripts/model_manager.gd (autoload)
enum ModelState { IDLE, RESOLVING, DOWNLOADING, VALIDATING, READY, FAILED }
enum ModelFailure { OFFLINE, SERVER, NOT_FOUND, MISSING_FILES, BAD_SIDECAR, SCHEMA_MISMATCH, BAD_ONNX, UNSUPPORTED_OP, TOO_LARGE, CANCELLED }
signal model_state_changed(slot: int, state: ModelState, detail: String)
signal model_ready(slot: int, model: OnnxPolicyModel)
signal model_failed(slot: int, reason: ModelFailure, message: String)
func request_model(slot: int, repo_id: String) -> void
func cancel(slot: int) -> void
func bundled_default() -> OnnxPolicyModel
```

`bvs.json` (sidecar, `format: "bvs-model/1"`):

```json
{
  "format": "bvs-model/1",
  "schema_version": 2,
  "obs_dim": 102,
  "action_branches": [{"name": "a0_move", "size": 3}, {"name": "a1_vertical", "size": 3},
    {"name": "a2_jump", "size": 2}, {"name": "a3_attack", "size": 5}, {"name": "a4_special", "size": 2},
    {"name": "a5_throw", "size": 2}, {"name": "a6_block", "size": 2}, {"name": "a7_dash", "size": 2}],
  "action_repeat": 4,
  "onnx": {"file": "model.onnx", "input": "obs", "output": "logits", "opset": 17},
  "trained_on_commit": "<git sha>",
  "label": "BVS default",
  "difficulty_hint": "easy",
  "eval": {"vs_cpu_easy": {"matches": 20, "win_rate": 0.0}}
}
```

Validation requires `schema_version`, `obs_dim`, `action_branches` (names and sizes, in order) and `action_repeat` to equal the schema. The ONNX input must be `[1|dyn, 102]` and the output's last dim must be 21. The other keys are informational.

`BVS_TRAIN_CONFIG` (JSON, read by TrainArena):

```json
{"rows": [{"opponent": "cpu_easy", "seed": 11}, {"opponent": "self"}, {"opponent": "snapshot", "model": "/abs/path/step_1000000.onnx"}],
 "reward": {"win": 3.0}, "episode_log": true}
```

## Testing Strategy

The user authorized running Godot, tests and training locally for this change (proposal Dependencies). That overrides the default no-local-tests rule for this change only. `strict_tdd: false` and there is no runner beyond the smoke scripts (`tests/smoke/run_all.sh` pattern).

| Layer | What to test | Approach |
|-------|-------------|----------|
| Unit (GDScript smoke) | Schema obs layout, clipping, P2 perspective, food/projectile slots, layout freeze, decoder edge semantics, jump guard, special overrides attack | `tests/smoke/schema_v2.gd` over synthetic snapshot dicts plus a real `game.tscn` |
| Unit (GDScript smoke) | Protobuf bounds, each whitelisted op, raw/float data, rejections (unknown op, external data, dim mismatch, truncation, size limits) | `tests/smoke/onnx_golden.gd` against `tests/fixtures/onnx/ops/*` |
| Parity | GDScript interpreter vs onnxruntime on the default model | `onnx_golden.gd`: max abs diff ≤ 1e-4, argmax equal on every case, sha256 of the bundled model matches the fixture |
| Integration | Arena build, rows apart, opponent kinds, ledges in training, `done` on defeat and timeout, reward log line | `tests/smoke/train_loads.gd` (Sync removed, as today) |
| Integration | Model manager: info, resolve, cache by sha, offline cached, failure reasons, cancel; no silent CPU | `tests/smoke/hf_picker.gd` and `cpu_select.gd` with the injected `hub_transport` |
| Python | Export op audit, ORT vs torch ≤ 1e-5, schema constants vs `env_info` | Assertions inside `export.py` and `train.py` (fail fast); no separate pytest suite needed |
| E2E | The default model plays a full match without Sync; eval ≥ 60% over ≥ 20 matches vs CPU Easy; self-KO and idle ratios | `tests/smoke/policy_match.gd`; `policy_eval.gd` via `evaluate.py` (report committed) |
| Manual | Web build: HF pick → download → play; bundled default offline; perf ≤ 3 ms per inference | Exported web build in the browser (CI deploys only) |

## Threat Matrix

The change adds a subprocess launch (godot-rl runs `training/bin/bvs-godot` with argument lists, no shell interpolation of user input) and a local TCP socket, but no routing, VCS or PR automation.

| Boundary | Applicability | Design response | Planned RED tests |
|---|---|---|---|
| Documentation-like paths | N/A: no file is classified or executed by name. The model card `README.md` and `bvs.json` are data. `.onnx` bytes are parsed, never executed | — | — |
| Git repository selection | N/A: tooling only reads `git rev-parse HEAD` for `trained_on_commit`, with no repository selection or mutation | — | — |
| Commit state | N/A: no commit automation | — | — |
| Push state | N/A: no push automation. The HF upload is printed, not run (D14) | — | — |
| PR commands | N/A: no PR automation | — | — |

Untrusted model input is outside the matrix but is a design requirement. Hub bytes go through D5's bounds and limits, with rejection tests in `onnx_golden.gd`. Sidecar JSON is validated by key and type before use.

## Migration / Rollout

- The schema bump makes schema-1 Hub models "Trained for an older version" (picker). Expected and in scope.
- Legacy `user://Agent*.onnx` files are deleted on the first ModelManager start (best effort, and useful on the web's IndexedDB).
- `ControllerConfig.onnx_model_path` is removed. No saved resources reference it (built at runtime by character select).
- One PR with `size:exception` and one logical commit per slice (S1–S5). S4 can be reverted alone. Rollback as in the proposal.
- The Godot project is 4.7 (`project.godot:20`, CI 4.7.2), while `openspec/config.yaml` still says 4.6. Updating that context line is a doc fix that can ride with S1.

## Open Questions

- [ ] Exact `godot-rl` version and its Python 3.12 / Godot 4.7.2 / addon protocol 0.7 compatibility. Verify at S3 start with `uv sync` and a handshake against `train.tscn`. If it fails, use the D11 fallback (our own protocol client). Not blocking design.
- [ ] Whether godot_rl's SB3 wrapper maps an all-discrete action dict to `MultiDiscrete` in insertion order. The ordering prefixes make either order safe, and `train.py` asserts the `nvec`. Verify at S3 start.
- [ ] `hf` CLI subcommand forms (`hf repo create --exist-ok`, `hf upload` auto-create). Check locally with `--help` at the gate.
- [ ] HF repo id and license for the default model (proposal Open Question 2). Needed only at the S6 gate.
- [ ] CORS and redirect behavior of `huggingface.co/<repo>/resolve/<sha>/…` from the GitHub Pages origin in the web build. Verify manually in S4. If it is blocked, the bundled default still works offline.
