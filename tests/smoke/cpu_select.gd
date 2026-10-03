extends SceneTree
## S3 controller select: character select builds the right ControllerConfig for
## Human, CPU Easy/Normal/Hard, the bundled "AI: BVS default" model and an
## explicitly chosen model, and scene_manager.play_game applies it to the match
## fighters. A Policy selection with no usable model is an explicit error state,
## never a scripted CPU; a rematch keeps the model handle. Run headless.

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

	s.check("each player has Human, 3 CPU levels and the bundled model", option_p1.item_count == 5 and option_p2.item_count == 5, "p1=%d p2=%d" % [option_p1.item_count, option_p2.item_count])
	s.check("the option labels are Human, CPU Easy, CPU Normal, CPU Hard, AI: BVS default", option_p1.get_item_text(0) == "Human" and option_p1.get_item_text(1) == "CPU Easy" and option_p1.get_item_text(2) == "CPU Normal" and option_p1.get_item_text(3) == "CPU Hard" and option_p1.get_item_text(4) == "AI: BVS default")

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

	# The bundled model is an explicit option: a Policy config holding the loaded
	# model, with no network request.
	var urls: Array[String] = []
	model_manager.hub_transport = func(url: String, done: Callable) -> void:
		urls.append(url)
		done.call(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())
	for is_p2 in [false, true]:
		var option: OptionButton = option_p2 if is_p2 else option_p1
		option.select(4)
		option.item_selected.emit(4)
		var bundled_config: ControllerConfig = ai.get_controller_config(is_p2)
		var bundled_model: OnnxPolicyModel = model_manager.bundled_default()
		s.check("%s 'AI: BVS default' builds a Policy config with the bundled model" % ("P2" if is_p2 else "P1"), bundled_model != null and bundled_config.kind == ControllerConfig.Kind.POLICY and bundled_config.model == bundled_model and bundled_config.is_playable(), "model=%s" % str(bundled_config.model))
	s.check("the bundled model is validated and labelled", model_manager.bundled_default().repo_id == "bundled" and model_manager.bundled_default().label == "BVS default" and model_manager.bundled_default().validate(BvsSchema.current()) == "")
	s.check("selecting the bundled model makes no HTTP request", urls.is_empty() and model_manager.get_children().all(func(child: Node): return not (child is HTTPRequest)), str(urls))
	s.check("the bundled selection keeps Play enabled and shows it is ready", ai.is_ready_to_play() and ai.status_label_p2.text.contains("bundled"), ai.status_label_p2.text)
	option_p1.select(0)
	option_p1.item_selected.emit(0)
	option_p2.select(3)
	option_p2.item_selected.emit(3)

	# A chosen Hub model that is not ready is an error state, never a CPU.
	ai.update_menu_button(ai.option_button_p2, ["someone/model"])
	ai.option_button_p2.select(0)
	var pending_config: ControllerConfig = ai.get_controller_config(true)
	s.check("a Hub model that is not ready yields a Policy config in its error state", pending_config.kind == ControllerConfig.Kind.POLICY and pending_config.model == null and pending_config.error_message != "" and not pending_config.is_playable(), pending_config.error_message)
	s.check("Play is not allowed while the selected model is not ready", not ai.is_ready_to_play())
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

	# A Policy config with no model is an error state: the fighter is a policy
	# fighter (neutral, one error), never the scripted CPU, and the AI controller's mode is untouched.
	var scratch_game: Node2D = s.spawn_game()
	var scratch_fighter: Fighter = scratch_game.get_node("Fighter2")
	var mode_before: int = scratch_fighter.ai_controller_2d.control_mode
	var missing := ControllerConfig.policy_model(null, "model failed to load")
	var built_missing := missing.build(scratch_fighter)
	s.check("a Policy config without a model never becomes the scripted CPU", built_missing is PolicyController and not (built_missing is ScriptedController) and (built_missing as PolicyController).model == null)
	s.check("the error state carries its reason and is not playable", missing.error_message == "model failed to load" and not missing.is_playable())
	s.check("building it leaves the AI controller mode alone", scratch_fighter.ai_controller_2d.control_mode == mode_before)
	await s.despawn(scratch_game)

	# An explicit Policy config carries the model handle into the PolicyController,
	# and a Human config never touches the AI controller.
	var onnx_game: Node2D = s.spawn_game()
	var onnx_fighter: Fighter = onnx_game.get_node("Fighter2")
	var human_built := ControllerConfig.human().build(onnx_fighter)
	s.check("a Human config leaves the AI controller alone", human_built is HumanController and onnx_fighter.ai_controller_2d.control_mode != AIController2D.ControlModes.ONNX_INFERENCE)
	var handle: OnnxPolicyModel = model_manager.bundled_default()
	var policy_built := ControllerConfig.policy_model(handle).build(onnx_fighter)
	s.check("a Policy config routes via PolicyController with that model handle and no ONNX mode switch", policy_built is PolicyController and (policy_built as PolicyController).model == handle and onnx_fighter.ai_controller_2d.control_mode != AIController2D.ControlModes.ONNX_INFERENCE)
	onnx_game.free()

	# A rematch keeps the model handle: no new download, no new load.
	var rematch_urls: Array[String] = []
	model_manager.hub_transport = func(url: String, done: Callable) -> void:
		rematch_urls.append(url)
		done.call(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())
	scene_manager.play_game(char_1, char_2, ControllerConfig.human(), ControllerConfig.policy_model(handle))
	await s.frames(3)
	scene_manager.current_scene.skip_countdown()
	var first_policy := _controller_of(scene_manager.current_scene.get_node("Fighter2")) as PolicyController
	s.check("the first match runs P2 on the model", first_policy != null and first_policy.model == handle)
	scene_manager.rematch()
	await s.frames(3)
	var second_policy := _controller_of(scene_manager.current_scene.get_node("Fighter2")) as PolicyController
	s.check("the rematch keeps the same model handle", second_policy != null and second_policy.model == handle and second_policy != first_policy)
	s.check("the rematch makes no HTTP request", rematch_urls.is_empty())
	scene_manager.current_scene.queue_free()
	await s.frames(2)
	model_manager.hub_transport = Callable()

	# A stale user://Agent<N>.onnx never influences the controller: P1 Human stays Human.
	var stale_path := "user://Agent0.onnx"
	var stale := FileAccess.open(stale_path, FileAccess.WRITE)
	stale.store_string("stale")
	stale.close()
	scene_manager.play_game(char_1, char_2, ControllerConfig.human(), ControllerConfig.cpu(Level.EASY))
	await s.frames(3)
	s.check("a stale Agent0.onnx with Human selected: P1 obeys human input", _controller_of(scene_manager.current_scene.get_node("Fighter1")) is HumanController)
	scene_manager.current_scene.queue_free()
	await s.frames(2)
	s.check("legacy Agent<N>.onnx files are deleted by the startup cleanup", model_manager.cleanup_legacy_files() >= 1 and not FileAccess.file_exists(stale_path))

	# A corrupted or missing bundled model is a visible error, never a CPU swap.
	var bad_dir := "user://smoke_bad_bundle"
	DirAccess.make_dir_recursive_absolute(bad_dir)
	var good_dir: String = model_manager.BUNDLED_DIR
	var corrupted := FileAccess.get_file_as_bytes(good_dir.path_join("model.onnx"))
	corrupted = corrupted.slice(0, corrupted.size() / 2)
	var bad_model := FileAccess.open(bad_dir.path_join("model.onnx"), FileAccess.WRITE)
	bad_model.store_buffer(corrupted)
	bad_model.close()
	var bad_sidecar := FileAccess.open(bad_dir.path_join("bvs.json"), FileAccess.WRITE)
	bad_sidecar.store_string(FileAccess.get_file_as_string(good_dir.path_join("bvs.json")))
	bad_sidecar.close()
	model_manager.bundled_dir = bad_dir
	model_manager.reload_bundled()
	option_p2.select(4)
	ai.refresh_status(true)
	var bad_config: ControllerConfig = ai.get_controller_config(true)
	s.check("a corrupted bundled model yields no model and a reason", model_manager.bundled_default() == null and model_manager.bundled_error.contains("bundled") and bad_config.kind == ControllerConfig.Kind.POLICY and bad_config.model == null and not bad_config.is_playable(), model_manager.bundled_error)
	s.check("the corruption is visible on the player's panel and Play is disabled", ai.status_label_p2.visible and ai.status_label_p2.text.contains("bundled") and select.play_button.disabled and not ai.is_ready_to_play(), ai.status_label_p2.text)
	s.check("the failed selection is not replaced by a CPU", ai.get_controller_config(true).kind != ControllerConfig.Kind.CPU)
	DirAccess.remove_absolute(bad_dir.path_join("model.onnx"))
	DirAccess.remove_absolute(bad_dir.path_join("bvs.json"))
	model_manager.bundled_dir = bad_dir
	model_manager.reload_bundled()
	s.check("a missing bundled model reports it too", model_manager.bundled_default() == null and model_manager.bundled_error.contains("missing"), model_manager.bundled_error)
	DirAccess.remove_absolute(bad_dir)
	model_manager.bundled_dir = good_dir
	model_manager.reload_bundled()
	option_p2.select(3)
	ai.refresh_status(true)
	s.check("with the bundle restored Play is enabled again", not select.play_button.disabled and ai.is_ready_to_play())
	s.finish()
