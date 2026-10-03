# RL Training Pipeline Specification

## Purpose

The training environment, the Python recipe (train, export, golden, evaluate), the default-model artifacts, and the gated upload procedure. All reward weights, curriculum stages, and time boxes are tunable data. Verification: Godot smoke tests (`train_loads.gd` and related), Python checks, and the committed evaluation report.

## Requirements

### Requirement: Episode done on match resolution

In training mode, the episode MUST end on every match resolution (elimination, timer expiry with a winner, sudden-death KO). A timer expiry with tied results MUST enter sudden death (see `match-flow`) instead of ending as a draw. The Game MUST call `Fighter.game_over()` on both fighters so a `done` signal is sent, and only then reset the row. The training path MUST NOT reset players silently without `done`. An episode step cap and a sudden-death safety cap (default about 60 s after sudden death starts) MUST exist so a stalled match still terminates (as truncation, a draw for reward purposes).
(Previously: timer expiry ended with a winner or a sudden-death KO but sudden death had no escalation and training had only a step cap.)

#### Scenario: Elimination ends episode
- GIVEN a training row where one fighter loses its last stock
- WHEN the defeat is processed
- THEN `game_over()` is called on both fighters, `done` is sent, and then the row resets

#### Scenario: Timeout tie enters sudden death
- GIVEN a training row whose timer expires with equal stocks
- WHEN the timeout is resolved
- THEN the row enters sudden death with bombs after the grace period and no `done` is sent at expiry

#### Scenario: Timeout ends episode
- GIVEN a training row whose timer expires with a winner, or whose sudden death ends in a KO
- WHEN the result is resolved
- THEN `done` is sent exactly once for that episode

#### Scenario: Stalled match
- GIVEN two fighters that never engage until the step cap
- WHEN the cap is reached
- THEN the episode ends as truncated and the row resets

#### Scenario: Sudden-death safety cap
- GIVEN a training row in sudden death that reaches the safety cap with no KO
- WHEN the cap is processed
- THEN the episode ends as a draw for reward purposes, flagged truncated, and the row resets

#### Scenario: Normal play unaffected
- GIVEN a non-training match
- WHEN a match resolves
- THEN the existing game-over screen flow runs unchanged and the training safety cap does not apply

### Requirement: Reward components

Per step, the training reward MUST be the sum of tunable components: damage dealt (+), damage taken (-), KO given (+), KO taken (-), stock lost (-), win (+), loss (-), small shaping terms (for example approaching the opponent, edge/recovery penalties), and the combat-depth terms: food pickup (+), food hit landed (+), shield break dealt (+), shield break taken (-), and a small penalty for holding the shield too long (-). Each component MUST be logged separately and MUST be changeable through data without code edits. Rewards MUST be derived from the damage, stock, match, pickup, food-hit and shield-break signals, not from observation reads.
(Previously: no food or shield terms.)

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

#### Scenario: Pickup term
- GIVEN fighter A picks up food
- WHEN the step is processed
- THEN A's reward includes the pickup term once

#### Scenario: Food hit term
- GIVEN fighter A's thrown food hits fighter B
- WHEN the step is processed
- THEN A's reward includes the food-hit-landed term

#### Scenario: Shield break terms
- GIVEN fighter A breaks fighter B's shield
- WHEN the step is processed
- THEN A receives the shield-break-dealt term and B the shield-break-taken term

#### Scenario: Long shield hold penalty
- GIVEN a fighter holds the shield beyond the tunable threshold
- WHEN steps are processed
- THEN a small negative term accrues each step beyond the threshold and none below it

#### Scenario: Observable in logs
- GIVEN a training run
- WHEN its log is inspected
- THEN KO, stock, win, pickup, food-hit and shield-break components appear as separate entries

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

The repo MUST contain a uv-managed Python 3.12 project under `training/` with pinned versions of `godot-rl`, `stable-baselines3`, `torch`, `onnx`, and `onnxruntime`, and scripts to train (PPO, Godot headless on `train.tscn`, curriculum including sudden-death episodes), export, generate golden fixtures, evaluate, and upload. A documented one-command setup MUST work from a clean checkout. Documentation MUST state the MLP-only constraint, the schema contract (schema 3), and the tags (`BVS` / `bvs-schema-3`).
(Previously: curriculum without sudden-death episodes; documentation stated schema 2 and `bvs-schema-2`.)

