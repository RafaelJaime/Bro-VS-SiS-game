# Delta for RL Training Pipeline

One retrain covers the shield fixes (`odd/tasks/shield-spam.md` T4, moved into this change) and the kits. All reward weights, thresholds, curriculum and time boxes are tunable data. Verification: Godot smoke tests, Python checks and the committed report.

## ADDED Requirements

### Requirement: Kit randomization per side

Training rows MUST randomize the kit of each fighter per episode and per side (Rafael or Matilde on either side, including mirror matchups), configurable in data. The observation MUST carry the kit one-hot (see `ai-schema`). Kit assignment MUST be reproducible from the row seed.

#### Scenario: Both kits seen on both sides
- GIVEN a training run of many episodes
- WHEN kit assignments are logged
- THEN each kit appears on each side and mirror matchups occur

#### Scenario: Seeded assignment
- GIVEN a fixed row seed
- WHEN two runs assign kits
- THEN the assignments are identical

#### Scenario: Train loads with kit randomization
- GIVEN `train.tscn` with kit randomization enabled
- WHEN loaded headless for a bounded number of frames
- THEN no script errors occur and every row reaches a running match

### Requirement: Combo and shield-spam harness metrics

The committed harness and the evaluation MUST also report: shield raises per fighter-minute, the combo length histogram and maximum combo, the longest continuous time any victim spent in Hurt, win share by kit and by side, and combo damage by kit. Metrics MUST be machine-readable and summarized in the readable report.

#### Scenario: Metrics present
- GIVEN a harness run
- WHEN the machine-readable output is inspected
- THEN shield raises per fighter-minute, the combo histogram and maximum, the longest Hurt duration, win share by kit and side, and combo damage by kit are present

#### Scenario: Both kits on both sides
- GIVEN the harness configuration
- WHEN the matchup list is read
- THEN model vs model, model vs CPU and CPU vs CPU cover both kits on both sides

### Requirement: Shield raise threshold recorded before the retrain

A numeric threshold for shield raises per fighter-minute MUST be derived in design from measured baselines (CPU Hard and the current bundled model) and recorded before the retrain starts. Promotion MUST be blocked if the threshold is not recorded.

#### Scenario: Threshold recorded
- GIVEN the design is complete
- WHEN the retrain is about to start
- THEN the threshold value and its baselines are written in the design artifact

#### Scenario: No threshold, no promotion
- GIVEN a candidate with no recorded threshold
- WHEN promotion is considered
- THEN promotion is blocked and the missing threshold is reported

## RENAMED Requirements

### Requirement: Golden parity before commit for schema 3 → Golden parity before commit for schema 4

(Reason: the bundled default model moves to schema 4, so golden parity now gates the v4 export.)
(Migration: references to "golden parity for schema 3" read "golden parity for schema 4"; the v2 and v3 frozen paths keep their own unedited checks.)

## MODIFIED Requirements

### Requirement: Reward components

Per step, the training reward MUST be the sum of tunable components: damage dealt (+), damage taken (-), KO given (+), KO taken (-), stock lost (-), win (+), loss (-), small shaping terms (for example approaching the opponent, edge/recovery penalties), the combat-depth terms: food pickup (+), food hit landed (+), shield break dealt (+), shield break taken (-), a small penalty for holding the shield too long (-), and a small combo term (+) per additional combo hit dealt, capped per episode and per combo. Each component MUST be logged separately and MUST be changeable through data without code edits. Rewards MUST be derived from the damage, stock, match, pickup, food-hit, shield-break and combat (combo) signals, not from observation reads.
(Previously: no combo term.)

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

#### Scenario: Combo term is capped
- GIVEN fighter A lands a 5-hit combo and many more combos in the same episode
- WHEN rewards are summed
- THEN the combo term per combo and per episode never exceeds its configured cap

#### Scenario: Combo term from combat signals
- GIVEN fighter A's second consecutive hit lands during hitstun
- WHEN the step is processed
- THEN A's reward includes the combo term, derived from the combat signal and not from observation reads

#### Scenario: Observable in logs
- GIVEN a training run
- WHEN its log is inspected
- THEN KO, stock, win, pickup, food-hit, shield-break and combo components appear as separate entries

#### Scenario: Weights are data
- GIVEN a reward weight changed in the data file
- WHEN training restarts
- THEN the new weight applies with no GDScript edit

### Requirement: Python training project

The repo MUST contain a uv-managed Python 3.12 project under `training/` with pinned versions of `godot-rl`, `stable-baselines3`, `torch`, `onnx`, and `onnxruntime`, and scripts to train (PPO, Godot headless on `train.tscn`, curriculum including sudden-death episodes and kit randomization), export, generate golden fixtures, evaluate, and upload. A documented one-command setup MUST work from a clean checkout. Documentation MUST state the MLP-only constraint, the schema contract (schema 4), and the tags (`BVS` / `bvs-schema-4`).
(Previously: stated schema 3 and `bvs-schema-3`; no kit randomization.)

