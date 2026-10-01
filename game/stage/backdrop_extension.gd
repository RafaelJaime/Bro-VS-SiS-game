class_name BackdropExtension
extends Node2D

## Fills the world around the kitchen backdrop so the camera can follow a
## fighter far above or beside the picture (a high up-recovery, a big launch)
## without ever showing the void. The fill is plain wall: smooth color gradients
## sampled from the picture's own edge pixels (never a copy of its objects, so no
## second fridge), darkened toward the outer edge like a vignette, with a soft
## shadow where the fridge ends and a darker skirting at the bottom. The top
## fades toward a ceiling tone. Game-local, drawn behind the table. Freed by
## `Game` in training together with the backdrop.

## The whole world the camera may show (Game-local). Must contain `inner`.
@export var outer: Rect2 = Rect2(-300.0, -300.0, 1460.0, 1202.0)
## Where the backdrop sprite sits (Game-local).
@export var inner_position: Vector2 = Vector2(-158.0, 0.0)
@export var texture: Texture2D
## Ceiling tone the top fades to, and how opaque it gets at the very top.
@export var ceiling_color: Color = Color(0.33, 0.2, 0.2, 1.0)
@export_range(0.0, 1.0) var ceiling_strength: float = 0.8
## Brightness multiplier at the outer edge of the fill (the vignette).
@export_range(0.0, 1.0) var vignette: float = 0.78
## Width in picture pixels averaged for each sampled color, and how many color
## stops a side or the top gets.
@export var sample_depth: int = 24
@export var stops: int = 24
## Width and opacity of the shadow cast on the fill where the picture ends.
@export var seam_shadow_width: float = 46.0
@export_range(0.0, 1.0) var seam_shadow_alpha: float = 0.0
## How far (picture pixels) the fill is feathered over the picture's top, left and
## right edges, so no hard line shows where the art ends.
@export var feather: float = 110.0
@export var side_feather: float = 220.0
## Height (picture pixels) of the darker skirting at the bottom of the fill.
@export var skirting_height: float = 44.0
@export_range(0.0, 1.0) var skirting_strength: float = 0.22

## Height of the object-free wall patch (top-left of the picture) the side
## gradient is sampled from.
const WALL_PATCH_HEIGHT := 410

# Wall colors down the picture's left edge and along its top edge.
var _side_colors: PackedColorArray = PackedColorArray()
var _top_colors: PackedColorArray = PackedColorArray()
# Wall colors down the picture's right edge.
var _right_colors: PackedColorArray = PackedColorArray()

func _ready() -> void:
	if texture == null:
		var backdrop := get_parent().get_node_or_null("Backdrop") as Sprite2D
		if backdrop != null:
			texture = backdrop.texture
			inner_position = backdrop.position
			modulate = backdrop.modulate
			texture_filter = backdrop.texture_filter
	_sample_wall()
	queue_redraw()

# Averages the picture's bare wall into `stops` colors. The sides get a vertical
# gradient taken from the wall patch at the top-left of the picture (no objects on
# it), and the top fill the colors along the picture's top edge.
func _sample_wall() -> void:
	_side_colors.clear()
	_top_colors.clear()
	_right_colors.clear()
	if texture == null:
		return
	var image := texture.get_image()
	if image == null:
		return
	image.decompress()
	var size := image.get_size()
	var depth := mini(sample_depth, size.x)
	var wall_height := mini(WALL_PATCH_HEIGHT, size.y)
	var band := maxi(wall_height / stops, 1)
	for i in stops:
		var y0 := int(float(wall_height - band) * i / maxi(stops - 1, 1))
		_side_colors.append(_average(image, Rect2i(0, y0, depth, band)))
		var ry0 := int(float(size.y) * i / stops)
		var ry1 := maxi(ry0 + 1, int(float(size.y) * (i + 1) / stops))
		_right_colors.append(_average(image, Rect2i(size.x - depth, ry0, depth, ry1 - ry0)))
		var x0 := int(float(size.x) * i / stops)
		var x1 := maxi(x0 + 1, int(float(size.x) * (i + 1) / stops))
		_top_colors.append(_average(image, Rect2i(x0, 0, x1 - x0, mini(sample_depth, size.y))))
	_right_colors = _smoothed(_right_colors, 4)
	_top_colors = _smoothed(_top_colors, 2)

