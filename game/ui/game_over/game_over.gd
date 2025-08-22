extends Control

@export var player1: Fighter
@export var player2: Fighter

@onready var winner_name_label: Label = $CenterContainer/VBoxContainer/HBoxContainer/WinnerNameLabel
@onready var up_gpu_particles_2d_5: GPUParticles2D = $UpGPUParticles2D

func _ready():
	connect("visibility_changed", _on_visibility_changed)

func _on_visibility_changed():
	if visible and player1 and player2:
		var winner: Fighter = player1 if player1.health > player2.health else player2
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
