class_name BackdropExtension
extends Node2D

## Fills the world around the kitchen backdrop so the camera can follow a
## fighter far above or beside the picture (a high up-recovery, a big launch)
## without ever showing the void. The fill is the art's own wall: the fine paint
## texture of a plain, object-free patch of the wall layer is tiled (mirrored
## repeat) over the left, right and top areas by `backdrop_wall.gdshader`, tinted
## with the color of the picture's nearest edge so it continues the art. No object
## of the picture is ever copied (no second fridge). Along the top and left edges
## the fill fades out over the art's own edge, so no line shows where the art
## ends. Game-local, drawn behind the table. Freed by `Game` in training together
## with the backdrop.

const WALL_SHADER := preload("res://game/stage/backdrop_wall.gdshader")

## Plain wall of the picture (the band under the cabinets of the wall layer, no
## objects), in picture pixels: the source of the tiled texture.
const WALL_PATCH := Rect2i(0, 480, 1176, 420)
## The patch is blurred by shrinking it this many times; the fill keeps only the
## detail the blur removes.
const BLUR_FACTOR := 10
## Picture rows/columns averaged for the edge tone, and the pixels per tone cell.
const TONE_DEPTH := 12
const TONE_CELL := 32

## The whole world the camera may show (Game-local). Must contain `inner`.
@export var outer: Rect2 = Rect2(-300.0, -300.0, 1460.0, 1202.0)
## Where the backdrop sprite sits (Game-local).
@export var inner_position: Vector2 = Vector2(-158.0, 0.0)
## The wall layer of the picture (the window must not matter: only plain wall is read).
@export var texture: Texture2D
## How far (picture pixels) the fill fades over the picture's top and left edges.
@export var feather: float = 20.0
## The counter starts on the left edge of the picture at this height; the left fade
## stops above it so the fill never paints over the cabinets.
@export var counter_top: float = 440.0

func _ready() -> void:
	if texture == null:
		var backdrop := get_parent().get_node_or_null("Backdrop") as Sprite2D
		if backdrop != null:
			texture = backdrop.texture
			inner_position = backdrop.position
			modulate = backdrop.modulate
			texture_filter = backdrop.texture_filter
	_build_material()
	queue_redraw()

func _build_material() -> void:
	if texture == null:
		return
	var image := texture.get_image()
	if image == null:
		return
	image.decompress()
	var size := image.get_size()
	var patch := image.get_region(WALL_PATCH)
	var blur := patch.duplicate() as Image
	blur.resize(maxi(WALL_PATCH.size.x / BLUR_FACTOR, 1), maxi(WALL_PATCH.size.y / BLUR_FACTOR, 1), Image.INTERPOLATE_TRILINEAR)
	patch.generate_mipmaps()
	blur.generate_mipmaps()
	var shader_material := ShaderMaterial.new()
	shader_material.shader = WALL_SHADER
	shader_material.set_shader_parameter("patch", ImageTexture.create_from_image(patch))
	shader_material.set_shader_parameter("patch_blur", ImageTexture.create_from_image(blur))
	shader_material.set_shader_parameter("tile_size", Vector2(WALL_PATCH.size))
	shader_material.set_shader_parameter("inner", Vector4(inner_position.x, inner_position.y, size.x, size.y))
	shader_material.set_shader_parameter("feather", feather)
	shader_material.set_shader_parameter("tone_left", _tone(image, Rect2i(0, 0, TONE_DEPTH, size.y), Vector2i(1, maxi(size.y / TONE_CELL, 1))))
	shader_material.set_shader_parameter("tone_right", _tone(image, Rect2i(size.x - TONE_DEPTH, 0, TONE_DEPTH, size.y), Vector2i(1, maxi(size.y / TONE_CELL, 1))))
	shader_material.set_shader_parameter("tone_top", _tone(image, Rect2i(0, 0, size.x, TONE_DEPTH), Vector2i(maxi(size.x / TONE_CELL, 1), 1)))
	material = shader_material

# A strip of the picture's edge averaged down to `cells` samples: the slow tone of
# the wall along that edge (the shader reads it with linear filtering).
func _tone(image: Image, area: Rect2i, cells: Vector2i) -> ImageTexture:
	var strip := image.get_region(area)
	strip.resize(cells.x, cells.y, Image.INTERPOLATE_TRILINEAR)
	return ImageTexture.create_from_image(strip)

func _draw() -> void:
	if material == null:
		return
	var size := texture.get_size()
	var inner := Rect2(inner_position, size)
	var f := feather
	# Above the picture, its whole width, plus the fade over the picture's top edge.
	draw_rect(Rect2(outer.position.x, outer.position.y, outer.size.x, inner.position.y + f - outer.position.y), Color.WHITE)
	# Left of the picture: the fade over the left edge only above the counter.
	var fade_end := inner.position.y + counter_top
	draw_rect(Rect2(outer.position.x, inner.position.y + f, inner.position.x + f - outer.position.x, fade_end - inner.position.y - f), Color.WHITE)
	draw_rect(Rect2(outer.position.x, fade_end, inner.position.x - outer.position.x, inner.end.y - fade_end), Color.WHITE)
	# Right of the picture (the fridge stands against the fill, no fade over it).
	draw_rect(Rect2(inner.end.x, inner.position.y + f, outer.end.x - inner.end.x, inner.end.y - inner.position.y - f), Color.WHITE)
