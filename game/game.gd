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
## Training only: a row's episode ended (a defeat or the timer). `winner` is the
## fighter that still has stocks, or null for a draw. Fighters are not reset yet,
## so the listeners (RewardTracker) can still read the stocks of both.
signal training_episode_ended(winner: Fighter)

@export var training: bool = false

## Training only (`BVS_TRAIN_CONFIG.match` overrides them): a tied timer expiry
## enters sudden death instead of ending the episode, and a row can begin straight
## in sudden death. The training sudden death has no intro.
var training_sudden_death: bool = true
var training_start_in_sudden_death: bool = false
var training_sd_intro: float = 0.0
## Why the last training episode ended: &"ko", &"timeout" or &"sd_cap" (the safety
## cap of a sudden death that never produced a KO, a truncation).
var last_episode_end_reason: StringName = &"ko"

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
@onready var hazards: SuddenDeathHazards = get_node_or_null("SuddenDeathHazards")
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
# Physics frame of the last training episode end, so a defeat and a timeout (or two
# defeats) on the same frame end it once.
var _episode_end_frame: int = -1
# Fighters that still have to finish their reset before a training row may start in
# sudden death (see _end_training_episode).
var _pending_resets: int = 0

# Loaded via load() at runtime, not preload()/ext_resource: this freesound
# asset has no .import file yet (same caveat as T0's food sprites).
const MUSIC_PATH := "res://assets/sounds/freesound/466126__nightwolfcfm__run-cinematic-music.mp3"

func _ready() -> void:
	var blast_zone := Rect2(blast_left, blast_top, blast_right - blast_left, blast_bottom - blast_top)
	fighter_1.blast_zone = blast_zone
	fighter_2.blast_zone = blast_zone
	var table := get_node_or_null("TableStage") as TableStage
	if table != null and not training:
		fighter_1.defeat_floor_y = table.floor_y
		fighter_2.defeat_floor_y = table.floor_y
		var tabletop := get_stage_bounds()
		fighter_1.defeat_table = tabletop
		fighter_2.defeat_table = tabletop

	# The kitchen art and the table are only for human matches: train.tscn runs
	# 25 Game instances and would just pay for 25 copies of a 1176x902 texture.
	if training:
		for decor in ["Clouds", "Backdrop", "Cocina", "BackdropExtension", "TableStage"]:
			if has_node(decor):
				get_node(decor).queue_free()

	_flow_timer = Timer.new()
	_flow_timer.one_shot = true
	add_child(_flow_timer)
	_flow_timer.timeout.connect(_on_flow_timeout)
	if hazards:
		hazards.training_cap_reached.connect(_on_training_cap_reached)
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
		# 0 outside sudden death, 1 while it waits (intro and grace), 2 once bombs fall.
		"sudden_death_phase": 0 if phase != Phase.SUDDEN_DEATH else maxi(1, hazards.phase() if hazards else 1),
		"sudden_death_elapsed": hazards.elapsed_seconds() if hazards and phase == Phase.SUDDEN_DEATH else 0.0,
		"bombs": hazards.snapshot_bombs() if hazards and phase == Phase.SUDDEN_DEATH else [],
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
## `bottom` the lowest grab height. Training rows have the ledges too (the table
## art is freed there, so `ledge_depth` stands in for the leg height), so the
## agent learns the same recovery the match has.
func get_ledges() -> Array:
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

## Top surface and horizontal extent of the table, Game-local ({} without a floor).
func get_stage_bounds() -> Dictionary:
	var floor_shape := get_node_or_null("StaticBody2D/Floor") as CollisionShape2D
	return _shape_bounds(floor_shape) if floor_shape else {}

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
	if training and training_start_in_sudden_death:
		force_sudden_death()
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
		# Deferred, so a double KO on the same frame is judged once, after both.
		_resolve_training_defeat.call_deferred()
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
		# Time up: the fighter with more stocks wins the episode. A tie goes to
		# sudden death (no `done` yet) unless the row turned that off, then it is a draw.
		var leader: Fighter = null
		if fighter_1.stocks != fighter_2.stocks:
			leader = fighter_1 if fighter_1.stocks > fighter_2.stocks else fighter_2
		elif training_sudden_death:
			_start_sudden_death()
			return
		_end_training_episode(leader, &"timeout")
		return
	if phase != Phase.PLAYING:
		return
	if fighter_1.stocks != fighter_2.stocks:
		_end_match(fighter_1 if fighter_1.stocks > fighter_2.stocks else fighter_2)
	else:
		_start_sudden_death()

## Starts (or restarts, after a double KO) sudden death: both fighters at one
## stock and 300%, any bomb gone. The bombs begin once the intro is over.
func _start_sudden_death() -> void:
	phase = Phase.SUDDEN_DEATH
	timer.stop()
	if hazards:
		hazards.stop_and_clear()
	if timer_label:
		timer_label.visible = false
	for fighter in [fighter_1, fighter_2]:
		fighter.prepare_sudden_death(sudden_death_damage)
	_lock_fighters(true)
	_show_banner("SUDDEN DEATH", SUDDEN_DEATH_COLOR, 84)
	Sfx.play_event(&"ko", self)
	var intro := training_sd_intro if training else sudden_death_intro
	if intro <= 0.0:
		_release_sudden_death()
	else:
		_after(intro, _release_sudden_death)

