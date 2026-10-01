class_name MatchCamera
extends Camera2D

## Smash-style match camera: follows the midpoint of the fighters that are still
## in play and zooms out as they separate. The world is the 1176x902 kitchen
## backdrop (placed so the 800px table sits in its middle); the Camera2D limits
## keep the view inside it.
##
## The bottom `hud_reserve` pixels of the screen belong to the HUD panels: the
## camera never lets the tabletop (plus the art that hangs under a jumping
## fighter's feet) drop into that band, at any zoom.
##
## Only `position` and `zoom` are driven here. The hurt shake keeps writing
## `offset`, and the HUD lives on its own CanvasLayer, so neither is affected.
## Does nothing in training: train.tscn runs 25 Game instances and its cameras
## must stay exactly as authored.

@export var world_rect: Rect2 = Rect2(-158.0, 0.0, 1176.0, 902.0)
## Zoom range. 0.75 shows 1067x800 of the world, 1.15 shows 696x522.
@export var min_zoom: float = 0.75
@export var max_zoom: float = 1.15
## World pixels kept visible around the fighters (the framing of the pair).
@export var margin: Vector2 = Vector2(560.0, 380.0)
## Exponential smoothing rates (per second) for the follow and the zoom.
@export var follow_speed: float = 8.0
@export var zoom_speed: float = 3.0
## Soft clamp for the view center's y: keeps the counter in the lower half of
## the screen and avoids chasing every jump.
@export var center_y_range: Vector2 = Vector2(300.0, 420.0)
## Screen pixels at the bottom kept free of fighters for the HUD panels.
@export var hud_reserve: float = 130.0
## World pixels of sprite art that hang below a fighter's feet (the jump pose
## dangles its legs); they count as part of the fighter for the HUD band.
@export var sprite_overhang: float = 46.0

## Y of the tabletop, read from the floor collider in `_ready`.
var stage_top: float = 480.0

var _fighters: Array[Fighter] = []

func _ready() -> void:
	var game := get_parent()
	if game != null and game.get("training") == true:
		set_process(false)
		return

	var stage: Dictionary = game.get_state_snapshot().get("stage", {}) if game.has_method("get_state_snapshot") else {}
	stage_top = stage.get("top", stage_top)

	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	position_smoothing_enabled = false
	limit_left = int(world_rect.position.x)
	limit_top = int(world_rect.position.y)
	limit_right = int(world_rect.end.x)
	limit_bottom = int(world_rect.end.y)

	for child in get_parent().get_children():
		if child is Fighter:
			_fighters.append(child)
	# Start framed on the fighters instead of easing in from the origin.
	var target := _compute_target()
	zoom = Vector2.ONE * target.z
	position = _clamp_center(Vector2(target.x, target.y), target.z)

func _process(delta: float) -> void:
	var target := _compute_target()
	var new_zoom := lerpf(zoom.x, target.z, 1.0 - exp(-zoom_speed * delta))
	zoom = Vector2.ONE * new_zoom
	var wanted := Vector2(target.x, target.y)
	position = _clamp_center(position.lerp(wanted, 1.0 - exp(-follow_speed * delta)), new_zoom)

## Returns (center.x, center.y, zoom) framing the fighters still in play.
func _compute_target() -> Vector3:
	var lower := Vector2(INF, INF)
	var upper := Vector2(-INF, -INF)
	for fighter in _fighters:
		if not is_instance_valid(fighter) or fighter.stocks <= 0:
			continue
		# A fighter knocked far off stage must not drag the camera with it.
		var point := fighter.position.clamp(world_rect.position, world_rect.end)
		lower = lower.min(point)
		upper = upper.max(point)
	if lower.x > upper.x:
		# Nobody in play (match over): hold the current framing.
		return Vector3(position.x, position.y, zoom.x)

	var extent := (upper - lower) + margin
	var viewport_size := get_viewport_rect().size
	var wanted_zoom := minf(viewport_size.x / extent.x, viewport_size.y / extent.y)
	var center := (lower + upper) / 2.0
	center.y = clampf(center.y, center_y_range.x, center_y_range.y)
	return Vector3(center.x, center.y, clampf(wanted_zoom, min_zoom, max_zoom))

## Lowest view-center y that keeps the tabletop and the art under a fighter's
## feet above the HUD band at this zoom.
func _min_center_y(zoom_level: float) -> float:
	var half_height := get_viewport_rect().size.y / 2.0
	return stage_top + sprite_overhang - (half_height - hud_reserve) / zoom_level

## The engine snaps the view to whole screen pixels, which can push it about a
## world pixel past the limit; the clamp keeps this much of a gap.
const EDGE_SLACK := 2.0

# Keeps the view inside the world even if the limits are changed at runtime,
# and the tabletop above the HUD band.
func _clamp_center(center: Vector2, zoom_level: float) -> Vector2:
	var half := get_viewport_rect().size / (2.0 * zoom_level) + Vector2.ONE * EDGE_SLACK
	var low := half.min(world_rect.size / 2.0) + world_rect.position
	var high := (world_rect.end - half).max(world_rect.get_center())
	var clamped := center.clamp(low, high)
	clamped.y = clampf(maxf(clamped.y, _min_center_y(zoom_level)), low.y, high.y)
	return clamped
