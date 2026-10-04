# Delta for Gameplay State Snapshot

## ADDED Requirements

### Requirement: Kit and combo snapshot fields

`Fighter.get_state_snapshot()` MUST add: kit id (integer slot; Rafael and Matilde have distinct values; unknown or default kit has a documented value), chain step (0 when not in a chain, otherwise the current step), link window open (bool), hitstun left (ticks or seconds of match time, 0 when not in hitstun), combo count dealt (hits of the combo currently being dealt by this fighter, 0 when none) and hits taken in the current combo (0 when not in a combo). The values MUST be read-only and MUST NOT mutate state. They MUST be tick-derived (not wall time).

#### Scenario: Fields present
- GIVEN a live fighter
- WHEN the snapshot is requested
- THEN kit id, chain step, link window open, hitstun left, combo count dealt and hits taken are present

#### Scenario: Kit id by character
- GIVEN Rafael and Matilde in a match
- WHEN snapshots are taken
- THEN the kit ids differ

#### Scenario: Mid-chain state
- GIVEN a fighter whose step 1 connected and the link window is open
- WHEN the snapshot is taken
- THEN chain step is 1 and link window open is true

#### Scenario: Idle state
- GIVEN a fighter not attacking and not in hitstun
- WHEN the snapshot is taken
- THEN chain step is 0, link window open is false, hitstun left is 0 and combo counts are 0

#### Scenario: Combo counts
- GIVEN a combo of 3 hits
- WHEN snapshots are taken for attacker and victim
- THEN the attacker's combo count dealt is 3 and the victim's hits taken is 3

#### Scenario: Read-only
- GIVEN a snapshot taken twice with no intervening frame
- WHEN the results are compared
- THEN they are equal

### Requirement: Schema-4 required keys

Every snapshot key read by `bvs-schema-4` MUST be present on both fighters and the Game, in addition to the schema-2 and schema-3 keys. Adding these keys MUST NOT change gameplay behavior or any existing key's value and MUST NOT mutate state. If a required key is absent at runtime, the schema MUST report an error naming it (see `ai-schema`).

#### Scenario: Schema keys complete
- GIVEN the list of keys read by schema 4
- WHEN each is looked up in the fighter and Game snapshots
- THEN every one is present

#### Scenario: Existing keys unchanged
- GIVEN the change applied
- WHEN the previously required keys are compared to baseline values for a fixed state
- THEN they are identical

#### Scenario: Schema 2 and 3 keys still present
- GIVEN the lists of keys read by schema 2 and schema 3
- WHEN each is looked up
- THEN every one is still present
