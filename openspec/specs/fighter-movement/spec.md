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

Jump and Fall states MUST allow air punch, air throw, and air block (via `available_actions`).

#### Scenario: Air punch
- GIVEN an airborne fighter
- WHEN attack is pressed
- THEN a punch occurs and the fighter returns to the appropriate air state

#### Scenario: Air throw
- GIVEN an airborne fighter holding food
- WHEN throw is pressed
- THEN the food is thrown

#### Scenario: Air block
- GIVEN an airborne fighter
- WHEN block is held
- THEN the fighter blocks until released

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
