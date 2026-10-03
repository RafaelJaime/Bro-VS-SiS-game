# Delta for AI Schema

Schema 2 stays frozen: the schema-2 observation layout, discrete action layout, decode rules, action repeat, snapshot-key requirement and golden fixtures requirements are unchanged, and the v2 module, decoder and fixtures MUST stay byte-identical. Schema 3 is added alongside it as the current playable version.

## MODIFIED Requirements

### Requirement: Schema version registry and constant

The system MUST expose a registry mapping schema version to its module, registering both version 2 (frozen) and version 3 (current), and `HubModel.BVS_SCHEMA_VERSION` MUST equal `3`. Looking up an unregistered version MUST return an explicit "unsupported" result, not a default layout. Adding a future version MUST NOT change how versions 2 or 3 build observations or decode actions.
(Previously: `HubModel.BVS_SCHEMA_VERSION` equaled 2 and only version 2 was registered; the extensibility scenario used a stub registered as version 3.)

#### Scenario: Version constant
- GIVEN the change applied
- WHEN `HubModel.BVS_SCHEMA_VERSION` is read
- THEN it is `3`

#### Scenario: Both versions registered
- GIVEN the registry
- WHEN versions 2 and 3 are queried
- THEN each returns its own module with its own `obs_dim`

#### Scenario: Unknown version
- GIVEN a sidecar declaring `schema_version` 99
- WHEN the registry is queried for 99
- THEN it reports unsupported and no layout is returned

#### Scenario: Extensibility
- GIVEN a test-only stub registered as version 4 with a different `obs_dim`
- WHEN versions 2 and 3 are used for building observations and decoding
- THEN results are identical to those without the stub registered

#### Scenario: Schema 2 frozen
- GIVEN the change applied
- WHEN the schema-2 module, decoder and fixtures are compared with the base commit
- THEN they are byte-identical, and the `schema_v2` smoke checks that exercise the frozen v2 module, decoder and fixtures pass; only assertions about the CURRENT schema version or the BUNDLED model's schema (for example the registry check that asserts the current version and registers a stub) are moved to the current schema (amendment, orchestrator decision)

#### Scenario: Version switch is gated
- GIVEN the retrained model has not passed every acceptance gate
- WHEN the change is finalized
- THEN `CURRENT_VERSION` stays 2 and the v2 bundled model ships; the switch of `CURRENT_VERSION` (and `HubModel.BVS_SCHEMA_VERSION`) to 3 happens only in the same commit that bundles the passing v3 model

## ADDED Requirements

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
