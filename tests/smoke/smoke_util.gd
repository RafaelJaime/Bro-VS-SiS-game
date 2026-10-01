extends RefCounted
## Shared helpers for the smoke scripts (run with `--script`, windowed).
##
## Every script is a SceneTree that builds a real `game/game.tscn`, drives the
## fighters through the controller intent seam and prints PASS/FAIL lines. The
## process exit code is non-zero when any check failed or the watchdog fired.

const GAME_SCENE := "res://game/game.tscn"
const WATCHDOG_SECONDS := 120.0

## Intent source for tests: levels (move_x, jump_held_level, block_held_level)
## persist, presses fire exactly once.
class IntentController extends FighterController:
	var move_x: float = 0.0
	## Level: keeps the jump key "down" after the press frame (full hop).
	var jump_held_level: bool = false
	## Level: keeps the block key down.
	var block_held_level: bool = false
	var _punch: bool = false
	var _jump: bool = false
	var _throw: bool = false
	var _dash: bool = false
	var _block: bool = false

	func press_punch() -> void:
		_punch = true

	func press_jump() -> void:
		_jump = true

	func press_throw() -> void:
		_throw = true

	func press_dash() -> void:
		_dash = true

	func press_block() -> void:
		_block = true

	func sample(_delta: float) -> FighterIntent:
		var intent := FighterIntent.new()
		intent.move_x = move_x
		intent.attack_pressed = _punch
		intent.jump_pressed = _jump
		intent.jump_held = _jump or jump_held_level
		intent.throw_pressed = _throw
		intent.dash_pressed = _dash
		intent.block_pressed = _block
		intent.block_held = _block or block_held_level
		_punch = false
		_jump = false
		_throw = false
		_dash = false
		_block = false
		return intent

	func kind_name() -> String:
		return "smoke"

## Watches both fighters of a game: damage taken, stock losses, and whether each
## loss happened without a recent hit (a self-inflicted fall). Time is game time
## (physics frames), so hit-stop does not distort it.
class MatchLog extends RefCounted:
	## A stock lost with no damage taken in this many seconds counts as self-inflicted.
	const SELF_INFLICTED_WINDOW := 3.0

	var game: Node2D
	## Refill stocks after every loss so a long run never ends the match.
	var keep_alive: bool
	var damage_taken: Array[float] = [0.0, 0.0]
	var hits_taken: Array[int] = [0, 0]
	var losses: Array[int] = [0, 0]
	var self_inflicted: Array[int] = [0, 0]
	var notes: Array[String] = []
	var _last_percent: Array[float] = [0.0, 0.0]
	var _last_stocks: Array[int] = [Fighter.MAX_STOCKS, Fighter.MAX_STOCKS]
	var _last_hit: Array[float] = [-100.0, -100.0]
	var _start_frame: int

	func _init(match_game: Node2D, refill: bool = false) -> void:
		game = match_game
		keep_alive = refill
		_start_frame = Engine.get_physics_frames()
		var fighters: Array[Fighter] = [game.get_node("Fighter1"), game.get_node("Fighter2")]
		for i in 2:
			fighters[i].damage_changed.connect(_on_damage.bind(i))
			fighters[i].stocks_changed.connect(_on_stocks.bind(i))

	func now() -> float:
		return float(Engine.get_physics_frames() - _start_frame) / float(Engine.physics_ticks_per_second)

	func _on_damage(percent: float, index: int) -> void:
		if percent > _last_percent[index]:
			damage_taken[index] += percent - _last_percent[index]
			hits_taken[index] += 1
			_last_hit[index] = now()
		_last_percent[index] = percent

	func _on_stocks(fighter: Fighter, stocks_left: int, index: int) -> void:
		if stocks_left < _last_stocks[index]:
			losses[index] += 1
			if now() - _last_hit[index] > SELF_INFLICTED_WINDOW:
				self_inflicted[index] += 1
				notes.append("fighter %d fell at t=%.1f pos=(%.0f, %.0f) state=%s" % [index + 1, now(), fighter.position.x, fighter.position.y, fighter.state_machine.current_state.name])
		if keep_alive and stocks_left < Fighter.MAX_STOCKS:
			# Set inside the signal, before Fighter._lose_stock checks for defeat,
			# so the fighter simply respawns.
			fighter.stocks = Fighter.MAX_STOCKS
			stocks_left = Fighter.MAX_STOCKS
		_last_stocks[index] = stocks_left

var tree: SceneTree
var _watchdog_seconds: float = WATCHDOG_SECONDS
var failures: int = 0
var checks: int = 0
var finished: bool = false

