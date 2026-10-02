class_name MatchCamera
extends Camera2D

## Smash-style match camera: follows the midpoint of the fighters that are still
## in play and zooms out as they separate. The world is the 1176x902 kitchen
## backdrop (placed so the 800px table sits in its middle) plus a band of the same
## wall texture around it (`BackdropExtension`); the Camera2D limits keep the view inside
## that world.
##
## Both fighters stay in view: when one is launched or recovers far above the
## table, the camera follows it up and, if the HUD band rule below leaves no
## room, zooms out past `min_zoom` (down to `min_view_zoom`) to fit it.
##
## The bottom `hud_reserve` pixels of the screen belong to the HUD panels: the
## camera never lets the tabletop (plus the art that hangs under a jumping
## fighter's feet) drop into that band, at any zoom.
##
## The camera never lets a fighter clip: every fighter in play has its full
## rectangle (hurtbox plus the visible sprite, swept by a velocity look-ahead and
## padded by `frame_pad`) forced inside the view each physics tick, zooming out
## down to `min_view_zoom` when needed. Only a launch that no zoom can frame leaves
## a fighter off screen, and then an `OffscreenIndicator` bubble with the face
## portrait points at them from the screen edge.
##
## Only `position` and `zoom` are driven here. The hurt shake keeps writing
## `offset`, and the HUD lives on its own CanvasLayer, so neither is affected.
## Does nothing in training: train.tscn runs 25 Game instances and its cameras
## must stay exactly as authored.

@export var world_rect: Rect2 = Rect2(-300.0, -300.0, 1460.0, 1202.0)
## Zoom range of the normal framing. 0.75 shows 1067x800 of the world, 1.15 shows
## 696x522.
@export var min_zoom: float = 0.75
## Lowest zoom, used only to keep a fighter far above the table in view (0.58
## shows 1379x1034, which still fits the world).
@export var min_view_zoom: float = 0.58
## World pixels kept above the highest fighter's position (the head) and, on the
## way to the HUD band, below the lowest.
@export var head_room: float = 150.0
## Speed multiplier for the follow and the zoom while a head is above the view.
@export var urgent_boost: float = 6.0
## Seconds of velocity the camera looks ahead (the framing and the hard fit).
@export var look_ahead: float = 0.2
## Cap (world pixels) on how far the look-ahead moves a fighter's anticipated spot.
@export var max_look_ahead: float = 260.0
## World pixels kept clear between a fighter's rectangle and the screen edge.
@export var frame_pad: float = 30.0
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
var _indicator: OffscreenIndicator
# Fighters whose center is outside the screen right now (the bubble is showing).
var _indicated: Array[Fighter] = []
# Opaque pixel rect of a sprite frame, per texture (computing it is not free).
var _used_rects: Dictionary = {}

func _ready() -> void:
	var game := get_parent()
	if game != null and game.get("training") == true:
		set_physics_process(false)
		return

	var stage: Dictionary = game.get_state_snapshot().get("stage", {}) if game.has_method("get_state_snapshot") else {}
	stage_top = stage.get("top", stage_top)

	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	position_smoothing_enabled = false
	# Driven in the physics step, after the fighters have moved (see `_physics_process`).
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	process_physics_priority = 100
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

	var layer := CanvasLayer.new()
	layer.name = "OffscreenLayer"
	layer.layer = 2
	add_child(layer)
	_indicator = OffscreenIndicator.new()
	layer.add_child(_indicator)
	_indicator.show_entries([])

