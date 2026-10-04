# Combat Hits Specification

## Purpose

Fair, readable hit rules: a correct punch hitbox, no stun-lock, and robust invulnerability and hit-stop lifecycles (resolves F4 and F5). Durations are tunable defaults.

## Requirements

### Requirement: Punch hitbox without owner displacement

The punch hitbox MUST be placed relative to the owner's facing and flip with it. The owner MUST NOT be moved by punching; `move_punch_offset` MUST be removed. (Delivered in slice S-A, moved up from S2 after the first playtest.)

There MUST be a single punch hitbox (default 110x40 centered `(75 * facing, -10)`), live only during the swing's active frames, and each target MUST be hit at most once per swing. Facing follows the move input (Smash): a fighter keeps the facing it had when the swing started, so an enemy behind the fighter is not hit.

#### Scenario: Enemy behind
- GIVEN a fighter facing right and the enemy standing clear of the hitbox on its left
- WHEN it punches
- THEN the enemy takes no damage

#### Scenario: One hit per swing
- GIVEN the enemy overlaps the hitbox for the whole active window
- WHEN the swing completes
- THEN the enemy took exactly one hit

### Requirement: Hurtbox separate from the movement body

Each fighter MUST have a movement body (default 56x150, feet on the floor) and a separate hurtbox Area2D matching the art (default 120x171). Punches and thrown food MUST resolve hits through the hurtbox. Fighters MUST NOT collide with each other (they pass through with a soft horizontal push-apart, never standing on each other) and food pickups MUST NOT be solid to fighters.

#### Scenario: Walk through the opponent
- GIVEN two fighters on the counter
- WHEN one walks into the other
- THEN it ends up on the far side and both remain on the floor

#### Scenario: Food does not block
- GIVEN a food pickup lies on the counter
- WHEN a fighter walks over it
- THEN the fighter is not blocked

#### Scenario: Facing right
- GIVEN a fighter facing right
- WHEN it punches
- THEN the hitbox is in front on the right and the owner's position is unchanged by the punch

#### Scenario: Facing left
- GIVEN a fighter facing left
- WHEN it punches
- THEN the hitbox is mirrored on the left

#### Scenario: No teleport
- GIVEN any punch
- WHEN the punch ends
- THEN the owner's position changed only through ordinary movement/physics

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

### Requirement: Respawn invulnerability lifecycle (F4)

Respawn invulnerability MUST use a bound tween/timer; a new respawn MUST cancel the previous one so an old timer never ends invulnerability early or leaves it stuck on.

#### Scenario: Overlapping respawns
- GIVEN a fighter respawns while a prior invulnerability tween is still running
- WHEN the first tween would have finished
- THEN it is cancelled and the new invulnerability duration is honored in full

#### Scenario: Invulnerability ends
- GIVEN a respawn with no further respawn
- WHEN its duration elapses
- THEN the fighter is vulnerable and visuals are reset

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

### Requirement: Knockback by charge and direction (S5)

With S5, damage and knockback MUST scale with charge level and use the angle of the attack direction (see `smash-moves`).

#### Scenario: Scaling applied
- GIVEN a fully charged side punch connects
- WHEN damage and knockback are computed
- THEN both exceed those of an uncharged side punch
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

