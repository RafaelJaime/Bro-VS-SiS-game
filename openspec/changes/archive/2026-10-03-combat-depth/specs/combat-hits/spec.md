# Delta for Combat Hits

Existing requirements (punch hitbox, hurtbox, hitstun and post-hit invulnerability, respawn invulnerability, serialized hit-stop, knockback by charge) are unchanged except where listed below. Hit-stop stays serialized.

## ADDED Requirements

### Requirement: Shield-aware hit resolution

Every hit MUST be resolved against the target's shield state in this order: (1) invulnerable targets take nothing; (2) an `unblockable` hit applies in full regardless of shield; (3) a dizzy target takes full damage and knockback; (4) a shielding, non-dizzy target takes shield damage, chip damage and reduced knockback per `fighter-shield`; (5) otherwise the hit applies normally. Punches and thrown food MUST follow the same resolution. A hit on a shielding target MUST NOT trigger the post-hit stun-lock bypass: hitstun and the post-hit invulnerability window apply only when full or chip damage was applied as a normal hit, as before the change; a blocked hit MUST NOT start hitstun.

#### Scenario: Shielded hit path
- GIVEN a shielding, non-dizzy target
- WHEN a punch connects
- THEN meter drain, chip damage and reduced knockback apply and the target is not put into hitstun

#### Scenario: Dizzy hit path
- GIVEN a dizzy target
- WHEN a punch connects
- THEN full damage and knockback apply

#### Scenario: Unblockable path
- GIVEN a shielding target
- WHEN an unblockable hit connects
- THEN full damage and knockback apply and the meter is unchanged

#### Scenario: Invulnerability precedes shield rules
- GIVEN a target in post-hit or respawn invulnerability
- WHEN any hit connects
- THEN no damage, knockback or meter drain applies

#### Scenario: Thrown food follows the same rules
- GIVEN a shielding target
- WHEN thrown food connects
- THEN the shielded path applies

### Requirement: Bomb hits bypass the shield

A bomb hit MUST be an `unblockable` hit (see `sudden-death-hazards`). A fighter holding the shield MUST NOT be exempt from bombs. Hit-stop caused by a bomb hit MUST stay serialized with other hit-stops, leaving `Engine.time_scale == 1.0` when all finish.

#### Scenario: Shield gives no bomb immunity
- GIVEN a shielding fighter outside any invulnerability window
- WHEN a bomb hits it
- THEN damage and knockback apply in full

#### Scenario: Hit-stop stays serialized
- GIVEN a bomb hit and a punch hit trigger hit-stop in the same window
- WHEN both stops finish
- THEN `Engine.time_scale == 1.0`

### Requirement: Timers independent of time scale

Shield regeneration delay, dizzy duration, air dodge window and cooldown, and bomb timing MUST be measured in match or physics ticks and MUST NOT depend on `Engine.time_scale`.

#### Scenario: Hit-stop leaves timers intact
- GIVEN hit-stop occurs during a dizzy period
- WHEN the dizzy and regeneration timers are measured in ticks
- THEN they match the values measured without hit-stop
