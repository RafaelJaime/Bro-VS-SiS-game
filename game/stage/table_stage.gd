class_name TableStage
extends Node2D

## The stage: a table in the foreground, in front of the kitchen backdrop. The
## top of its front edge is the fight floor (the `StaticBody2D/Floor` collider),
## so the table spans exactly the playable floor and a fighter walks off either
## end into a ring-out.
##
## Everything is drawn in code except the cloth, which reuses the existing
## gingham strip: a thin perspective band for the tabletop, a drape hanging over
## the front with a wavy, shaded hem, flaps over both ends, wooden legs and a
## room floor with a soft contact shadow. The outline follows the kitchen art
## (thick red-brown strokes). Fighter shadows live in the `FighterShadows` child.
##
## Game-local coordinates, drawn behind the fighters. Freed by `Game` in
## training (25 copies would only cost draw calls).

const CLOTH_TEXTURE := preload("res://assets/images/game/plataformacuadrados.png")

const OUTLINE := Color(0.42, 0.13, 0.07)
const WOOD := Color(0.66, 0.42, 0.22)
const WOOD_LIGHT := Color(0.8, 0.57, 0.33)
const WOOD_DARK := Color(0.47, 0.28, 0.14)
const FLOOR_COLOR := Color(0.55, 0.33, 0.2)
const FLOOR_PLANK := Color(0.4, 0.22, 0.12)
const BASEBOARD := Color(0.72, 0.4, 0.24)

## Seam between the cloth strip rows: one gingham period is 78 px tall.
const CLOTH_PERIOD := 78.0
## How far the outer legs stick out past the table ends.
const LEG_OVERHANG := 4.0
## Rows of the strip used for the drape (red, white, red); the art is 128 tall.
const DRAPE_ROWS := 120.0

## Tabletop surface, front edge and hem geometry (Game-local, filled in `_ready`).
var left_x: float = 30.0
var right_x: float = 830.0
var top_y: float = 480.0
## Back edge of the tabletop band, and its front edge (the cloth turns over it).
var back_y: float = 462.0
var front_y: float = 488.0
## How far the back edge is pulled in on each side (perspective).
@export var back_inset: float = 26.0
@export var drape_height: float = DRAPE_ROWS
@export var leg_height: float = 130.0
@export var leg_width: float = 36.0
@export var leg_count: int = 4

## Y of the line where the legs meet the room floor.
var floor_y: float = 0.0

var cloth_texture: Texture2D = CLOTH_TEXTURE

func _ready() -> void:
	var floor_node := get_parent().get_node_or_null("StaticBody2D/Floor") as CollisionShape2D
	var rect := floor_node.shape as RectangleShape2D if floor_node else null
	if rect != null:
		var center: Vector2 = get_parent().to_local(floor_node.global_position)
		left_x = center.x - rect.size.x / 2.0
		right_x = center.x + rect.size.x / 2.0
		top_y = center.y - rect.size.y / 2.0
	back_y = top_y - 18.0
	front_y = top_y + 8.0
	floor_y = front_y + drape_height + leg_height
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	queue_redraw()

func _draw() -> void:
	_draw_room()
	_draw_legs()
	_draw_drape()
	_draw_end_flaps()
	_draw_tabletop()

func _hem_y() -> float:
	return front_y + drape_height

# Wall base, wooden room floor and the shadows the table throws on it.
func _draw_room() -> void:
	var span_left := left_x - 700.0
	var span_width := (right_x - left_x) + 1400.0
	draw_rect(Rect2(span_left, floor_y - 26.0, span_width, 26.0), BASEBOARD)
	draw_rect(Rect2(span_left, floor_y - 26.0, span_width, 4.0), OUTLINE.lightened(0.15))
	draw_rect(Rect2(span_left, floor_y, span_width, 420.0), FLOOR_COLOR)
	draw_line(Vector2(span_left, floor_y), Vector2(span_left + span_width, floor_y), OUTLINE, 5.0)
	# Planks: seams widen toward the viewer.
	var seam_y := floor_y + 22.0
	var step := 22.0
	while seam_y < floor_y + 420.0:
		draw_line(Vector2(span_left, seam_y), Vector2(span_left + span_width, seam_y), FLOOR_PLANK, 2.0)
		seam_y += step
		step += 10.0
	# Contact shadow of the whole table on the floor.
	var mid := (left_x + right_x) / 2.0
	draw_colored_polygon(_ellipse(Vector2(mid, floor_y + 20.0), Vector2((right_x - left_x) / 2.0 + 40.0, 30.0)), Color(0.0, 0.0, 0.0, 0.38))
	draw_colored_polygon(_ellipse(Vector2(mid, floor_y + 14.0), Vector2((right_x - left_x) / 2.0 - 20.0, 18.0)), Color(0.0, 0.0, 0.0, 0.3))
	# Shaded underside between the legs, under the cloth.
	draw_rect(Rect2(left_x + 8.0, _hem_y(), right_x - left_x - 16.0, floor_y - _hem_y()), Color(0.1, 0.05, 0.04, 0.55))

