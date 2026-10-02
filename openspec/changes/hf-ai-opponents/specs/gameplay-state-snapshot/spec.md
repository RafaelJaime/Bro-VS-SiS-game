# Delta for Gameplay State Snapshot

## MODIFIED Requirements

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

## ADDED Requirements

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
