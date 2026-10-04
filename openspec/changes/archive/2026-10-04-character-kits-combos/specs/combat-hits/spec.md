# Delta for Combat Hits

## ADDED Requirements

### Requirement: Blocked hits do not extend combos

A hit resolved against a shielding, non-dizzy target MUST NOT start hitstun, MUST NOT increment the combo counter and MUST NOT start the combo timer (see `attack-combos`). A hit on a dizzy target follows the normal hit path and counts toward a combo.

#### Scenario: Blocked hit leaves combo state
- GIVEN a shielding target with no active combo
- WHEN a punch connects and is blocked
- THEN the combo count stays 0 and no hitstun starts

#### Scenario: Dizzy hit counts
- GIVEN a dizzy target
- WHEN a punch connects
- THEN the combo count becomes 1

## MODIFIED Requirements

### Requirement: Hitstun and post-hit invulnerability

A hit MUST cause hitstun whose duration comes from the attack's frame data (see `attack-combos`; the previous global formula is the per-attack default), followed by a brief post-hitstun invulnerability window (default 0.5 s). A hit that lands during hitstun MUST land normally (damage and knockback apply) and extend the combo, subject to the `attack-combos` safeguards (hitstun decay from hit 4, knockback growth, hard cap at hit 6, 1.5 s time cap). A fighter MUST NOT take damage or knockback from hits during the post-hitstun invulnerability window or during the invulnerability granted by the hard cap or time cap. Hitstun MUST be measured in ticks; the invulnerability window keeps the existing fighter invulnerability timer.
(Previously: a global ~0.3 s stun plus ~0.5 s invulnerability; no hit could land during hitstun so no combo could form.)

#### Scenario: No stun-lock
- GIVEN a fighter whose hitstun has expired and the invulnerability window is running
- WHEN a second hit lands
- THEN no damage or knockback is applied

#### Scenario: Window ends
- GIVEN the invulnerability window has elapsed
- WHEN another hit lands
- THEN it applies normally and starts a new combo

#### Scenario: Hit during hitstun lands
- GIVEN a victim in hitstun after a jab step
- WHEN the next jab step connects before hitstun expires
- THEN damage and knockback apply and the combo count increments

#### Scenario: Hitstun from frame data
- GIVEN an attack with an explicit hitstun of 0.55 s
- WHEN it connects at 0% damage
- THEN the victim's hitstun is 33 ticks

#### Scenario: Cap-granted invulnerability
- GIVEN the 6th hit of a combo launches the victim
- WHEN another hit lands immediately after
- THEN no damage or knockback is applied

### Requirement: Serialized hit-stop (F5)

Hit-stop MUST be serialized so that overlapping hits never leave `Engine.time_scale` at a wrong value. Hit-stop duration MUST scale with the attack's hit-stop scale (jab steps lighter than finishers and smashes; see `attack-combos`).
(Previously: hit-stop was serialized with a single duration for all hits.)

#### Scenario: Overlapping hits
- GIVEN two hits trigger hit-stop within the same window
- WHEN both stops finish
- THEN `Engine.time_scale == 1.0`

#### Scenario: Single hit
- GIVEN one hit
- WHEN hit-stop ends
- THEN `Engine.time_scale == 1.0`

#### Scenario: Scale per attack
- GIVEN a jab step (scale below 1.0) and a heavy launcher
- WHEN each connects
- THEN the jab step's hit-stop is shorter and `Engine.time_scale == 1.0` after both

### Requirement: Timers independent of time scale

Shield regeneration delay, dizzy duration, air dodge window and cooldown, bomb timing, punch duration, punch endlag, attack input buffer, link windows and hitstun MUST be measured in match or physics ticks and MUST NOT depend on `Engine.time_scale`. Punch and Hurt MUST NOT use `Timer` nodes for these durations. The post-hitstun invulnerability window is unchanged (existing fighter timer, started when hitstun ends).
(Previously: listed shield, dizzy, air dodge and bomb timers only; punch and hurt used idle `Timer` nodes.)

#### Scenario: Hit-stop leaves timers intact
- GIVEN hit-stop occurs during a dizzy period
- WHEN the dizzy and regeneration timers are measured in ticks
- THEN they match the values measured without hit-stop

#### Scenario: Hitstun unaffected by hit-stop
- GIVEN hit-stop occurs while a victim is in hitstun
- WHEN hitstun is measured in ticks
- THEN it ends after the same tick count as without hit-stop

#### Scenario: Link window unaffected by hit-stop
- GIVEN hit-stop occurs after a jab step connects
- WHEN the link window is measured in ticks
- THEN it opens and closes at the same ticks as without hit-stop
