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

`PolicyController` MUST adapt the existing `PlayerAIController` action values into intent and MUST leave S5 fields neutral. `PlayerAIController.get_obs()` and `get_action_space()` MUST remain unchanged, and `sync.gd` TRAINING/ONNX modes MUST keep working.

#### Scenario: Training mode intact
- GIVEN `train.tscn` in TRAINING mode
- WHEN it loads and runs
- THEN fighters receive actions through `PolicyController` and no script errors occur

#### Scenario: Obs/action API unchanged
- GIVEN the change applied
- WHEN `get_obs()` and `get_action_space()` are statically compared with baseline
- THEN they are identical

### Requirement: Explicit controller selection, no implicit ONNX

The controller kind MUST be chosen explicitly per player (Human, CPU, or Policy/ONNX). The game path MUST NOT switch to ONNX because `user://Agent{N}.onnx` exists.

#### Scenario: Stale model with Human selected
- GIVEN `user://Agent1.onnx` exists and P1 is Human
- WHEN a match starts
- THEN P1 obeys human input

#### Scenario: ONNX option routes via policy
- GIVEN the existing ONNX/HF option is selected
- WHEN a match starts
- THEN that fighter uses `PolicyController` and the option's behavior is otherwise unchanged

### Requirement: Debug output removal

Per-frame paths (`Motion._enter`, `PlayerAIController._ready`, `Fighter`) MUST NOT call `print()`.

#### Scenario: Print audit
- GIVEN the change applied
- WHEN those files are searched for `print(`
- THEN no calls remain
