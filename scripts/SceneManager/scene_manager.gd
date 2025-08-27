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

func play_game(character1: CharacterUI, character2: CharacterUI) -> void:
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
