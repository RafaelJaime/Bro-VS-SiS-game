# Delta for Fighter Movement

Snappy jump, coyote and jump buffer, double jump and dash availability are unchanged.

## MODIFIED Requirements

### Requirement: Air actions

Jump and Fall states MUST allow air punch, air throw, and air dodge (via `available_actions`). Block intent in the air MUST trigger an air dodge, not a sustained shield (see `fighter-shield`). While holding food, air throw keeps the priority defined in `food-fight-items`.
(Previously: Jump and Fall states allowed air punch, air throw and a sustained air block held until released.)

#### Scenario: Air punch
- GIVEN an airborne fighter
- WHEN attack is pressed
- THEN a punch occurs and the fighter returns to the appropriate air state

#### Scenario: Air throw
- GIVEN an airborne fighter holding food
- WHEN throw is pressed
- THEN the food is thrown

#### Scenario: Air dodge replaces air block
- GIVEN an airborne fighter with the air dodge available
- WHEN block is pressed
- THEN a brief air dodge with invulnerability occurs, no shield bubble is shown, and the shield meter is unchanged

#### Scenario: One air dodge per airtime
- GIVEN an airborne fighter that already air dodged
- WHEN block is pressed again before landing
- THEN nothing happens

#### Scenario: Air dodge restored
- GIVEN an air dodge was used
- WHEN the fighter lands, grabs the ledge, or is hit
- THEN the air dodge is available again
