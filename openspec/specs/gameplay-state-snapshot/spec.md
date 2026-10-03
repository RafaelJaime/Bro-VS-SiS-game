# Gameplay State Snapshot Specification

## Purpose

Read-only plain-dictionary accessors for gameplay state. They are documented as unversioned and NOT a schema; the future AI schema module reads them.

## Requirements

### Requirement: Fighter snapshot

`Fighter.get_state_snapshot()` MUST return a plain Dictionary with: position local to the owning Game, velocity, facing, on_floor, damage %, stocks, held food, FSM state, cooldowns, and jumps left. It MUST NOT mutate state.

#### Scenario: Fields present
- GIVEN a live fighter
- WHEN the snapshot is requested
- THEN all listed keys are present

#### Scenario: Local position
- GIVEN a Game at a non-zero global offset
- WHEN the snapshot is taken
- THEN position is relative to the Game, not global

#### Scenario: Read-only
- GIVEN a snapshot is taken twice with no intervening frame
- WHEN the results are compared
- THEN they are equal and fighter state is unchanged

### Requirement: Game snapshot

`Game.get_state_snapshot()` MUST return a Dictionary with food positions (Game-local) and the timer, and MAY include the fighters' snapshots.

#### Scenario: Food positions
- GIVEN two foods on stage
- WHEN the Game snapshot is taken
- THEN it lists both positions

#### Scenario: Timer
- GIVEN a running match
- WHEN the snapshot is taken
- THEN the timer value is included

### Requirement: S5 snapshot fields

With S5, the Fighter snapshot MUST add charge level (0..1), recovery available, and last attack direction; the Game snapshot MUST add camera center and zoom.

#### Scenario: Charging
- GIVEN a fighter charged halfway
- WHEN the snapshot is taken
- THEN charge level is about 0.5

#### Scenario: Camera fields
- GIVEN the match camera is active
- WHEN the Game snapshot is taken
- THEN it includes camera center and zoom

### Requirement: Documented as unversioned, not a schema

The accessor MUST be documented (code comment) as unversioned and not a schema, and MUST NOT carry a version field. The versioned contract is the `ai-schema` module, which is the snapshot's consumer and carries the version. The snapshot MUST include every key listed as required by the schema (see "Schema-required keys"); the previous clause freezing `get_obs()`/`get_action_space()` no longer applies.
(Previously: also required `get_obs()`/`get_action_space()` to remain unchanged.)

#### Scenario: Documentation check
- GIVEN the accessor source
- WHEN reviewed
- THEN a comment states it is unversioned and not a schema

#### Scenario: Open dictionary
- GIVEN a new key is later added
- WHEN existing consumers read the dictionary
- THEN they are unaffected

#### Scenario: No version field
- GIVEN a Fighter or Game snapshot
- WHEN its keys are listed
- THEN no version key is present

### Requirement: Schema-required keys

Beyond the fighter and Game keys already required, the Game snapshot MUST include stage edges (or platform extents) in Game-local coordinates, and every snapshot key read by `bvs-schema-2` MUST be present on both fighters and the Game. Adding these keys MUST NOT change gameplay behavior or any existing key's value, and MUST NOT mutate state.

#### Scenario: Stage edges present
- GIVEN a Game
- WHEN its snapshot is taken
- THEN stage edge values are present and Game-local

#### Scenario: Offset invariance of new keys
- GIVEN a Game at a non-zero global offset
- WHEN the snapshot is taken
- THEN the stage edge values equal those of the same Game at the origin

#### Scenario: Schema keys complete
- GIVEN the list of keys read by schema 2
- WHEN each is looked up in the fighter and Game snapshots
- THEN every one is present

#### Scenario: Existing keys unchanged
- GIVEN the change applied
- WHEN the previously required keys are compared to baseline values for a fixed state
- THEN they are identical

## UNCHANGED Requirements

Fighter snapshot, Game snapshot, and S5 snapshot fields are unchanged by this change.