#### Scenario: Reproducible environment
- GIVEN a clean checkout
- WHEN the documented uv setup runs
- THEN the environment resolves to the pinned versions

#### Scenario: Handshake with Godot
- GIVEN Godot headless running `train.tscn`
- WHEN the trainer connects
- THEN the handshake succeeds and observations of length v4 `obs_dim` (149) are received

#### Scenario: Train loads with sudden death
- GIVEN `train.tscn` with sudden death enabled
- WHEN loaded headless for a bounded number of frames
- THEN no script errors occur

#### Scenario: Documented constraints
- GIVEN the trainer docs
- WHEN reviewed
- THEN they state MLP-only, the schema 4 contract, and the `BVS` / `bvs-schema-4` tags

### Requirement: Export contract

The export script MUST emit an MLP ONNX at opset 17 with constants folded, using only whitelisted ops, an input dimension equal to the schema `obs_dim`, and a deterministic output head from which the eight branch indices of the current schema are derived. It MUST verify the exported graph against the whitelist before writing, and MUST fail rather than emit a graph with an unsupported op. The sidecar MUST carry the current schema version (4).
(Previously: sidecar carried `schema_version` 3 and v3 `obs_dim`.)

#### Scenario: Clean export
- GIVEN a trained checkpoint
- WHEN exported
- THEN the file's ops are a subset of the whitelist and its input dimension equals the v4 `obs_dim` (149)

#### Scenario: Unsupported op fails export
- GIVEN a model whose export would include `Gather`
- WHEN export runs
- THEN it fails with an error naming the op and writes no model file

#### Scenario: Sidecar emitted
- GIVEN a successful export
- WHEN the output directory is listed
- THEN `bvs.json` exists with `schema_version` 4, `obs_dim` 149, the action layout, `action_repeat`, and `trained_on_commit`

### Requirement: Evaluation

An evaluation script MUST run the model versus CPU Easy and CPU Normal for at least N = 20 headless matches each and write a report with win rate, mean stocks taken, behavior indicators (approach, attacks thrown, recoveries, self-KO share of stocks lost, idle share), the combat-depth metrics (sudden-death length, food pickups per minute, throws per minute, blocked-hit share, damage by source, shield breaks) and the combo and shield-spam metrics (see "Combo and shield-spam harness metrics"). The report MUST be committed with the model.
(Previously: no combo or shield-raise metrics.)

#### Scenario: Report produced
- GIVEN the default model
- WHEN the evaluation runs
- THEN a report lists matches played, win rate versus Easy and Normal, the behavior indicators, the combat-depth metrics and the combo and shield-spam metrics

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
- THEN it is NOT committed as the default, the previous bundled model is kept in the repo until a passing model exists, and the failure is reported

### Requirement: Default model artifacts

After parity (the `onnx-mlp-inference` golden checks) and evaluation pass, the project MUST commit the default model ONNX, its `bvs.json` (schema 4), the golden fixtures (v4 added, v2 and v3 kept), the evaluation report and the replay `replay.mp4`. The bundled model MUST live under `res://` so it can be selected offline (see `hub-model-distribution`).
(Previously: no replay and no schema-4 or v3-kept fixtures.)

#### Scenario: Artifacts present
- GIVEN the change applied
- WHEN the repo is listed
- THEN the model, `bvs.json`, v4 fixtures, report and `replay.mp4` exist at their documented paths

#### Scenario: Gate order
- GIVEN a model that fails golden parity
- WHEN commit of artifacts is attempted
- THEN the procedure stops before committing and reports the parity failure

### Requirement: Harness acceptance metrics

A retrained default model MUST be promoted to the bundled default only if the harness rerun (100+ matches covering model vs model, model vs CPU and CPU vs CPU, both kits on both sides) shows all of:
1. model-vs-model sudden death ends in under about 45 s on average (from sudden-death start);
2. food pickups exceed 1 per minute per fighter;
3. blocked-hit share at most 70%;
4. the model wins at least 60% by KO versus CPU Easy over at least 20 matches with non-trivial play;
5. shield raises per fighter-minute at or under the threshold recorded in design;
6. 2+ hit combos occur in CPU Normal, CPU Hard and model matches;
7. maximum combo is at most 6;
8. no victim spends more than 1.5 s continuously in Hurt;
9. Rafael's win share is between 40% and 60% in the CPU Hard mirror and in model vs model;
10. combo damage differs by at most 20% between kits.
If a gate fails, iteration MUST continue (reward weights, curriculum, steps, kit data) within the time box and the change MUST NOT merge until every gate passes. If the time box is exhausted with a gate still failing, work MUST STOP and the user MUST choose between merging the best candidate with the failed gate reported and merging the gameplay slices on schema 3 with schema 4 and the retrain moved to a follow-up.
(Previously: four gates only; on failure the old bundled model was kept and the failure reported.)

