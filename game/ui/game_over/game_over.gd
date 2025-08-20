extends Control

@export var player1: Fighter
@export var player2: Fighter

@onready var winner_name_label: Label = $CenterContainer/VBoxContainer/HBoxContainer/WinnerNameLabel

func _ready():
	connect("visibility_changed", _on_visibility_changed)

func _on_visibility_changed():
	if visible and player1 and player2:
		winner_name_label.text = player1.player_name if player1.health > player2.health else player2.player_name
		winner_name_label.add_theme_color_override("font_color", player1.color if player1.health > player2.health else player2.color)
	else:
		assert("P1 or P2 is not configured")
func _on_replay_button_pressed() -> void:
	SceneManager.change_scene("res://ui/character_select/character_select.tscn")

func _on_main_menu_button_pressed() -> void:
	SceneManager.change_scene("res://ui/main_menu/main_menu.tscn")