func _leg_xs() -> Array[Dictionary]:
	var legs: Array[Dictionary] = []
	var width := right_x - left_x
	# Back legs first (set in from the front legs and a touch darker/higher).
	if leg_count >= 4:
		legs.append({"x": left_x + width * 0.16, "back": true})
		legs.append({"x": right_x - width * 0.16 - leg_width * 0.8, "back": true})
	if leg_count >= 2:
		# The outer legs are flush with the table ends: they are the ledge (grab
		# zone) of the stage, see Game.get_ledges().
		legs.append({"x": left_x - LEG_OVERHANG, "back": false})
		legs.append({"x": right_x + LEG_OVERHANG - leg_width, "back": false})
	return legs

func _draw_legs() -> void:
	for leg in _leg_xs():
		var is_back: bool = leg["back"]
		var w := leg_width * (0.8 if is_back else 1.0)
		var x: float = leg["x"]
		var foot := floor_y - (8.0 if is_back else 0.0)
		var body := WOOD_DARK if is_back else WOOD
		var top := _hem_y() - 6.0
		var taper := 3.0
		var quad := PackedVector2Array([Vector2(x, top), Vector2(x + w, top), Vector2(x + w - taper, foot), Vector2(x + taper, foot)])
		draw_colored_polygon(quad, body)
		# Grain highlight on the lit side and shade on the other.
		draw_colored_polygon(PackedVector2Array([Vector2(x + 4.0, top), Vector2(x + 11.0, top), Vector2(x + 11.0 - taper, foot), Vector2(x + 4.0 + taper * 0.5, foot)]), WOOD_LIGHT if not is_back else WOOD)
		draw_colored_polygon(PackedVector2Array([Vector2(x + w - 8.0, top), Vector2(x + w, top), Vector2(x + w - taper, foot), Vector2(x + w - 8.0 - taper, foot)]), WOOD_DARK)
		draw_polyline(PackedVector2Array([quad[0], quad[3], quad[2], quad[1]]), OUTLINE, 4.0)
		# Foot shadow.
		draw_colored_polygon(_ellipse(Vector2(x + w / 2.0, foot + 2.0), Vector2(w * 0.7, 6.0)), Color(0.0, 0.0, 0.0, 0.35))

# Hem points with a soft wave, left to right.
func _hem_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	var segments := 40
	for i in segments + 1:
		var x := lerpf(left_x, right_x, float(i) / segments)
		points.append(Vector2(x, _hem_y() + 4.0 * sin(float(i) * 0.9)))
	return points

# draw_colored_polygon takes normalized UVs; these helpers take strip pixels.
func _uv(pixels: Vector2) -> Vector2:
	return pixels / Vector2(cloth_texture.get_size())

func _cloth_uv(point: Vector2) -> Vector2:
	return _uv(Vector2(point.x - left_x, point.y - front_y))

