# Match Camera Specification

## Purpose

Camera follow and dynamic zoom on the game `Camera2D` (slice S-A, moved up from S5a after the first playtest). Values are tunable defaults. The viewport is 800x600 and the world is the 1176x902 kitchen backdrop (one scene, one counter height); the camera shows a moving window of that world.

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

Zoom MUST decrease (zoom out) as fighter distance grows, and MUST be clamped to the range 0.75..1.15 (0.75 shows about 1067x800 of the world, 1.15 about 696x522).

#### Scenario: Fighters close
- GIVEN fighters are close
- WHEN the camera updates
- THEN zoom is high (zoomed in, never above 1.15)

#### Scenario: Fighters far
- GIVEN fighters are at opposite ends of the counter
- WHEN the camera updates
- THEN zoom settles at the minimum (0.75) and never below

### Requirement: Clamp to bounds

The `Camera2D` limits MUST be `0..1176` horizontally and `0..902` vertically, and the view MUST never show past them at any zoom in the allowed range. The view center SHOULD additionally be clamped in the script so smoothing never drifts against the limits.

#### Scenario: Fighter near the edge
- GIVEN a fighter near the left or right edge of the world
- WHEN the camera updates
- THEN the view edge does not exceed the limits

#### Scenario: Zoomed in near a corner
- GIVEN high zoom and fighters near a corner
- WHEN the camera updates
- THEN the center is shifted inward so the view stays inside the bounds

### Requirement: Vertical framing

The view center's y MUST be soft-clamped (default 300..420) so the counter stays in the lower half of the screen and jumps do not make the camera chase.

#### Scenario: Fighter jumps high
- GIVEN a fighter is airborne
- WHEN the camera updates
- THEN the view center y stays inside the soft-clamp range

### Requirement: State snapshot

The match snapshot MUST expose the camera as `camera: {center, zoom}` (screen center in Game-local coordinates, scalar zoom), read-only and unversioned like the rest of the snapshot.

#### Scenario: Snapshot read
- GIVEN a running match
- WHEN `get_state_snapshot()` is called
- THEN `camera.center` and `camera.zoom` match the live `Camera2D`

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
