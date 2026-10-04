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

The system MUST expose a registry mapping schema version to its module, registering versions 2 and 3 (both frozen) and version 4 (current in the final state), and `HubModel.BVS_SCHEMA_VERSION` MUST equal `4` in the final state. Version 4 is registered when the schema-4 slice lands, but `CURRENT_VERSION` (and therefore `HubModel.BVS_SCHEMA_VERSION`) flips to 4 only in the commit that bundles the retrained model. Looking up an unregistered version MUST return an explicit "unsupported" result, not a default layout. Adding a future version MUST NOT change how versions 2, 3 or 4 build observations or decode actions.
(Previously: versions 2 (frozen) and 3 (current) were registered and `HubModel.BVS_SCHEMA_VERSION` equaled 3.)

#### Scenario: Version constant
- GIVEN the change applied
- WHEN `HubModel.BVS_SCHEMA_VERSION` is read
- THEN it is `4`

#### Scenario: All versions registered
- GIVEN the registry
- WHEN versions 2, 3 and 4 are queried
- THEN each returns its own module with its own `obs_dim` (v4 is 149)

#### Scenario: Unknown version
- GIVEN a sidecar declaring `schema_version` 99
- WHEN the registry is queried for 99
- THEN it reports unsupported and no layout is returned

#### Scenario: Extensibility
- GIVEN a test-only stub registered as version 5 with a different `obs_dim`
- WHEN versions 2, 3 and 4 are used for building observations and decoding
- THEN results are identical to those without the stub registered

#### Scenario: Schemas 2 and 3 frozen
- GIVEN the change applied
- WHEN the schema-2 and schema-3 modules, decoders and fixtures are compared with the base commit
- THEN they are byte-identical, and the `schema_v2` and `schema_v3` layout, observation, decode and fixture checks pass unedited (the registry test stub version may move from 4 to 5, since version 4 becomes a built-in); only assertions about the CURRENT schema version or the BUNDLED model's schema move to the current schema

#### Scenario: Version switch is gated
- GIVEN the retrained model has not passed every acceptance gate
- WHEN the change is finalized
- THEN the switch of `CURRENT_VERSION` (and `HubModel.BVS_SCHEMA_VERSION`) to 4 does not ship; it happens only in the same commit that bundles the passing v4 model, and the merge waits until every gate passes (iterate within the time box; if the time box is exhausted with a gate still failing, work STOPs and the user decides between merging the best candidate with the failed gate reported or merging the gameplay slices on schema 3 and moving schema 4 and the retrain to a follow-up)
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
### Requirement: Schema-3 observation layout

The v3 observation MUST be a flat float vector of fixed order and fixed `obs_dim` (declared by the v3 module), built only from `Fighter.get_state_snapshot()` and `Game.get_state_snapshot()`. It MUST contain everything the v2 layout carries, and MUST add: shield meter (self and opponent, normalized to [0, 1]), dizzy flag and normalized remaining dizzy time (self and opponent), air-dodge availability (self), sudden-death phase and normalized elapsed time, and the nearest K falling bombs (default K = 2) each with self-relative Game-local position and velocity. Absent bombs MUST encode as documented sentinel values with `obs_dim` unchanged. Every value MUST be normalized into a documented bounded range, clamped and finite (never NaN or infinity). Positions MUST be Game-local and self-relative where declared; global positions MUST NOT be used.

#### Scenario: Fixed dimension
- GIVEN any fighter in any match state, including sudden death with 0, 1 or many bombs
- WHEN the v3 observation is built
- THEN its length equals the v3 declared `obs_dim`

#### Scenario: Shield features
- GIVEN self at half meter and the opponent dizzy with half the dizzy time left
- WHEN the observation is built
- THEN the self shield slot is about 0.5, and the opponent dizzy flag is 1 with remaining time about 0.5 in its normalized slot

#### Scenario: Nearest bombs
- GIVEN three bombs at different distances
- WHEN the observation is built
- THEN the two nearest are encoded in order of distance with self-relative position and velocity

#### Scenario: No bombs sentinel
- GIVEN no bombs and no sudden death
- WHEN the observation is built
- THEN the bomb slots hold the documented sentinel, the phase slot is 0 and the length is unchanged

#### Scenario: Game offset invariance
- GIVEN two Games identical in state but at different global offsets
- WHEN observations are built for the same fighter in each
- THEN the vectors are equal

#### Scenario: Bounded and finite
- GIVEN a fighter far outside the stage, at 999% damage, with maximum velocity and many bombs
- WHEN the observation is built
- THEN every element is finite and inside its documented range

