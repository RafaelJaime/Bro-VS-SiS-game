extends Node2D

func _on_play_button_pressed() -> void:
	SceneManager.change_scene("res://ui/character_select/character_select.tscn")

func _on_intructions_button_pressed() -> void:
	print("_on_intructions_button_pressed")


func _on_credits_button_pressed() -> void:
	print("_on_credits_button_pressed")
