extends SceneTree
## Saves screenshots (idle start, mid-fight, fighters far apart) into $SHOT_DIR
## (default user://). Screenshots are review aids and are never committed.

const Smoke := preload("res://tests/smoke/smoke_util.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	var game: Node2D = s.spawn_game()
	var controllers: Array = s.attach_controllers(game)
	await s.frames(150)
	await s.screenshot("01_idle_start")

	var fighter_1: Fighter = game.get_node("Fighter1")
	var fighter_2: Fighter = game.get_node("Fighter2")
	fighter_1.position.x = 480.0
	fighter_2.position.x = 560.0
	await s.frames(60)
	controllers[0].press_punch()
	await s.frames(14)
	await s.screenshot("02_mid_fight")

	await s.frames(90)
	fighter_1.position.x = 60.0
	fighter_2.position.x = 800.0
	await s.frames(240)
	await s.screenshot("03_far_apart")
	s.check("screenshots written", true)
	s.finish()
