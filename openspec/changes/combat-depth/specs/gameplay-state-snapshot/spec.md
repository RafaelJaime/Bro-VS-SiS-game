# Delta for Gameplay State Snapshot

Existing keys and values are unchanged. The snapshot stays unversioned and not a schema; new keys are additive.

## ADDED Requirements

### Requirement: Shield and dizzy snapshot fields

`Fighter.get_state_snapshot()` MUST add: shield meter value, shield meter maximum, dizzy flag (bool), dizzy time remaining (seconds of match time, 0 when not dizzy), and air-dodge availability (bool). The values MUST be read-only and MUST NOT mutate state.

#### Scenario: Fields present
- GIVEN a live fighter
- WHEN the snapshot is requested
- THEN shield value, shield maximum, dizzy flag, dizzy time remaining and air-dodge availability are present

#### Scenario: Dizzy reported
- GIVEN a dizzy fighter
- WHEN the snapshot is taken
- THEN the dizzy flag is true, time remaining is positive and shield value is 0

#### Scenario: Not dizzy
- GIVEN a healthy fighter
- WHEN the snapshot is taken
- THEN the dizzy flag is false and time remaining is 0

#### Scenario: Read-only
- GIVEN a snapshot taken twice with no intervening frame
- WHEN the results are compared
- THEN they are equal

### Requirement: Sudden-death and bomb snapshot fields

`Game.get_state_snapshot()` MUST add: a sudden-death phase value (0 not in sudden death, 1 grace, 2 bombs active), the elapsed sudden-death time in seconds of match time (0 outside sudden death), and a list of active bombs each with Game-local position and velocity. All positions MUST be Game-local.

#### Scenario: Not in sudden death
- GIVEN a regulation match
- WHEN the Game snapshot is taken
- THEN the phase is 0, elapsed is 0 and the bomb list is empty

#### Scenario: Grace phase
- GIVEN sudden death within the grace period
- WHEN the snapshot is taken
- THEN the phase is 1, elapsed is positive and the bomb list is empty

#### Scenario: Bombs active
- GIVEN sudden death with two bombs falling
- WHEN the snapshot is taken
- THEN the phase is 2 and the list holds two entries with Game-local position and velocity

#### Scenario: Offset invariance
- GIVEN a Game at a non-zero global offset
- WHEN the snapshot is taken
- THEN the bomb positions equal those of the same Game at the origin

### Requirement: Schema-3 required keys

Every snapshot key read by `bvs-schema-3` MUST be present on both fighters and the Game, in addition to the schema-2 keys. Adding these keys MUST NOT change gameplay behavior or any existing key's value, and MUST NOT mutate state. If a required key is absent at runtime, the schema MUST report an error naming it (see `ai-schema`).

#### Scenario: Schema keys complete
- GIVEN the list of keys read by schema 3
- WHEN each is looked up in the fighter and Game snapshots
- THEN every one is present

#### Scenario: Existing keys unchanged
- GIVEN the change applied
- WHEN the previously required keys are compared to baseline values for a fixed state
- THEN they are identical

#### Scenario: Schema 2 keys still present
- GIVEN the list of keys read by schema 2
- WHEN each is looked up
- THEN every one is still present
