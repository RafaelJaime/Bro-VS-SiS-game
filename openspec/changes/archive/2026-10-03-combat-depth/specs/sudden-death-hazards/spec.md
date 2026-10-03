# Sudden Death Hazards Specification

## Purpose

Smash Ultimate-style escalation: after a grace period of sudden death, bombs fall from above the stage at an increasing rate until someone is KO'd. Bombs are unblockable, use existing VFX and SFX only, and are owned by the `Game` so they are Game-local and safe in training rows. All numeric values are tunable defaults held in data. Verification: Godot smoke tests under `tests/smoke/`.

## Requirements

### Requirement: Bomb start after grace period

Bombs MUST NOT fall during the sudden-death grace period (default about 20 s of sudden-death match time). After the grace period, the hazard system MUST begin spawning bombs from above the stage. Sudden-death time MUST be measured in match or physics ticks, not wall time, so hit-stop `Engine.time_scale` changes do not shift it. Bombs MUST NOT exist outside sudden death.

#### Scenario: No bombs during grace
- GIVEN sudden death has just started
- WHEN 15 s of match time elapse
- THEN no bomb has spawned

#### Scenario: Bombs begin after grace
- GIVEN sudden death with a 20 s grace period
- WHEN 25 s of match time elapse with no KO
- THEN at least one bomb has spawned

#### Scenario: No bombs in regulation
- GIVEN a match in regulation time
- WHEN any amount of time passes
- THEN no bomb spawns

#### Scenario: Hit-stop does not shift timing
- GIVEN repeated hit-stop events change `Engine.time_scale` during sudden death
- WHEN the first-bomb time is measured in physics ticks
- THEN it equals the tick count measured without hit-stop

### Requirement: Escalating spawn rate

After bombs begin, the spawn interval MUST shrink over time (default: start around 2 s and tighten by a tunable factor down to a tunable floor of about 0.4 s). The number of simultaneous bombs MUST be capped by a tunable maximum to bound cost. Each bomb MUST be visibly telegraphed before impact (a shadow or visible fall) and use CPU particles for compatibility with the web build.

#### Scenario: Interval shrinks
- GIVEN bombs have started
- WHEN spawn intervals are recorded over 30 s
- THEN each later interval is less than or equal to the earlier one, and never below the floor

#### Scenario: Simultaneous cap
- GIVEN the maximum simultaneous bombs is N
- WHEN spawning would exceed N
- THEN no more than N bombs are active at once

#### Scenario: Telegraph
- GIVEN a bomb is falling
- WHEN it has not yet hit
- THEN it is visible on screen for at least a tunable minimum fall time before impact

### Requirement: Unblockable damaging bombs

A bomb that overlaps a fighter's hurtbox MUST deal damage and knockback as an `unblockable` hit (see `fighter-shield`): it MUST ignore a held shield and MUST NOT drain the shield meter. The knockback MUST scale with the target's damage %, and at 300% (the sudden-death starting damage) MUST be lethal: the fighter MUST leave the stage bounds and lose its stock without further input within a tunable time (default 3 s), including when the fighter was shielding. A bomb MUST hit each fighter at most once. A fighter inside respawn invulnerability MUST NOT be hit.

#### Scenario: Unblockable against shield
- GIVEN a fighter shielding at full meter
- WHEN a bomb hits it
- THEN damage and knockback apply in full and the meter is unchanged

#### Scenario: Lethal at 300%
- GIVEN a fighter at 300% damage and one stock, with no input
- WHEN a bomb hits it
- THEN it is KO'd within the lethal-time default

#### Scenario: One hit per bomb
- GIVEN a bomb overlapping a fighter for several frames
- WHEN the bomb resolves
- THEN the fighter was hit exactly once by that bomb

#### Scenario: Respawn invulnerability respected
- GIVEN a fighter in respawn invulnerability
- WHEN a bomb overlaps it
- THEN no damage or knockback applies

### Requirement: Existing VFX and SFX only

Bomb visuals MUST reuse the existing `2D Fire - Tutorial` textures and the explosion sound reuses the existing `fireball-explosion` audio through `Sfx` with its own event band. No new asset files MAY be added.

#### Scenario: No new assets
- GIVEN the change applied
- WHEN `assets/` is diffed
- THEN no new files exist

#### Scenario: Explosion cue
- GIVEN a bomb impacts
- WHEN the impact is processed
- THEN an explosion VFX and SFX play, with SFX pitch inside its own band

### Requirement: Game-local and training-safe

Bomb positions MUST be Game-local (relative to the owning `Game`) so multiple Games, including training rows at different global offsets, never share or cross-hit bombs. The hazard system MUST NOT use global state. It MUST NOT error when the Game has no HUD or no training rows. Active bombs MUST be exposed in the Game snapshot (see `gameplay-state-snapshot`).

#### Scenario: Two Games
- GIVEN two Games in sudden death at different global offsets
- WHEN bombs fall in each
- THEN each bomb lies within its own Game's bounds and only affects its own fighters

#### Scenario: Offset invariance
- GIVEN a Game at a non-zero global offset in sudden death
- WHEN its bomb positions are read from the snapshot
- THEN they equal those of the same Game at the origin

#### Scenario: Cleanup on reset
- GIVEN bombs are active when the match ends or the row resets
- WHEN the reset completes
- THEN no bomb remains and none carries over into the next match

### Requirement: Sudden death always ends

With bombs active, sudden death MUST end in a KO in practice. Across 20 forced sudden-death matches between inactive or active fighters, every match MUST end with a KO result, and the mean duration after bomb start MUST be well under the previous never-ending behavior (target at most about 20 s after bombs start, tunable).

#### Scenario: Forced sudden deaths end
- GIVEN 20 forced sudden deaths with two idle fighters
- WHEN each is run to resolution
- THEN all 20 end in a KO

#### Scenario: Turtle cannot stall
- GIVEN two fighters holding the shield through the entire sudden death
- WHEN bombs fall
- THEN a KO occurs because bombs ignore the shield
