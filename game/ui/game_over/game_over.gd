extends Control

@export var player1: Fighter
@export var player2: Fighter

@onready var winner_name_label: Label = %WinnerNameLabel
@onready var up_gpu_particles_2d_5: GPUParticles2D = $UpGPUParticles2D
@onready var winner_panel: ResultsPanel = %WinnerPanel
@onready var loser_panel: ResultsPanel = %LoserPanel
@onready var winner_label: Label = %WinnerLabel
@onready var stats_label: Label = %StatsLabel
@onready var loser_label: Label = %LoserLabel
@onready var characters_button: Button = %CharactersButton

# Set by Game when the match is decided (elimination, or more stocks at
# time-up; a tie goes to sudden death, so there is always a winner).
var forced_winner: Fighter = null

## Focus-highlight scale of a menu button.
const FOCUS_SCALE := 1.12

func _ready():
	connect("visibility_changed", _on_visibility_changed)
	for button in [characters_button]:
		button.pivot_offset = button.custom_minimum_size / 2.0
		button.focus_entered.connect(_set_highlight.bind(button, true))
		button.focus_exited.connect(_set_highlight.bind(button, false))
		button.mouse_entered.connect(button.grab_focus)

func set_forced_winner(winner: Fighter) -> void:
	forced_winner = winner

# A focused (or hovered) button grows and its caption turns yellow.
func _set_highlight(button: Button, on: bool) -> void:
	var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(button, "scale", Vector2.ONE * (FOCUS_SCALE if on else 1.0), 0.1)
	var caption := button.get_node("Caption") as Label
	caption.add_theme_color_override("font_color", Color(1, 0.9, 0.2) if on else Color.WHITE)

func _on_visibility_changed():
	if visible and player1 and player2:
		var winner: Fighter = forced_winner
		if winner == null:
			winner_name_label.text = ""
			winner_label.text = "DRAW"
			winner_panel.texture = null
			winner_panel.color = Color(0.5, 0.5, 0.5)
			loser_panel.visible = false
			loser_label.text = ""
			stats_label.text = "Stocks left %d - %d" % [player1.stocks, player2.stocks]
			up_gpu_particles_2d_5.modulate = Color(1, 1, 1, 1)
			characters_button.grab_focus()
			return
		var loser: Fighter = player2 if winner == player1 else player1
		winner_label.text = "WINS!"
		_set_art(winner_panel, winner_texture(winner.character_ui))
		winner_panel.color = winner.character_ui.color
		winner_name_label.text = winner.character_ui.name.to_upper()
		winner_name_label.add_theme_color_override("font_color", winner.character_ui.color.lightened(0.45))
		up_gpu_particles_2d_5.modulate = winner.character_ui.color
		loser_panel.visible = true
		_set_art(loser_panel, face_texture(loser.character_ui))
		loser_panel.color = loser.character_ui.color
		loser_label.text = loser.character_ui.name.to_upper()
		stats_label.text = stats_text(winner, loser)
		characters_button.grab_focus()
	elif visible:
		push_error("P1 or P2 is not configured")

## Final stats of the winner: opponents knocked out, stocks left, damage taken.
static func stats_text(winner: Fighter, loser: Fighter) -> String:
	var kos := Fighter.MAX_STOCKS - maxi(loser.stocks, 0)
	return "KOs  %d\nStocks left  %d\nDamage taken  %d%%" % [kos, maxi(winner.stocks, 0), int(winner.damage_percent)]

## A tall illustration is shown as a bust (cut at the chest by the panel edge);
## a face portrait is shown whole.
const ART_ILLUSTRATION_CROP := 0.62

func _set_art(panel: ResultsPanel, art: Texture2D) -> void:
	panel.texture = art
	var tall := art != null and art.get_height() > art.get_width() * 1.2
	panel.crop = ART_ILLUSTRATION_CROP if tall else 1.0

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

## The face portrait, else the winner art.
static func face_texture(character: CharacterUI) -> Texture2D:
	if character == null:
		return null
	if character.face_texture:
		return character.face_texture
	return winner_texture(character)

func _on_characters_button_pressed() -> void:
	get_tree().paused = false
	SceneManager.change_scene("res://ui/character_select/character_select.tscn")