#### Scenario: Read-only
- GIVEN an observation is built twice with no intervening frame
- WHEN the results and the state are compared
- THEN the vectors are equal and no state changed

#### Scenario: Training and inference identical
- GIVEN a live Game in a fixed state
- WHEN the v3 observation is built via `PlayerAIController` and via `PolicyController`
- THEN both vectors are element-wise equal

### Requirement: Schema-3 action layout

The v3 action space MUST keep the v2 MultiDiscrete layout (`nvec` = [3,3,2,5,2,2,2,2], eight branches `a0_move` to `a7_dash`) unless design documents a need to change it. `get_action_space()` MUST report the layout and it MUST be serialized identically into `bvs.json`. `a6_block` yes in the air MUST map to the air dodge (see `fighter-shield`).

#### Scenario: Declared layout
- GIVEN schema 3
- WHEN `get_action_space()` is read
- THEN it lists the branch names and sizes of the v3 layout, matching the sidecar

#### Scenario: Sidecar parity
- GIVEN the sidecar produced for the default model
- WHEN its action layout is compared with `get_action_space()`
- THEN they are equal

### Requirement: Schema-3 decode with exclusive throw

The v3 decoder MUST follow the v2 decode rules (move, vertical, jump, attack, special, dash, block, `attack_held` false, out-of-range or wrong-length vectors rejected with a neutral intent) with one change: `a5_throw` MUST be exclusive. While the fighter holds food, a throw decision MUST suppress the same-window attack pulse so punch and throw never fire together. When no food is held, throw is ignored as in v2.

#### Scenario: Throw suppresses attack
- GIVEN a fighter holding food and a decision with `a5_throw` = 1 and `a3_attack` = 1
- WHEN decoded
- THEN throw pressed is true and attack pressed is false in that window

#### Scenario: Attack kept without throw
- GIVEN a decision with `a5_throw` = 0 and `a3_attack` = 1
- WHEN decoded
- THEN attack pressed is true

#### Scenario: Move mapping unchanged
- GIVEN action indices with move = 0, 1, 2 in three successive decodes
- WHEN decoded
- THEN `move_x` is -1, 0, 1 respectively

#### Scenario: No charged smash
- GIVEN any action vector
- WHEN decoded
- THEN `attack_held` is false

#### Scenario: Invalid action rejected
- GIVEN a vector with a branch index equal to its branch size, or with seven branches
- WHEN decoded
- THEN an error is reported and the resulting intent is neutral

#### Scenario: Pulse fires once
- GIVEN a throw decision with `action_repeat` = N
- WHEN N physics ticks run
- THEN throw pressed is true on exactly one tick

### Requirement: Schema-3 golden fixtures

A committed JSON fixture for schema 3 MUST pair fixed snapshot inputs (including shield, dizzy and bomb states) with expected observation vectors. The v2 fixtures MUST be kept unchanged. The smoke test and the Python side MUST both fail if the v3 layout or normalization changes without the fixture being regenerated.

#### Scenario: Observation parity with v3 fixture
- GIVEN the committed v3 observation fixture
- WHEN the v3 schema builds observations from its recorded snapshots
- THEN each result equals the expected vector within 1e-6

#### Scenario: Python parity
- GIVEN the same v3 fixture
- WHEN the Python golden check runs
- THEN the Python-side layout agrees with the fixture

#### Scenario: v2 fixtures untouched
- GIVEN the change applied
- WHEN the v2 fixtures are compared with the base commit
- THEN they are byte-identical

### Requirement: Missing schema-3 keys reported

If a snapshot key required by schema 3 is absent at runtime, the v3 schema MUST report an error naming the key rather than silently substituting zero.

#### Scenario: Missing shield key
- GIVEN a snapshot lacking the shield meter key
- WHEN the v3 schema builds an observation
- THEN an error naming the missing key is reported
### Requirement: Schema-4 observation layout

