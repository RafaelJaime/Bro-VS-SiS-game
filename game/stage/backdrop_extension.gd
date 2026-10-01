class_name BackdropExtension
extends Node2D

## Fills the world around the kitchen backdrop so the camera can follow a
## fighter far above or beside the picture (a high up-recovery, a big launch)
## without ever showing the void. The sides mirror the picture across its edge and
## the top repeats its first pixel row, so the wall color is continuous with the
## art, and the top fades toward a darker ceiling tone so the stretched pixels do
## not read as streaks. Game-local, drawn behind the table. Freed by `Game` in
## training together with the backdrop.

## The whole world the camera may show (Game-local). Must contain `inner`.
@export var outer: Rect2 = Rect2(-300.0, -300.0, 1460.0, 1202.0)
## Where the backdrop sprite sits (Game-local).
@export var inner_position: Vector2 = Vector2(-158.0, 0.0)
@export var texture: Texture2D
## Ceiling tone the top fades to, and how opaque it gets at the very top.
@export var ceiling_color: Color = Color(0.33, 0.2, 0.2, 1.0)
@export_range(0.0, 1.0) var ceiling_strength: float = 0.8

func _ready() -> void:
	if texture == null:
		var backdrop := get_parent().get_node_or_null("Backdrop") as Sprite2D
		if backdrop != null:
			texture = backdrop.texture
			inner_position = backdrop.position
			modulate = backdrop.modulate
			texture_filter = backdrop.texture_filter
	queue_redraw()

func _draw() -> void:
	if texture == null:
		return
	var size := texture.get_size()
	var inner := Rect2(inner_position, size)
	var left := inner.position.x - outer.position.x
	var right := outer.end.x - inner.end.x
	var top := inner.position.y - outer.position.y
	# Above: the top pixel row stretched up. The sides mirror the picture across its
	# edge (a stretched last column of the fridge would be a wide dark-red band),
	# and the corners mirror the top row.
	draw_texture_rect_region(texture, Rect2(inner.position.x, outer.position.y, size.x, top), Rect2(0.0, 0.0, size.x, 1.0))
	draw_set_transform(Vector2(2.0 * inner.position.x, 0.0), 0.0, Vector2(-1.0, 1.0))
	draw_texture_rect_region(texture, Rect2(inner.position.x, inner.position.y, left, size.y), Rect2(0.0, 0.0, left, size.y))
	draw_texture_rect_region(texture, Rect2(inner.position.x, outer.position.y, left, top), Rect2(0.0, 0.0, left, 1.0))
	draw_set_transform(Vector2(2.0 * inner.end.x, 0.0), 0.0, Vector2(-1.0, 1.0))
	draw_texture_rect_region(texture, Rect2(inner.end.x - right, inner.position.y, right, size.y), Rect2(size.x - right, 0.0, right, size.y))
	draw_texture_rect_region(texture, Rect2(inner.end.x - right, outer.position.y, right, top), Rect2(size.x - right, 0.0, right, 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Ceiling fade over the whole width of the extension (sides included).
	var faded := Color(ceiling_color, ceiling_strength)
	var clear := Color(ceiling_color, 0.0)
	var band := PackedVector2Array([
		Vector2(outer.position.x, outer.position.y), Vector2(outer.end.x, outer.position.y),
		Vector2(outer.end.x, inner.position.y), Vector2(outer.position.x, inner.position.y),
	])
	draw_polygon(band, PackedColorArray([faded, faded, clear, clear]))