# Runs after the fighters (priority 100) so the view matches this tick's positions.
func _physics_process(delta: float) -> void:
	var target := _compute_target()
	# A fighter about to leave the top of the view (a launch, an up-recovery) gets
	# a much faster camera so the head is never cut off.
	var boost := urgent_boost if _head_above_view() else 1.0
	var new_zoom := lerpf(zoom.x, target.z, 1.0 - exp(-zoom_speed * boost * delta))
	var wanted := Vector2(target.x, target.y)
	var eased := position.lerp(wanted, 1.0 - exp(-follow_speed * boost * delta))
	# The smoothing never wins over the hard fit: whatever it left out of view is
	# pulled back in this very tick.
	var fitted := _enforce_visible(eased, new_zoom)
	zoom = Vector2.ONE * fitted.z
	position = _clamp_center(Vector2(fitted.x, fitted.y), fitted.z)
	# Apply it now: the engine would otherwise render the previous tick's view.
	force_update_scroll()
	_update_indicator()

## True while `fighter` is off screen and the bubble points at them.
func is_indicating(fighter: Fighter) -> bool:
	return fighter in _indicated

func _in_play(fighter: Fighter) -> bool:
	return is_instance_valid(fighter) and fighter.stocks > 0

# Opaque pixel rect of the fighter's current sprite frame, in texture pixels.
func _used_rect(texture: Texture2D) -> Rect2i:
	if not _used_rects.has(texture):
		_used_rects[texture] = texture.get_image().get_used_rect()
	return _used_rects[texture]

