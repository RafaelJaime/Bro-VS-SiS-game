extends Control

@export var player1: Fighter
@export var player2: Fighter

@onready var winner_name_label: Label = $CenterContainer/VBoxContainer/HBoxContainer/WinnerNameLabel
@onready var up_gpu_particles_2d_5: GPUParticles2D = $UpGPUParticles2D
@onready var winner_label: Label = $CenterContainer/VBoxContainer/HBoxContainer/WinnerLabel

# Set by Game right before this is made visible when the match ended by
# stock elimination, so the correct (unambiguous) winner is shown instead of
# falling back to the damage % comparison below. Full stocks-first win logic
# (more stocks wins, tie -> lower %, else draw) lands in T4; this only fixes
# the elimination case, which T2's ring-out/stocks made reachable.
var forced_winner: Fighter = null

func _ready():
	connect("visibility_changed", _on_visibility_changed)

func set_forced_winner(winner: Fighter) -> void:
	forced_winner = winner

func _on_visibility_changed():
	if visible and player1 and player2:
		var winner: Fighter = forced_winner
		if winner == null:
			if player1.damage_percent == player2.damage_percent:
				winner_name_label.text = ""
				winner_label.text = "Draw"
				up_gpu_particles_2d_5.modulate = Color(1, 1, 1, 1)
				return
			# Interim rule for a timeout (no elimination) until T4: lower % wins.
			winner = player1 if player1.damage_percent < player2.damage_percent else player2
		winner_name_label.text = winner.character_ui.name
		winner_name_label.add_theme_color_override("font_color", winner.character_ui.color)
		up_gpu_particles_2d_5.modulate = winner.character_ui.color
	else:
		push_error("P1 or P2 is not configured")

func _on_replay_button_pressed() -> void:
	SceneManager.change_scene("res://ui/character_select/character_select.tscn")
	get_tree().paused = false

func _on_main_menu_button_pressed() -> void:
	SceneManager.change_scene("res://ui/main_menu/main_menu.tscn")
	get_tree().paused = false
