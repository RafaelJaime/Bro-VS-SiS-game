extends Node2D

@export var training: bool = false

@onready var game_over: Control = $UI/GameOver
@onready var fighter_1: Fighter = $Fighter1
@onready var fighter_2: Fighter = $Fighter2
@onready var timer: Timer = $Timer
@onready var music_player: AudioStreamPlayer = $MusicPlayer

# Loaded via load() at runtime, not preload()/ext_resource: this freesound
# asset has no .import file yet (same caveat as T0's food sprites).
const MUSIC_PATH := "res://assets/sounds/freesound/466126__nightwolfcfm__run-cinematic-music.mp3"

func _ready() -> void:
	# Skip music during AI training (train.tscn runs many Game instances in
	# parallel, so playing it there would just be noise).
	if not training:
		_start_music()

func _start_music() -> void:
	if not music_player:
		return
	var stream = load(MUSIC_PATH)
	if not stream:
		push_warning("Game: could not load music stream " + MUSIC_PATH)
		return
	if "loop" in stream:
		stream.loop = true
	music_player.stream = stream
	music_player.volume_db = -8.0
	music_player.play()

func _on_player_defeated(player_instance: Fighter) -> void:
	if player_instance and player_instance.enemy is Fighter:
		game_over.set_forced_winner(player_instance.enemy)
	_game_over()

func _on_timer_timeout() -> void:
	game_over.set_forced_winner(null)
	_game_over()

func _game_over() -> void:
	if training:
		_reset_players_for_training()
	else:
		if music_player:
			music_player.stop()
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
