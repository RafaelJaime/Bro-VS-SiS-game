# AI Schema Specification

## Purpose

A versioned observation/action contract (`bvs-schema-N`) shared by training and in-game inference so the two cannot drift. Schema 2 is frozen by this change. It reads only the gameplay state snapshot and decodes into `FighterIntent`. Verification: Godot smoke tests (`tests/smoke/`) and Python golden checks.

## Requirements

### Requirement: Single shared schema module

The system MUST provide one schema module that is the only source of observation layout, action layout, decode rules, `action_repeat`, and the version constant. `PlayerAIController` (training) and `PolicyController` (inference) MUST both build observations and decode actions exclusively through it. Neither MAY keep its own copy of the layout.

#### Scenario: Training and inference produce identical observations
- GIVEN a live Game with two fighters in a fixed state
- WHEN the observation is built via `PlayerAIController` and via `PolicyController` for the same fighter
- THEN both vectors are element-wise equal

#### Scenario: No private layout
- GIVEN the change applied
- WHEN `player_ai_controller.gd` and `policy_controller.gd` are reviewed
- THEN neither defines observation indices, normalization constants, or action decode tables of its own

### Requirement: Schema version registry and constant

The system MUST expose a registry mapping schema version to its module, and `HubModel.BVS_SCHEMA_VERSION` MUST equal `2`. Looking up an unregistered version MUST return an explicit "unsupported" result, not a default layout. Adding a future version MUST NOT change how version 2 builds observations or decodes actions.

#### Scenario: Version constant
- GIVEN the change applied
- WHEN `HubModel.BVS_SCHEMA_VERSION` is read
- THEN it is `2`

#### Scenario: Unknown version
- GIVEN a sidecar declaring `schema_version` 99
- WHEN the registry is queried for 99
- THEN it reports unsupported and no layout is returned

#### Scenario: Extensibility
- GIVEN a test-only stub registered as version 3 with a different `obs_dim`
- WHEN version 2 is used for building observations and decoding
- THEN results are identical to those without the stub registered

### Requirement: Schema-2 observation layout

The v2 observation MUST be a flat float vector of fixed order and fixed `obs_dim`, built only from `Fighter.get_state_snapshot()` and `Game.get_state_snapshot()`. It MUST include, for self and opponent: Game-local position, velocity, facing, on-floor, damage %, stocks, jumps left, FSM state, and cooldowns; and for the match: food positions, held food, stage edges (or platform extents), and timer. Positions MUST be Game-local and expressed self-relative where the layout declares so; global positions MUST NOT be used. Every value MUST be normalized into a documented bounded range (default [-1, 1] or [0, 1]), clamped, and finite (never NaN or infinity). Missing optional entities (no food on stage, opponent mid-respawn) MUST encode as documented sentinel values and keep `obs_dim` unchanged.

#### Scenario: Fixed dimension
- GIVEN any fighter in any match state
- WHEN the observation is built
- THEN its length equals the schema's declared `obs_dim`

#### Scenario: Game offset invariance
- GIVEN two Games identical in state but at different global offsets
- WHEN observations are built for the same fighter in each
- THEN the vectors are equal

#### Scenario: Bounded and finite
- GIVEN a fighter far outside the stage, at 999% damage, with maximum velocity
- WHEN the observation is built
- THEN every element is finite and inside its documented range

#### Scenario: Absent food
- GIVEN no food on stage and no held food
- WHEN the observation is built
- THEN the food slots hold the documented sentinel and the length is unchanged

#### Scenario: Read-only
- GIVEN an observation is built twice with no intervening physics frame
- WHEN the results and the fighter state are compared
- THEN the vectors are equal and no fighter or Game state changed

### Requirement: Schema-2 discrete action layout

The v2 action space MUST be MultiDiscrete (`nvec` = [3,3,2,5,2,2,2,2], 21 logits) with this fixed branch order, names and sizes: `a0_move` {left, none, right} (3), `a1_vertical` {none, up, down} (3), `a2_jump` {release, hold} (2), `a3_attack` {none, neutral, up, down, side} (5), `a4_special` {no, yes} (2), `a5_throw` {no, yes} (2), `a6_block` {no, yes} (2), `a7_dash` {no, yes} (2). `get_action_space()` MUST report exactly this layout, and the layout MUST be serialized identically into the `bvs.json` sidecar.