The v4 observation MUST be a flat float vector of fixed order and fixed `obs_dim` of 149 (v3's 136 plus 13), built only from `Fighter.get_state_snapshot()` and `Game.get_state_snapshot()`. It MUST contain everything the v3 layout carries, in the same order and normalization, and MUST add: self kit one-hot (4 slots), opponent kit one-hot (4 slots; spare slots reserved for future kits), self chain step (normalized), self link-window-open flag, opponent hitstun left (normalized), combo count dealt (normalized), and hits taken in the current combo (normalized). Every value MUST be normalized into a documented bounded range, clamped and finite (never NaN or infinity). Positions MUST stay Game-local and self-relative where declared. The kit slots MUST be one-hot (exactly one 1.0 among the known kits, all zeros for an unknown kit as a documented sentinel).

#### Scenario: Fixed dimension
- GIVEN any fighter in any match state
- WHEN the v4 observation is built
- THEN its length is 149

#### Scenario: v3 prefix preserved
- GIVEN a fixed state
- WHEN the v3 and v4 observations are built for the same fighter
- THEN the first 136 elements of v4 equal the v3 vector

#### Scenario: Kit one-hot
- GIVEN self is Matilde and the opponent is Rafael
- WHEN the observation is built
- THEN the self kit slots have exactly one 1.0 at Matilde's slot and the opponent slots one 1.0 at Rafael's slot

#### Scenario: Combo features
- GIVEN the opponent in hitstun with half its normalizing maximum left and 3 hits taken
- WHEN the observation is built
- THEN the opponent hitstun slot is about 0.5 and the combo slots reflect the counts, all within their bounds

#### Scenario: Unknown kit sentinel
- GIVEN a fighter with the default (unknown) kit
- WHEN the observation is built
- THEN its kit slots are all zero and the length is unchanged

#### Scenario: Bounded and finite
- GIVEN a fighter far outside the stage, at 999% damage, with maximum velocity, bombs, and an extreme combo count
- WHEN the observation is built
- THEN every element is finite and inside its documented range

#### Scenario: Game offset invariance
- GIVEN two Games identical in state but at different global offsets
- WHEN observations are built for the same fighter in each
- THEN the vectors are equal

#### Scenario: Read-only
- GIVEN an observation is built twice with no intervening frame
- WHEN the results and the state are compared
- THEN the vectors are equal and no state changed

#### Scenario: Training and inference identical
- GIVEN a live Game in a fixed state
- WHEN the v4 observation is built via `PlayerAIController` and via `PolicyController`
- THEN both vectors are element-wise equal

### Requirement: Schema-4 action layout and decode

The v4 action space MUST keep the v3 MultiDiscrete layout (`nvec` = [3,3,2,5,2,2,2,2], eight branches `a0_move` to `a7_dash`) unchanged, and the v4 decoder MUST decode identically to v3 (exclusive throw, `attack_held` false, out-of-range or wrong-length vectors rejected with a neutral intent). A decoded attack pulse MUST be one press per decision (the attack buffer owns chaining), so one decision never chains two steps. `get_action_space()` MUST report the layout and it MUST be serialized identically into `bvs.json`.

#### Scenario: Layout unchanged
- GIVEN schema 4
- WHEN `get_action_space()` is read
- THEN it lists eight branches with sizes 3, 3, 2, 5, 2, 2, 2, 2 named `a0_move` to `a7_dash`

#### Scenario: Decode parity with v3
- GIVEN any valid action vector
- WHEN decoded with the v3 and v4 decoders
- THEN the resulting intents are equal

#### Scenario: Pulse fires once
- GIVEN an attack decision with `action_repeat` = N
- WHEN N physics ticks run
- THEN attack pressed is true on exactly one tick, so a decision starts at most one chain step

#### Scenario: No charged smash
- GIVEN any action vector
- WHEN decoded
- THEN `attack_held` is false

#### Scenario: Invalid action rejected
- GIVEN a vector with a branch index equal to its branch size, or with seven branches
- WHEN decoded
- THEN an error is reported and the resulting intent is neutral

### Requirement: Schema-4 golden fixtures

A committed JSON fixture for schema 4 MUST pair fixed snapshot inputs (including kit one-hot, chain, link window, hitstun and combo states) with expected observation vectors. The v2 and v3 fixtures MUST be kept byte-identical. The smoke test and the Python side MUST both fail if the v4 layout or normalization changes without the fixture being regenerated.

#### Scenario: Observation parity with v4 fixture
- GIVEN the committed v4 observation fixture
- WHEN the v4 schema builds observations from its recorded snapshots
- THEN each result equals the expected vector within 1e-6

#### Scenario: Python parity
- GIVEN the same v4 fixture
- WHEN the Python golden check runs
- THEN the Python-side layout agrees with the fixture

#### Scenario: v2 and v3 fixtures untouched
- GIVEN the change applied
- WHEN the v2 and v3 fixtures are compared with the base commit
- THEN they are byte-identical

### Requirement: Missing schema-4 keys reported

If a snapshot key required by schema 4 is absent at runtime, the v4 schema MUST report an error naming the key rather than silently substituting zero.

#### Scenario: Missing combo key
- GIVEN a snapshot lacking the hitstun-left key
- WHEN the v4 schema builds an observation
- THEN an error naming the missing key is reported