## Enters sudden death from the current match at once (tests, the harness and
## training rows that start in sudden death).
func force_sudden_death() -> void:
	if phase == Phase.OVER:
		return
	_start_sudden_death()

func _release_sudden_death() -> void:
	if phase != Phase.SUDDEN_DEATH:
		return
	_lock_fighters(false)
	_fade_banner()
	if hazards:
		hazards.begin()

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
	if hazards:
		hazards.stop_and_clear()
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
	# The results own the screen: no timer and no fighter panels behind them.
	if timer_label:
		timer_label.visible = false
	for fighter in [fighter_1, fighter_2]:
		var hud := fighter.get_node_or_null("PlayerUI") as CanvasLayer
		if hud:
			hud.visible = false
	if music_player:
		music_player.stop()
	Combat.cancel_hit_stop()
	if game_over:
		game_over.visible = true
	get_tree().paused = true

func _resolve_training_defeat() -> void:
	var alive_1 := fighter_1.stocks > 0
	var alive_2 := fighter_2.stocks > 0
	if alive_1 and alive_2:
		return
	var survivor: Fighter = null
	if alive_1 != alive_2:
		survivor = fighter_1 if alive_1 else fighter_2
	elif phase == Phase.SUDDEN_DEATH:
		# A double KO inside sudden death restarts it (no `done`).
		_start_sudden_death()
		return
	_end_training_episode(survivor, &"ko")

# The hazards' safety cap: a sudden death that never produced a KO ends the episode
# as a draw (the reward tracker reads the reason and flags the log as truncated).
func _on_training_cap_reached() -> void:
	if training and phase == Phase.SUDDEN_DEATH:
		_end_training_episode(null, &"sd_cap")

## Ends a training row's episode, exactly once per frame: tells the reward
## trackers, flags `done` on both fighters through Fighter.game_over() (each resets
## itself on its next physics frame, after Sync has seen `done`), clears the stage
## (food, bombs, sudden death) and restarts the timer and the food spawner for the
## next episode. `reason` is kept in `last_episode_end_reason` before the unchanged
## one-argument `training_episode_ended` signal is emitted.
func _end_training_episode(winning_fighter: Fighter, reason: StringName = &"ko") -> void:
	var frame := Engine.get_physics_frames()
	if _episode_end_frame == frame:
		return
	_episode_end_frame = frame
	last_episode_end_reason = reason
	phase = Phase.PLAYING
	if hazards:
		hazards.stop_and_clear()
	training_episode_ended.emit(winning_fighter)
	fighter_1.game_over()
	fighter_2.game_over()
	for child in get_children():
		if child is FoodPickup or child is FoodProjectile:
			child.queue_free()
	if timer:
		timer.stop()
		timer.start()
	if food_spawner:
		food_spawner.stop()
		food_spawner.start()
	if training_start_in_sudden_death:
		# Each fighter resets itself on its next physics frame and would overwrite the
		# sudden-death damage and stocks, so wait for both before entering it.
		_pending_resets = 2
		for fighter in [fighter_1, fighter_2]:
			fighter.reset_done.connect(_on_fighter_reset_done, CONNECT_ONE_SHOT)

func _on_fighter_reset_done() -> void:
	_pending_resets -= 1
	if _pending_resets == 0 and training and training_start_in_sudden_death:
		force_sudden_death()

# ------------------------------------------------------------------- banner

## The banner is a screen-space label (UI CanvasLayer): the camera zoom never
## touches it. Its text is shrunk so that, at the largest pop-in scale, it still
## fits the viewport width with a margin.
const BANNER_POP_SCALE := 1.5
const BANNER_MARGIN := 0.9

func _fit_font_size(text: String, wanted: int) -> int:
	var font := countdown_label.get_theme_font("font")
	var outline := countdown_label.get_theme_constant("outline_size")
	var limit := countdown_label.get_viewport_rect().size.x * BANNER_MARGIN / BANNER_POP_SCALE
	var size := wanted
	while size > 16 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + outline * 2.0 > limit:
		size -= 4
	return size

## The banner text's rect on screen (viewport pixels) at its current scale.
func banner_screen_rect() -> Rect2:
	var font := countdown_label.get_theme_font("font")
	var size := countdown_label.get_theme_font_size("font_size")
	var outline := countdown_label.get_theme_constant("outline_size")
	var text_size := font.get_string_size(countdown_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size) + Vector2.ONE * outline * 2.0
	var center := countdown_label.get_global_rect().get_center()
	var shown := text_size * countdown_label.scale
	return Rect2(center - shown / 2.0, shown)

func _center_banner_pivot() -> void:
	if countdown_label:
		countdown_label.pivot_offset = countdown_label.size / 2.0

## Big centered text that pops in (scales down from BANNER_POP_SCALE with an overshoot). With
## `hold` > 0 it fades out afterwards. `speed` compensates a slowed game clock.
func _show_banner(text: String, color: Color, font_size: int, hold: float = 0.0, speed: float = 1.0) -> void:
	if countdown_label == null:
		return
	if _banner_tween:
		_banner_tween.kill()
	countdown_label.text = text
	countdown_label.add_theme_font_size_override("font_size", _fit_font_size(text, font_size))
	countdown_label.add_theme_color_override("font_color", color)
	countdown_label.modulate.a = 1.0
	countdown_label.scale = Vector2.ONE * BANNER_POP_SCALE
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
