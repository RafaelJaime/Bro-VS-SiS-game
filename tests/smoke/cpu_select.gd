extends SceneTree
## S3 controller select: character select builds the right ControllerConfig for
## Human, CPU Easy/Normal/Hard and an explicitly chosen model, and
## scene_manager.play_game applies it to the match fighters. Run headless.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const SELECT_SCENE := "res://ui/character_select/character_select.tscn"
const Level := CpuDifficulty.Level

func _initialize() -> void:
	_run()

func _controller_of(fighter: Fighter) -> FighterController:
	return fighter.controller

func _run() -> void:
	var s := Smoke.new(self)
	# Autoloads are looked up by node name: a --script main script is compiled
	# before the autoload globals exist.
	var model_manager: Node = root.get_node("ModelManager")
	var scene_manager: Node = root.get_node("SceneManager")
	var select: Control = load(SELECT_SCENE).instantiate()
	root.add_child(select)
	await s.frames(2)
	var ai: Control = select.get_node("AIController")
	var option_p1: OptionButton = ai.get_node("ControlP1/ControllerOption")
	var option_p2: OptionButton = ai.get_node("ControlP2/ControllerOption")

	s.check("each player has Human + 3 CPU levels", option_p1.item_count == 4 and option_p2.item_count == 4, "p1=%d p2=%d" % [option_p1.item_count, option_p2.item_count])
	s.check("the option labels are Human, CPU Easy, CPU Normal, CPU Hard", option_p1.get_item_text(0) == "Human" and option_p1.get_item_text(1) == "CPU Easy" and option_p1.get_item_text(2) == "CPU Normal" and option_p1.get_item_text(3) == "CPU Hard")

	# Options show up once the player has picked a character.
	s.check("controller options start hidden", not option_p1.visible and not option_p2.visible)
	select.select_player1(select.characters[0])
	s.check("P1's option shows after P1 picks a character", option_p1.visible and not option_p2.visible)
	select.select_player2(select.characters[1])
	s.check("P2's option shows after P2 picks a character", option_p2.visible)

	# Defaults: P1 Human, P2 CPU Normal.
	var p1_default: ControllerConfig = ai.get_controller_config(false)
	var p2_default: ControllerConfig = ai.get_controller_config(true)
	s.check("default P1 is Human", p1_default.kind == ControllerConfig.Kind.HUMAN)
	s.check("default P2 is CPU Normal", p2_default.kind == ControllerConfig.Kind.CPU and p2_default.difficulty == Level.NORMAL, "kind=%d difficulty=%d" % [p2_default.kind, p2_default.difficulty])

	# Every option maps to the right config, for both players.
	var expected := [
		[ControllerConfig.Kind.HUMAN, -1],
		[ControllerConfig.Kind.CPU, Level.EASY],
		[ControllerConfig.Kind.CPU, Level.NORMAL],
		[ControllerConfig.Kind.CPU, Level.HARD],
	]
	for is_p2 in [false, true]:
		var option: OptionButton = option_p2 if is_p2 else option_p1
		for index in 4:
			option.select(index)
			var config: ControllerConfig = ai.get_controller_config(is_p2)
			var want_kind: int = expected[index][0]
			var want_level: int = expected[index][1]
			var ok: bool = config.kind == want_kind and (want_level < 0 or config.difficulty == want_level)
			s.check("%s option '%s' builds the matching config" % ["P2" if is_p2 else "P1", option.get_item_text(index)], ok, "kind=%d difficulty=%d" % [config.kind, config.difficulty])

	# A downloaded HF model is explicit and wins over the CPU option.
	ai.update_menu_button(ai.option_button_p2, ["someone/model"])
	ai.option_button_p2.select(0)
	option_p2.select(3)
	var policy_config: ControllerConfig = ai.get_controller_config(true)
	s.check("a selected HF model yields a Policy config", policy_config.kind == ControllerConfig.Kind.POLICY and policy_config.onnx_model_path == model_manager.get_model_path(1), "kind=%d path=%s" % [policy_config.kind, policy_config.onnx_model_path])
	ai.option_button_p2.selected = -1
	s.check("clearing the model returns to the CPU option", ai.get_controller_config(true).kind == ControllerConfig.Kind.CPU)

	# Opening the model picker hides the option; backing out restores it. The Hub
	# is faked (an offline answer), a smoke script never touches the network.
	model_manager.hub_transport = func(_url: String, done: Callable) -> void:
		done.call(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())
	ai.open_model_picker(true)
	s.check("the model picker hides the CPU option", not option_p2.visible)
	ai.model_picker.cancel()
	model_manager.hub_transport = Callable()
	s.check("cancelling the picker restores the CPU option", option_p2.visible)
	ai.initial_menu(true)
	s.check("the initial menu shows the CPU option again", option_p2.visible)

	# Pressing Play passes both configs on, via scene_manager.
	var holder := Node.new()
	root.add_child(holder)
	scene_manager.scene_container = holder
	option_p1.select(0)
	option_p2.select(3)
	var char_1: CharacterUI = select.characters[0]
	var char_2: CharacterUI = select.characters[1]
	scene_manager.play_game(char_1, char_2, ai.get_controller_config(false), ai.get_controller_config(true))
	await s.frames(3)
	var game: Node = scene_manager.current_scene
	game.skip_countdown()
	var fighter_1: Fighter = game.get_node("Fighter1")
	var fighter_2: Fighter = game.get_node("Fighter2")
	s.check("play_game gives P1 a human controller", _controller_of(fighter_1) is HumanController)
	var cpu_controller := _controller_of(fighter_2) as ScriptedController
	s.check("play_game gives P2 a scripted CPU of the chosen level", cpu_controller != null and is_equal_approx(cpu_controller.difficulty.decision_interval, CpuDifficulty.preset(Level.HARD).decision_interval))
	s.check("play_game keeps the characters", fighter_1.character_ui == char_1 and fighter_2.character_ui == char_2)
	s.check("play_game remembers the match for a rematch", scene_manager.last_match.get("cfg2") != null and scene_manager.last_match.get("character1") == char_1)

	# The CPU acts from the first frames (never idles at spawn).
	var start_x := fighter_2.position.x
	await s.sim(1.5)
	s.check("the CPU moves from its spawn within 1.5 s", absf(fighter_2.position.x - start_x) > 20.0, "moved=%.0f" % absf(fighter_2.position.x - start_x))
	game.queue_free()
	await s.frames(2)

	# A null config keeps the fighter's AUTO controller (a human on the keyboard).
	scene_manager.play_game(char_1, char_2)
	await s.frames(3)
	var plain_game: Node = scene_manager.current_scene
	s.check("a null config keeps the human AUTO controller", _controller_of(plain_game.get_node("Fighter2")) is HumanController)
	plain_game.queue_free()
	await s.frames(2)

	# A Policy config with a model that is not on disk must not leave an idle fighter.
	var scratch_game: Node2D = s.spawn_game()
	var missing := ControllerConfig.policy("user://does_not_exist.onnx")
	var fallback := missing.build(scratch_game.get_node("Fighter2"))
	s.check("a missing ONNX model falls back to the scripted CPU", fallback is ScriptedController)
	s.check("the AI controller stays out of ONNX mode on that fallback", scratch_game.get_node("Fighter2").ai_controller_2d.control_mode != AIController2D.ControlModes.ONNX_INFERENCE)
	await s.despawn(scratch_game)

	# An explicit Policy config with a model on disk switches the AI controller to
	# ONNX mode (the only way ONNX ever turns on), and a Human config never does.
	var model_path := "user://smoke_policy_stub.onnx"
	var stub := FileAccess.open(model_path, FileAccess.WRITE)
	stub.store_string("stub")
	stub.close()
	var onnx_game: Node2D = s.spawn_game()
	var onnx_fighter: Fighter = onnx_game.get_node("Fighter2")
	var human_built := ControllerConfig.human().build(onnx_fighter)
	s.check("a Human config leaves the AI controller alone", human_built is HumanController and onnx_fighter.ai_controller_2d.control_mode != AIController2D.ControlModes.ONNX_INFERENCE)
	var policy_built := ControllerConfig.policy(model_path).build(onnx_fighter)
	s.check("an explicit Policy config selects ONNX mode and the model", policy_built is PolicyController and onnx_fighter.ai_controller_2d.control_mode == AIController2D.ControlModes.ONNX_INFERENCE and onnx_fighter.ai_controller_2d.onnx_model_path == model_path)
	onnx_game.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(model_path))
	s.finish()
