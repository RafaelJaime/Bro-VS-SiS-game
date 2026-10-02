extends SceneTree
## S4 end to end, headless: a CPU-vs-CPU match started through SceneManager runs
## the whole flow (countdown, play, time-up, GAME!, results), then rematch and
## back to character select, without script errors (run_all.sh also greps the
## engine output for them).

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const SELECT_SCENE := "res://ui/character_select/character_select.tscn"
const Level := CpuDifficulty.Level
const MATCH_LIMIT := 200.0

var s: RefCounted

func _initialize() -> void:
	_run()

func _real_characters() -> Array:
	var select: Control = load(SELECT_SCENE).instantiate()
	root.add_child(select)
	await s.frames(2)
	var characters: Array = select.characters.duplicate()
	select.free()
	return characters

# Plays the current match to its results screen. A short clock keeps it quick;
# the flow (time-up, maybe sudden death, GAME!, results) is the real one.
func _play_to_results(game: Game, label: String, clock: float) -> void:
	var waited := 0.0
	while game.phase == Game.Phase.COUNTDOWN and waited < 10.0:
		await s.sim(0.25)
		waited += 0.25
	s.check("%s: the countdown hands over to PLAYING" % label, game.phase == Game.Phase.PLAYING, "phase=%d" % game.phase)
	game.timer.start(clock)
	var elapsed := 0.0
	while not game.game_over.visible and elapsed < MATCH_LIMIT:
		await s.sim(1.0)
		elapsed += 1.0
	s.check("%s: the CPU match reaches the results" % label, game.game_over.visible and paused, "after %.0f s, phase=%d" % [elapsed, game.phase])
	s.check("%s: the match has a winner" % label, game.winner != null and game.winner.stocks > 0, "winner=%s" % [game.winner])
	s.check("%s: the clock is back to normal" % label, is_equal_approx(Engine.time_scale, 1.0))

func _run() -> void:
	s = Smoke.new(self, 1500.0)
	var scene_manager: Node = root.get_node("SceneManager")
	var characters := await _real_characters()
	var holder := Node.new()
	root.add_child(holder)
	scene_manager.scene_container = holder

	scene_manager.play_game(characters[0], characters[1], ControllerConfig.cpu(Level.HARD), ControllerConfig.cpu(Level.NORMAL))
	await s.frames(3)
	var first: Game = scene_manager.current_scene
	s.check("e2e: the match opens in the countdown with both CPUs locked", first.phase == Game.Phase.COUNTDOWN and first.get_node("Fighter1").controls_locked and first.get_node("Fighter2").controls_locked)
	await _play_to_results(first, "match 1", 20.0)

	first.game_over.get_node("%ReplayButton").pressed.emit()
	await s.frames(4)
	var second: Game = scene_manager.current_scene
	s.check("e2e: rematch starts a new match in COUNTDOWN", second != first and second.phase == Game.Phase.COUNTDOWN and not paused)
	s.check("e2e: rematch keeps both CPUs", second.get_node("Fighter1").controller is ScriptedController and second.get_node("Fighter2").controller is ScriptedController)
	await _play_to_results(second, "match 2 (rematch)", 15.0)

	second.game_over.get_node("%ReplayButton").pressed.emit()
	await s.frames(4)
	var third: Game = scene_manager.current_scene
	await _play_to_results(third, "match 3 (second rematch)", 15.0)

	third.game_over.get_node("%CharactersButton").pressed.emit()
	await s.frames(4)
	s.check("e2e: Characters returns to character select", scene_manager.current_scene_path == SELECT_SCENE and not paused)
	s.finish()
