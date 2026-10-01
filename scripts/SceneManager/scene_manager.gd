extends Node

var history: Array = []
var current_scene_path: String = ""
var current_scene: Node
var scene_container: Node

func change_scene(scene_path: String):
	if current_scene:
		history.append(current_scene_path)
		current_scene.queue_free()

	current_scene_path = scene_path
	current_scene = load(scene_path).instantiate()
	assert(scene_container, "Scene container doesn't exist, so I can't change scene")
	scene_container.add_child(current_scene)

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

func change_scene_splash(scene_path: String):
	if current_scene:
		history.append(current_scene_path)
		current_scene.queue_free()
	
	current_scene_path = scene_path
	current_scene = load(scene_path).instantiate()
	get_tree().root.add_child_deferred(current_scene)

func go_back():
	if history.size() > 0:
		var previous_scene_path = history.pop_back()
		change_scene(previous_scene_path)
	else:
		change_scene("res://ui/main_menu/main_menu.tscn")
