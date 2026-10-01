extends SceneTree
## S2 movement feel: short vs full hop, double jump (once per airtime, restored
## on landing), coyote time, jump buffer, dash from Idle/Run/air (one air dash).

const Smoke := preload("res://tests/smoke/smoke_util.gd")

func _initialize() -> void:
	_run()

# Spawns a fresh game and lets both fighters settle on the counter.
func _setup(s: RefCounted, p1_x: float = 330.0, p2_x: float = 700.0) -> Array:
	var game: Node2D = s.spawn_game(p1_x, p2_x)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(90)
	return [game, controllers]

# Highest point (pixels above the starting y) reached by one jump.
func _apex(s: RefCounted, hold_jump: bool) -> float:
	var setup := await _setup(s)
	var fighter: Fighter = setup[0].get_node("Fighter1")
	var controller = setup[1][0]
	var start_y := fighter.position.y
	var min_y := start_y
	controller.jump_held_level = hold_jump
	controller.press_jump()
	for i in 90:
		await s.frames(1)
		min_y = minf(min_y, fighter.position.y)
	await s.despawn(setup[0])
	return start_y - min_y

func _run() -> void:
	var s := Smoke.new(self)
	await _jump_heights(s)
	await _double_jump(s)
	await _coyote(s)
	await _buffered_jump(s)
	await _dashes(s)
	s.finish()

func _jump_heights(s: RefCounted) -> void:
	var full := await _apex(s, true)
	var short := await _apex(s, false)
	s.check("full hop apex is snappy (well under the 360 px baseline)", full > 120.0 and full < 260.0, "full=%.0f px" % full)
	s.check("short hop apex is lower than the full hop", short > 10.0 and short < full * 0.6, "short=%.0f full=%.0f" % [short, full])

func _double_jump(s: RefCounted) -> void:
	var setup := await _setup(s)
	var game: Node2D = setup[0]
	var fighter: Fighter = game.get_node("Fighter1")
	var controller = setup[1][0]
	var max_jumps := fighter.profile.max_air_jumps
	s.check("a grounded fighter has its air jump available", fighter.jumps_left == max_jumps, "jumps_left=%d" % fighter.jumps_left)

	controller.jump_held_level = true
	controller.press_jump()
	await s.frames(10)
	s.check("first jump leaves the floor and keeps the air jump", not fighter.is_on_floor() and fighter.jumps_left == max_jumps, "jumps_left=%d" % fighter.jumps_left)

	controller.press_jump()
	await s.frames(2)
	s.check("second press in the air double-jumps", s.state_of(fighter) == "Jump" and fighter.jumps_left == max_jumps - 1 and fighter.velocity.y < -300.0, "state=%s jumps_left=%d vy=%.0f" % [s.state_of(fighter), fighter.jumps_left, fighter.velocity.y])
	await s.screenshot("s2_double_jump_midair")

	var vy_before := fighter.velocity.y
	controller.press_jump()
	await s.frames(1)
	s.check("a third press does nothing (no triple jump)", fighter.jumps_left == 0 and fighter.velocity.y >= vy_before, "vy %.0f -> %.0f" % [vy_before, fighter.velocity.y])

	controller.jump_held_level = false
	var landed: bool = await s.wait_grounded(fighter)
	await s.frames(3)
	s.check("landing restores the air jump", landed and fighter.jumps_left == max_jumps, "jumps_left=%d" % fighter.jumps_left)
	await s.despawn(game)

# Walks off the left edge; returns [game, controller, fighter] right after the
# first airborne frame, with the walk input released.
func _walk_off_edge(s: RefCounted) -> Array:
	var setup := await _setup(s)
	var fighter: Fighter = setup[0].get_node("Fighter1")
	var controller = setup[1][0]
	controller.move_x = -1.0
	var waited := 0
	while fighter.is_on_floor() and waited < 400:
		await s.frames(1)
		waited += 1
	controller.move_x = 0.0
	return [setup[0], controller, fighter]

