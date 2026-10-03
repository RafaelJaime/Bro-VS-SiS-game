extends Node2D
class_name DizzyStars

## The dizzy cue: three stars orbiting above the head plus a sprite wobble, shown
## only while the fighter is in the Dizzy state. Built from the existing
## `T_LeLuStar11` texture with an additive material (a black-background jpg). It
## never touches the fighter sprite's `visible` (Fighter._apply_visibility owns it),
## only its `offset`, and puts it back when the dizzy ends. Training keeps it off.

@export var star_texture: Texture2D
## The texture carries a "LE LU" caption above the star: only this region (the star)
## is drawn.
@export var star_region: Rect2 = Rect2(170.0, 330.0, 700.0, 660.0)
@export var star_count: int = 3
@export var star_scale: float = 0.05
## Orbit centre above the origin, horizontal radius and the squash of the ellipse.
@export var orbit_center: Vector2 = Vector2(0.0, -105.0)
@export var orbit_radius: float = 38.0
@export var orbit_squash: float = 0.3
@export var orbit_speed: float = 4.5
@export var wobble_pixels: float = 3.0

var _stars: Array[Sprite2D] = []
var _wobbling: bool = false

func _ready() -> void:
	visible = false
	var fighter := owner as Fighter
	var game := fighter.get_parent() if fighter else null
	if fighter == null or (game != null and game.get("training") == true):
		set_process(false)
		return
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for i in star_count:
		var star := Sprite2D.new()
		star.texture = star_texture
		star.region_enabled = true
		star.region_rect = star_region
		star.material = material
		star.scale = Vector2.ONE * star_scale
		star.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(star)
		_stars.append(star)

func _process(_delta: float) -> void:
	var fighter := owner as Fighter
	var dizzy := fighter != null and fighter.is_dizzy()
	visible = dizzy
	if not dizzy:
		if _wobbling:
			_wobbling = false
			fighter.animated_sprite_2d.offset = Vector2.ZERO
		return
	var seconds := Time.get_ticks_msec() / 1000.0
	for i in _stars.size():
		var angle := seconds * orbit_speed + TAU * float(i) / float(_stars.size())
		_stars[i].position = orbit_center + Vector2(cos(angle) * orbit_radius, sin(angle) * orbit_radius * orbit_squash)
		_stars[i].z_index = 1 if sin(angle) > 0.0 else -1
	_wobbling = true
	fighter.animated_sprite_2d.offset = Vector2(sin(seconds * TAU * 7.0) * wobble_pixels, 0.0)
