# Fighter Shield Specification

## Purpose

A Smash-style shield meter on the ground: it drains while held and when it absorbs hits, regenerates after release, and breaks into a punishable dizzy state at zero. Air block is replaced by a meter-free air dodge. All numeric values are tunable defaults held in data (a Resource or the fighter profile), never hard-coded in state scripts. Timers MUST be driven by match or physics ticks, never wall time or `Engine.time_scale`-scaled real time. Verification: Godot smoke tests under `tests/smoke/`.

## Requirements

### Requirement: Shield meter

Every fighter MUST have a shield meter with a maximum value (default 100) that starts full at spawn and respawn. While the fighter holds the shield on the floor, the meter MUST drain continuously at a tunable rate (default sized so a continuous hold from full breaks the shield in about 5 s). After the shield is released, the meter MUST regenerate at a tunable rate after a tunable delay (defaults: 0.5 s delay, full recovery from empty in about 6 s). The meter MUST be clamped to [0, max]. Holding the shield MUST keep the existing `block` intent; no new controller input is introduced.

#### Scenario: Continuous hold drains the meter
- GIVEN a grounded fighter with a full shield and default data
- WHEN block is held continuously with no incoming hits
- THEN the meter decreases monotonically and reaches 0 (shield break) within 5 s plus or minus 0.5 s of match time

#### Scenario: Release regenerates
- GIVEN a fighter whose meter is at 40 after releasing the shield
- WHEN the regeneration delay elapses and 2 s more of match time pass without shielding
- THEN the meter is greater than 40 and never exceeds the maximum

#### Scenario: No regeneration while held
- GIVEN a fighter holding the shield
- WHEN time passes
- THEN the meter never increases

#### Scenario: Meter is data-driven
- GIVEN the drain rate is edited in the shield data resource
- WHEN a match starts
- THEN the break time reflects the edit with no script change

#### Scenario: Respawn refills
- GIVEN a fighter with a depleted meter loses a stock
- WHEN it respawns
- THEN its meter is full

### Requirement: Blocked hit cost, chip and knockback

A hit that lands on a shielding, non-dizzy target MUST NOT apply full damage or full knockback. It MUST drain the target's meter by shield damage scaled from the hit (default: hit damage multiplied by a tunable scale, with a per-hit `shield_damage` override where an attack profile or food stats define one). It MUST apply chip damage to the target (default: a tunable fraction strictly between 0 and 1 of the hit damage) and a reduced knockback (a tunable fraction of full). If the drain brings the meter to 0, the shield breaks (see "Shield break and dizzy state").

(Previously: blocked hits dealt 50% damage and 30% knockback with no meter.)

#### Scenario: Blocked punch costs meter and deals chip
- GIVEN a grounded shielding target at full meter and a neutral punch of 8 damage
- WHEN the punch connects
- THEN the meter drops by hit damage times the shield-damage scale, the target's damage % rises by the chip amount (greater than 0 and less than 8), and knockback is lower than the unshielded knockback

#### Scenario: Higher damage drains more
- GIVEN two shielding targets at equal meter
- WHEN one is hit for 8 damage and the other for 16 damage
- THEN the second loses more meter than the first

#### Scenario: Hit that breaks the shield
- GIVEN a shielding target with meter lower than the incoming shield damage
- WHEN the hit connects
- THEN the meter is 0 and the target enters the dizzy state

#### Scenario: Shield damage override
- GIVEN an attack or food stat that defines `shield_damage`
- WHEN it hits a shielding target
- THEN the meter drains by that value instead of the damage-derived default

### Requirement: Shield break and dizzy state

When the meter reaches 0, the fighter MUST enter a dizzy state lasting a tunable duration (default about 2 s of match time). While dizzy, the fighter MUST NOT act on intent (no movement, attack, throw, shield or jump) and MUST NOT shield. Hits that land on a dizzy fighter MUST apply full damage and full knockback (as for an unshielded target). A hit that lands on a dizzy fighter MUST end the dizzy state through the normal hitstun transition. When dizzy ends without a hit, the fighter MUST return to idle (or fall, if airborne) with the meter at a tunable recovery value (default 50% of max, tunable). Dizzy MUST use the existing hitstun visuals plus a wobble or stars cue built only from existing sprites.

