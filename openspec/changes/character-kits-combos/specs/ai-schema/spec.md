# Delta for AI Schema

Schemas 2 and 3 are frozen by this change: their modules, decoders and fixtures MUST stay byte-identical to the base commit. The only permitted edit to the frozen smoke checks (`schema_v2.gd`, `schema_v3.gd`) is moving their registry test stub from version 4 to version 5.

## ADDED Requirements

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

## MODIFIED Requirements

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