## World-space rectangle a fighter occupies on screen: the union of the hurtbox
## and the opaque pixels of the current sprite frame.
func fighter_rect(fighter: Fighter) -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var corners: Array[Vector2] = []
	var shape_node := fighter.get_node_or_null("Hurtbox/CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		var half := (shape_node.shape as RectangleShape2D).size / 2.0
		var xf := shape_node.global_transform
		for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
			corners.append(xf * corner)
	var sprite := fighter.animated_sprite_2d
	if sprite != null and sprite.sprite_frames != null:
		var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		if texture != null:
			var used := _used_rect(texture)
			var origin := Vector2(texture.get_size()) / 2.0 if sprite.centered else Vector2.ZERO
			var sprite_xf := sprite.global_transform
			for corner in [used.position, Vector2(used.end.x, used.position.y), used.end, Vector2(used.position.x, used.end.y)]:
				corners.append(sprite_xf * (Vector2(corner) - origin + sprite.offset))
	if corners.is_empty():
		return Rect2(fighter.global_position - Vector2(60.0, 85.0), Vector2(120.0, 171.0))
	for point in corners:
		low = low.min(point)
		high = high.max(point)
	return Rect2(low, high - low)

## The area every fighter in play must stay inside: each fighter's rectangle swept
## `look_ahead` seconds along its velocity, padded, and held inside the world.
## Returns an empty rect when nobody is in play.
func _needed_rect() -> Rect2:
	var needed := Rect2()
	var have := false
	for fighter in _fighters:
		if not _in_play(fighter):
			continue
		var rect := fighter_rect(fighter)
		var shift := (fighter.velocity * look_ahead).limit_length(max_look_ahead)
		var swept := rect.merge(Rect2(rect.position + shift, rect.size)).grow(frame_pad)
		var low := swept.position.clamp(world_rect.position, world_rect.end)
		var high := swept.end.clamp(world_rect.position, world_rect.end)
		var held := Rect2(low, high - low)
		needed = held if not have else needed.merge(held)
		have = true
	return needed

## Pulls (center, zoom) so `_needed_rect` fits the view: the zoom drops (never
## below `min_view_zoom`) until it does, then the center moves just enough. When
## the rectangle cannot fit even at the lowest zoom the center is its middle.
func _enforce_visible(center: Vector2, zoom_level: float) -> Vector3:
	var needed := _needed_rect()
	if needed.size == Vector2.ZERO:
		return Vector3(center.x, center.y, zoom_level)
	var viewport_size := get_viewport_rect().size
	var fit := minf(viewport_size.x / maxf(needed.size.x, 1.0), viewport_size.y / maxf(needed.size.y, 1.0))
	# The HUD band rule needs the tabletop and the art under the feet clear of the
	# bottom `hud_reserve` px; a high fighter therefore also caps the zoom.
	var below_view := stage_top + sprite_overhang - needed.position.y
	if below_view > 0.0:
		fit = minf(fit, (viewport_size.y - hud_reserve) / below_view)
	var new_zoom := clampf(minf(zoom_level, fit), min_view_zoom, max_zoom)
	var half := viewport_size / (2.0 * new_zoom)
	var out := center
	out.x = _fit_axis(center.x, needed.position.x, needed.end.x, half.x)
	out.y = _fit_axis(center.y, needed.position.y, needed.end.y, half.y)
	return Vector3(out.x, out.y, new_zoom)

# Moves `center` the least that puts [low, high] inside center +- half; centers on
# the span when it is wider than the view.
func _fit_axis(center: float, low: float, high: float, half: float) -> float:
	if high - low > 2.0 * half:
		return (low + high) / 2.0
	return clampf(center, high - half, low + half)

# Shows a bubble for every fighter whose center is off screen (a launch the
# camera cannot frame even fully zoomed out).
func _update_indicator() -> void:
	_indicated.clear()
	if _indicator == null:
		return
	var canvas := get_viewport().get_canvas_transform()
	var size := get_viewport_rect().size
	var entries: Array[Dictionary] = []
	for fighter in _fighters:
		if not _in_play(fighter):
			continue
		var screen := canvas * fighter.global_position
		if Rect2(Vector2.ZERO, size).has_point(screen):
			continue
		_indicated.append(fighter)
		var dir := (screen - size / 2.0).normalized()
		var hud := fighter.get_node_or_null("PlayerUI") as FighterHud
		var face: Texture2D = hud.portrait.texture if hud != null and hud.portrait != null else null
		var color := fighter.character_ui.color if fighter.character_ui != null else Color.WHITE
		entries.append({
			"pos": OffscreenIndicator.bubble_position(screen, size, hud_reserve),
			"dir": dir,
			"color": color,
			"face": face,
		})
	_indicator.show_entries(entries)

## True when a fighter in play has its head (or is about to: `head_room` is the
## margin) above the top edge of the current view.
func _head_above_view() -> bool:
	var view_top := position.y - get_viewport_rect().size.y / (2.0 * zoom.x)
	for fighter in _fighters:
		if is_instance_valid(fighter) and fighter.stocks > 0 and _anticipated(fighter).y - head_room * 0.9 < view_top:
			return true
	return false

## Where the fighter will be in `look_ahead` seconds (a launch, a run, an
## up-recovery), so the camera is already there when it arrives.
func _anticipated(fighter: Fighter) -> Vector2:
	return fighter.position + (fighter.velocity * look_ahead).limit_length(max_look_ahead)

## Returns (center.x, center.y, zoom) framing the fighters still in play.
func _compute_target() -> Vector3:
	var lower := Vector2(INF, INF)
	var upper := Vector2(-INF, -INF)
	for fighter in _fighters:
		if not is_instance_valid(fighter) or fighter.stocks <= 0:
			continue
		# A fighter knocked far off stage must not drag the camera with it.
		var point := _anticipated(fighter).clamp(world_rect.position, world_rect.end)
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
	var zoom_target := clampf(wanted_zoom, min_zoom, max_zoom)

	# Keep the highest fighter's head in view. The HUD band rule fixes the lowest
	# view top at (stage_top + overhang - (half - reserve)/z) - half/z, so a high
	# fighter may need a lower zoom to fit.
	var top_needed := lower.y - head_room
	var below_view := stage_top + sprite_overhang - top_needed
	if below_view > 0.0:
		var half_height := viewport_size.y / 2.0
		var fit_zoom := (2.0 * half_height - hud_reserve) / below_view
		zoom_target = clampf(minf(zoom_target, fit_zoom), min_view_zoom, max_zoom)
	center.y = minf(center.y, top_needed + viewport_size.y / (2.0 * zoom_target))
	return Vector3(center.x, center.y, zoom_target)

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