#### Scenario: Reproducible environment
- GIVEN a clean checkout
- WHEN the documented uv setup runs
- THEN the environment resolves to the pinned versions

#### Scenario: Handshake with Godot
- GIVEN Godot headless running `train.tscn`
- WHEN the trainer connects
- THEN the handshake succeeds and observations of length v3 `obs_dim` are received

#### Scenario: Train loads with sudden death
- GIVEN `train.tscn` with sudden death enabled
- WHEN loaded headless for a bounded number of frames
- THEN no script errors occur

#### Scenario: Documented constraints
- GIVEN the trainer docs
- WHEN reviewed
- THEN they state MLP-only, the schema 3 contract, and the `BVS` / `bvs-schema-3` tags

### Requirement: Export contract

The export script MUST emit an MLP ONNX at opset 17 with constants folded, using only whitelisted ops, an input dimension equal to the schema `obs_dim`, and a deterministic output head from which the eight branch indices of the current schema are derived. It MUST verify the exported graph against the whitelist before writing, and MUST fail rather than emit a graph with an unsupported op. The sidecar MUST carry the current schema version.
(Previously: the head derived the seven schema-2 branch indices and the sidecar carried `schema_version` 2.)

#### Scenario: Clean export
- GIVEN a trained checkpoint
- WHEN exported
- THEN the file's ops are a subset of the whitelist and its input dimension equals the v3 `obs_dim`

#### Scenario: Unsupported op fails export
- GIVEN a model whose export would include `Gather`
- WHEN export runs
- THEN it fails with an error naming the op and writes no model file

#### Scenario: Sidecar emitted
- GIVEN a successful export
- WHEN the output directory is listed
- THEN `bvs.json` exists with `schema_version` 3, `obs_dim`, the action layout, `action_repeat`, and `trained_on_commit`

### Requirement: Evaluation

An evaluation script MUST run the model versus CPU Easy and CPU Normal for at least N = 20 headless matches each and write a report with win rate, mean stocks taken, behavior indicators (approach, attacks thrown, recoveries, self-KO share of stocks lost, idle share) and the combat-depth metrics: sudden-death length, food pickups per minute, throws per minute, blocked-hit share, damage by source, and shield breaks. The report MUST be committed with the model.
(Previously: no combat-depth metrics.)

#### Scenario: Report produced
- GIVEN the default model
- WHEN the evaluation runs
- THEN a report lists matches played, win rate versus Easy and Normal, the behavior indicators and the combat-depth metrics

#### Scenario: Default model success criterion
- GIVEN the committed report
- WHEN win rate by KO versus CPU Easy is read
- THEN it is at least 60% over at least 20 matches

#### Scenario: Non-trivial play
- GIVEN the committed report
- WHEN behavior indicators are read
- THEN the model approaches and attacks, and self-KO is not the majority of its stocks lost

#### Scenario: Criterion not met
- GIVEN a candidate model below 60% versus CPU Easy, or failing any harness acceptance metric
- WHEN promotion to default is considered
- THEN it is NOT committed as the default, the previous bundled model is kept, and the failure is reported

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

### Requirement: Committed exploration harness

The exploration harness MUST be a committed, repeatable eval scenario (model vs model, model vs CPU, CPU vs CPU) with a fixed seed option, producing the combat-depth metrics as machine-readable output and a readable summary.

#### Scenario: Repeatable
- GIVEN the harness and a fixed seed
- WHEN it runs twice
- THEN the metrics agree within a documented tolerance

#### Scenario: Matchups covered
- GIVEN the harness configuration
- WHEN listed
- THEN it covers model vs model, model vs CPU and CPU vs CPU

### Requirement: Harness acceptance metrics

A retrained default model MUST be promoted to the bundled default only if the harness rerun shows all of: model-vs-model sudden death ends in under about 45 s on average (measured from sudden-death start); food pickups exceed 1 per minute per fighter; the blocked-hit share is at most 70% (and well under the pre-change 99%); and the model wins at least 60% by KO versus CPU Easy over at least 20 matches with non-trivial play. If a gate fails, the old bundled model MUST be kept and the failure reported after iterating reward weights only within the time box.

