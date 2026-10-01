# Combat Hits Specification

## Purpose

Fair, readable hit rules: a correct punch hitbox, no stun-lock, and robust invulnerability and hit-stop lifecycles (resolves F4 and F5). Durations are tunable defaults.

## Requirements

### Requirement: Punch hitbox without owner displacement

The punch hitbox MUST be placed relative to the owner's facing and flip with it. The owner MUST NOT be moved by punching; `move_punch_offset` MUST be removed.

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

A hit MUST cause a short hitstun followed by a brief invulnerability window (defaults tunable, e.g. ~0.3 s stun, ~0.5 s invulnerable). A fighter MUST NOT take damage or knockback from hits during the invulnerability window.

#### Scenario: No stun-lock
- GIVEN a fighter was just hit
- WHEN a second hit lands during invulnerability
- THEN no damage or knockback is applied

#### Scenario: Window ends
- GIVEN the invulnerability window has elapsed
- WHEN another hit lands
- THEN it applies normally

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

Hit-stop MUST be serialized so that overlapping hits never leave `Engine.time_scale` at a wrong value.

#### Scenario: Overlapping hits
- GIVEN two hits trigger hit-stop within the same window
- WHEN both stops finish
- THEN `Engine.time_scale == 1.0`

#### Scenario: Single hit
- GIVEN one hit
- WHEN hit-stop ends
- THEN `Engine.time_scale == 1.0`

### Requirement: Knockback by charge and direction (S5)

With S5, damage and knockback MUST scale with charge level and use the angle of the attack direction (see `smash-moves`).

#### Scenario: Scaling applied
- GIVEN a fully charged side punch connects
- WHEN damage and knockback are computed
- THEN both exceed those of an uncharged side punch
