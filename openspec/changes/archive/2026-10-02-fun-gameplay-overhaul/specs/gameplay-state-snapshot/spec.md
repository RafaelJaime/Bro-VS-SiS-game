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

The accessor MUST be documented (code comment) as unversioned and not a schema, and MUST NOT carry a version field. `get_obs()`/`get_action_space()` MUST remain unchanged.

#### Scenario: Documentation check
- GIVEN the accessor source
- WHEN reviewed
- THEN a comment states it is unversioned and not a schema

#### Scenario: Open dictionary
- GIVEN a new key is later added
- WHEN existing consumers read the dictionary
- THEN they are unaffected
