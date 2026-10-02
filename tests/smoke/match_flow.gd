extends SceneTree
## S4 match flow, windowed (screenshots): the 3-2-1-GO countdown, pause (Esc and
## Start toggle, the countdown and the match timer freeze), sudden death on a tie,
## the winner by stocks, "GAME!" in slow motion, the results screen, rematch and
## the SFX pitch bands. The CPU-vs-CPU end-to-end run is `match_e2e.gd`.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const SELECT_SCENE := "res://ui/character_select/character_select.tscn"
const Level := CpuDifficulty.Level

var s: RefCounted
var scene_manager: Node

func _initialize() -> void:
	_run()

# ------------------------------------------------------------------ helpers

func _key(keycode: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	return event

## A full Esc key press (down and up), delivered through the real input path.
func _press_escape() -> void:
	Input.parse_input_event(_key(KEY_ESCAPE, true))
	await s.frames(2)
	Input.parse_input_event(_key(KEY_ESCAPE, false))
	await s.frames(2)

func _press_start() -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_START
	event.pressed = true
	Input.parse_input_event(event)
	await s.frames(2)
	event = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_START
	event.pressed = false
	Input.parse_input_event(event)
	await s.frames(2)

func _pause_menu(game: Node) -> Control:
	return game.get_node("UI/Pause")

## Samples the banner every frame and records each new text, so a skipped or
## repeated digit shows up in the sequence.
func _watch_banner(game: Game, seen: Array[String], max_frames: int, until_phase: Game.Phase = Game.Phase.PLAYING) -> void:
	for i in max_frames:
		var label: Label = game.countdown_label
		if label.visible and (seen.is_empty() or seen[-1] != label.text):
			seen.append(label.text)
		if game.phase == until_phase:
			# One more frame so a "GO!" shown by the same step is recorded.
			await s.frames(1)
			if label.visible and seen[-1] != label.text:
				seen.append(label.text)
			return
		await s.frames(1)

func _knock_out(fighter: Fighter) -> void:
	fighter.position = Vector2(fighter.blast_zone.position.x - 80.0, 300.0)

## Waits until the results screen is up (real time: GAME! runs in slow motion).
func _wait_results(game: Game) -> bool:
	for i in 40:
		if game.game_over.visible:
			return true
		await s.real_wait(0.1)
	return game.game_over.visible

func _leave(game: Node) -> void:
	paused = false
	Engine.time_scale = 1.0
	await s.despawn(game)

func _real_characters() -> Array:
	var select: Control = load(SELECT_SCENE).instantiate()
	root.add_child(select)
	await s.frames(2)
	var characters: Array = select.characters.duplicate()
	select.free()
	return characters

# --------------------------------------------------------------- scenarios

func _countdown() -> void:
	var game: Game = s.spawn_game(NAN, NAN, true)
	var controllers: Array = s.attach_controllers(game)
	var fighter: Fighter = game.get_node("Fighter1")
	var start_x := fighter.position.x
	var seen: Array[String] = []
	var blocked := true
	var timer_stopped := true
	var phase_ok := true
	for i in 70:
		controllers[0].move_x = 1.0
		controllers[0].press_punch()
		controllers[0].press_jump()
		controllers[1].move_x = -1.0
		await s.frames(1)
		blocked = blocked and absf(fighter.position.x - start_x) < 1.0 and s.state_of(fighter) in ["Idle", "Fall"]
		timer_stopped = timer_stopped and game.timer.is_stopped()
		phase_ok = phase_ok and game.phase == Game.Phase.COUNTDOWN
		if game.countdown_label.visible and (seen.is_empty() or seen[-1] != game.countdown_label.text):
			seen.append(game.countdown_label.text)
		if i == 30:
			await s.screenshot("s4_countdown_3")
	s.check("countdown: the banner starts at 3", seen.size() > 0 and seen[0] == "3", str(seen))
	s.check("countdown: move, punch and jump are ignored while it runs", blocked, "x=%.1f from %.1f" % [fighter.position.x, start_x])
	s.check("countdown: the match timer is stopped and the phase is COUNTDOWN", timer_stopped and phase_ok)
	s.check("countdown: the timer label shows the full match length", game.get_node("UI/TimerLabel").text == "99", game.get_node("UI/TimerLabel").text)
	s.check("countdown: fighters are locked", fighter.controls_locked and game.get_node("Fighter2").controls_locked)

	await _watch_banner(game, seen, 400)
	s.check("countdown: 3, 2, 1, GO! in order, none skipped", seen == ["3", "2", "1", "GO!"], str(seen))
	s.check("GO: the match is PLAYING, fighters unlocked, timer running", game.phase == Game.Phase.PLAYING and not fighter.controls_locked and not game.timer.is_stopped())
	await s.frames(8)
	await s.screenshot("s4_countdown_go")

	var before := fighter.position.x
	for i in 30:
		controllers[0].move_x = 1.0
		await s.frames(1)
	s.check("GO: input moves the fighter at once", fighter.position.x - before > 20.0, "dx=%.0f" % (fighter.position.x - before))
	await s.sim(0.5)
	s.check("GO: the timer counts down", game.timer.time_left < 99.0, "left=%.2f" % game.timer.time_left)
	var spawner: FoodSpawner = game.food_spawner
	s.check("GO: the food spawner is running", not spawner.spawn_timer.is_stopped())
	await _leave(game)

func _spawner_waits_for_go() -> void:
	var game: Game = s.spawn_game(NAN, NAN, true)
	await s.frames(5)
	s.check("countdown: the food spawner has not started", game.food_spawner.spawn_timer.is_stopped())
	game.skip_countdown()
	s.check("skip_countdown starts the match at once", game.phase == Game.Phase.PLAYING and not game.timer.is_stopped() and not game.countdown_label.visible)
	await _leave(game)

func _pause_in_countdown() -> void:
	var game: Game = s.spawn_game(NAN, NAN, true)
	var seen: Array[String] = []
	var frames_done := 0
	while game.countdown_label.text != "2" and frames_done < 200:
		await s.frames(1)
		frames_done += 1
		if game.countdown_label.visible and (seen.is_empty() or seen[-1] != game.countdown_label.text):
			seen.append(game.countdown_label.text)
	var left_before: float = game._flow_timer.time_left
	await _press_escape()
	var menu := _pause_menu(game)
	s.check("pause: Esc during the countdown opens the pause menu", paused and menu.visible)
	await s.screenshot("s4_pause_menu")
	var left_paused: float = game._flow_timer.time_left
	await s.real_wait(1.5)
	s.check("pause: the countdown digit stays put for longer than a step", game.countdown_label.text == "2" and game.phase == Game.Phase.COUNTDOWN, game.countdown_label.text)
	s.check("pause: the countdown timer does not advance", is_equal_approx(game._flow_timer.time_left, left_paused), "%.3f vs %.3f" % [game._flow_timer.time_left, left_paused])
	await _press_escape()
	s.check("pause: Esc again resumes", not paused and not menu.visible)
	await _watch_banner(game, seen, 400)
	s.check("pause: the countdown resumes with no skipped digit", seen == ["3", "2", "1", "GO!"], str(seen) + " before=%.2f" % left_before)
	await _leave(game)

func _timer_pauses() -> void:
	var game: Game = s.spawn_game()
	await s.sim(1.0)
	var menu := _pause_menu(game)
	await _press_start()
	var t_before: float = game.timer.time_left
	s.check("pause: Start opens the pause menu in a live match", paused and menu.visible)
	await s.real_wait(0.6)
	s.check("pause: the match timer is frozen", is_equal_approx(game.timer.time_left, t_before), "%.3f -> %.3f" % [t_before, game.timer.time_left])
	await _press_escape()
	s.check("pause: Esc closes it again", not paused and not menu.visible)
	t_before = game.timer.time_left
	await s.sim(0.5)
	s.check("pause: the timer runs again after resuming", game.timer.time_left < t_before - 0.4, "%.2f -> %.2f" % [t_before, game.timer.time_left])
	var button: Button = menu.get_node("UnpauseButton")
	await _press_escape()
	s.check("pause: opens a second time", paused and menu.visible)
	button.pressed.emit()
	s.check("pause: the on-screen button resumes too", not paused and not menu.visible)
	await _leave(game)

## Every banner (3/2/1/GO!/GAME!/SUDDEN DEATH) at its worst moment (the start of
## the pop-in) is fully inside the viewport at any camera zoom.
func _banners_fit_any_zoom() -> void:
	var game: Game = s.spawn_game()
	var viewport := Rect2(Vector2.ZERO, game.get_viewport().get_visible_rect().size)
	var camera: Camera2D = game.get_node("Camera2D")
	var banners: Array = [["3", 170], ["2", 170], ["1", 170], ["GO!", 190], ["GAME!", 170], ["SUDDEN DEATH", 84], ["A VERY LONG ANNOUNCEMENT TEXT", 170]]
	for zoom in [0.58, 1.0, 1.15]:
		camera.zoom = Vector2.ONE * zoom
		var worst := ""
		for banner in banners:
			game._show_banner(banner[0], Color.WHITE, banner[1])
			await s.frames(1)
			var rect: Rect2 = game.banner_screen_rect()
			if not viewport.encloses(rect):
				worst += " %s=%s;" % [banner[0], str(rect)]
		s.check("banners fit the viewport at camera zoom %.2f" % zoom, worst.is_empty(), worst)
	game._hide_banner()
	game.queue_free()
	await s.frames(2)

func _sudden_death() -> void:
	var game: Game = s.spawn_game()
	var controllers: Array = s.attach_controllers(game)
	var fighter_1: Fighter = game.get_node("Fighter1")
	var fighter_2: Fighter = game.get_node("Fighter2")
	fighter_1.add_damage(50.0)
	fighter_1.position.x = 400.0
	game.timer.start(0.3)
	await s.sim(0.6)
	s.check("sudden death: equal stocks at time-up start sudden death", game.phase == Game.Phase.SUDDEN_DEATH and game.get_state_snapshot()["sudden_death"])
	s.check("sudden death: both fighters at 1 stock", fighter_1.stocks == 1 and fighter_2.stocks == 1, "%d/%d" % [fighter_1.stocks, fighter_2.stocks])
	s.check("sudden death: both at 300%", is_equal_approx(fighter_1.damage_percent, 300.0) and is_equal_approx(fighter_2.damage_percent, 300.0), "%.0f/%.0f" % [fighter_1.damage_percent, fighter_2.damage_percent])
	s.check("sudden death: the timer is off and its label hidden", game.timer.is_stopped() and not game.get_node("UI/TimerLabel").visible)
	s.check("sudden death: fighters are back on their start spots", absf(fighter_1.position.x - fighter_1.initial_position.x) < 30.0, "x=%.0f" % fighter_1.position.x)
	s.check("sudden death: the banner reads SUDDEN DEATH", game.countdown_label.visible and game.countdown_label.text == "SUDDEN DEATH")
	await s.screenshot("s4_sudden_death")
	var hud_text: String = fighter_1.get_node("PlayerUI/Panel/PercentLabel").text
	s.check("sudden death: the HUD shows 300%", hud_text == "300%", hud_text)

	var x_locked := fighter_1.position.x
	for i in 20:
		controllers[0].move_x = 1.0
		await s.frames(1)
	s.check("sudden death: fighters are locked during the intro", absf(fighter_1.position.x - x_locked) < 1.0)
	await s.sim(2.0)
	s.check("sudden death: unlocked after the intro, no new stocks or timer", not fighter_1.controls_locked and game.timer.is_stopped() and game.phase == Game.Phase.SUDDEN_DEATH)
	_knock_out(fighter_2)
	await s.frames(4)
	s.check("sudden death: the next KO ends the match with the survivor as winner", game.phase == Game.Phase.OVER and game.winner == fighter_1)
	s.check("sudden death: GAME! is announced", game.countdown_label.visible and game.countdown_label.text == "GAME!")
	await _wait_results(game)
	await _leave(game)

func _winner_by_stocks() -> void:
	var game: Game = s.spawn_game()
	var fighter_1: Fighter = game.get_node("Fighter1")
	var fighter_2: Fighter = game.get_node("Fighter2")
	fighter_1.set_stocks(2)
	fighter_2.add_damage(80.0)
	game.timer.start(0.2)
	await s.sim(0.5)
	s.check("timeout with unequal stocks: no sudden death, the match is over", game.phase == Game.Phase.OVER and not game.get_state_snapshot()["sudden_death"])
	s.check("timeout with unequal stocks: more stocks wins", game.winner == fighter_2, "winner=%s" % [game.winner])
	s.check("timeout with unequal stocks: stocks and damage untouched", fighter_1.stocks == 2 and fighter_2.stocks == 3 and is_equal_approx(fighter_2.damage_percent, 80.0))
	await _wait_results(game)
	s.check("timeout with unequal stocks: the results name the winner", game.game_over.get_node("%WinnerNameLabel").text == fighter_2.character_ui.name.to_upper())
	await _leave(game)

func _double_ko() -> void:
	var game: Game = s.spawn_game()
	var fighter_1: Fighter = game.get_node("Fighter1")
	var fighter_2: Fighter = game.get_node("Fighter2")
	fighter_1.set_stocks(1)
	fighter_2.set_stocks(1)
	_knock_out(fighter_1)
	_knock_out(fighter_2)
	await s.frames(4)
	s.check("double KO on the last stocks: sudden death, not a game over", game.phase == Game.Phase.SUDDEN_DEATH and not game.game_over.visible)
	s.check("double KO: both are alive again at 1 stock and 300%", fighter_1.stocks == 1 and fighter_2.stocks == 1 and is_equal_approx(fighter_1.damage_percent, 300.0))
	await _leave(game)

func _game_and_results() -> void:
	var game: Game = s.spawn_game()
	var fighter_1: Fighter = game.get_node("Fighter1")
	var fighter_2: Fighter = game.get_node("Fighter2")
	var overs := [0]
	game.match_over.connect(func(_w: Fighter) -> void: overs[0] += 1)
	fighter_2.set_stocks(1)
	_knock_out(fighter_2)
	await s.frames(6)
	s.check("last stock lost: the phase is OVER and the survivor wins", game.phase == Game.Phase.OVER and game.winner == fighter_1)
	s.check("last stock lost: GAME! is on screen", game.countdown_label.visible and game.countdown_label.text == "GAME!")
	s.check("last stock lost: slow motion", Engine.time_scale < 1.0, "time_scale=%.2f" % Engine.time_scale)
	s.check("last stock lost: both fighters locked", fighter_1.controls_locked and fighter_2.controls_locked)
	await s.frames(25)
	await s.screenshot("s4_game")
	await _press_escape()
	s.check("pause is ignored once the match is decided", not paused and not _pause_menu(game).visible)
	s.check("the results are not up yet during GAME!", not game.game_over.visible)
	var reached := await _wait_results(game)
	s.check("GAME! gives way to the results screen", reached and paused)
	s.check("time scale is back to 1.0 on the results", is_equal_approx(Engine.time_scale, 1.0), "%.2f" % Engine.time_scale)
	s.check("the match is decided exactly once", overs[0] == 1, "count=%d" % overs[0])
	var portrait: ResultsPanel = game.game_over.get_node("%WinnerPanel")
	s.check("the results show the winner's art", portrait.texture != null)
	s.check("the results name the winner", game.game_over.get_node("%WinnerNameLabel").text == fighter_1.character_ui.name.to_upper())
	var result_name: Label = game.game_over.get_node("%WinnerNameLabel")
	var result_wins: Label = game.game_over.get_node("%WinnerLabel")
	s.check("the results read '<NAME> WINS!' in big letters", (result_name.text + " " + result_wins.text).strip_edges() == fighter_1.character_ui.name.to_upper() + " WINS!" and result_name.get_theme_font_size("font_size") >= 56, "text=%s size=%d" % [result_name.text + " " + result_wins.text, result_name.get_theme_font_size("font_size")])
	var captions: Array[String] = []
	for button_name in ["%ReplayButton", "%CharactersButton", "%MainMenuButton"]:
		captions.append((game.game_over.get_node(button_name).get_node("Caption") as Label).text)
	s.check("the results buttons are captioned Rematch, Characters, Main Menu", captions == ["Rematch", "Characters", "Main Menu"], str(captions))
	var timer_hidden: bool = not game.timer_label.visible
	var huds_hidden := true
	for fighter in [fighter_1, fighter_2]:
		huds_hidden = huds_hidden and not (fighter.get_node("PlayerUI") as CanvasLayer).visible
	s.check("the in-game timer and fighter panels are hidden behind the results", timer_hidden and huds_hidden, "timer_hidden=%s huds_hidden=%s" % [timer_hidden, huds_hidden])
	await s.frames(10)
	await s.screenshot("s5b_results")
	await _press_escape()
	s.check("pause stays closed on the results screen", paused and not _pause_menu(game).visible)
	await _leave(game)

func _rematch() -> void:
	var characters := await _real_characters()
	var holder := Node.new()
	root.add_child(holder)
	scene_manager.scene_container = holder
	var cfg_1 := ControllerConfig.human()
	var cfg_2 := ControllerConfig.cpu(Level.HARD)
	scene_manager.play_game(characters[0], characters[1], cfg_1, cfg_2)
	await s.frames(3)
	var first: Game = scene_manager.current_scene
	first.skip_countdown()
	first.get_node("Fighter2").set_stocks(1)
	_knock_out(first.get_node("Fighter2"))
	await s.frames(4)
	s.check("rematch: the first match ends", first.phase == Game.Phase.OVER)
	var reached := await _wait_results(first)
	s.check("rematch: the results offer the three buttons", reached and first.game_over.get_node("%ReplayButton") != null and first.game_over.get_node("%CharactersButton") != null and first.game_over.get_node("%MainMenuButton") != null)
	var winner_art: Texture2D = first.game_over.get_node("%WinnerPanel").texture
	s.check("rematch: a real character's illustration is shown", winner_art != null and winner_art == characters[0].illustration)

	first.game_over.get_node("%ReplayButton").pressed.emit()
	await s.frames(4)
	var second: Game = scene_manager.current_scene
	s.check("rematch: a new Game replaces the old one", second != first and is_instance_valid(second))
	var f1: Fighter = second.get_node("Fighter1")
	var f2: Fighter = second.get_node("Fighter2")
	s.check("rematch: same characters", f1.character_ui == characters[0] and f2.character_ui == characters[1])
	s.check("rematch: same controller configs", f1.controller is HumanController and f2.controller is ScriptedController and (f2.controller as ScriptedController).difficulty.decision_interval == CpuDifficulty.preset(Level.HARD).decision_interval)
	s.check("rematch: the countdown runs again", second.phase == Game.Phase.COUNTDOWN and second.countdown_label.visible and second.countdown_label.text == "3" and f1.controls_locked)
	s.check("rematch: the tree is unpaused and the clock normal", not paused and is_equal_approx(Engine.time_scale, 1.0))
	s.check("rematch: fresh state (3 stocks, 0%)", f1.stocks == 3 and f2.stocks == 3 and f1.damage_percent == 0.0)
	await s.real_wait(0.1)

	second.get_node("UI/GameOver/%CharactersButton").pressed.emit()
	await s.frames(4)
	s.check("back to select: the Characters button opens character select", scene_manager.current_scene_path == SELECT_SCENE and not paused)
	scene_manager.current_scene.queue_free()
	await s.frames(2)
	holder.queue_free()

func _sfx_bands() -> void:
	var events: Dictionary = Sfx.EVENTS
	for needed in [&"pickup", &"throw", &"jump", &"ko", &"hit", &"block", &"heavy_hit", &"double_jump"]:
		s.check("sfx: event %s exists" % needed, events.has(needed))
	var by_stream := {}
	for event in events:
		var entry: Array = events[event]
		if not by_stream.has(entry[0]):
			by_stream[entry[0]] = []
		by_stream[entry[0]].append([entry[1], entry[2], event])
	var disjoint := true
	var detail := ""
	for stream in by_stream:
		var bands: Array = by_stream[stream]
		bands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for i in range(1, bands.size()):
			if bands[i][0] <= bands[i - 1][1]:
				disjoint = false
				detail += " %s overlaps %s;" % [bands[i][2], bands[i - 1][2]]
	s.check("sfx: bands of the same sound never overlap", disjoint, detail)
	var pitches := {}
	var in_band := true
	for i in 30:
		var pitch := Sfx.pick_pitch(&"pickup")
		pitches[snappedf(pitch, 0.0001)] = true
		in_band = in_band and pitch >= events[&"pickup"][1] and pitch <= events[&"pickup"][2]
	s.check("sfx: repeated plays vary inside the band", in_band and pitches.size() > 10, "distinct=%d" % pitches.size())
	s.check("sfx: pickup and KO use different sounds or bands", events[&"pickup"][0] != events[&"ko"][0] or events[&"pickup"][1] != events[&"ko"][1])

func _run() -> void:
	s = Smoke.new(self, 240.0)
	scene_manager = root.get_node("SceneManager")
	await _countdown()
	await _spawner_waits_for_go()
	await _pause_in_countdown()
	await _timer_pauses()
	await _banners_fit_any_zoom()
	await _sudden_death()
	await _winner_by_stocks()
	await _double_ko()
	await _game_and_results()
	await _rematch()
	_sfx_bands()
	s.finish()
