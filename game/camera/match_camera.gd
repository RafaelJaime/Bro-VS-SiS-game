class_name MatchCamera
extends Camera2D

## Smash-style match camera: follows the midpoint of the fighters that are still
## in play and zooms out as they separate. The world is the 1176x902 kitchen
## backdrop; the Camera2D limits keep the view inside it, so no manual bounds
## logic is needed for the edges.
##
## Only `position` and `zoom` are driven here. The hurt shake keeps writing
## `offset`, and the HUD lives on its own CanvasLayer, so neither is affected.
## Does nothing in training: train.tscn runs 25 Game instances and its cameras
## must stay exactly as authored.

@export var world_size: Vector2 = Vector2(1176.0, 902.0)
## Zoom range. 0.75 shows 1067x800 of the world, 1.15 shows 696x522.
@export var min_zoom: float = 0.75
@export var max_zoom: float = 1.15
## World pixels kept visible around the fighters (the framing of the pair).
@export var margin: Vector2 = Vector2(520.0, 380.0)
## Exponential smoothing rates (per second) for the follow and the zoom.
@export var follow_speed: float = 6.0
@export var zoom_speed: float = 3.0
## Soft clamp for the view center's y: keeps the counter in the lower half of
## the screen and avoids chasing every jump.
@export var center_y_range: Vector2 = Vector2(300.0, 420.0)

var _fighters: Array[Fighter] = []

func _ready() -> void:
	var game := get_parent()
	if game != null and game.get("training") == true:
		set_process(false)
		return

	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	position_smoothing_enabled = false
	limit_left = 0
	limit_top = 0
	limit_right = int(world_size.x)
	limit_bottom = int(world_size.y)

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
		var point := fighter.position.clamp(Vector2.ZERO, world_size)
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

# Keeps the view inside the world even if the limits are changed at runtime.
func _clamp_center(center: Vector2, zoom_level: float) -> Vector2:
	var half := get_viewport_rect().size / (2.0 * zoom_level)
	var low := half.min(world_size / 2.0)
	var high := (world_size - half).max(world_size / 2.0)
	return center.clamp(low, high)
