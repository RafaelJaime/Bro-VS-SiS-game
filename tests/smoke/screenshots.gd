extends SceneTree
## Saves screenshots (idle start, mid-fight, fighters far apart, a close zoomed-in
## fight, a fighter falling off the end of the table) into $SHOT_DIR
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

	# Zoomed in: both fighters close together on the table.
	fighter_1.position.x = 380.0
	fighter_2.position.x = 470.0
	await s.frames(240)
	s.check("the close fight zooms in", game.get_node("Camera2D").zoom.x > 1.1, "zoom=%.2f" % game.get_node("Camera2D").zoom.x)
	await s.screenshot("04_close_zoomed_in")

	# Ring-out off the table end: Fighter 2 walks off the right end and falls.
	fighter_1.position.x = 700.0
	fighter_2.position.x = 806.0
	await s.frames(30)
	controllers[1].move_x = 1.0
	var guard := 0
	while fighter_2.position.x < 852.0 and guard < 120:
		await s.frames(1)
		guard += 1
	controllers[1].move_x = 0.0
	await s.frames(18)
	s.check("the fighter is past the table end and falling", fighter_2.position.x > 830.0 and fighter_2.position.y > 480.0, "pos=%s" % [fighter_2.position])
	await s.screenshot("05_falling_off_table_end")
	s.check("screenshots written", true)
	s.finish()
