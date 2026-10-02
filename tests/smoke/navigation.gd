extends SceneTree
## Back navigation, windowed (real mouse clicks): the Back button of the character
## select leads to the main menu from every way in (the main menu, the results
## screen after a match, a rematch), and the pause menu Back, the results Main Menu
## button and the other screens' Back buttons never return to a previous match.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const MENU_SCENE := "res://ui/main_menu/main_menu.tscn"
const SELECT_SCENE := "res://ui/character_select/character_select.tscn"
const GAME_SCENE := "res://game/game.tscn"
const RESULTS_BUTTONS := "%"
const Level := CpuDifficulty.Level

var s: RefCounted
var scene_manager: Node
var characters: Array = []

func _initialize() -> void:
	_run()

func click(control: Control) -> void:
	var pos := control.get_global_transform_with_canvas() * (control.size / 2.0)
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await s.frames(3)
	for pressed in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.position = pos
		button.global_position = pos
		button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(button)
		await s.frames(3)

func _key(keycode: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	return event

func _scene_path() -> String:
	return scene_manager.current_scene_path

## Starts a match through the SceneManager and ends it, returning the results.
func _match_to_results() -> Game:
	scene_manager.play_game(characters[0], characters[1], ControllerConfig.human(), ControllerConfig.cpu(Level.HARD))
	await s.frames(3)
	var game: Game = scene_manager.current_scene
	game.skip_countdown()
	var loser: Fighter = game.get_node("Fighter2")
	loser.set_stocks(1)
	loser.position = Vector2(loser.blast_zone.position.x - 80.0, 300.0)
	for i in 40:
		if game.game_over.visible:
			break
		await s.real_wait(0.1)
	return game

func _run() -> void:
	s = Smoke.new(self)
	scene_manager = root.get_node("SceneManager")
	var holder := Node.new()
	root.add_child(holder)
	scene_manager.scene_container = holder
	var select: Control = load(SELECT_SCENE).instantiate()
	root.add_child(select)
	await s.frames(2)
	characters = select.characters.duplicate()
	select.free()

	# The first-launch dialog would cover the menu (the flag file is a throwaway one).
	MainMenu.mark_intro_seen()
	# --- main menu -> Characters (Play) -> Back
	scene_manager.change_scene(MENU_SCENE)
	await s.frames(3)
	var menu: Node = scene_manager.current_scene
	await click(menu.get_node("MainMenuButtons/PlayButton"))
	await s.frames(5)
	s.check("nav: Play opens the character select", _scene_path() == SELECT_SCENE, _scene_path())
	await click(scene_manager.current_scene.get_node("BackButton"))
	await s.frames(5)
	s.check("nav: Back from the character select (from the main menu) returns to the main menu", _scene_path() == MENU_SCENE, _scene_path())

	# --- a match -> results -> Characters -> Back (the old bug: it went back to the match)
	var game := await _match_to_results()
	s.check("nav: the match ends in the results screen", game.game_over.visible)
	await click(game.game_over.get_node(RESULTS_BUTTONS + "CharactersButton"))
	await s.frames(5)
	s.check("nav: results -> Characters opens the character select", _scene_path() == SELECT_SCENE, _scene_path())
	await click(scene_manager.current_scene.get_node("BackButton"))
	await s.frames(5)
	s.check("nav: Back from the character select (after the results) goes to the main menu, not the match", _scene_path() == MENU_SCENE, _scene_path())
	s.check("nav: no match is left running behind the menu", scene_manager.current_scene is MainMenu and not (scene_manager.current_scene is Game))

	# --- match -> results -> Rematch -> results -> Characters -> Back
	game = await _match_to_results()
	await click(game.game_over.get_node(RESULTS_BUTTONS + "ReplayButton"))
	await s.frames(5)
	s.check("nav: Rematch starts the match again", _scene_path() == GAME_SCENE)
	game = scene_manager.current_scene
	game.skip_countdown()
	var loser: Fighter = game.get_node("Fighter2")
	loser.set_stocks(1)
	loser.position = Vector2(loser.blast_zone.position.x - 80.0, 300.0)
	for i in 40:
		if game.game_over.visible:
			break
		await s.real_wait(0.1)
	await click(game.game_over.get_node(RESULTS_BUTTONS + "CharactersButton"))
	await s.frames(5)
	await click(scene_manager.current_scene.get_node("BackButton"))
	await s.frames(5)
	s.check("nav: Back after a rematch and the results also goes to the main menu", _scene_path() == MENU_SCENE, _scene_path())

	# --- results -> Main Menu button
	game = await _match_to_results()
	await click(game.game_over.get_node(RESULTS_BUTTONS + "MainMenuButton"))
	await s.frames(5)
	s.check("nav: results -> Main Menu opens the main menu", _scene_path() == MENU_SCENE, _scene_path())

	# --- pause -> Back leaves the match for the main menu and unpauses
	scene_manager.play_game(characters[0], characters[1], ControllerConfig.human(), ControllerConfig.cpu(Level.NORMAL))
	await s.frames(3)
	game = scene_manager.current_scene
	game.skip_countdown()
	await s.frames(5)
	Input.parse_input_event(_key(KEY_ESCAPE, true))
	await s.frames(2)
	Input.parse_input_event(_key(KEY_ESCAPE, false))
	await s.frames(4)
	var pause_menu: Control = game.get_node("UI/Pause")
	s.check("nav: Esc opens the pause menu", pause_menu.visible and paused)
	await click(pause_menu.get_node("BackButton"))
	await s.frames(5)
	s.check("nav: pause -> Back goes to the main menu", _scene_path() == MENU_SCENE, _scene_path())
	s.check("nav: pause -> Back unpauses the tree", not paused)

	# --- instructions and credits Back buttons
	for entry in [["MainMenuButtons/InstructionsButton", "instructions"], ["MainMenuButtons/CreditsButton", "credits"]]:
		menu = scene_manager.current_scene
		var opener := menu.get_node_or_null(entry[0]) as Control
		if opener == null:
			continue
		await click(opener)
		await s.frames(5)
		var opened: String = _scene_path()
		await click(scene_manager.current_scene.get_node("BackButton"))
		await s.frames(5)
		s.check("nav: Back from %s returns to the main menu" % entry[1], opened.contains(entry[1]) and _scene_path() == MENU_SCENE, "%s -> %s" % [opened, _scene_path()])

	s.finish()
