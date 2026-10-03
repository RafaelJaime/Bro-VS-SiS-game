extends Control
## Credits screen: each author sits on their own side with the illustration's cut
## edge glued to the bottom of the screen. On open the art slides in from its side,
## then breathes (scaled around the bottom edge, so the cut never leaves the
## screen bottom), a light sweep crosses it every few seconds and the names pop in.

const SLIDE_TIME := 0.6
const POP_TIME := 0.3
const BREATH_SCALE := 1.014
const BREATH_TIME := 2.2
const SWEEP_TIME := 0.9
const SWEEP_PERIOD := 4.5
const COLUMN_WIDTH := 400.0

@onready var _columns: Array[Dictionary] = [
	{"art": $MatildeButton/Art, "label": $MatildeButton/VBoxContainer/MLabel, "from_left": true, "sweep_delay": 1.6},
	{"art": $RafaelButton/Art, "label": $RafaelButton/VBoxContainer/RLabel, "from_left": false, "sweep_delay": 3.8},
]

func _ready() -> void:
	var screen_height := get_viewport_rect().size.y
	for column in _columns:
		var art: TextureRect = column["art"]
		var label: Label = column["label"]
		var tex_size := art.texture.get_size()
		art.size = Vector2(art.size.y * tex_size.x / tex_size.y, art.size.y)
		art.pivot_offset = Vector2(art.size.x / 2.0, art.size.y)
		var rest_x := (COLUMN_WIDTH - art.size.x) / 2.0
		var rest_y := screen_height - art.size.y  # the button spans the full screen height, so its local y is the screen y
		art.position = Vector2(_start_x(column), rest_y)
		column["rest_x"] = rest_x
		label.pivot_offset = label.custom_minimum_size / 2.0
		label.scale = Vector2.ZERO
		_play_intro(column)

func _start_x(column: Dictionary) -> float:
	var art: TextureRect = column["art"]
	return -art.size.x - 10.0 if column["from_left"] else COLUMN_WIDTH + 10.0

func _play_intro(column: Dictionary) -> void:
	var art: TextureRect = column["art"]
	var label: Label = column["label"]
	var slide := create_tween()
	slide.tween_property(art, "position:x", column["rest_x"], SLIDE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	slide.tween_callback(_start_idle.bind(column))
	var pop := create_tween()
	pop.tween_interval(SLIDE_TIME)
	pop.tween_property(label, "scale", Vector2.ONE * 1.1, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(label, "scale", Vector2.ONE, 0.12)

func _start_idle(column: Dictionary) -> void:
	var art: TextureRect = column["art"]
	var breath := create_tween().set_loops()
	breath.tween_property(art, "scale", Vector2.ONE * BREATH_SCALE, BREATH_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breath.tween_property(art, "scale", Vector2.ONE, BREATH_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var first := create_tween()
	first.tween_interval(column["sweep_delay"])
	first.tween_callback(_start_sweep_loop.bind(art))

func _start_sweep_loop(art: TextureRect) -> void:
	play_sweep(art)
	var loop := create_tween().set_loops()
	loop.tween_interval(SWEEP_PERIOD)
	loop.tween_callback(play_sweep.bind(art))

## Runs one light sweep across an illustration (also called by the periodic loop).
func play_sweep(art: TextureRect) -> void:
	var material := art.material as ShaderMaterial
	material.set_shader_parameter("sweep", -0.3)
	var tween := create_tween()
	tween.tween_property(material, "shader_parameter/sweep", 1.3, SWEEP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_rafael_button_pressed() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open('https://huggingface.co/spaces/RafaelJaime', '_blank')")

func _on_matilde_button_pressed() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open('https://linktr.ee/mati_mola', '_blank')")