#### Scenario: All gates pass
- GIVEN a candidate whose harness rerun meets every gate
- WHEN promotion is considered
- THEN it is committed as the default with `bvs.json`, fixtures and report

#### Scenario: Sudden-death gate
- GIVEN the model-vs-model matches
- WHEN mean sudden-death duration is computed
- THEN it is under about 45 s

#### Scenario: Food gate
- GIVEN the harness output
- WHEN pickups per fighter-minute are computed
- THEN they exceed 1

#### Scenario: Blocked-share gate
- GIVEN the harness output
- WHEN blocked hits over total hits is computed
- THEN it is at most 70%

#### Scenario: Gate failure keeps old model
- GIVEN a candidate failing one gate
- WHEN promotion is considered
- THEN the v2 bundled model is kept and the result is reported

### Requirement: Golden parity before commit for schema 3

Before the bundled model is replaced, v3 golden parity (the `onnx-mlp-inference` golden checks against the v3 fixtures) MUST pass. The frozen v2 path (v2 module, v2 decoder, v2 fixtures) MUST stay byte-identical and its checks MUST pass. Only checks that assert the CURRENT schema version or the BUNDLED model's schema (`schema_v2` registry check, `onnx_golden`, `policy_match`, `cpu_select`, `hf_picker`, `train_loads` bundled-model checks) move to the current schema when the version switches (amendment, orchestrator decision).

#### Scenario: Parity gate
- GIVEN a candidate failing v3 golden parity
- WHEN commit of artifacts is attempted
- THEN the procedure stops and reports the parity failure

#### Scenario: v2 tests green
- GIVEN the change applied
- WHEN the v2 smoke checks run
- THEN the frozen-v2 checks pass unedited, and the current-version and bundled-model checks pass against the current schema

### Requirement: Remote operation authorization gate

Publishing to Hugging Face and updating the Space are remote operations. They MUST NOT run, and the agent MUST NOT probe ambient authentication state (for example `hf auth whoami`) or the Space deploy method, before the user explicitly confirms, in the same session, all of: the destination (model repo `RafaelJaime/BVS-default` and, separately, Space `RafaelJaime/BroVSister`), the operation (files to upload, tags, visibility, which build to deploy), and the credential to use. Before asking, the agent MUST present the repo ids, files and tags (`BVS`, `bvs-schema-3`), credential, and the evaluation and harness results, and then STOP. A missing or ambiguous part MUST keep the work local, and confirming the model repo MUST NOT authorize the Space update (or the reverse). After upload, a read-only listing check MUST confirm the model appears under `filter=BVS` with the `bvs-schema-3` tag. The upload script MUST refuse to run without an explicit confirmation argument carrying the repo id. The agent MUST NOT perform remote cleanup or rollback without separate authorization.

#### Scenario: No remote write without confirmation
- GIVEN artifacts are committed and the user has not confirmed
- WHEN the pipeline reaches S4
- THEN no network write, auth probe or deploy-method probe occurs and a confirmation request listing repo ids, files/tags, credential and results is presented, then the work STOPs

#### Scenario: Partial confirmation
- GIVEN the user confirmed the repo id but not the credential
- WHEN the upload would run
- THEN it does not run and the agent asks for the missing part

#### Scenario: Model confirmation does not cover Space
- GIVEN the user confirmed the model repo upload only
- WHEN the pipeline reaches the Space update
- THEN no Space change occurs until the Space destination, operation and credential are separately confirmed

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
- THEN the repo appears with the `bvs-schema-3` tag, and the in-game picker marks it Compatible

#### Scenario: Space updated after confirmation
- GIVEN the user confirmed the Space destination, operation and credential
- WHEN the web build is deployed
- THEN the Space runs the new build

#### Scenario: Model card content
- GIVEN the generated model card
- WHEN reviewed
- THEN it states the MLP-only schema 3 contract, the tags, the evaluation and harness results, and the license confirmed by the user
