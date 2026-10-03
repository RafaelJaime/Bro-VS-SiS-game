extends Sprite2D
class_name ShieldBubble

## The shield bubble around a fighter: visible while it is shielding (the Protect
## state) and while it shrinks away during the shield drop lag. It is tinted with
## the fighter's player colour (the CharacterUI colour the HUD panel uses), shrinks
## as the meter drains and, when the shield gets weak, fades and pulses instead of
## changing colour, so the player's colour stays readable. It reuses the glow
## texture of the charge effect with an additive material, so it needs no new
## asset, and it never touches the fighter sprite. Training rows keep it hidden
## with processing off.

## Sprite scale at an empty and at a full meter (the glow texture is 512 px).
@export var scale_empty: float = 0.22
@export var scale_full: float = 0.52
@export var alpha: float = 0.9
## Below this meter ratio the bubble fades and pulses.
@export var weak_ratio: float = 0.35
## Alpha multiplier at an empty meter (before the pulse).
@export var weak_alpha: float = 0.5
@export var pulse_hz: float = 4.0
## How far the player colour is mixed towards white so the additive glow reads
## (the hue does not change).
@export var brighten: float = 0.2

func _ready() -> void:
	visible = false
	var fighter := owner as Fighter
	var game := fighter.get_parent() if fighter else null
	if fighter == null or (game != null and game.get("training") == true):
		set_process(false)

## The colour of a fighter's shield: its player colour, from the same CharacterUI
## the HUD panel reads (white until a character is assigned).
static func player_color(fighter: Fighter) -> Color:
	return fighter.character_ui.color if fighter.character_ui else Color.WHITE

## Bubble colour for a meter `ratio`, a drop `progress` (-1 when shielding) and the
## pulse phase in seconds.
func bubble_color(base: Color, ratio: float, drop_progress: float, seconds: float) -> Color:
	var a := alpha
	if ratio < weak_ratio:
		a *= lerpf(weak_alpha, 1.0, ratio / weak_ratio)
		a *= 0.8 + 0.2 * sin(seconds * TAU * pulse_hz)
	if drop_progress >= 0.0:
		a *= 1.0 - drop_progress
	var c := base.lightened(brighten)
	return Color(c.r, c.g, c.b, a)

func _process(_delta: float) -> void:
	var fighter := owner as Fighter
	if fighter == null or fighter.shield == null:
		visible = false
		return
	var drop := fighter.shield_drop_progress()
	if not fighter.is_shielding() and drop < 0.0:
		visible = false
		return
	var ratio := fighter.shield.ratio()
	var size := lerpf(scale_empty, scale_full, ratio)
	if drop >= 0.0:
		size *= 1.0 - drop
	scale = Vector2.ONE * size
	modulate = bubble_color(player_color(fighter), ratio, drop, Time.get_ticks_msec() / 1000.0)
	visible = true
