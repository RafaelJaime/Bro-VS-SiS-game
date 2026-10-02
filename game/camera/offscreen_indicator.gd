class_name OffscreenIndicator
extends Control

## Smash-style off-screen bubble: when a fighter is launched beyond what the
## camera can frame, a round bubble with the fighter's face and an arrow pointing
## at them sits on the screen edge, in the fighter's color. Purely visual: the
## `MatchCamera` decides who is off screen and feeds it through `show_for`.

const BUBBLE_RADIUS := 34.0
const ARROW_LENGTH := 16.0
## Distance kept between the bubble center and the screen edge.
const EDGE_INSET := 46.0

## One entry per indicated fighter: { "pos": bubble center, "dir": unit vector
## toward the fighter, "color": Color, "face": Texture2D or null }.
var _entries: Array[Dictionary] = []

func _ready() -> void:
	name = "OffscreenIndicator"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## Replaces what is drawn. `bottom_reserve` keeps bubbles above the HUD panels.
func show_entries(entries: Array[Dictionary]) -> void:
	_entries = entries
	visible = not _entries.is_empty()
	queue_redraw()

## Where the bubble for a fighter at `screen_pos` sits: the point where the line
## from the screen center to the fighter meets the inset screen rectangle.
static func bubble_position(screen_pos: Vector2, screen_size: Vector2, bottom_reserve: float) -> Vector2:
	var area := Rect2(Vector2.ONE * EDGE_INSET, screen_size - Vector2(2.0 * EDGE_INSET, 2.0 * EDGE_INSET + bottom_reserve))
	var center := screen_size / 2.0
	var dir := screen_pos - center
	if dir.length_squared() < 0.0001:
		return area.get_center()
	var half := area.size / 2.0
	var scale_x := half.x / maxf(absf(dir.x), 0.0001)
	var scale_y := half.y / maxf(absf(dir.y), 0.0001)
	return area.get_center() + dir * minf(scale_x, scale_y)

func _draw() -> void:
	for entry in _entries:
		var pos: Vector2 = entry["pos"]
		var dir: Vector2 = entry["dir"]
		var color: Color = entry["color"]
		var face: Texture2D = entry["face"]
		var side := Vector2(-dir.y, dir.x)
		var tip := pos + dir * (BUBBLE_RADIUS + ARROW_LENGTH)
		var base := pos + dir * (BUBBLE_RADIUS - 2.0)
		draw_colored_polygon(PackedVector2Array([tip, base + side * 12.0, base - side * 12.0]), color)
		draw_circle(pos, BUBBLE_RADIUS + 3.0, color)
		draw_circle(pos, BUBBLE_RADIUS, Color(0.08, 0.08, 0.1, 0.92))
		if face != null:
			var box := Vector2.ONE * (BUBBLE_RADIUS * 1.6)
			draw_texture_rect(face, Rect2(pos - box / 2.0, box), false)
