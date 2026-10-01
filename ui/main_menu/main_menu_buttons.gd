extends Node2D

func _on_play_button_pressed() -> void:
	SceneManager.change_scene("res://ui/character_select/character_select.tscn")

func _on_instructions_button_pressed() -> void:
	SceneManager.change_scene("res://ui/instructions/instructions.tscn")

func _on_credits_button_pressed() -> void:
	SceneManager.change_scene("res://ui/credits/credits.tscn")
