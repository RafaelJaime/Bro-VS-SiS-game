extends Node2D

@export var training: bool = false

@onready var game_over: Control = $UI/GameOver
@onready var fighter_1: Fighter = $Fighter1
@onready var fighter_2: Fighter = $Fighter2
@onready var timer: Timer = $Timer

func _on_hurt_player_defeated(_player_instance: Fighter) -> void:
	_game_over()

func _on_timer_timeout() -> void:
	_game_over()

func _game_over() -> void:
	if training:
		_reset_players_for_training()
	else:
		get_tree().paused = true
		game_over.visible = true

func _reset_players_for_training() -> void:
	if fighter_1:
		fighter_1.reset_player()
	
	if fighter_2:
		fighter_2.reset_player()
	
	if timer:
		timer.stop()
		timer.start()
