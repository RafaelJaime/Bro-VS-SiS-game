extends Node2D
class_name Game

## Match phases. COUNTDOWN: fighters locked, timer stopped ("3, 2, 1, GO!").
## PLAYING: the timed match. SUDDEN_DEATH: after a tie at time-up, everybody at
## 300% and one stock, the next KO ends it. OVER: "GAME!" then the results.
enum Phase { COUNTDOWN, PLAYING, SUDDEN_DEATH, OVER }

## Emitted with the text of every countdown beat ("3", "2", "1", "GO!").
signal countdown_tick(text: String)
## Emitted once when the match is decided (never in training).
signal match_over(winner: Fighter)

@export var training: bool = false

# Match flow timings (seconds), all tunable.
@export_group("Match flow")
@export var countdown_step: float = 0.9
@export var go_hold: float = 0.7
@export var sudden_death_intro: float = 1.8
## Damage % both fighters start sudden death with (Smash rule).
@export var sudden_death_damage: float = 300.0
## "GAME!" runs in slow motion for slow_motion_duration real seconds at
## slow_motion_scale, and the results appear game_over_delay real seconds after.
@export var slow_motion_scale: float = 0.3
@export var slow_motion_duration: float = 1.2
@export var game_over_delay: float = 1.6

# Ring-out bounds (blast zones), local to this Game so offset rows (train.tscn)
# work. Smash has a top blast zone as well as the sides and the bottom. The
# table spans x 30..830 and the camera never shows beyond the backdrop
# (x -158..1018), so the side zones sit just outside what can be seen.
@export var blast_left: float = -230.0
@export var blast_right: float = 1090.0
@export var blast_top: float = -400.0
@export var blast_bottom: float = 810.0

## Table legs at both ends of the table are grab zones (Smash ledge). They run
## from the tabletop down to the bottom of the legs; when a TableStage is present
## its leg bottom wins over this default (floor top 480, leg bottom 738).
@export var ledge_depth: float = 258.0

@onready var game_over: Control = get_node_or_null("UI/GameOver")
@onready var fighter_1: Fighter = $Fighter1
@onready var fighter_2: Fighter = $Fighter2
@onready var timer: Timer = $Timer
@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var food_spawner: FoodSpawner = get_node_or_null("FoodSpawner")
@onready var countdown_label: Label = get_node_or_null("UI/CountdownLabel")
@onready var timer_label: Control = get_node_or_null("UI/TimerLabel")

const COUNTDOWN_BEATS: Array[Dictionary] = [
	{"text": "3", "color": Color(1.0, 1.0, 1.0), "pitch": 0.9},
	{"text": "2", "color": Color(1.0, 0.92, 0.3), "pitch": 1.0},
	{"text": "1", "color": Color(1.0, 0.55, 0.15), "pitch": 1.12},
]
const GO_COLOR := Color(0.45, 1.0, 0.45)
const GAME_COLOR := Color(1.0, 0.85, 0.2)
const SUDDEN_DEATH_COLOR := Color(1.0, 0.25, 0.2)

## Who won; null until the match is decided.
var winner: Fighter = null
var phase: Phase = Phase.PLAYING

# One node-owned timer drives every timed beat (countdown, sudden death intro,
# the delay before the results). It is a child, so it pauses with the game and
# dies with the Game: no coroutine can outlive a rematch or a scene change.
var _flow_timer: Timer
var _flow_callback: Callable
var _countdown_index: int = 0
var _skip_pending: bool = false
var _banner_tween: Tween
var _ledges: Array = []

# Loaded via load() at runtime, not preload()/ext_resource: this freesound
# asset has no .import file yet (same caveat as T0's food sprites).
const MUSIC_PATH := "res://assets/sounds/freesound/466126__nightwolfcfm__run-cinematic-music.mp3"