#### Scenario: Break enters dizzy
- GIVEN a shield whose meter reaches 0
- WHEN the break is processed
- THEN the fighter is in the dizzy state with a remaining time of about 2 s

#### Scenario: Dizzy ignores input
- GIVEN a dizzy fighter
- WHEN move, attack, throw, jump and block intents are emitted
- THEN none of them changes the fighter's action or position through intent

#### Scenario: Full punish
- GIVEN a dizzy target and a neutral punch of 8 damage
- WHEN the punch connects
- THEN the target takes the full 8 damage and the full unshielded knockback

#### Scenario: Dizzy times out
- GIVEN a dizzy fighter that is not hit
- WHEN the dizzy duration elapses
- THEN the fighter returns to a controllable state with the meter at the recovery value

#### Scenario: Dizzy timer ignores hit-stop
- GIVEN hit-stop scales `Engine.time_scale` during the dizzy period
- WHEN the dizzy duration is measured in match or physics ticks
- THEN dizzy ends after the same tick count as without hit-stop

### Requirement: Ground-only shield and air dodge

The shield MUST work only on the floor. In the air, `block` intent MUST trigger an air dodge instead: a brief invulnerability window (tunable, default about 0.3 s) followed by a cooldown (tunable, default about 0.6 s), costing no shield meter. The fighter MUST have at most one air dodge per airtime; the allowance MUST reset on landing, on ledge grab, and when the fighter is hit. Landing or leaving the floor while holding block MUST NOT carry shield meter state across as an air shield.

(Previously: block was available in Jump and Fall states as a sustained air block.)

#### Scenario: Air block becomes air dodge
- GIVEN an airborne fighter with the air dodge available
- WHEN block is pressed
- THEN the fighter is invulnerable for the dodge window and the shield meter is unchanged

#### Scenario: One per airtime
- GIVEN an airborne fighter that already used its air dodge
- WHEN block is pressed again in the same airtime
- THEN no second dodge occurs

#### Scenario: Reset on landing
- GIVEN an air dodge was used
- WHEN the fighter lands and becomes airborne again
- THEN the air dodge is available

#### Scenario: Reset on ledge grab or hit
- GIVEN an air dodge was used
- WHEN the fighter grabs the ledge, or is hit while airborne
- THEN the air dodge is available again

#### Scenario: Dodge invulnerability
- GIVEN a fighter in its air dodge window
- WHEN a punch or thrown food hits it
- THEN no damage or knockback applies

#### Scenario: No air shield
- GIVEN an airborne fighter
- WHEN block is held for 2 s
- THEN no shield bubble is shown and the shield meter does not drain

### Requirement: Unblockable hit flag

A hit MAY be flagged `unblockable`. An unblockable hit MUST ignore the shield entirely: it MUST apply full damage and full knockback to a shielding target and MUST NOT drain the shield meter. Normal punches and thrown food MUST NOT be unblockable.

#### Scenario: Unblockable ignores shield
- GIVEN a shielding target with a full meter and an unblockable hit
- WHEN it connects
- THEN full damage and full knockback apply and the meter is unchanged

#### Scenario: Normal hit does not
- GIVEN a punch or thrown food
- WHEN its hit data is inspected
- THEN `unblockable` is false

### Requirement: Shield HUD

Each fighter MUST show its shield level: a shrinking bubble around the fighter or a bar on its HUD card, using only existing assets. A shield break and the dizzy state MUST show a distinct, readable cue. The indicator MUST reflect the meter within one frame of change and MUST disappear (bubble) or sit idle (bar) when the shield is not in use at full meter.

#### Scenario: Level reflects meter
- GIVEN a fighter holding the shield at half meter
- WHEN the HUD updates
- THEN the indicator size or fill corresponds to the meter ratio of about 0.5

#### Scenario: Break cue
- GIVEN a shield break
- WHEN the dizzy state starts
- THEN the break and dizzy cue is visible until dizzy ends

#### Scenario: No new assets
- GIVEN the change applied
- WHEN `assets/` is diffed
- THEN no new files exist

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

