extends Node2D

@onready var game_over: Control = $UI/GameOver

func _on_hurt_player_defeated(_player_instance: Fighter) -> void:
	get_tree().paused = true
	game_over.visible = true
