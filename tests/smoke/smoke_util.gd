extends RefCounted
## Shared helpers for the smoke scripts (run with `--script`, windowed).
##
## Every script is a SceneTree that builds a real `game/game.tscn`, drives the
## fighters through the controller intent seam and prints PASS/FAIL lines. The
## process exit code is non-zero when any check failed or the watchdog fired.

const GAME_SCENE := "res://game/game.tscn"
const WATCHDOG_SECONDS := 120.0

## Intent source for tests: levels (move_x) persist, presses fire exactly once.
class IntentController extends FighterController:
	var move_x: float = 0.0
	var _punch: bool = false
	var _jump: bool = false
	var _throw: bool = false

	func press_punch() -> void:
		_punch = true

	func press_jump() -> void:
		_jump = true

	func press_throw() -> void:
		_throw = true

	func sample(_delta: float) -> FighterIntent:
		var intent := FighterIntent.new()
		intent.move_x = move_x
		intent.attack_pressed = _punch
		intent.jump_pressed = _jump
		intent.jump_held = _jump
		intent.throw_pressed = _throw
		_punch = false
		_jump = false
		_throw = false
		return intent

	func kind_name() -> String:
		return "smoke"

var tree: SceneTree
var failures: int = 0
var checks: int = 0
var finished: bool = false

func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree
	# Keep the music and SFX quiet; the checks do not need audio.
	AudioServer.set_bus_mute(0, true)
	tree.create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(_on_watchdog)

func _on_watchdog() -> void:
	if finished:
		return
	failures += 1
	print("FAIL watchdog: script did not finish within %d s" % int(WATCHDOG_SECONDS))
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
## they also become the fighters' respawn anchors and initial facing.
func spawn_game(p1_x: float = NAN, p2_x: float = NAN) -> Node2D:
	var game: Node2D = load(GAME_SCENE).instantiate()
	if not is_nan(p1_x):
		game.get_node("Fighter1").position.x = p1_x
	if not is_nan(p2_x):
		game.get_node("Fighter2").position.x = p2_x
	tree.root.add_child(game)
	return game

func attach_controllers(game: Node2D) -> Array:
	var controllers: Array = []
	for fighter_name in ["Fighter1", "Fighter2"]:
		var controller := IntentController.new()
		game.get_node(fighter_name).set_controller(controller)
		controllers.append(controller)
	return controllers

func despawn(game: Node) -> void:
	game.queue_free()
	await tree.process_frame

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
