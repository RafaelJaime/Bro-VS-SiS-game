# Delta for CPU Opponent

## ADDED Requirements

### Requirement: Combo behavior by difficulty

The bot MUST use attacks according to its difficulty, values tunable in the difficulty `Resource` (chain and follow-up probabilities):
- Easy: single jab presses only (no chaining, no launcher follow-ups).
- Normal: jab chains (one press per step).
- Hard: jab chains plus launcher follow-ups (for example up launcher into an air jab for the Matilde kit).
The bot MUST queue chain presses through the attack input buffer so its 0.12 to 0.40 s decision interval does not prevent chaining. The bot MUST NOT hold attack to chain.

#### Scenario: Easy single jab
- GIVEN CPU Easy attacking a target in range for 20 s
- WHEN chain steps are counted
- THEN no jab step 2 or launcher follow-up is ever emitted

#### Scenario: Normal chains
- GIVEN CPU Normal in range of a target at low damage over many trials
- WHEN combo lengths are recorded
- THEN 2+ hit combos occur at a rate greater than zero

#### Scenario: Hard follows up launchers
- GIVEN CPU Hard with the Matilde kit and the target at low damage
- WHEN it lands the up launcher
- THEN it emits an air jab follow-up within the victim's hitstun at a rate greater than Normal's over many trials

#### Scenario: Buffer bridges decision interval
- GIVEN a CPU decision interval of 0.40 s
- WHEN a chain press is queued during step 1's endlag
- THEN the press fires on the first actionable tick

#### Scenario: Difficulty ordering of combos
- GIVEN the three difficulty resources
- WHEN chain and follow-up probabilities are compared
- THEN Easy <= Normal <= Hard with Normal < Hard for at least one

#### Scenario: Never holds attack
- GIVEN any difficulty chaining
- WHEN attack held is measured
- THEN it never exceeds the tap threshold

### Requirement: CPU respects shield drop lag

The bot MUST treat `ShieldDrop` as a no-action state and MUST NOT toggle the shield repeatedly between attacks. It MUST release block through its shield-release rules without exceeding the shield raise cost budget.

#### Scenario: No actions in drop lag
- GIVEN a CPU in `ShieldDrop`
- WHEN its decision runs
- THEN it emits no action intent until the lag ends

#### Scenario: Shield raises are bounded
- GIVEN CPU Hard vs CPU Hard for 60 s
- WHEN shield raises per fighter-minute are measured
- THEN they are at most the threshold recorded in design (see `rl-training-pipeline`)

## MODIFIED Requirements

### Requirement: Easy restrictions preserved under combat depth

The "Directional and recovery use (S5)" and "Single-player playable" requirements are unchanged and MUST keep holding with the new behaviours: Easy MUST NOT gain directional aim or special intent from shield, food, bomb or combo logic, and no difficulty MAY charge smash attacks. Easy's combat is single jab only (see "Combo behavior by difficulty"), and the CPU's use of the attack buffer MUST NOT turn a tap into a held attack.
(Previously: restrictions covered shield, food and bomb logic only; combos did not exist.)

#### Scenario: Easy emits no aim or special in new situations
- GIVEN CPU Easy
- WHEN a shield, a dizzy opponent, food pressure, falling bombs and an open combo window all occur
- THEN it never emits directional aim or special intent

#### Scenario: Taps only
- GIVEN any difficulty punishing a dizzy opponent or chaining
- WHEN the CPU attacks
- THEN attack held never exceeds the tap threshold

#### Scenario: Easy has no chain
- GIVEN CPU Easy and an open link window
- WHEN its decision runs
- THEN it does not emit a chain press