# Softens a color ramp (a few neighbor-averaging passes) so a bright or dark
# object right at the edge does not paint a stripe into the fill.
func _smoothed(colors: PackedColorArray, passes: int) -> PackedColorArray:
	var out := colors.duplicate()
	for pass_index in passes:
		var next := out.duplicate()
		for i in out.size():
			var left := out[maxi(i - 1, 0)]
			var right := out[mini(i + 1, out.size() - 1)]
			next[i] = (left + out[i] * 2.0 + right) / 4.0
		out = next
	return out

func _average(image: Image, area: Rect2i) -> Color:
	var sum := Color(0.0, 0.0, 0.0, 0.0)
	var count := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			sum += image.get_pixel(x, y)
			count += 1
	var mean := sum / maxf(float(count), 1.0)
	return Color(mean.r, mean.g, mean.b, 1.0)

func _shade(color: Color, factor: float) -> Color:
	return Color(color.r * factor, color.g * factor, color.b * factor, 1.0)

func _draw() -> void:
	if texture == null or _side_colors.is_empty():
		return
	var size := texture.get_size()
	var inner := Rect2(inner_position, size)
	var left_x := outer.position.x
	var right_x := outer.end.x
	# Both sides share the wall tone sampled on the left edge, one strip per stop.
	for i in stops:
		var y0 := inner.position.y + size.y * i / stops
		var y1 := inner.position.y + size.y * (i + 1) / stops
		var c0 := _side_colors[i]
		var c1 := _side_colors[mini(i + 1, stops - 1)]
		var r0 := _right_colors[i]
		var r1 := _right_colors[mini(i + 1, stops - 1)]
		var bottom_dim := _skirting(inner, y1)
		_strip(Rect2(left_x, y0, inner.position.x - left_x, y1 - y0), c0, c1, true, bottom_dim)
		_strip(Rect2(inner.end.x, y0, right_x - inner.end.x, y1 - y0), r0, r1, false, bottom_dim)
	# Above the picture: the top edge colors, stretched up and dimmed toward the top.
	for i in stops:
		var x0 := inner.position.x + size.x * i / stops
		var x1 := inner.position.x + size.x * (i + 1) / stops
		# The end columns run on to the outer edge, so the top fill owns the corners.
		if i == 0:
			x0 = outer.position.x
		if i == stops - 1:
			x1 = outer.end.x
		var c0 := _top_colors[i]
		var c1 := _top_colors[mini(i + 1, stops - 1)]
		var far := PackedColorArray([_shade(c0, vignette), _shade(c1, vignette), c1, c0])
		var pts := PackedVector2Array([
			Vector2(x0, outer.position.y), Vector2(x1, outer.position.y),
			Vector2(x1, inner.position.y), Vector2(x0, inner.position.y),
		])
		draw_polygon(pts, far)
	# Corners above the picture: the top fill hands over to the side color so the
	# step at the picture's top line disappears.
	var rise := inner.position.y - outer.position.y
	_feather(Vector2(outer.position.x, inner.position.y), Vector2(inner.position.x, inner.position.y), Vector2(0.0, -rise),
			_shade(_side_colors[0], vignette), _side_colors[0])
	_feather(Vector2(inner.end.x, inner.position.y), Vector2(outer.end.x, inner.position.y), Vector2(0.0, -rise),
			_right_colors[0], _shade(_right_colors[0], vignette))
	_draw_feathers(inner, size)
	# A soft shadow where the picture (the fridge on the right) meets the fill.
	var shadow := Color(0.0, 0.0, 0.0, seam_shadow_alpha)
	var none := Color(0.0, 0.0, 0.0, 0.0)
	draw_polygon(PackedVector2Array([
		Vector2(inner.end.x, inner.position.y), Vector2(inner.end.x + seam_shadow_width, inner.position.y),
		Vector2(inner.end.x + seam_shadow_width, inner.end.y), Vector2(inner.end.x, inner.end.y),
	]), PackedColorArray([shadow, none, none, shadow]))
	# Ceiling fade over the whole width of the extension (sides included).
	var faded := Color(ceiling_color, ceiling_strength)
	var clear := Color(ceiling_color, 0.0)
	var band := PackedVector2Array([
		Vector2(outer.position.x, outer.position.y), Vector2(outer.end.x, outer.position.y),
		Vector2(outer.end.x, inner.position.y), Vector2(outer.position.x, inner.position.y),
	])
	draw_polygon(band, PackedColorArray([faded, faded, clear, clear]))

