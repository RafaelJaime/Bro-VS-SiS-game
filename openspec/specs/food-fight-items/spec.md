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

`Sfx` MUST apply random pitch within a per-event band reusing the existing 3 sounds, with bands for at least pickup, throw, jump, KO, bomb explosion and shield break so cues are audibly distinct. No new audio assets.
(Previously: bands were required for pickup, throw, jump and KO only.)

#### Scenario: Distinct bands
- GIVEN pickup and KO events
- WHEN each plays
- THEN pitch falls in that event's band and the bands differ

#### Scenario: Random variation
- GIVEN the same event fires repeatedly
- WHEN pitches are observed
- THEN they vary within the band

#### Scenario: New event bands
- GIVEN a bomb explosion and a shield break
- WHEN each plays
- THEN each has its own band and its pitch falls inside it

#### Scenario: No new assets
- GIVEN the change applied
- WHEN `assets/` is diffed
- THEN no new files exist
### Requirement: Food beats a neutral punch

Every food weight class MUST deal more damage and more knockback than a neutral punch (reference: punch 8 damage, about 220 knockback). The per-class values MUST live in `FoodCatalog` data. Food MUST NOT pierce the shield: a thrown food that hits a shielding target MUST follow `fighter-shield` (chip, meter drain, reduced knockback).

#### Scenario: Every class out-damages a punch
- GIVEN the food catalog
- WHEN each weight class's damage and knockback are compared with a neutral punch
- THEN every class has strictly greater damage and strictly greater knockback

#### Scenario: Food does not pierce the shield
- GIVEN a shielding target with a non-empty meter
- WHEN thrown food hits it
- THEN the target takes chip damage only, the meter drains, and knockback is reduced

### Requirement: Food shield damage per weight class

Each weight class MUST define a `shield_damage` value. Heavy food MUST break a weakened shield in one hit, and a full shield MUST need more than one heavy hit to break. Light food MUST drain less than heavy food.

#### Scenario: Heavy food breaks a weakened shield
- GIVEN a shielding target whose meter is at or below the heavy `shield_damage`
- WHEN heavy food hits it
- THEN the shield breaks and the target is dizzy

#### Scenario: Full shield survives one heavy hit
- GIVEN a shielding target at full meter
- WHEN one heavy food hits it
- THEN the shield does not break and the meter is positive

#### Scenario: Two heavy hits break a full shield
- GIVEN a shielding target at full meter
- WHEN two heavy foods hit it in succession within the regeneration delay
- THEN the shield breaks

#### Scenario: Ordering by class
- GIVEN the three weight classes
- WHEN their `shield_damage` values are compared
- THEN light is less than or equal to medium, which is less than or equal to heavy, and at least one pair is strictly different

### Requirement: Faster food spawns with a cap

The spawner MUST spawn food at a shorter default interval than before the change, and MUST cap the number of simultaneous foods on stage at a tunable maximum. The interval and the cap MUST be exported tunables. Spawn positions remain Game-local.

#### Scenario: Faster than baseline
- GIVEN default spawner settings
- WHEN the mean spawn interval is compared with the pre-change baseline
- THEN it is shorter

#### Scenario: Cap respected
- GIVEN the cap is N foods and N are on stage
- WHEN the spawn timer fires
- THEN no new food spawns until one is picked up, thrown or removed

### Requirement: Larger, feet-centered pickup reach

The pickup area MUST be larger than before the change (the previous horizontal reach was about 26..70 px from the fighter) and MUST be centered near the fighter's feet so food on the floor is picked up when standing near it, including slightly in front or behind. The reach MUST be a tunable value.

#### Scenario: Wider band
- GIVEN food on the floor at a horizontal distance of 100 px from the fighter
- WHEN the fighter presses pick up
- THEN the fighter picks it up if 100 px is within the configured reach, and the default reach is strictly larger than 70 px

#### Scenario: Feet-centered
- GIVEN food lying on the floor level with the fighter's feet, at 40 px
- WHEN pick up is pressed
- THEN it is picked up

#### Scenario: Out of reach
- GIVEN food beyond the configured reach
- WHEN pick up is pressed
- THEN nothing is picked up

### Requirement: Throw priority while holding food

While a fighter holds food, a throw intent MUST resolve ahead of punch and protect (shield) in action priority. Only recovery, dash and jump MUST still outrank it. This MUST apply to human, scripted and policy controllers alike, including when a punch and a throw are pressed in the same frame.

#### Scenario: Throw beats punch
- GIVEN a fighter holding food
- WHEN attack and throw are pressed in the same frame
- THEN the food is thrown and no punch occurs

#### Scenario: Throw beats protect
- GIVEN a fighter holding food on the floor
- WHEN block and throw are pressed together
- THEN the food is thrown and the shield is not raised that frame

#### Scenario: Recovery, dash and jump still outrank
- GIVEN a fighter holding food
- WHEN throw is pressed together with recovery, dash or jump
- THEN recovery, dash or jump resolves first

#### Scenario: Throw alone is not masked
- GIVEN a fighter holding food and no other intent
- WHEN throw is pressed
- THEN the food is thrown

#### Scenario: No food, no change
- GIVEN a fighter holding no food
- WHEN throw is pressed
- THEN no throw occurs and punch and protect priority is unchanged

### Requirement: Item-identity effects

At least two and at most three item-identity effects MUST exist, defined as data tags in `FoodCatalog`, using existing art and VFX only. At minimum, "hot" items (coffee, soup, stew) MUST show a fire VFX and apply a tunable knockback multiplier greater than 1. Items without a tag MUST behave exactly as their weight class defines. The final list is fixed in design.

#### Scenario: Hot item effect
- GIVEN a hot food (for example soup)
- WHEN it is thrown and hits an unshielded target
- THEN a fire VFX plays and knockback exceeds that of an untagged food of the same weight class

#### Scenario: Untagged item unchanged
- GIVEN an untagged food
- WHEN it hits
- THEN damage and knockback equal its weight-class values

#### Scenario: No new assets
- GIVEN the change applied
- WHEN `assets/` is diffed
- THEN no new files exist