func _ready() -> void:
	var blast_zone := Rect2(blast_left, blast_top, blast_right - blast_left, blast_bottom - blast_top)
	fighter_1.blast_zone = blast_zone
	fighter_2.blast_zone = blast_zone

	# The kitchen art and the table are only for human matches: train.tscn runs
	# 25 Game instances and would just pay for 25 copies of a 1176x902 texture.
	if training:
		for decor in ["Backdrop", "TableStage"]:
			if has_node(decor):
				get_node(decor).queue_free()

	_flow_timer = Timer.new()
	_flow_timer.one_shot = true
	add_child(_flow_timer)
	_flow_timer.timeout.connect(_on_flow_timeout)
	if countdown_label:
		countdown_label.visible = false
		countdown_label.resized.connect(_center_banner_pivot)
		_center_banner_pivot()

	# Skip music during AI training (train.tscn runs many Game instances in
	# parallel, so playing it there would just be noise).
	if not training:
		_start_music()
		if _skip_pending:
			_begin_match(false)
		else:
			_start_countdown()
	else:
		# Training starts at once, as before the phase machine existed.
		_begin_match(false)

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
	var ledges: Array = get_ledges().duplicate(true)
	for ledge: Dictionary in ledges:
		ledge["occupied"] = (fighter_1 and fighter_1.ledge_side == ledge["side"]) or (fighter_2 and fighter_2.ledge_side == ledge["side"])
	var camera := get_node_or_null("Camera2D") as Camera2D
	return {
		"phase": String(Phase.find_key(phase)).to_lower(),
		"timer_left": timer.time_left if timer else 0.0,
		"timer_running": timer != null and not timer.is_stopped(),
		"sudden_death": phase == Phase.SUDDEN_DEATH,
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
		"ledges": ledges,
		"foods": foods,
		"projectiles": projectiles,
		"fighters": [
			fighter_1.get_state_snapshot() if fighter_1 else {},
			fighter_2.get_state_snapshot() if fighter_2 else {},
		],
	}

## The two table legs a fighter can grab, Game-local: `side` -1 left end, +1 right
## end; `x` the table end (the fighter hangs just outside it); `top` the tabletop;
## `bottom` the lowest grab height. Empty in training (the table is not there and
## the RL environment stays as it was).
func get_ledges() -> Array:
	if training:
		return []
	if _ledges.is_empty():
		var floor_shape := get_node_or_null("StaticBody2D/Floor") as CollisionShape2D
		if floor_shape == null:
			return []
		var bounds := _shape_bounds(floor_shape)
		var depth := ledge_depth
		var table := get_node_or_null("TableStage") as TableStage
		if table != null and table.floor_y > 0.0:
			depth = table.floor_y - bounds["top"]
		for side in [-1, 1]:
			_ledges.append({
				"side": side,
				"x": bounds["left"] if side < 0 else bounds["right"],
				"top": bounds["top"],
				"bottom": bounds["top"] + depth,
			})
	return _ledges

# Top surface and horizontal extent of a rectangle collider, Game-local.
func _shape_bounds(shape_node: CollisionShape2D) -> Dictionary:
	var rect_shape := shape_node.shape as RectangleShape2D
	var center := to_local(shape_node.global_position)
	if rect_shape == null:
		return {"left": center.x, "right": center.x, "top": center.y}
	var half := rect_shape.size / 2.0
	return {"left": center.x - half.x, "right": center.x + half.x, "top": center.y - half.y}

# ---------------------------------------------------------------- match flow

func _start_countdown() -> void:
	phase = Phase.COUNTDOWN
	_lock_fighters(true)
	_countdown_index = 0
	_countdown_next()

func _countdown_next() -> void:
	if _countdown_index >= COUNTDOWN_BEATS.size():
		_begin_match(true)
		return
	var beat: Dictionary = COUNTDOWN_BEATS[_countdown_index]
	_show_banner(beat["text"], beat["color"], 170)
	countdown_tick.emit(beat["text"])
	Sfx.play_event(&"countdown", self, beat["pitch"])
	_countdown_index += 1
	_after(countdown_step, _countdown_next)

## GO: input is accepted, the timer and the food spawner start.
func _begin_match(announce: bool) -> void:
	phase = Phase.PLAYING
	_lock_fighters(false)
	timer.start()
	if food_spawner:
		food_spawner.start()
	if announce:
		_show_banner("GO!", GO_COLOR, 190, go_hold)
		countdown_tick.emit("GO!")
		Sfx.play_event(&"go", self)

## Ends the countdown at once and starts the match (used by tests and tools that
## do not want to sit through "3, 2, 1").
func skip_countdown() -> void:
	if not is_node_ready():
		# Called before _ready (the node was added during the engine's own
		# start-up): remember it, _ready then starts the match directly.
		_skip_pending = true
		return
	if phase != Phase.COUNTDOWN:
		return
	_flow_timer.stop()
	_flow_callback = Callable()
	_hide_banner()
	_begin_match(false)

func _lock_fighters(locked: bool) -> void:
	fighter_1.controls_locked = locked
	fighter_2.controls_locked = locked

func _after(seconds: float, callback: Callable, real_time: bool = false) -> void:
	_flow_callback = callback
	_flow_timer.ignore_time_scale = real_time
	_flow_timer.start(seconds)