#### Scenario: All gates pass
- GIVEN a candidate whose harness rerun meets every gate
- WHEN promotion is considered
- THEN it is committed as the default with `bvs.json`, fixtures, report and `replay.mp4`

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

#### Scenario: Shield-raise gate
- GIVEN the harness output
- WHEN shield raises per fighter-minute are computed
- THEN they are at most the recorded threshold

#### Scenario: Combo gate
- GIVEN the harness output
- WHEN combo statistics are read
- THEN 2+ hit combos occur, the maximum combo is at most 6 and no victim spent more than 1.5 s continuously in Hurt

#### Scenario: Balance gate
- GIVEN the harness output
- WHEN win share and combo damage by kit are read
- THEN Rafael's win share is 40% to 60% in CPU Hard mirror and model vs model, and combo damage differs by at most 20%

#### Scenario: Gate failure keeps iterating
- GIVEN a candidate failing one gate within the time box
- WHEN promotion is considered
- THEN it is not promoted, iteration continues, and the failure is reported

#### Scenario: Time box exhausted
- GIVEN the time box is exhausted with a gate still failing
- WHEN the pipeline decides what to do
- THEN work stops and asks the user to choose between merging the best candidate with the failure reported and merging the gameplay slices on schema 3

### Requirement: Golden parity before commit for schema 4

Before the bundled model is replaced, v4 golden parity (the `onnx-mlp-inference` golden checks against the v4 fixtures) MUST pass. The frozen v2 and v3 paths (modules, decoders, fixtures) MUST stay byte-identical and their layout, observation, decode and fixture checks MUST pass unedited (their registry test stub moves from version 4 to 5). Only checks that assert the CURRENT schema version or the BUNDLED model's schema (`onnx_golden`, `policy_match`, `cpu_select`, `hf_picker`, `train_loads` bundled-model checks, the current-version registry check) move to schema 4 when the version switches.
(Previously: schema 3 current with only v2 frozen.)

#### Scenario: Parity gate
- GIVEN a candidate failing v4 golden parity
- WHEN commit of artifacts is attempted
- THEN the procedure stops and reports the parity failure

#### Scenario: Frozen tests green
- GIVEN the change applied
- WHEN the v2 and v3 smoke checks run
- THEN the frozen layout/observation/decode/fixture checks pass unedited (registry stub version 5), and the current-version and bundled-model checks pass against schema 4

### Requirement: Remote operation authorization gate

Publishing to Hugging Face and updating the Space are remote operations that happen only after the PR is merged. They MUST NOT run, and the agent MUST NOT probe ambient authentication state (for example `hf auth whoami`) or the Space deploy method, before the user explicitly confirms, in the same session, all of: the destination (model repo `RafaelJaime/BVS-default` and, separately, Space `RafaelJaime/BroVSister`), the operation (files to upload including `model.onnx`, `bvs.json`, the model card and `replay.mp4`, tags, visibility, which build to deploy), and the credential to use. Before asking, the agent MUST present the repo ids, files and tags (`BVS`, `bvs-schema-4`), credential, and the evaluation and harness results, and then STOP. A missing or ambiguous part MUST keep the work local, and confirming the model repo MUST NOT authorize the Space update (or the reverse). After upload, a read-only listing check MUST confirm the model appears under `filter=BVS` with the `bvs-schema-4` tag. The upload script MUST refuse to run without an explicit confirmation argument carrying the repo id. The agent MUST NOT perform remote cleanup or rollback without separate authorization.
(Previously: tag `bvs-schema-3`, no replay file, no explicit merge-first precondition.)

#### Scenario: No remote write without confirmation
- GIVEN artifacts are committed and the user has not confirmed
- WHEN the pipeline reaches the upload step
- THEN no network write, auth probe or deploy-method probe occurs and a confirmation request listing repo ids, files/tags, credential and results is presented, then the work STOPs

#### Scenario: Not before merge
- GIVEN the PR is not merged
- WHEN the pipeline considers uploading
- THEN no remote operation runs

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
- THEN exactly the confirmed files (including `replay.mp4`) and tags are uploaded to the confirmed repo id

#### Scenario: Post-upload verification
- GIVEN a completed upload
- WHEN the read-only Hub listing is queried with `filter=BVS`
- THEN the repo appears with the `bvs-schema-4` tag, and the in-game picker marks it Compatible

#### Scenario: Space updated after confirmation
- GIVEN the user confirmed the Space destination, operation and credential
- WHEN the web build is deployed
- THEN the Space runs the new build

#### Scenario: Model card content
- GIVEN the generated model card
- WHEN reviewed
- THEN it states the MLP-only schema 4 contract, the tags, the evaluation and harness results (including combo and balance metrics), and the license confirmed by the user
