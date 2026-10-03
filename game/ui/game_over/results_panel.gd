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
## Portrait framing for a head-and-hair face art: instead of cropping a bust, the
## visible head is scaled to fit the panel (centered, its center-column bottom on
## the panel's bottom border) so the face, not the top of the hair, is what shows.
@export var portrait: bool = false:
	set(value):
		portrait = value
		queue_redraw()
## A greyed panel (the loser): the base color and the art lose their saturation.
@export var greyed: bool = false:
	set(value):
		greyed = value
		queue_redraw()

const STRIPE_WIDTH := 22.0
const STRIPE_GAP := 46.0
const DOT_SPACING := 13.0
## The art is lowered this many pixels so it reaches the bottom border (no strip of panel background between the character and the edge).
const ART_DROP := 12.0
## Portrait framing: breathing room above the head, and how far the bottom of the head overlaps the border (hidden under it).
const PORTRAIT_TOP := 6.0
const PORTRAIT_OVERLAP := 4.0
## Share of the art's width, around its center, that decides where the head's bottom is.
const PORTRAIT_CENTER_BAND := 0.4

static var _bounds_cache: Dictionary = {}

## The visible part of a face art, in texture pixels: where it starts at the top,
## where it ends at the bottom of its center band, and its horizontal extent.
## Returns Rect2(left, top, width, center_bottom - top).
static func head_bounds(art: Texture2D) -> Rect2:
	if _bounds_cache.has(art):
		return _bounds_cache[art]
	var image := art.get_image()
	var used := image.get_used_rect()
	var band_from := int(float(image.get_width()) * (0.5 - PORTRAIT_CENTER_BAND / 2.0))
	var band_to := int(float(image.get_width()) * (0.5 + PORTRAIT_CENTER_BAND / 2.0))
	var bottom := used.position.y
	for x in range(band_from, band_to):
		var y := used.end.y - 1
		while y > bottom and image.get_pixel(x, y).a < 0.1:
			y -= 1
		bottom = maxi(bottom, y)
	var bounds := Rect2(float(used.position.x), float(used.position.y), float(used.size.x), float(bottom + 1 - used.position.y))
	_bounds_cache[art] = bounds
	return bounds

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)

## The panel outline in local coordinates: leaning sides, flat top and bottom.
func outline() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(slant, 0.0), Vector2(size.x, 0.0),
		Vector2(size.x - slant, size.y), Vector2(0.0, size.y),
	])

## Where the art is placed (local coordinates): it is centered horizontally and
## lowered by ART_DROP (never past the point where its bottom leaves the panel).
## In portrait mode the head is fitted instead (see `portrait`).
func art_rect() -> Rect2:
	if texture == null:
		return Rect2()
	var tex_size := texture.get_size()
	if portrait:
		var head := head_bounds(texture)
		var fit := minf((size.y - PORTRAIT_TOP + PORTRAIT_OVERLAP) / head.size.y, (size.x - slant) / head.size.x)
		var head_center_x := (head.position.x + head.size.x / 2.0) * fit
		var head_bottom := (head.position.y + head.size.y) * fit
		return Rect2(Vector2(size.x / 2.0 - head_center_x, size.y + PORTRAIT_OVERLAP - head_bottom), tex_size * fit)
	var scale_to_fit := maxf(size.y / (tex_size.y * crop), size.x / tex_size.x)
	var drawn := tex_size * scale_to_fit
	var drop := clampf(ART_DROP, 0.0, maxf(drawn.y - size.y, 0.0))
	return Rect2(Vector2((size.x - drawn.x) / 2.0, drop), drawn)

## True when the art covers the panel's flat bottom edge and its sides: the crop
## is the panel's own edge. The top may start a few pixels lower (the drop).
func art_covers_panel() -> bool:
	if texture == null or portrait:
		return true
	var rect := art_rect().grow(0.5)
	for point in outline():
		if point.y > 0.0 and not rect.has_point(point):
			return false
		if point.y == 0.0 and (point.x < rect.position.x or point.x > rect.end.x):
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
		var tint := Color.WHITE
		if greyed:
			tint = Color(0.62, 0.62, 0.62)
		var pieces: Array[PackedVector2Array] = [poly]
		if portrait:
			# Clipped to the art's own rectangle so an edge pixel is never smeared.
			var art_poly := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
			pieces = Geometry2D.intersect_polygons(poly, art_poly)
		for clipped in pieces:
			var uvs := PackedVector2Array()
			for point in clipped:
				uvs.append((point - rect.position) / rect.size)
			draw_colored_polygon(clipped, tint, uvs, texture)
	var closed := poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, Color(0, 0, 0, 0.9), 9.0, true)
	draw_polyline(closed, Color(1, 1, 1, 0.95), 4.0, true)

static func _offset(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var moved := PackedVector2Array()
	for point in points:
		moved.append(point + by)
	return moved
