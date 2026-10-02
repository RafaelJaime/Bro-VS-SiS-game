# Match Flow Specification

## Purpose

A complete match loop: selection, countdown, sudden death, rematch, and pause. Durations are tunable defaults.

## Requirements

### Requirement: Pre-match countdown

Every match MUST begin with a "3-2-1-GO" countdown using the existing `Label`/fonts. Fighters MUST NOT act (and the match timer MUST NOT run) until GO.

#### Scenario: Countdown blocks input
- GIVEN a match just loaded
- WHEN the countdown shows 3, 2, or 1
- THEN fighter input is ignored and the match timer is stopped

#### Scenario: GO starts the match
- GIVEN the countdown reaches GO
- WHEN GO displays
- THEN input is accepted and the timer starts

#### Scenario: Rematch countdown
- GIVEN a rematch begins
- WHEN it loads
- THEN the countdown runs again

### Requirement: Sudden death

If the timer expires with tied results, both fighters MUST be set to 1 stock, the timer MUST be disabled, and the next KO MUST end the match.

#### Scenario: Timeout tie
- GIVEN timer expiry with equal stocks
- WHEN timeout is processed
- THEN both have 1 stock and the timer is off

#### Scenario: Timeout non-tie
- GIVEN timer expiry with unequal stocks
- WHEN timeout is processed
- THEN the fighter with more stocks wins and no sudden death occurs

#### Scenario: Sudden death KO
- GIVEN sudden death
- WHEN either fighter is KO'd
- THEN the match ends with the other as winner

### Requirement: Instant rematch

Game over MUST offer an instant rematch with the same characters and controllers. Character select MUST remain reachable.

#### Scenario: Rematch
- GIVEN the game over screen
- WHEN rematch is chosen
- THEN a new match starts with the same selections without passing character select

#### Scenario: Back to select
- GIVEN the game over screen
- WHEN character select is chosen
- THEN character select opens

### Requirement: Pause toggle

Esc MUST open pause when playing and close it when paused.

#### Scenario: Open and close
- GIVEN a live match
- WHEN Esc is pressed twice
- THEN the first pauses and the second resumes

#### Scenario: During countdown
- GIVEN the countdown is running
- WHEN Esc is pressed
- THEN pause behavior is consistent (countdown pauses, then resumes with no skipped digits)

### Requirement: Controller and difficulty selection UI

Character select MUST let each player choose Human or CPU (Easy/Normal/Hard). The existing ONNX/HF option MUST stay where it is and route via `PolicyController`.

#### Scenario: One player vs CPU
- GIVEN character select
- WHEN P1 = Human and P2 = CPU Hard
- THEN the match starts with P2 on a scripted Hard controller

#### Scenario: Two humans
- GIVEN both players = Human
- WHEN the match starts
- THEN both are human controlled

#### Scenario: Selection persists
- GIVEN a rematch
- WHEN it starts
- THEN controller and difficulty choices are retained

### Requirement: Instructions text and typo

The "Intructions" typo MUST be corrected everywhere. The instructions MUST describe double jump and air actions, and (with S5) charge, directional attacks, recovery, and the up/down keys.

#### Scenario: Typo audit
- GIVEN the change applied
- WHEN project text is searched for "Intructions"
- THEN no matches remain

#### Scenario: Controls text
- GIVEN the instructions screen
- WHEN viewed
- THEN the new moves and bindings are listed