#### Scenario: Declared layout
- GIVEN schema 2
- WHEN `get_action_space()` is read
- THEN it lists eight discrete branches with sizes 3, 3, 2, 5, 2, 2, 2, 2 in that order, named `a0_move` through `a7_dash`

#### Scenario: Sidecar parity
- GIVEN the sidecar produced for the default model
- WHEN its action layout is compared with `get_action_space()`
- THEN they are equal

### Requirement: Decode into FighterIntent

The schema MUST decode a vector of branch indices into a `FighterIntent`: move left/none/right to `move_x` -1/0/1 (held); vertical up/down to a held aim UP/DOWN (fast fall, ledge drop); jump hold to jump held, with jump pressed on the first tick of the window when the previous decision was release or the fighter is on the floor; attack `none` to no attack, any other value to attack pressed on the first tick with aim neutral/up/down/side; special yes to special pressed with aim UP on the first tick (overriding the attack branch); throw and dash yes to the matching pressed fields on the first tick; block yes to block held for the whole window with block pressed on a rising edge. `attack_held` MUST stay false (no charged smash for policies in v2). An out-of-range or wrong-length (not eight branches) action vector MUST be rejected with an error and MUST NOT produce an intent that acts.

#### Scenario: Move mapping
- GIVEN action indices with move = 0, 1, 2 in three successive decodes
- WHEN decoded
- THEN `move_x` is -1, 0, 1 respectively

#### Scenario: Attack aim mapping
- GIVEN `a3_attack` = 3 (down)
- WHEN decoded
- THEN attack pressed is true and aim direction is down

#### Scenario: Vertical and special mapping
- GIVEN `a1_vertical` = 2 (down), then `a4_special` = 1 with `a3_attack` = 2
- WHEN decoded
- THEN aim is DOWN held in the first decode, and in the second special pressed is true with aim UP and attack pressed is false

#### Scenario: Attack none
- GIVEN `a3_attack` = 0
- WHEN decoded
- THEN attack pressed is false

#### Scenario: No charged smash
- GIVEN any action vector
- WHEN decoded
- THEN `attack_held` is false

#### Scenario: Invalid action rejected
- GIVEN a vector with a branch index equal to its branch size, or with seven branches
- WHEN decoded
- THEN an error is reported and the resulting intent is neutral

### Requirement: Action repeat

The schema MUST declare `action_repeat` (a positive integer count of physics ticks). The decoded intent MUST be held constant for that many ticks, except that single-tick pulses (attack, throw, dash, special pressed) MUST fire once per decision, not once per held tick.

#### Scenario: Intent held
- GIVEN `action_repeat` = N and a decision of move right
- WHEN N physics ticks run
- THEN `move_x` is 1 on all N ticks

#### Scenario: Pulse fires once
- GIVEN a decision of attack neutral with `action_repeat` = N
- WHEN N physics ticks run
- THEN attack pressed is true on exactly one tick

### Requirement: Snapshot keys the schema depends on

Every snapshot key read by schema 2 MUST be listed in the `gameplay-state-snapshot` required keys. If a required key is absent at runtime, the schema MUST report an error naming the key rather than silently substituting zero.

#### Scenario: Missing key
- GIVEN a snapshot dictionary lacking a required key
- WHEN the schema builds an observation
- THEN an error naming the missing key is reported

### Requirement: Golden observation fixtures

A committed JSON fixture MUST pair fixed snapshot inputs with the expected observation vector, so the Python training side and the GDScript side can both check the layout. The smoke test MUST fail if the layout or normalization changes without the fixture being regenerated.

#### Scenario: Observation parity with fixture
- GIVEN the committed observation fixture
- WHEN the schema builds observations from its recorded snapshots
- THEN each result equals the expected vector within 1e-6
