# CPU Opponent Specification

## Purpose

A scripted bot emitting `FighterIntent` so single player works without any ONNX/HF model. Difficulty values are tunable defaults held in data (Resource), not code.

## Requirements

### Requirement: Scripted bot behaviours

`ScriptedController` MUST emit intent only (no direct fighter manipulation) and MUST: approach the opponent, punch when in range, block incoming attacks, pick up and throw food, and recover to the stage when off-stage. It SHOULD read state via `get_state_snapshot()`.

#### Scenario: Approach and punch
- GIVEN a CPU fighter and a human opponent on the floor
- WHEN the match is live
- THEN the CPU moves toward the opponent and punches when within range

#### Scenario: Block
- GIVEN an opponent attack is imminent in range
- WHEN the CPU's block probability roll succeeds
- THEN the CPU emits block intent

#### Scenario: Food pickup and throw
- GIVEN food exists on the stage and the CPU holds none
- WHEN the CPU decides to fetch food
- THEN it moves to the food, picks it up, and later throws it toward the opponent

#### Scenario: Edge recovery
- GIVEN the CPU is airborne below or beside the stage edge
- WHEN it has jumps left
- THEN it moves toward the stage and uses its double jump to return to the floor; it MUST NOT stay stuck moving away or idling

### Requirement: Three difficulty levels

Easy, Normal, and Hard MUST differ by tunable reaction delay, action accuracy, and block/throw probability, defined in a difficulty `Resource`. Defaults (tunable): Easy slowest and least accurate; Hard fastest and most accurate; Normal between.

#### Scenario: Ordered difficulty
- GIVEN the three difficulty resources
- WHEN their reaction delay and accuracy are compared
- THEN Easy delay > Normal delay > Hard delay, and Easy accuracy < Normal < Hard

#### Scenario: Data-driven
- GIVEN a difficulty value is edited in its Resource
- WHEN a match starts
- THEN bot behavior reflects it with no script change

### Requirement: Directional and recovery use (S5)

At Normal and Hard the bot MAY use directional punches and the up-recovery move. Easy MUST remain unchanged. The bot MUST NOT charge smash attacks.

#### Scenario: Normal uses recovery
- GIVEN S5 applied, CPU Normal is off-stage with recovery available
- WHEN it needs height to return
- THEN it emits the special intent to use up-recovery

#### Scenario: Easy unchanged
- GIVEN CPU Easy
- WHEN any situation occurs
- THEN it never emits directional aim or special intent

#### Scenario: No charging
- GIVEN any difficulty
- WHEN the CPU attacks
- THEN it emits only tap attacks (attack held never exceeds the tap threshold)

### Requirement: Single-player playable

A match vs CPU MUST start from character select with no HF model present.

#### Scenario: CPU match
- GIVEN no `user://Agent*.onnx` and no HF model
- WHEN P1 picks Human and P2 picks CPU Normal
- THEN the match starts and CPU acts without idling