func _on_flow_timeout() -> void:
	var callback := _flow_callback
	_flow_callback = Callable()
	if callback.is_valid():
		callback.call()

func _on_player_defeated(_player_instance: Fighter) -> void:
	if training:
		_reset_players_for_training()
		return
	# Deferred, so a double KO on the same frame is judged once, after both.
	_resolve_defeat.call_deferred()

func _resolve_defeat() -> void:
	if phase == Phase.OVER or phase == Phase.COUNTDOWN:
		return
	var alive_1 := fighter_1.stocks > 0
	var alive_2 := fighter_2.stocks > 0
	if alive_1 and alive_2:
		return
	if not alive_1 and not alive_2:
		# Smash: a simultaneous last KO is settled in sudden death.
		_start_sudden_death()
	else:
		_end_match(fighter_1 if alive_1 else fighter_2)

func _on_timer_timeout() -> void:
	if training:
		_reset_players_for_training()
		return
	if phase != Phase.PLAYING:
		return
	if fighter_1.stocks != fighter_2.stocks:
		_end_match(fighter_1 if fighter_1.stocks > fighter_2.stocks else fighter_2)
	else:
		_start_sudden_death()

func _start_sudden_death() -> void:
	phase = Phase.SUDDEN_DEATH
	timer.stop()
	if timer_label:
		timer_label.visible = false
	for fighter in [fighter_1, fighter_2]:
		fighter.prepare_sudden_death(sudden_death_damage)
	_lock_fighters(true)
	_show_banner("SUDDEN DEATH", SUDDEN_DEATH_COLOR, 84)
	Sfx.play_event(&"ko", self)
	_after(sudden_death_intro, _release_sudden_death)

func _release_sudden_death() -> void:
	if phase != Phase.SUDDEN_DEATH:
		return
	_lock_fighters(false)
	_fade_banner()

## "GAME!" in slow motion, then the results.
func _end_match(winning_fighter: Fighter) -> void:
	if phase == Phase.OVER:
		return
	phase = Phase.OVER
	winner = winning_fighter
	_flow_timer.stop()
	timer.stop()
	if food_spawner:
		food_spawner.stop()
	_lock_fighters(true)
	if game_over:
		game_over.set_forced_winner(winner)
	match_over.emit(winner)
	Combat.slow_motion(slow_motion_duration, slow_motion_scale)
	_show_banner("GAME!", GAME_COLOR, 170, 0.0, 1.0 / slow_motion_scale)
	Sfx.play_event(&"game", self)
	_after(game_over_delay, _show_results, true)

func _show_results() -> void:
	_hide_banner()
	if music_player:
		music_player.stop()
	Combat.cancel_hit_stop()
	if game_over:
		game_over.visible = true
	get_tree().paused = true

func _reset_players_for_training() -> void:
	if fighter_1:
		fighter_1.reset_player()

	if fighter_2:
		fighter_2.reset_player()

	if timer:
		timer.stop()
		timer.start()

# ------------------------------------------------------------------- banner

func _center_banner_pivot() -> void:
	if countdown_label:
		countdown_label.pivot_offset = countdown_label.size / 2.0

## Big centered text that pops in (scales down from 2.2x with an overshoot). With
## `hold` > 0 it fades out afterwards. `speed` compensates a slowed game clock.
func _show_banner(text: String, color: Color, font_size: int, hold: float = 0.0, speed: float = 1.0) -> void:
	if countdown_label == null:
		return
	if _banner_tween:
		_banner_tween.kill()
	countdown_label.text = text
	countdown_label.add_theme_font_size_override("font_size", font_size)
	countdown_label.add_theme_color_override("font_color", color)
	countdown_label.modulate.a = 1.0
	countdown_label.scale = Vector2.ONE * 2.2
	countdown_label.visible = true
	_banner_tween = create_tween()
	_banner_tween.set_speed_scale(speed)
	_banner_tween.tween_property(countdown_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if hold > 0.0:
		_banner_tween.tween_interval(hold)
		_banner_tween.tween_property(countdown_label, "modulate:a", 0.0, 0.25)
		_banner_tween.tween_callback(_hide_banner)

func _fade_banner() -> void:
	if countdown_label == null:
		return
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(countdown_label, "modulate:a", 0.0, 0.3)
	_banner_tween.tween_callback(_hide_banner)

func _hide_banner() -> void:
	if _banner_tween:
		_banner_tween.kill()
		_banner_tween = null
	if countdown_label:
		countdown_label.visible = false
