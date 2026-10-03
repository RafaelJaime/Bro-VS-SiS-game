# Fighter Control Specification

## Purpose

Separates where a fighter's input comes from (human, scripted, external policy) from the fighter that acts on it, via a per-frame intent contract. All numeric values are tunable defaults. Verification: static review plus manual playtest.

## Requirements

### Requirement: Per-frame FighterIntent contract

The system MUST define a `FighterIntent` value carrying: move_x, jump pressed, jump held, attack pressed, attack held, attack released, throw, block, dash, aim direction (neutral / up / down / side), and special pressed. A Fighter MUST sample its controller's intent exactly once per physics frame, and `Motion` and all states MUST read only that intent (no direct `Input` or `PlayerAIController` reads in states).

#### Scenario: Single intent sample per frame
- GIVEN a Fighter with any controller
- WHEN one physics frame runs
- THEN the controller is sampled once and every state in that frame sees the same intent

#### Scenario: Unified path
- GIVEN a Fighter controlled by Human, Scripted, or Policy
- WHEN a state evaluates a transition
- THEN it uses the same `Motion` helpers with no controller-kind branching

#### Scenario: S5 fields inert before S5
- GIVEN S1 is applied and S5 is not
- WHEN a controller sets aim direction, attack held/released, or special
- THEN no gameplay behavior changes

### Requirement: Human controller

`HumanController` MUST map the player's input actions to intent. With S5, it MUST map `P{N}_up` / `P{N}_down` (new actions, Option B) to aim direction up/down, and `left`/`right` held together with punch to side. The existing bindings (`left`, `right`, `jump`, `protect`, `punch`, `shoot`) MUST keep working for local 2P.

#### Scenario: Existing bindings preserved
- GIVEN two local human players
- WHEN each uses existing keys
- THEN each fighter responds exactly to its own player's keys

#### Scenario: New up/down actions
- GIVEN S5 applied
- WHEN P1 holds `P1_up`
- THEN P1's intent aim direction is up; releasing returns it to neutral

#### Scenario: No binding collision
- GIVEN `project.godot` after S5
- WHEN P1 and P2 up/down bindings are reviewed
- THEN the four new bindings do not duplicate any existing binding

### Requirement: Policy controller adapter

`PolicyController` MUST obtain observations and decode actions through the `ai-schema` module and MUST leave charged-attack fields (`attack_held`) false. In a match, `PolicyController` MUST run the loaded ONNX model (`onnx-mlp-inference`) itself every `action_repeat` physics ticks and hold the decoded intent in between; no `Sync` node is required in the game scene. `PlayerAIController.get_obs()`, `get_action_space()` and `set_action()` MUST delegate to the schema module and be used for training; `sync.gd` TRAINING mode MUST keep working.
(Previously: PolicyController adapted legacy PlayerAIController action values, `get_obs()`/`get_action_space()` were frozen at the legacy layout, and ONNX mode relied on a Sync node.)

#### Scenario: Training mode intact
- GIVEN `train.tscn` in TRAINING mode
- WHEN it loads and runs
- THEN fighters receive actions through `PolicyController` and no script errors occur

#### Scenario: Obs/action API delegates to schema
- GIVEN the change applied
- WHEN `get_obs()` and `get_action_space()` are called on `PlayerAIController`
- THEN they return exactly the schema 2 observation and the schema 2 action layout

#### Scenario: In-game inference without Sync
- GIVEN a match scene with no `Sync` node and a fighter using a validated model
- WHEN the match runs for several seconds
- THEN that fighter's intent changes over time driven by the model

#### Scenario: Decision cadence
- GIVEN `action_repeat` = N
- WHEN 3N physics ticks run
- THEN the model runs exactly 3 times and the intent is constant between runs

#### Scenario: Inference error is surfaced
- GIVEN a loaded model that returns an error at run time
- WHEN the fighter's decision is due
- THEN the error is reported once, the fighter's intent is neutral, and the game does not crash

### Requirement: Explicit controller selection, no implicit ONNX

The controller kind MUST be chosen explicitly per player (Human, CPU, or Policy/ONNX). The game path MUST NOT switch to ONNX because any file exists on disk. A Policy selection whose model is missing or invalid MUST NOT silently fall back to the scripted CPU: `ControllerConfig` MUST carry a loaded model handle (repo, revision, parsed model, sidecar) or an explicit error state.
(Previously: only `user://Agent{N}.onnx` was forbidden as an implicit switch, and a missing model silently fell back to the scripted CPU.)

#### Scenario: Stale model with Human selected
- GIVEN `user://Agent1.onnx` exists and P1 is Human
- WHEN a match starts
- THEN P1 obeys human input

#### Scenario: ONNX option routes via policy
- GIVEN the ONNX/HF option is selected with a validated model
- WHEN a match starts
- THEN that fighter uses `PolicyController` with that model handle

#### Scenario: Missing model does not become CPU
- GIVEN the Policy option is selected but its model failed to load
- WHEN the match start is attempted
- THEN the match does not start with a substituted CPU and the error state is shown

## UNCHANGED Requirements

Per-frame FighterIntent contract, Human controller, and Debug output removal are unchanged by this change.
### Requirement: Debug output removal

Per-frame paths (`Motion._enter`, `PlayerAIController._ready`, `Fighter`) MUST NOT call `print()`.

#### Scenario: Print audit
- GIVEN the change applied
- WHEN those files are searched for `print(`
- THEN no calls remain
