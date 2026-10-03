# Delta for Fighter Shield

Records behavior already implemented on branch `fix/shield-spam` (`odd/tasks/shield-spam.md` T1 and T3; commits `a5e7b8b`, `5606ce5`) so the spec matches the branch the retrain targets. These requirements add no new gameplay in this change. Timers are tick-based and values are tunable data.

## ADDED Requirements

### Requirement: Shield drop lag

Releasing the shield on the floor MUST put the fighter in a `ShieldDrop` state for a tunable number of ticks (default 11 ticks, about 0.18 s). During the lag the fighter MUST NOT act (no attack, throw, shield or dodge), MUST stay planted, and the bubble MUST shrink away over the lag. A hit during the lag MUST resolve as a normal hit (the shield is not active), not as a blocked hit. When the lag ends without a hit, the fighter MUST return to Idle.

#### Scenario: Release enters drop lag
- GIVEN a fighter holding the shield on the floor
- WHEN block is released
- THEN the fighter is in `ShieldDrop` for 11 ticks and then Idle

#### Scenario: No actions during lag
- GIVEN a fighter in `ShieldDrop`
- WHEN attack, throw and block intents are emitted
- THEN none changes the fighter's action until the lag ends

#### Scenario: Hit during lag is a normal hit
- GIVEN a fighter in `ShieldDrop`
- WHEN a punch connects
- THEN full damage and knockback apply and no shield damage is taken

#### Scenario: Bubble shrinks
- GIVEN the lag is running
- WHEN the bubble scale is read at the first and last lag tick
- THEN it decreases and the bubble is hidden when the lag ends

### Requirement: Minimum shield hold

A shield raise MUST be held for at least a tunable minimum (default 4 ticks) so that a one-tick tap still pays the full drop lag. Releasing earlier than the minimum MUST still enter `ShieldDrop` after the minimum hold.

#### Scenario: One-tick tap pays the lag
- GIVEN block is pressed for one tick only
- WHEN the tap ends
- THEN the shield stays up until tick 4 and the drop lag follows

#### Scenario: Shield spam is bounded
- GIVEN a policy alternating attack and block every 4 ticks for 10 s
- WHEN shield raises per second are counted
- THEN they are at most about 3.75 per second

### Requirement: Shield raise cost

Each shield raise MUST cost a tunable amount of meter (default 4) at the moment of raising. The meter MUST stay clamped to [0, max].

#### Scenario: Raise costs meter
- GIVEN a full meter of 100
- WHEN the shield is raised
- THEN the meter is 96 at the raise tick

#### Scenario: Raise at empty meter
- GIVEN a meter of 2
- WHEN the shield is raised
- THEN the meter is 0 and the shield breaks as defined by the break rule

### Requirement: Jump out of shield

A jump intent while shielding MUST be allowed and MUST skip the drop lag (Smash behavior).

#### Scenario: Jump from shield
- GIVEN a fighter holding the shield on the floor
- WHEN jump is pressed
- THEN the fighter jumps immediately without entering `ShieldDrop`

### Requirement: Shield bubble in the player color

The shield bubble MUST be tinted with the fighter's primary player color (the same source as the HUD card color). A weak meter MUST read as fading and pulsing, not as a color change to red.

#### Scenario: Bubble matches HUD color
- GIVEN fighters with different player colors
- WHEN each raises the shield
- THEN each bubble's hue matches its own HUD card color

#### Scenario: Weak meter pulses
- GIVEN a meter near zero
- WHEN the bubble is shown
- THEN it fades and pulses and its hue is unchanged

## MODIFIED Requirements

### Requirement: Shield state in snapshots

The fighter snapshot MUST expose shield meter value, meter maximum, dizzy flag, dizzy time remaining, and air-dodge availability (see `gameplay-state-snapshot`). The `ShieldDrop` state MUST be reported in the FSM state field.
(Previously: no `ShieldDrop` state existed.)

#### Scenario: Snapshot shows shield state
- GIVEN a dizzy fighter with a depleted meter
- WHEN its snapshot is taken
- THEN the dizzy flag is true, remaining time is positive, and the meter value is 0

#### Scenario: Drop lag reported
- GIVEN a fighter in the drop lag
- WHEN its snapshot is taken
- THEN the FSM state names `ShieldDrop`
