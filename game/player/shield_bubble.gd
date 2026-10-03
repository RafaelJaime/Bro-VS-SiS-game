extends Sprite2D
class_name ShieldBubble

## The shield bubble around a fighter: visible only while it is shielding (the
## Protect state), it shrinks as the meter drains and goes from the character's
## colour to red as the shield gets weak. It reuses the glow texture of the charge
## effect with an additive material, so it needs no new asset, and it never touches
## the fighter sprite. Training rows keep it hidden with processing off.

## Sprite scale at an empty and at a full meter (the glow texture is 512 px).
@export var scale_empty: float = 0.22
@export var scale_full: float = 0.52
@export var alpha: float = 0.9

func _ready() -> void:
	visible = false
	var fighter := owner as Fighter
	var game := fighter.get_parent() if fighter else null
	if fighter == null or (game != null and game.get("training") == true):
		set_process(false)

func _process(_delta: float) -> void:
	var fighter := owner as Fighter
	if fighter == null or fighter.shield == null or not fighter.is_shielding():
		visible = false
		return
	var ratio := fighter.shield.ratio()
	var base: Color = fighter.character_ui.color if fighter.character_ui else Color.WHITE
	scale = Vector2.ONE * lerpf(scale_empty, scale_full, ratio)
	modulate = Color(base.lightened(0.35).lerp(Color(1.0, 0.15, 0.1), 1.0 - ratio), alpha)
	visible = true