# Fade strips laid over the picture's own edges: the fill color (opaque at the
# edge) dissolves inward on a smoothstep curve (no visible end line), so the art
# melts into the fill with no seam.
func _draw_feathers(inner: Rect2, size: Vector2) -> void:
	var f := minf(feather, minf(size.x, size.y) * 0.5)
	var sf := minf(side_feather, size.x * 0.5)
	for i in stops:
		var x0 := inner.position.x + size.x * i / stops
		var x1 := inner.position.x + size.x * (i + 1) / stops
		var t0 := _top_colors[i]
		var t1 := _top_colors[mini(i + 1, stops - 1)]
		_feather(Vector2(x0, inner.position.y), Vector2(x1, inner.position.y), Vector2(0.0, f), t0, t1)
		var y0 := inner.position.y + size.y * i / stops
		var y1 := inner.position.y + size.y * (i + 1) / stops
		var d0 := _skirting(inner, y0)
		var d1 := _skirting(inner, y1)
		var s0 := _shade(_side_colors[i], d0)
		var s1 := _shade(_side_colors[mini(i + 1, stops - 1)], d1)
		_feather(Vector2(inner.position.x, y0), Vector2(inner.position.x, y1), Vector2(sf, 0.0), s0, s1)
		var r0 := _shade(_right_colors[i], d0)
		var r1 := _shade(_right_colors[mini(i + 1, stops - 1)], d1)
		_feather(Vector2(inner.end.x, y0), Vector2(inner.end.x, y1), Vector2(-sf, 0.0), r0, r1)

# One fade strip: from the edge segment a-b (opaque, colors ca/cb) inward by
# `inward`, in slices whose alpha follows a smoothstep down to zero.
func _feather(a: Vector2, b: Vector2, inward: Vector2, ca: Color, cb: Color) -> void:
	const SLICES := 10
	for k in SLICES:
		var u0 := float(k) / SLICES
		var u1 := float(k + 1) / SLICES
		var a0 := 1.0 - smoothstep(0.0, 1.0, u0)
		var a1 := 1.0 - smoothstep(0.0, 1.0, u1)
		draw_polygon(PackedVector2Array([
			a + inward * u0, b + inward * u0, b + inward * u1, a + inward * u1,
		]), PackedColorArray([
			Color(ca.r, ca.g, ca.b, a0), Color(cb.r, cb.g, cb.b, a0),
			Color(cb.r, cb.g, cb.b, a1), Color(ca.r, ca.g, ca.b, a1),
		]))

# Brightness factor of the skirting at world y (1 above it, darker at the bottom).
func _skirting(inner: Rect2, y: float) -> float:
	var depth := clampf((y - (inner.end.y - skirting_height)) / skirting_height, 0.0, 1.0)
	return 1.0 - skirting_strength * depth

# One side strip: the sampled color at the picture seam, vignetted at the outer
# edge. `left` says which edge of the rect is the outer one.
func _strip(area: Rect2, top_color: Color, bottom_color: Color, left: bool, bottom_dim: float) -> void:
	var inner_top := top_color
	var inner_bottom := _shade(bottom_color, bottom_dim)
	var outer_top := _shade(top_color, vignette)
	var outer_bottom := _shade(bottom_color, vignette * bottom_dim)
	var pts := PackedVector2Array([
		area.position, Vector2(area.end.x, area.position.y),
		area.end, Vector2(area.position.x, area.end.y),
	])
	var colors := PackedColorArray([outer_top, inner_top, inner_bottom, outer_bottom]) if left \
			else PackedColorArray([inner_top, outer_top, outer_bottom, inner_bottom])
	draw_polygon(pts, colors)
