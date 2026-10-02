class_name ResultsPanel
extends Control
## A slanted, player-colored panel in the Smash Ultimate results style: diagonal
## stripes and a halftone fade over a base color, with the character's art drawn
## as a deliberate BUST. The art is cropped by the panel itself (it is drawn as a
## textured polygon), so the cut at the chest is the panel's flat bottom edge and
## never looks like a missing piece of the illustration.

## Panel color (the player's color).
@export var color: Color = Color(0.2, 0.3, 0.8)
## The art to show; null draws the panel alone.
@export var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
## Fraction of the art's height that is visible (from the top). An illustration
## is cut below the sweater hem; a face portrait is shown whole.
@export_range(0.2, 1.0) var crop: float = 0.62:
	set(value):
		crop = value
		queue_redraw()
## Horizontal lean of the panel sides, in pixels.
@export var slant: float = 36.0
## A greyed panel (the loser): the base color and the art lose their saturation.
@export var greyed: bool = false:
	set(value):
		greyed = value
		queue_redraw()

const STRIPE_WIDTH := 22.0
const STRIPE_GAP := 46.0
const DOT_SPACING := 13.0
const BOTTOM_BAND := 9.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)

## The panel outline in local coordinates: leaning sides, flat top and bottom.
func outline() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(slant, 0.0), Vector2(size.x, 0.0),
		Vector2(size.x - slant, size.y), Vector2(0.0, size.y),
	])

## Where the art is placed (local coordinates): it covers the whole panel,
## showing `crop` of its height from the top, centered horizontally.
func art_rect() -> Rect2:
	if texture == null:
		return Rect2()
	var tex_size := texture.get_size()
	var scale_to_fit := maxf(size.y / (tex_size.y * crop), size.x / tex_size.x)
	var drawn := tex_size * scale_to_fit
	return Rect2(Vector2((size.x - drawn.x) / 2.0, 0.0), drawn)

## True when the art covers the whole panel outline: no gap, so the crop is the
## panel's own edge.
func art_covers_panel() -> bool:
	if texture == null:
		return true
	var rect := art_rect().grow(0.5)
	for point in outline():
		if not rect.has_point(point):
			return false
	return true

func _base_color() -> Color:
	if not greyed:
		return color.darkened(0.25)
	var grey := color.get_luminance() * 0.55
	return Color(grey, grey, grey)

func _draw() -> void:
	var poly := outline()
	var base := _base_color()
	var stripe := base.lightened(0.22)
	var dot := base.lightened(0.45)
	# Drop shadow, base fill.
	draw_colored_polygon(_offset(poly, Vector2(8.0, 8.0)), Color(0, 0, 0, 0.5))
	draw_colored_polygon(poly, base)
	# Diagonal stripes leaning like the panel, clipped to it.
	var x := -size.y
	while x < size.x + size.y:
		var band := PackedVector2Array([
			Vector2(x + slant, 0.0), Vector2(x + slant + STRIPE_WIDTH, 0.0),
			Vector2(x + STRIPE_WIDTH, size.y), Vector2(x, size.y),
		])
		for clipped in Geometry2D.intersect_polygons(poly, band):
			draw_colored_polygon(clipped, stripe)
		x += STRIPE_GAP
	# Halftone dots, big at the bottom and fading out toward the top.
	var row := 0
	var y := size.y - DOT_SPACING * 0.5
	while y > 0.0:
		var radius := 3.6 * clampf(y / size.y, 0.0, 1.0) * 1.1
		var offset := DOT_SPACING * 0.5 * float(row % 2)
		var px := offset
		while px < size.x:
			var pos := Vector2(px, y)
			if radius > 0.6 and Geometry2D.is_point_in_polygon(pos, poly):
				draw_circle(pos, radius, dot)
			px += DOT_SPACING
		y -= DOT_SPACING * 0.82
		row += 1
	# The bust: the art as a textured polygon, so the panel cuts it.
	if texture != null:
		var rect := art_rect()
		var uvs := PackedVector2Array()
		for point in poly:
			uvs.append((point - rect.position) / rect.size)
		var tint := Color.WHITE
		if greyed:
			tint = Color(0.62, 0.62, 0.62)
		draw_colored_polygon(poly, tint, uvs, texture)
	# The cut: a bold band along the flat bottom edge, then the outline.
	var band_poly := PackedVector2Array([
		Vector2(size.x - slant + (slant * BOTTOM_BAND / size.y), size.y - BOTTOM_BAND),
		Vector2(size.x - slant, size.y), Vector2(0.0, size.y),
		Vector2(slant * BOTTOM_BAND / size.y, size.y - BOTTOM_BAND),
	])
	draw_colored_polygon(band_poly, color.lightened(0.15) if not greyed else base.lightened(0.3))
	var closed := poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, Color(0, 0, 0, 0.9), 9.0, true)
	draw_polyline(closed, Color(1, 1, 1, 0.95), 4.0, true)

static func _offset(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var moved := PackedVector2Array()
	for point in points:
		moved.append(point + by)
	return moved
