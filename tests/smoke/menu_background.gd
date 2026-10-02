extends SceneTree
## The single shared menu background, windowed: one instance below the current
## scene, the cloud scroll keeps going across menu -> character select -> credits
## -> menu (no restart), and it is hidden and paused during a match and back after.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const MENU_SCENE := "res://ui/main_menu/main_menu.tscn"
const SELECT_SCENE := "res://ui/character_select/character_select.tscn"
const CREDITS_SCENE := "res://ui/credits/credits.tscn"
const INSTRUCTIONS_SCENE := "res://ui/instructions/instructions.tscn"
const Level := CpuDifficulty.Level

var s: RefCounted
var scene_manager: Node

func _initialize() -> void:
	_run()

func _count(node: Node) -> int:
	var total := 1 if node is MenuBackground else 0
	for child in node.get_children():
		total += _count(child)
	return total

## Distance the clouds have travelled (they scroll towards negative x).
func _travel() -> float:
	return absf(scene_manager.menu_background.cloud_offset())

func _go(path: String) -> void:
	scene_manager.change_scene(path)
	await s.frames(15)

func _run() -> void:
	s = Smoke.new(self)
	scene_manager = root.get_node("SceneManager")
	var holder := Node.new()
	root.add_child(holder)
	scene_manager.scene_container = holder
	var select: Control = load(SELECT_SCENE).instantiate()
	root.add_child(select)
	await s.frames(2)
	var characters: Array = select.characters.duplicate()
	select.free()
	s.check("no menu background exists before the first screen", scene_manager.menu_background == null)

	MainMenu.mark_intro_seen()
	await _go(MENU_SCENE)
	var shared: Node = scene_manager.menu_background
	s.check("the main menu shows the shared background", shared != null and shared.visible and _count(root) == 1)
	s.check("it is the first child of the container, below the screen", holder.get_child(0) == shared and holder.get_child(1) == scene_manager.current_scene)
	s.check("the main menu has no background of its own", scene_manager.current_scene.get_node_or_null("background") == null)
	var last := _travel()
	s.check("the clouds are moving", last > 0.0, str(last))
	await s.screenshot("menu_background_menu")

	for path in [SELECT_SCENE, INSTRUCTIONS_SCENE, CREDITS_SCENE, MENU_SCENE]:
		await _go(path)
		var now := _travel()
		s.check("the cloud scroll continues into %s (no reset)" % path.get_file(), now > last, "%.2f -> %.2f" % [last, now])
		s.check("still one background, the same instance, for %s" % path.get_file(), _count(root) == 1 and scene_manager.menu_background == shared and is_instance_valid(shared) and shared.visible)
		last = now

	# a match hides and pauses it
	scene_manager.play_game(characters[0], characters[1], ControllerConfig.human(), ControllerConfig.cpu(Level.HARD))
	await s.frames(5)
	var frozen := _travel()
	s.check("the match hides the menu background", not shared.visible and not shared.get_node("ParallaxBackground").visible)
	await s.frames(30)
	s.check("the clouds are paused during the match", is_equal_approx(_travel(), frozen), "%.2f vs %.2f" % [frozen, _travel()])
	s.check("the game still has none of its own", scene_manager.current_scene.get_node_or_null("background") == null)

	# and it comes back after, continuing where it stopped
	await _go(SELECT_SCENE)
	s.check("after the match the menu background is shown again", shared.visible and shared.get_node("ParallaxBackground").visible and scene_manager.menu_background == shared and _count(root) == 1)
	await s.frames(15)
	s.check("the clouds continue from where they stopped", _travel() > frozen, "%.2f -> %.2f" % [frozen, _travel()])
	s.finish()
