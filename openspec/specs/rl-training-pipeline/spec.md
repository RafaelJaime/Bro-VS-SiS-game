# RL Training Pipeline Specification

## Purpose

The training environment, the Python recipe (train, export, golden, evaluate), the default-model artifacts, and the gated upload procedure. All reward weights, curriculum stages, and time boxes are tunable data. Verification: Godot smoke tests (`train_loads.gd` and related), Python checks, and the committed evaluation report.

## Requirements

### Requirement: Episode done on match resolution

In training mode, the episode MUST end on every match resolution (elimination, timer expiry with a winner, sudden-death KO). The Game MUST call `Fighter.game_over()` on both fighters so a `done` signal is sent, and only then reset the row. The training path MUST NOT reset players silently without `done`. An episode step cap MUST exist so a stalled match still terminates (as truncation).

#### Scenario: Elimination ends episode
- GIVEN a training row where one fighter loses its last stock
- WHEN the defeat is processed
- THEN `game_over()` is called on both fighters, `done` is sent, and then the row resets

#### Scenario: Timeout ends episode
- GIVEN a training row whose timer expires
- WHEN the timeout is resolved (winner or sudden-death KO)
- THEN `done` is sent exactly once for that episode

#### Scenario: Stalled match
- GIVEN two fighters that never engage until the step cap
- WHEN the cap is reached
- THEN the episode ends as truncated and the row resets

#### Scenario: Normal play unaffected
- GIVEN a non-training match
- WHEN a match resolves
- THEN the existing game-over screen flow runs unchanged

### Requirement: Reward components

Per step, the training reward MUST be the sum of tunable components: damage dealt (+), damage taken (-), KO given (+), KO taken (-), stock lost (-), win (+), loss (-), and small shaping terms (for example approaching the opponent, edge/recovery penalties). Each component MUST be logged separately and MUST be changeable through data without code edits. Rewards MUST be derived from the damage, stock and match signals, not from observation reads.

#### Scenario: Damage reward
- GIVEN fighter A hits fighter B for 12%
- WHEN the step is processed
- THEN A's reward includes the damage-dealt term for 12% and B's includes the damage-taken term

#### Scenario: KO and stock terms
- GIVEN B loses a stock
- WHEN the step is processed
- THEN A receives the KO-given term and B receives the KO-taken and stock-lost terms

#### Scenario: Win term
- GIVEN the match ends with A as winner
- WHEN the terminal step is processed
- THEN A receives the win term and B the loss term

#### Scenario: Observable in logs
- GIVEN a training run
- WHEN its log is inspected
- THEN KO, stock and win components appear as separate entries

#### Scenario: Weights are data
- GIVEN a reward weight changed in the data file
- WHEN training restarts
- THEN the new weight applies with no GDScript edit

### Requirement: Training scene layout

`train.tscn` MUST place every Game row at a consistent spacing with no overlap in global space, and MUST carry no stale per-fighter StateMachine overrides. Row count MUST be configurable and every row MUST load without script errors.

#### Scenario: Uniform spacing
- GIVEN `train.tscn`
- WHEN the global offsets of all Game rows are read
- THEN consecutive offsets differ by one constant spacing

#### Scenario: Loads clean
- GIVEN the smoke harness
- WHEN `train.tscn` is loaded headless for a bounded number of frames
- THEN no script errors occur and every row reaches a running match

#### Scenario: No stale overrides
- GIVEN `train.tscn`
- WHEN fighter nodes are inspected
- THEN none carry StateMachine overrides that differ from the base fighter scene

### Requirement: Opponent mode per row

Each training row MUST select its opponent: TRAINING (self-play, policy shared across agents) or a scripted CPU at a given difficulty (Easy, Normal, Hard). Selection MUST be configurable per row and MUST support the curriculum Easy, then Normal, then mixed self-play.

#### Scenario: Scripted opponent row
- GIVEN a row configured with CPU Normal
- WHEN the row runs
- THEN the second fighter is driven by the scripted controller at Normal and only one agent in the row is externally controlled

#### Scenario: Self-play row
- GIVEN a row configured with TRAINING
- WHEN the row runs
- THEN both fighters are policy-controlled

#### Scenario: Invalid mode
- GIVEN a row with an unknown opponent mode
- WHEN the scene loads
- THEN an error naming the row is reported and the scripted CPU Easy is NOT silently used

### Requirement: Python training project

The repo MUST contain a uv-managed Python 3.12 project under `training/` with pinned versions of `godot-rl`, `stable-baselines3`, `torch`, `onnx`, and `onnxruntime`, and scripts to train (PPO, Godot headless on `train.tscn`, curriculum), export, generate golden fixtures, evaluate, and upload. A documented one-command setup MUST work from a clean checkout. Documentation MUST state the MLP-only constraint, the schema contract, and the tags.

#### Scenario: Reproducible environment
- GIVEN a clean checkout
- WHEN the documented uv setup runs
- THEN the environment resolves to the pinned versions