## `watchdog_seconds` is game time under --fixed-fps (60 frames per second), so a
## headless script that simulates minutes needs a larger budget than the default.
func _init(scene_tree: SceneTree, watchdog_seconds: float = WATCHDOG_SECONDS) -> void:
	_watchdog_seconds = watchdog_seconds
	tree = scene_tree
	# Keep the music and SFX quiet; the checks do not need audio.
	AudioServer.set_bus_mute(0, true)
	tree.create_timer(_watchdog_seconds, true, false, true).timeout.connect(_on_watchdog)

func _on_watchdog() -> void:
	if finished:
		return
	failures += 1
	print("FAIL watchdog: script did not finish within %d s" % int(_watchdog_seconds))
	finish()

func check(check_name: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if condition:
		print("PASS %s%s" % [check_name, (" (" + detail + ")") if detail != "" else ""])
	else:
		failures += 1
		print("FAIL %s%s" % [check_name, (": " + detail) if detail != "" else ""])

## Waits `count` physics frames.
func frames(count: int) -> void:
	for i in count:
		await tree.physics_frame

## Instantiates game.tscn. Positions given here are applied before _ready, so
## they also become the fighters' respawn anchors and initial facing. The match
## countdown is skipped unless `with_countdown` is set, so scripts that test
## movement or combat can act at once.
func spawn_game(p1_x: float = NAN, p2_x: float = NAN, with_countdown: bool = false) -> Node2D:
	var game: Node2D = load(GAME_SCENE).instantiate()
	if not is_nan(p1_x):
		game.get_node("Fighter1").position.x = p1_x
	if not is_nan(p2_x):
		game.get_node("Fighter2").position.x = p2_x
	tree.root.add_child(game)
	if not with_countdown:
		game.skip_countdown()
	return game

func attach_controllers(game: Node2D) -> Array:
	var controllers: Array = []
	for fighter_name in ["Fighter1", "Fighter2"]:
		var controller := IntentController.new()
		game.get_node(fighter_name).set_controller(controller)
		controllers.append(controller)
	return controllers

## Gives `fighter` a scripted CPU of `level` (a CpuDifficulty.Level). The seed
## makes the run reproducible.
func set_cpu(fighter: Fighter, level: int, rng_seed: int) -> ScriptedController:
	var cpu := ScriptedController.new(CpuDifficulty.preset(level as CpuDifficulty.Level), rng_seed)
	fighter.set_controller(cpu)
	return cpu

## Runs `seconds` of game time (physics frames).
func sim(seconds: float) -> void:
	await frames(int(seconds * Engine.physics_ticks_per_second))

func despawn(game: Node) -> void:
	game.queue_free()
	await tree.process_frame

## Waits `seconds` of real (unscaled) time, so hit-stop does not stretch it.
func real_wait(seconds: float) -> void:
	await tree.create_timer(seconds, true, false, true).timeout

## Name of the fighter's current state ("Idle", "Jump", ...).
func state_of(fighter: Fighter) -> String:
	return String(fighter.state_machine.current_state.name)

## Waits (in physics frames) until `fighter` is grounded; returns false on timeout.
func wait_grounded(fighter: Fighter, max_frames: int = 240) -> bool:
	for i in max_frames:
		if fighter.is_on_floor():
			return true
		await tree.physics_frame
	return fighter.is_on_floor()

func floor_top(game: Node) -> float:
	return game.get_state_snapshot()["stage"]["top"]

## Y of the bottom edge of a fighter's movement body, Game-local.
func body_bottom(fighter: Fighter) -> float:
	var shape_node: CollisionShape2D = fighter.get_node("CollisionShape2D")
	var rect := shape_node.shape as RectangleShape2D
	return fighter.position.y + shape_node.position.y + rect.size.y / 2.0

## Y of the lowest opaque pixel of the fighter's current sprite frame, Game-local.
func sprite_feet(fighter: Fighter) -> float:
	var sprite := fighter.animated_sprite_2d
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	var used := texture.get_image().get_used_rect()
	var local_y := sprite.position.y + (float(used.end.y) - texture.get_height() / 2.0) * sprite.scale.y
	return fighter.position.y + local_y

func screenshot(shot_name: String) -> String:
	await RenderingServer.frame_post_draw
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("user://")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(shot_name + ".png")
	tree.root.get_texture().get_image().save_png(path)
	print("SHOT %s" % path)
	return path

func finish() -> void:
	if finished:
		return
	finished = true
	print("SUMMARY %d checks, %d failed" % [checks, failures])
	tree.quit(1 if failures > 0 else 0)