func _coyote(s: RefCounted) -> void:
	var early := await _walk_off_edge(s)
	var fighter: Fighter = early[2]
	var max_jumps := fighter.profile.max_air_jumps
	s.check("fighter walked off the edge", not fighter.is_on_floor() and fighter.stocks == Fighter.MAX_STOCKS)
	await s.frames(3)
	early[1].jump_held_level = true
	early[1].press_jump()
	await s.frames(2)
	s.check("coyote jump shortly after leaving the edge is a ground jump", s.state_of(fighter) == "Jump" and fighter.jumps_left == max_jumps and fighter.velocity.y < -400.0, "state=%s jumps_left=%d vy=%.0f" % [s.state_of(fighter), fighter.jumps_left, fighter.velocity.y])
	await s.despawn(early[0])

	var late := await _walk_off_edge(s)
	var late_fighter: Fighter = late[2]
	await s.frames(20)
	late[1].jump_held_level = true
	late[1].press_jump()
	await s.frames(2)
	s.check("after the coyote window the press is the air jump", s.state_of(late_fighter) == "Jump" and late_fighter.jumps_left == max_jumps - 1, "state=%s jumps_left=%d" % [s.state_of(late_fighter), late_fighter.jumps_left])
	await s.despawn(late[0])

func _buffered_jump(s: RefCounted) -> void:
	var setup := await _setup(s)
	var game: Node2D = setup[0]
	var fighter: Fighter = game.get_node("Fighter1")
	var controller = setup[1][0]
	controller.press_jump()
	await s.frames(8)
	controller.press_jump()
	await s.frames(2)
	s.check("air jump is spent before the buffered press", fighter.jumps_left == 0, "jumps_left=%d" % fighter.jumps_left)

	var guard := 0
	while guard < 240 and not (fighter.velocity.y > 0.0 and s.floor_top(game) - s.body_bottom(fighter) < 35.0):
		await s.frames(1)
		guard += 1
	var gap: float = s.floor_top(game) - s.body_bottom(fighter)
	controller.press_jump()
	var touched_floor := false
	var jumped := false
	for i in 14:
		await s.frames(1)
		touched_floor = touched_floor or fighter.is_on_floor()
		if s.state_of(fighter) == "Jump" and fighter.velocity.y < -300.0:
			jumped = true
			break
	s.check("jump pressed just before landing fires on landing", touched_floor and jumped, "gap=%.0f touched=%s jumped=%s" % [gap, touched_floor, jumped])
	await s.frames(3)
	s.check("the buffered jump is a ground jump (air jump restored)", fighter.jumps_left == fighter.profile.max_air_jumps, "jumps_left=%d" % fighter.jumps_left)
	await s.despawn(game)

func _dashes(s: RefCounted) -> void:
	var setup := await _setup(s)
	var game: Node2D = setup[0]
	var fighter: Fighter = game.get_node("Fighter1")
	var controller = setup[1][0]

	controller.press_dash()
	await s.frames(2)
	s.check("dash works from Idle", s.state_of(fighter) == "Dash", "state=%s" % s.state_of(fighter))
	await s.frames(40)

	controller.move_x = 1.0
	await s.frames(12)
	s.check("fighter is running", s.state_of(fighter) == "Run", "state=%s" % s.state_of(fighter))
	controller.press_dash()
	await s.frames(2)
	s.check("dash works from Run", s.state_of(fighter) == "Dash", "state=%s" % s.state_of(fighter))
	controller.move_x = 0.0
	await s.frames(40)

	controller.press_jump()
	await s.frames(8)
	controller.move_x = 1.0
	controller.press_dash()
	await s.frames(2)
	s.check("dash works in the air and spends the air dash", s.state_of(fighter) == "Dash" and not fighter.air_dash_available and fighter.velocity.x > 400.0, "state=%s available=%s vx=%.0f" % [s.state_of(fighter), fighter.air_dash_available, fighter.velocity.x])
	controller.move_x = 0.0
	await s.frames(20)
	controller.press_dash()
	await s.frames(2)
	s.check("a second air dash in the same airtime is ignored", s.state_of(fighter) != "Dash", "state=%s" % s.state_of(fighter))
	var landed: bool = await s.wait_grounded(fighter)
	await s.frames(3)
	s.check("landing restores the air dash", landed and fighter.air_dash_available)
	await s.despawn(game)