#### Scenario: Handshake with Godot
- GIVEN Godot headless running `train.tscn`
- WHEN the trainer connects
- THEN the handshake succeeds and observations of length `obs_dim` are received

#### Scenario: Documented constraints
- GIVEN the trainer docs
- WHEN reviewed
- THEN they state MLP-only, the schema 2 contract, and the `BVS` / `bvs-schema-2` tags

### Requirement: Export contract

The export script MUST emit an MLP ONNX at opset 17 with constants folded, using only whitelisted ops, an input dimension equal to `obs_dim`, and a deterministic output head from which the seven schema-2 branch indices are derived. It MUST verify the exported graph against the whitelist before writing, and MUST fail rather than emit a graph with an unsupported op.

#### Scenario: Clean export
- GIVEN a trained checkpoint
- WHEN exported
- THEN the file's ops are a subset of the whitelist and its input dimension equals `obs_dim`

#### Scenario: Unsupported op fails export
- GIVEN a model whose export would include `Gather`
- WHEN export runs
- THEN it fails with an error naming the op and writes no model file

#### Scenario: Sidecar emitted
- GIVEN a successful export
- WHEN the output directory is listed
- THEN `bvs.json` exists with `schema_version` 2, `obs_dim`, the action layout, `action_repeat`, and `trained_on_commit`

### Requirement: Evaluation

An evaluation script MUST run the model versus CPU Easy and CPU Normal for at least N = 20 headless matches each and write a report with win rate, mean stocks taken, and behavior indicators (approach, attacks thrown, recoveries, self-KO share of stocks lost, idle share). The report MUST be committed with the model.

#### Scenario: Report produced
- GIVEN the default model
- WHEN the evaluation runs
- THEN a report lists matches played, win rate versus Easy and Normal, and the behavior indicators

#### Scenario: Default model success criterion
- GIVEN the committed report
- WHEN win rate versus CPU Easy is read
- THEN it is at least 60% over at least 20 matches

#### Scenario: Non-trivial play
- GIVEN the committed report
- WHEN behavior indicators are read
- THEN the model approaches and attacks, and self-KO is not the majority of its stocks lost

#### Scenario: Criterion not met
- GIVEN a candidate model below 60% versus CPU Easy
- WHEN promotion to default is considered
- THEN it is NOT committed as the default and the failure is reported

### Requirement: Default model artifacts

After parity (the `onnx-mlp-inference` golden checks) and evaluation pass, the project MUST commit the default model ONNX, its `bvs.json`, the golden fixtures, and the evaluation report. The bundled model MUST live under `res://` so it can be selected offline (see `hub-model-distribution`).

#### Scenario: Artifacts present
- GIVEN the change applied
- WHEN the repo is listed
- THEN the model, `bvs.json`, fixtures, and report exist at their documented paths

#### Scenario: Gate order
- GIVEN a model that fails golden parity
- WHEN commit of artifacts is attempted
- THEN the procedure stops before committing and reports the parity failure

### Requirement: Remote upload authorization gate

Publishing to Hugging Face is a remote operation. The upload MUST NOT run, and the agent MUST NOT probe ambient HF authentication state (for example `hf auth whoami`) before the user explicitly confirms, in the same session, all of: the destination repo id, the operation (create-if-missing, files to upload, tags, visibility), and the credential to use. Before asking, the agent MUST present the repo id, files and tags, credential, and the evaluation results, and then STOP. A missing or ambiguous part of the confirmation MUST keep the work local. After upload, a read-only listing check MUST confirm the model appears under `filter=BVS` with the `bvs-schema-2` tag. The upload script MUST refuse to run without an explicit confirmation argument carrying the repo id.

#### Scenario: No upload without confirmation
- GIVEN artifacts are committed and the user has not confirmed
- WHEN the pipeline reaches the upload step
- THEN no network write or auth probe occurs and a confirmation request listing repo id, files/tags and credential is presented

#### Scenario: Partial confirmation
- GIVEN the user confirmed the repo id but not the credential
- WHEN the upload would run
- THEN it does not run and the agent asks for the missing part

#### Scenario: Script refuses without confirmation
- GIVEN the upload script invoked with no confirmation argument
- WHEN it starts
- THEN it exits non-zero with a message stating that explicit confirmation is required, before any network call

#### Scenario: Confirmed upload
- GIVEN the user confirmed destination, operation and credential
- WHEN the upload runs
- THEN exactly the confirmed files and tags are uploaded to the confirmed repo id

#### Scenario: Post-upload verification
- GIVEN a completed upload
- WHEN the read-only Hub listing is queried with `filter=BVS`
- THEN the repo appears with the `bvs-schema-2` tag, and the in-game picker marks it Compatible

#### Scenario: Model card content
- GIVEN the generated model card
- WHEN reviewed
- THEN it states the MLP-only schema 2 contract, the tags, the evaluation results, and the license confirmed by the user
