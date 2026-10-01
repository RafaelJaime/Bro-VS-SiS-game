extends Node2D

@export var training: bool = false

# Ring-out bounds (blast zones), local to this Game so offset rows (train.tscn)
# work. Smash has a top blast zone as well as the sides and the bottom. The
# world art is 1176x902; the zones sit just outside the visible stage.
@export var blast_left: float = -100.0
@export var blast_right: float = 1276.0
@export var blast_top: float = -400.0
@export var blast_bottom: float = 810.0

@onready var game_over: Control = $UI/GameOver
@onready var fighter_1: Fighter = $Fighter1
@onready var fighter_2: Fighter = $Fighter2
@onready var timer: Timer = $Timer
@onready var music_player: AudioStreamPlayer = $MusicPlayer

# Loaded via load() at runtime, not preload()/ext_resource: this freesound
# asset has no .import file yet (same caveat as T0's food sprites).
const MUSIC_PATH := "res://assets/sounds/freesound/466126__nightwolfcfm__run-cinematic-music.mp3"

func _ready() -> void:
	var blast_zone := Rect2(blast_left, blast_top, blast_right - blast_left, blast_bottom - blast_top)
	fighter_1.blast_zone = blast_zone
	fighter_2.blast_zone = blast_zone

	# The kitchen art is only for human matches: train.tscn runs 25 Game
	# instances and would just pay for 25 copies of a 1176x902 texture.
	if training and has_node("Backdrop"):
		$Backdrop.queue_free()

	# Skip music during AI training (train.tscn runs many Game instances in
	# parallel, so playing it there would just be noise).
	if not training:
		_start_music()

func _exit_tree() -> void:
	# A hit-stop still running when the match ends must not leave the whole game
	# slowed. Training never touches Engine.time_scale (Sync owns it there).
	if not training:
		Combat.cancel_hit_stop()

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

## Read-only view of the match for consumers such as the CPU and the future
## schema module. Unversioned and not a schema: it is an open Dictionary, keys
## may be added later, and nothing here is a stable contract yet. All positions
## are local to this Game, so offset rows (train.tscn) work.
func get_state_snapshot() -> Dictionary:
	var foods: Array = []
	var projectiles: Array = []
	for child in get_children():
		if child is FoodPickup and not child.picked_up:
			foods.append({"name": child.food_name, "position": child.position})
		elif child is FoodProjectile:
			projectiles.append({
				"position": child.position,
				"velocity": child.velocity,
				"shooter": 1 if child.shooter == fighter_1 else 2,
			})

	var floor_shape := get_node_or_null("StaticBody2D/Floor") as CollisionShape2D
	var camera := get_node_or_null("Camera2D") as Camera2D
	return {
		"phase": "playing", # Placeholder until the match phase machine exists.
		"timer_left": timer.time_left if timer else 0.0,
		"timer_running": timer != null and not timer.is_stopped(),
		"sudden_death": false,
		"stage": _shape_bounds(floor_shape) if floor_shape else {},
		"platforms": [], # The counter is the only surface.
		"blast_zone": {
			"left": blast_left,
			"right": blast_right,
			"top": blast_top,
			"bottom": blast_bottom,
		},
		"camera": {
			"center": camera.get_screen_center_position() if camera else Vector2.ZERO,
			"zoom": camera.zoom.x if camera else 1.0,
		},
		"foods": foods,
		"projectiles": projectiles,
		"fighters": [
			fighter_1.get_state_snapshot() if fighter_1 else {},
			fighter_2.get_state_snapshot() if fighter_2 else {},
		],
	}

# Top surface and horizontal extent of a rectangle collider, Game-local.
func _shape_bounds(shape_node: CollisionShape2D) -> Dictionary:
	var rect_shape := shape_node.shape as RectangleShape2D
	var center := to_local(shape_node.global_position)
	if rect_shape == null:
		return {"left": center.x, "right": center.x, "top": center.y}
	var half := rect_shape.size / 2.0
	return {"left": center.x - half.x, "right": center.x + half.x, "top": center.y - half.y}

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
