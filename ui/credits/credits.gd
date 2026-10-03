extends Control
## Credits screen: each author sits on their own side with the illustration's cut
## edge glued to the bottom of the screen. On open the art slides in from its side.

const SLIDE_TIME := 0.6
const COLUMN_WIDTH := 400.0

@onready var _columns: Array[Dictionary] = [
	{"art": $MatildeButton/Art, "from_left": true},
	{"art": $RafaelButton/Art, "from_left": false},
]

func _ready() -> void:
	var screen_height := get_viewport_rect().size.y
	for column in _columns:
		var art: TextureRect = column["art"]
		var tex_size := art.texture.get_size()
		art.size = Vector2(art.size.y * tex_size.x / tex_size.y, art.size.y)
		var rest_x := (COLUMN_WIDTH - art.size.x) / 2.0
		var rest_y := screen_height - art.size.y  # the button spans the full screen height, so its local y is the screen y
		art.position = Vector2(_start_x(column), rest_y)
		column["rest_x"] = rest_x
		_play_intro(column)

func _start_x(column: Dictionary) -> float:
	var art: TextureRect = column["art"]
	return -art.size.x - 10.0 if column["from_left"] else COLUMN_WIDTH + 10.0

func _play_intro(column: Dictionary) -> void:
	var art: TextureRect = column["art"]
	var slide := create_tween()
	slide.tween_property(art, "position:x", column["rest_x"], SLIDE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_rafael_button_pressed() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open('https://huggingface.co/spaces/RafaelJaime', '_blank')")

func _on_matilde_button_pressed() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open('https://linktr.ee/mati_mola', '_blank')")
