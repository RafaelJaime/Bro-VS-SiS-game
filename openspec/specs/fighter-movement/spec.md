# Fighter Movement Specification

## Purpose

Snappier, forgiving platform movement with air actions, using existing frames only. All numbers are tunable exported defaults to be validated in manual playtest.

## Requirements

### Requirement: Snappy jump with short hop

Jump MUST use higher gravity and jump velocity than baseline (baseline apex ~360 px at gravity 500) so apex and hang time are visibly shorter. Releasing jump early MUST cut the ascent (short hop).

#### Scenario: Full hop
- GIVEN a grounded fighter
- WHEN jump is held through the apex
- THEN apex height and air time are clearly lower than baseline

#### Scenario: Short hop
- GIVEN a fighter ascending
- WHEN jump is released early
- THEN upward velocity is cut and the apex is lower than a full hop

### Requirement: Coyote time and jump buffer

A fighter MUST be able to jump up to ~0.1 s after leaving a ledge (coyote), and a jump pressed up to ~0.1 s before landing MUST execute on landing (buffer). Both durations are tunable.

#### Scenario: Coyote jump
- GIVEN a fighter walked off a platform edge 0.05 s ago without jumping
- WHEN jump is pressed
- THEN a ground jump occurs and the double jump is not consumed

#### Scenario: Coyote expired
- GIVEN 0.3 s since leaving the edge
- WHEN jump is pressed
- THEN the double jump is used instead

#### Scenario: Buffered jump
- GIVEN a falling fighter
- WHEN jump is pressed 0.05 s before touching the floor
- THEN the fighter jumps immediately on landing

### Requirement: Double jump

A fighter MUST have exactly one extra jump per airtime, restored on landing.

#### Scenario: Double jump once
- GIVEN an airborne fighter with the extra jump available
- WHEN jump is pressed twice in the air
- THEN the first press jumps again and the second does nothing

#### Scenario: Restored on landing
- GIVEN the double jump was used
- WHEN the fighter lands
- THEN the extra jump is available again

### Requirement: Air actions

Jump and Fall states MUST allow air punch, air throw, and air dodge (via `available_actions`). The air punch set MUST include the kit's air jab (single hit for Rafael, 2-hit chain for Matilde, one press per step) and the down-air spike. Block intent in the air MUST trigger an air dodge, not a sustained shield (see `fighter-shield`). While holding food, air throw keeps the priority defined in `food-fight-items`.
(Previously: Jump and Fall states allowed air punch, air throw and air dodge, with no kit-defined air jab or down-air spike.)

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

#### Scenario: Kit air jab
- GIVEN Matilde airborne and Rafael airborne, each pressing neutral attack twice inside the link window
- WHEN both presses are processed
- THEN Matilde's second press starts a second air jab step and Rafael's second press starts a new single air jab

#### Scenario: Down-air spike
- GIVEN an airborne fighter pressing down plus attack
- WHEN it connects
- THEN the victim is sent downward with the kit's spike knockback
### Requirement: Dash availability

Dash MUST be usable from Idle, Run, and air, with one air dash per airtime (restored on landing). The double-tap trigger MUST stay and no new binding is added for dash.

#### Scenario: Ground dash
- GIVEN Idle or Run
- WHEN a direction is double-tapped
- THEN the fighter dashes

#### Scenario: One air dash
- GIVEN an airborne fighter
- WHEN double-tap is performed twice in the same airtime
- THEN the first dashes and the second is ignored

#### Scenario: Air dash restored
- GIVEN an air dash was used
- WHEN the fighter lands and becomes airborne again
- THEN an air dash is available
### Requirement: Kit-driven movement values

Run speed, jump velocity and double-jump velocity MUST come from the fighter's kit (see `fighter-kits`). The jump behavior rules (short hop, coyote time, jump buffer, one double jump per airtime) MUST remain unchanged for every kit.

#### Scenario: Run speed per kit
- GIVEN Rafael and Matilde running on the floor for 1 s
- WHEN their horizontal speeds are measured
- THEN Rafael's is 270 and Matilde's is 340 (within tolerance)

#### Scenario: Jump velocity per kit
- GIVEN each fighter jumps from the floor with jump held
- WHEN initial vertical velocity is read
- THEN Rafael's is -820 and Matilde's is -900, and the double jump is -720 and -780

#### Scenario: Jump rules unchanged
- GIVEN Matilde walks off a ledge 0.05 s ago
- WHEN jump is pressed
- THEN a ground jump occurs and the double jump is not consumed

### Requirement: Air attack keeps momentum

An air punch MUST NOT stop or brake the fighter: the jump or fall's vertical and horizontal momentum and air control MUST continue during the attack. (Already delivered on this branch by `odd/tasks/shield-spam.md` T2; recorded here so the spec matches the retrain target.)

#### Scenario: Apex and distance preserved
- GIVEN a full jump with a punch pressed in the air versus the same jump with no punch
- WHEN apex height and horizontal distance are compared
- THEN each is within 5%

#### Scenario: Punch still hits
- GIVEN an airborne punch with an overlapping target
- WHEN the active frames run
- THEN the target takes the hit

