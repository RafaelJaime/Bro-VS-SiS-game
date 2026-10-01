extends Control

@export var player1: Fighter
@export var player2: Fighter

@onready var winner_name_label: Label = $CenterContainer/VBoxContainer/HBoxContainer/WinnerNameLabel
@onready var up_gpu_particles_2d_5: GPUParticles2D = $UpGPUParticles2D
@onready var winner_portrait: TextureRect = $CenterContainer/VBoxContainer/WinnerPortrait
@onready var winner_label: Label = $CenterContainer/VBoxContainer/HBoxContainer/WinnerLabel
@onready var replay_button: Button = $CenterContainer/VBoxContainer/HBoxContainer2/ReplayButton

# Set by Game when the match is decided (elimination, or more stocks at
# time-up; a tie goes to sudden death, so there is always a winner).
var forced_winner: Fighter = null

func _ready():
	connect("visibility_changed", _on_visibility_changed)

func set_forced_winner(winner: Fighter) -> void:
	forced_winner = winner

func _on_visibility_changed():
	if visible and player1 and player2:
		var winner: Fighter = forced_winner
		if winner == null:
			winner_name_label.text = ""
			winner_label.text = "DRAW"
			winner_portrait.texture = null
			up_gpu_particles_2d_5.modulate = Color(1, 1, 1, 1)
			replay_button.grab_focus()
			return
		winner_label.text = " WINS!"
		winner_portrait.texture = winner_texture(winner.character_ui)
		winner_name_label.text = winner.character_ui.name.to_upper()
		winner_name_label.add_theme_color_override("font_color", winner.character_ui.color.lightened(0.45))
		up_gpu_particles_2d_5.modulate = winner.character_ui.color
		replay_button.grab_focus()
	elif visible:
		push_error("P1 or P2 is not configured")

# Winner art: the character select's illustration, else the face portrait; the
# built-in fighters carry neither, so fall back to the art next to their sprites.
const ART_DIR := "res://assets/images/game/characters/%s/%s"

static func winner_texture(character: CharacterUI) -> Texture2D:
	if character == null:
		return null
	if character.illustration:
		return character.illustration
	if character.face_texture:
		return character.face_texture
	var key := character.name.to_lower()
	var initial := key.substr(0, 1)
	for path in [ART_DIR % [key, "ilustration/Ilustracion_%s1.png" % initial], ART_DIR % [key, "face/%s_014.png" % initial]]:
		if ResourceLoader.exists(path):
			return load(path)
	return null

func _on_replay_button_pressed() -> void:
	get_tree().paused = false
	SceneManager.rematch()

func _on_characters_button_pressed() -> void:
	get_tree().paused = false
	SceneManager.change_scene("res://ui/character_select/character_select.tscn")

func _on_main_menu_button_pressed() -> void:
	get_tree().paused = false
	SceneManager.change_scene("res://ui/main_menu/main_menu.tscn")
