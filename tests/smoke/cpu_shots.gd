extends SceneTree
## S3 review screenshots (windowed): character select with the controller
## options, and a CPU fight. They go to $SHOT_DIR and are never committed.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const SELECT_SCENE := "res://ui/character_select/character_select.tscn"

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)

	var select: Control = load(SELECT_SCENE).instantiate()
	root.add_child(select)
	await s.frames(5)
	select.select_player1(select.characters[0])
	select.select_player2(select.characters[1])
	await s.frames(60)
	await s.screenshot("s3_character_select_cpu_options")
	var ai: Control = select.get_node("AIController")
	ai.controller_option_p1.select(0)
	ai.controller_option_p2.select(3)
	await s.frames(5)
	var p2_config: ControllerConfig = ai.get_controller_config(true)
	s.check("P2 CPU Hard selection is reflected in the config", p2_config.kind == ControllerConfig.Kind.CPU and p2_config.difficulty == CpuDifficulty.Level.HARD)
	await s.screenshot("s3_character_select_cpu_hard")
	select.queue_free()
	await s.frames(2)

	var game: Node2D = s.spawn_game()
	s.set_cpu(game.get_node("Fighter1"), CpuDifficulty.Level.NORMAL, 2)
	s.set_cpu(game.get_node("Fighter2"), CpuDifficulty.Level.HARD, 4)
	await s.sim(6.0)
	await s.screenshot("s3_cpu_fight")
	await s.sim(4.0)
	await s.screenshot("s3_cpu_fight_later")
	s.check("both CPUs still stand on the stage", game.get_node("Fighter1").stocks > 0 and game.get_node("Fighter2").stocks > 0)
	s.finish()
