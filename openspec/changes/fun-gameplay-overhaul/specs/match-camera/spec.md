# Match Camera Specification

## Purpose

Camera follow and dynamic zoom on the game `Camera2D` (slice S5). Values are tunable defaults; viewport is 800x600.

## Requirements

### Requirement: Follow midpoint

The camera MUST track the midpoint between both fighters, using Game-local positions, smoothly.

#### Scenario: Fighters move right
- GIVEN both fighters move right
- WHEN frames elapse
- THEN the camera center moves right to follow the midpoint

#### Scenario: One fighter KO'd
- GIVEN one fighter is out (respawning)
- WHEN the camera updates
- THEN it does not jump to an invalid position or error

### Requirement: Distance-based zoom

Zoom MUST decrease (zoom out) as fighter distance grows, and MUST be clamped to >= 1.0 so the widest view equals the full 800x600 framing.

#### Scenario: Fighters close
- GIVEN fighters are close
- WHEN the camera updates
- THEN zoom is above 1.0 (zoomed in)

#### Scenario: Fighters far
- GIVEN fighters are at opposite ends
- WHEN the camera updates
- THEN zoom is 1.0 and never below

### Requirement: Clamp to bounds

Center and zoom MUST be clamped so the view never shows past the stage/blast-zone bounds.

#### Scenario: Fighter near the edge
- GIVEN a fighter near the blast-zone edge
- WHEN the camera updates
- THEN the view edge does not exceed the bounds

#### Scenario: Zoomed in near a corner
- GIVEN high zoom and fighters near a corner
- WHEN the camera updates
- THEN the center is shifted inward so the view stays inside the bounds

### Requirement: Coexistence with shake and HUD

The follow script MUST drive only `position`/`zoom`; hurt shake MUST keep using `offset`. HUD MUST stay on its `CanvasLayer` unaffected by zoom. `train.tscn`'s camera MUST NOT get the follow script.

#### Scenario: Shake while following
- GIVEN the camera is following
- WHEN a fighter is hurt
- THEN the shake plays via `offset` and follow is not disturbed

#### Scenario: HUD fixed
- GIVEN zoom changes
- WHEN the HUD is observed
- THEN its size and position stay unchanged

#### Scenario: Training unaffected
- GIVEN `train.tscn`
- WHEN reviewed statically
- THEN its Camera2D has no follow script
