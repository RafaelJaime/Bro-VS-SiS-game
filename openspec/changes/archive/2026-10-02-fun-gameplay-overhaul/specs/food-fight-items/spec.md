# Food Fight Items Specification

## Purpose

Correct food spawning and pickup behavior (F2, F3, F8) and distinguishable SFX using existing sounds only. Per-food effects are out of scope.

## Requirements

### Requirement: Spawn coordinates local to the owning Game (F2)

The food spawner MUST compute spawn positions in coordinates local to its owning `Game`, so multiple Game instances (e.g. training) do not spawn food at global offsets.

#### Scenario: Offset Game
- GIVEN a Game node placed at a non-zero global position
- WHEN food spawns
- THEN it appears inside that Game's stage area

#### Scenario: Two Games
- GIVEN two Game instances
- WHEN each spawns food
- THEN each food lies within its own Game's bounds

### Requirement: Null-guard in training rows (F3)

`game.gd` MUST null-guard training-row access so missing nodes do not error.

#### Scenario: Missing row
- GIVEN a scene without training rows
- WHEN `game.gd` runs
- THEN no null-reference error occurs

### Requirement: Pickup collision isolation (F8)

`FoodPickup` MUST NOT be on the fighter collision layer: it MUST NOT block fighters and MUST NOT rest on their heads. Pickup by fighters MUST still work.

#### Scenario: Walk through
- GIVEN a food pickup on the floor
- WHEN a fighter walks into it
- THEN the fighter is not blocked and picks it up

#### Scenario: Falling food
- GIVEN food falls onto a fighter
- WHEN it overlaps the fighter's head
- THEN it does not land on or ride the head

### Requirement: SFX pitch variation

`Sfx` MUST apply random pitch within a per-event band reusing the existing 3 sounds, with bands for at least pickup, throw, jump, and KO so cues are audibly distinct. No new audio assets.

#### Scenario: Distinct bands
- GIVEN pickup and KO events
- WHEN each plays
- THEN pitch falls in that event's band and the bands differ

#### Scenario: Random variation
- GIVEN the same event fires repeatedly
- WHEN pitches are observed
- THEN they vary within the band

#### Scenario: No new assets
- GIVEN the change applied
- WHEN `assets/` is diffed
- THEN no new files exist
