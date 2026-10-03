# Delta for CPU Opponent

All new values live in the `CpuDifficulty` Resource (tunable data, not code). The CPU is tuned to be fun against humans, not to beat the model.

## MODIFIED Requirements

### Requirement: Scripted bot behaviours

`ScriptedController` MUST emit intent only (no direct fighter manipulation) and MUST: approach the opponent, punch when in range, block incoming attacks, pick up and throw food, and recover to the stage when off-stage. It MUST respect the shield meter: it MUST release block before the shield breaks (at a per-difficulty shield-release threshold) and MUST NOT hold the shield indefinitely. It SHOULD read state via `get_state_snapshot()`. The larger pickup reach from `food-fight-items` MUST be used when fetching food.
(Previously: no shield-meter awareness; pickup used the narrower reach.)

#### Scenario: Approach and punch
- GIVEN a CPU fighter and a human opponent on the floor
- WHEN the match is live
- THEN the CPU moves toward the opponent and punches when within range

#### Scenario: Block
- GIVEN an opponent attack is imminent in range
- WHEN the CPU's block probability roll succeeds
- THEN the CPU emits block intent

#### Scenario: Releases before break
- GIVEN a CPU holding the shield whose meter falls to its release threshold
- WHEN the next decision is made
- THEN it emits no block intent until the meter recovers above the threshold or a new attack is imminent with meter above threshold

#### Scenario: Never holds forever
- GIVEN a CPU facing a passive opponent for 20 s
- WHEN its shield hold time is measured
- THEN its shield never breaks from its own continuous hold

#### Scenario: Food pickup and throw
- GIVEN food exists on the stage and the CPU holds none
- WHEN the CPU decides to fetch food
- THEN it moves to the food, picks it up, and later throws it toward the opponent

#### Scenario: Edge recovery
- GIVEN the CPU is airborne below or beside the stage edge
- WHEN it has jumps left
- THEN it moves toward the stage and uses its double jump to return to the floor; it MUST NOT stay stuck moving away or idling

### Requirement: Three difficulty levels

Easy, Normal, and Hard MUST differ by tunable reaction delay, action accuracy, and block/throw probability, plus the new combat-depth values (shield-release threshold, punish-dizzy probability, food-pressure probability, bomb-dodge), defined in a difficulty `Resource`. Defaults (tunable): Easy slowest and least accurate; Hard fastest and most accurate; Normal between. Difficulty ordering MUST be preserved for the new values: punish-dizzy and food-pressure probabilities satisfy Easy <= Normal <= Hard (Easy MAY be zero).
(Previously: only reaction delay, accuracy and block/throw probability were differentiated.)

#### Scenario: Ordered difficulty
- GIVEN the three difficulty resources
- WHEN their reaction delay and accuracy are compared
- THEN Easy delay > Normal delay > Hard delay, and Easy accuracy < Normal < Hard

#### Scenario: Ordered combat-depth values
- GIVEN the three difficulty resources
- WHEN punish-dizzy and food-pressure probabilities are compared
- THEN Easy <= Normal <= Hard for each, with Normal < Hard for at least one

#### Scenario: Data-driven
- GIVEN a difficulty value is edited in its Resource
- WHEN a match starts
- THEN bot behavior reflects it with no script change

## ADDED Requirements

### Requirement: Punish dizzy opponents

At Normal and Hard, when the opponent is dizzy and within reach, the CPU MUST attack it with a probability given by the difficulty's punish-dizzy value, after its reaction delay. Easy MUST NOT systematically punish dizzy (probability may be 0 or low, and Easy keeps its slower reaction).

#### Scenario: Hard punishes
- GIVEN CPU Hard and a dizzy opponent in range with probability 1.0 in a test resource
- WHEN the reaction delay elapses
- THEN the CPU emits an attack intent

#### Scenario: Normal punishes
- GIVEN CPU Normal and a dizzy opponent in range
- WHEN rolled over many trials
- THEN the CPU attacks at a rate consistent with its punish-dizzy value, and greater than zero

#### Scenario: Easy does not systematically punish
- GIVEN CPU Easy and a dizzy opponent in range
- WHEN rolled over many trials
- THEN its punish rate is no higher than Normal's

### Requirement: Pressure shields with food

At Normal and Hard, when the opponent is shielding and the CPU holds food (preferring heavy food), the CPU MUST throw it with a probability given by the food-pressure value. At Normal and Hard it SHOULD fetch heavy food when the opponent turtles. It MUST NOT shield-pressure with punches indefinitely when food is available.

#### Scenario: Throws at a shielding opponent
- GIVEN CPU Hard holding heavy food and an opponent shielding in range
- WHEN the decision is made with pressure probability 1.0 in a test resource
- THEN the CPU emits throw intent

#### Scenario: Fetches food against a turtle
- GIVEN CPU Normal, food on stage, the CPU holds none and the opponent has shielded for several seconds
- WHEN the CPU decides
- THEN it moves toward food rather than only punching

### Requirement: Bomb dodge

At Hard, the CPU MUST avoid falling bombs: when a bomb is predicted to land on its position, it MUST move out of the impact column, and MAY use the air dodge when airborne. Normal and Easy are not required to dodge.

#### Scenario: Hard leaves the impact column
- GIVEN CPU Hard on the floor and a bomb falling onto its position
- WHEN the bomb is within a tunable lookahead time
- THEN the CPU emits move intent out of the impact column before impact

#### Scenario: Hard survives more bombs than Easy
- GIVEN sudden death in CPU Hard vs CPU Hard and CPU Easy vs CPU Easy over equal trials
- WHEN time to first bomb hit is compared
- THEN Hard's mean time is greater

### Requirement: Easy restrictions preserved under combat depth

The "Directional and recovery use (S5)" and "Single-player playable" requirements are unchanged and MUST keep holding with the new behaviours: Easy MUST NOT gain directional aim or special intent from shield, food or bomb logic, and no difficulty MAY charge smash attacks.

#### Scenario: Easy emits no aim or special in new situations
- GIVEN CPU Easy
- WHEN a shield, a dizzy opponent, food pressure and falling bombs all occur
- THEN it never emits directional aim or special intent

#### Scenario: Taps only
- GIVEN any difficulty punishing a dizzy opponent
- WHEN the CPU attacks
- THEN attack held never exceeds the tap threshold