func _draw_drape() -> void:
	var hem := _hem_points()
	var poly := PackedVector2Array([Vector2(left_x, front_y), Vector2(right_x, front_y)])
	for i in range(hem.size() - 1, -1, -1):
		poly.append(hem[i])
	var uvs := PackedVector2Array()
	for point in poly:
		uvs.append(_cloth_uv(point))
	draw_colored_polygon(poly, Color.WHITE, uvs, cloth_texture)
	# Shade: the cloth darkens toward the hem and just under the table edge.
	var shade := PackedVector2Array([Vector2(left_x, front_y), Vector2(right_x, front_y), Vector2(right_x, _hem_y() + 6.0), Vector2(left_x, _hem_y() + 6.0)])
	draw_polygon(shade, PackedColorArray([Color(0, 0, 0, 0.22), Color(0, 0, 0, 0.22), Color(0.25, 0.0, 0.0, 0.0), Color(0.25, 0.0, 0.0, 0.0)]))
	var hem_shade := PackedVector2Array([Vector2(left_x, _hem_y() - 22.0), Vector2(right_x, _hem_y() - 22.0), Vector2(right_x, _hem_y() + 6.0), Vector2(left_x, _hem_y() + 6.0)])
	draw_polygon(hem_shade, PackedColorArray([Color(0.2, 0.0, 0.0, 0.0), Color(0.2, 0.0, 0.0, 0.0), Color(0.2, 0.0, 0.0, 0.34), Color(0.2, 0.0, 0.0, 0.34)]))
	# Soft vertical folds.
	var fold_count := 7
	for i in range(1, fold_count):
		var x := lerpf(left_x, right_x, float(i) / fold_count) + (12.0 if i % 2 == 0 else -9.0)
		draw_line(Vector2(x, front_y + 6.0), Vector2(x + (4.0 if i % 2 == 0 else -4.0), _hem_y() + 2.0), Color(0.3, 0.0, 0.0, 0.16), 7.0)
		draw_line(Vector2(x + 5.0, front_y + 6.0), Vector2(x + 8.0, _hem_y() + 2.0), Color(1.0, 1.0, 1.0, 0.1), 4.0)
	# Hem outline and the top fold line.
	draw_polyline(hem, OUTLINE, 5.0)
	draw_line(Vector2(left_x, front_y), Vector2(right_x, front_y), OUTLINE, 5.0)
	draw_line(Vector2(left_x, front_y), hem[0], OUTLINE, 5.0)
	draw_line(Vector2(right_x, front_y), hem[hem.size() - 1], OUTLINE, 5.0)

# The cloth also hangs over both ends of the table: a darker, flared flap.
func _draw_end_flaps() -> void:
	for side in [-1, 1]:
		var edge_x: float = left_x if side < 0 else right_x
		var flare: float = 18.0 * side
		var flap := PackedVector2Array([
			Vector2(edge_x, front_y),
			Vector2(edge_x + flare * 0.55, front_y + 10.0),
			Vector2(edge_x + flare, _hem_y() - 6.0),
			Vector2(edge_x + flare * 0.7, _hem_y() + 6.0),
			Vector2(edge_x, _hem_y() + 2.0),
		])
		var uvs := PackedVector2Array()
		for point in flap:
			uvs.append(_uv(Vector2(absf(point.x - edge_x) + 700.0, point.y - front_y)))
		draw_colored_polygon(flap, Color(0.72, 0.62, 0.62), uvs, cloth_texture)
		draw_polygon(flap, PackedColorArray([Color(0, 0, 0, 0.25), Color(0, 0, 0, 0.25), Color(0.2, 0, 0, 0.4), Color(0.2, 0, 0, 0.45), Color(0.2, 0, 0, 0.35)]))
		# Corner fold lines.
		draw_line(Vector2(edge_x + flare * 0.1, front_y + 8.0), Vector2(edge_x + flare * 0.6, _hem_y() - 4.0), Color(0.2, 0.0, 0.0, 0.35), 3.0)
		draw_polyline(PackedVector2Array([flap[0], flap[1], flap[2], flap[3], flap[4]]), OUTLINE, 5.0)

func _draw_tabletop() -> void:
	var surface := PackedVector2Array([
		Vector2(left_x + back_inset, back_y),
		Vector2(right_x - back_inset, back_y),
		Vector2(right_x, front_y),
		Vector2(left_x, front_y),
	])
	# One gingham period squeezed into the band: the squares foreshorten.
	var uvs := PackedVector2Array([
		_uv(Vector2(back_inset, 0.0)),
		_uv(Vector2(right_x - left_x - back_inset, 0.0)),
		_uv(Vector2(right_x - left_x, CLOTH_PERIOD)),
		_uv(Vector2(0.0, CLOTH_PERIOD)),
	])
	draw_colored_polygon(surface, Color.WHITE, uvs, cloth_texture)
	# Light falls off toward the back of the table.
	draw_polygon(surface, PackedColorArray([Color(0.2, 0, 0, 0.3), Color(0.2, 0, 0, 0.3), Color(0.2, 0, 0, 0.0), Color(0.2, 0, 0, 0.0)]))
	draw_polyline(PackedVector2Array([surface[3], surface[0], surface[1], surface[2]]), OUTLINE, 5.0)

static func _ellipse(center: Vector2, radius: Vector2, points: int = 28) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for i in points:
		var angle := TAU * float(i) / points
		poly.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return poly
