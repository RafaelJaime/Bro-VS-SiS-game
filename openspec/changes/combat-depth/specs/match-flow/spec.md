# Delta for Match Flow

## MODIFIED Requirements

### Requirement: Sudden death

If the timer expires with tied results, both fighters MUST be set to 1 stock and 300% damage, the timer MUST be disabled, and the next KO MUST end the match. Sudden death MUST escalate through `sudden-death-hazards`: after the grace period, bombs fall at an increasing rate. In real (non-training) matches there MUST be no cap and no time-based resolution rule: the match continues until a fighter is KO'd. If both fighters are KO'd in the same physics tick (a double KO), sudden death MUST restart (both set again to 1 stock and 300%, grace period and escalation reset) instead of ending the match. In training rows only, a tunable safety cap (default about 60 s after sudden death starts) MUST end the episode as a draw for reward purposes and as truncation.
(Previously: sudden death set 1 stock with no damage preset, no escalation, no double-KO rule and no training cap; the match could run forever.)

#### Scenario: Timeout tie
- GIVEN timer expiry with equal stocks
- WHEN timeout is processed
- THEN both have 1 stock and 300% damage and the timer is off

#### Scenario: Timeout non-tie
- GIVEN timer expiry with unequal stocks
- WHEN timeout is processed
- THEN the fighter with more stocks wins and no sudden death occurs

#### Scenario: Sudden death KO
- GIVEN sudden death
- WHEN either fighter is KO'd
- THEN the match ends with the other as winner

#### Scenario: Escalation starts
- GIVEN sudden death with no KO
- WHEN the grace period elapses
- THEN bombs begin to fall

#### Scenario: Real match has no cap
- GIVEN a non-training sudden death that has run 120 s with no KO
- WHEN time continues
- THEN the match is still running, bombs are still falling, and no draw or timeout result is produced

#### Scenario: Double KO restarts sudden death
- GIVEN sudden death
- WHEN both fighters are KO'd in the same physics tick
- THEN the match does not end, both fighters respawn at 1 stock and 300%, and the grace period and escalation restart

#### Scenario: Training safety cap
- GIVEN a training row in sudden death with no KO
- WHEN the training safety cap elapses
- THEN the episode ends as a draw for reward purposes, is flagged truncated, and the row resets

#### Scenario: Hard-cap smoke across forced sudden deaths
- GIVEN 20 forced sudden deaths
- WHEN each runs to resolution
- THEN all end with a KO and none relies on the training cap
