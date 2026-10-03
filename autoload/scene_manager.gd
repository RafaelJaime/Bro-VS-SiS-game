extends Node

var history: Array = []
var current_scene_path: String = ""
var current_scene: Node
var scene_container: Node

const MENU_BACKGROUND_SCENE := "res://ui/global/background/background.tscn"

## The single menu backdrop shared by every menu screen. It lives in the scene
## container below the current scene, so the cloud scroll continues across screen
## changes. Null until the first menu screen is shown.
var menu_background: MenuBackground

func change_scene(scene_path: String):
	if current_scene:
		history.append(current_scene_path)
		current_scene.queue_free()

	current_scene_path = scene_path
	current_scene = load(scene_path).instantiate()
	assert(scene_container, "Scene container doesn't exist, so I can't change scene")
	_show_menu_background()
	scene_container.add_child(current_scene)

## Creates the shared backdrop on first use, keeps it as the first child of the
## scene container (so it draws below every screen) and turns it on.
func _show_menu_background() -> void:
	if not is_instance_valid(menu_background):
		menu_background = load(MENU_BACKGROUND_SCENE).instantiate()
	var parent := menu_background.get_parent()
	if parent != scene_container:
		if parent != null:
			parent.remove_child(menu_background)
		scene_container.add_child(menu_background)
	scene_container.move_child(menu_background, 0)
	menu_background.set_active(true)

## The match has its own backdrop: hide the menu one and pause its clouds.
func _hide_menu_background() -> void:
	if is_instance_valid(menu_background):
		menu_background.set_active(false)

## What the last match was started with (characters and controller configs), so a
## rematch can replay it. Empty until the first match starts.
var last_match: Dictionary = {}

## Starts a match. `cfg1`/`cfg2` pick each fighter's controller (human, CPU,
## policy); a null config keeps the fighter's AUTO controller.
func play_game(character1: CharacterUI, character2: CharacterUI, cfg1: ControllerConfig = null, cfg2: ControllerConfig = null) -> void:
	last_match = {
		"character1": character1,
		"character2": character2,
		"cfg1": cfg1,
		"cfg2": cfg2,
	}
	if current_scene:
		history.append(current_scene_path)
		current_scene.queue_free()

	current_scene_path = "res://game/game.tscn"
	current_scene = load("res://game/game.tscn").instantiate()

	assert(scene_container, "Scene container doesn't exist, so I can't change scene")
	_hide_menu_background()
	scene_container.add_child(current_scene)

	var fighters = []
	for child in current_scene.get_children():
		if child is Fighter:
			fighters.append(child)
			if fighters.size() >= 2:
				break

	if fighters.size() >= 2:
		fighters[0].character_ui = character1
		fighters[1].character_ui = character2
		if cfg1 != null:
			fighters[0].set_controller(cfg1.build(fighters[0]))
		if cfg2 != null:
			fighters[1].set_controller(cfg2.build(fighters[1]))
	else:
		push_error("Could not find two Fighter nodes in the game scene.")

## Instant rematch: the same characters and controller configs, fresh state.
## Falls back to the main menu when no match has been played yet.
func rematch() -> void:
	if last_match.is_empty():
		change_scene("res://ui/main_menu/main_menu.tscn")
		return
	play_game(last_match["character1"], last_match["character2"], last_match["cfg1"], last_match["cfg2"])

func change_scene_splash(scene_path: String):
	if current_scene:
		history.append(current_scene_path)
		current_scene.queue_free()
	
	current_scene_path = scene_path
	current_scene = load(scene_path).instantiate()
	get_tree().root.add_child_deferred(current_scene)

## Every Back button (credits, instructions, character select, the pause menu)
## leads to the main menu. The history is not replayed: after the results ->
## Characters, popping it returned to the previous match.
func go_back() -> void:
	change_scene("res://ui/main_menu/main_menu.tscn")
	history.clear()
