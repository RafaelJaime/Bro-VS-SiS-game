extends SceneTree
## S5b ledge grab on the table legs: grab zone, snap, invulnerability and its
## decay, climb, ledge jump, drop, climb attack, trump, max hang.

const Smoke := preload("res://tests/smoke/smoke_util.gd")

func _initialize() -> void:
	_run()

func _setup(s: RefCounted) -> Array:
	var game: Node2D = s.spawn_game()
	var controllers: Array = s.attach_controllers(game)
	await s.frames(60)
	return [game, controllers, game.get_node("Fighter1"), game.get_node("Fighter2")]

# Drops `fighter` just outside the table end `side` (-1 left, 1 right), `depth`
# below the tabletop, falling slowly.
func _drop_at(game: Node2D, fighter: Fighter, side: int, depth: float, dx: float = 0.0, clear_lockout: bool = false) -> void:
	if clear_lockout:
		fighter.block_ledge_grab(0.0)
		fighter._ledge_lockout = 0.0
	var ledge: Dictionary = game.get_ledges()[0 if side < 0 else 1]
	fighter.position = Vector2(ledge["x"] + side * fighter.profile.ledge_hang_offset + dx, ledge["top"] + depth)
	fighter.velocity = Vector2(0.0, 100.0)
	fighter.state_machine._change_state("Fall")

func _run() -> void:
	var s := Smoke.new(self)

	# --- the zone, in the snapshot and the table art ---
	var setup := await _setup(s)
	var game: Node2D = setup[0]
	var f1: Fighter = setup[2]
	var f2: Fighter = setup[3]
	var c1 = setup[1][0]
	var c2 = setup[1][1]
	var stage: Dictionary = game.get_state_snapshot()["stage"]
	var ledges: Array = game.get_state_snapshot()["ledges"]
	s.check("the snapshot lists two ledges at the table ends", ledges.size() == 2 and is_equal_approx(ledges[0]["x"], stage["left"]) and is_equal_approx(ledges[1]["x"], stage["right"]), "ledges=%s" % [ledges])
	var table: TableStage = game.get_node("TableStage")
	s.check("the grab zone runs from the tabletop to the bottom of the legs", is_equal_approx(ledges[0]["top"], stage["top"]) and is_equal_approx(ledges[0]["bottom"], table.floor_y), "bottom=%.0f floor_y=%.0f" % [ledges[0]["bottom"], table.floor_y])
	var outer_left: float = table._leg_xs().filter(func(leg): return not leg["back"])[0]["x"]
	s.check("the outer legs are flush with the table ends", absf(outer_left - stage["left"]) <= 8.0, "leg x=%.0f table end=%.0f" % [outer_left, stage["left"]])

	# --- grab ---
	_drop_at(game, f1, -1, 40.0)
	await s.frames(3)
	var hang_x: float = stage["left"] - f1.profile.ledge_hang_offset
	s.check("a fighter falling past the table end grabs the leg", s.state_of(f1) == "LedgeHang" and f1.ledge_side == -1, "state=%s side=%d" % [s.state_of(f1), f1.ledge_side])
	s.check("it snaps to the leg", absf(f1.position.x - hang_x) < 1.0 and f1.velocity == Vector2.ZERO and f1.facing == 1, "x=%.1f want %.1f facing=%d" % [f1.position.x, hang_x, f1.facing])
	s.check("hanging fighters are invulnerable and refill their air actions", f1.is_invulnerable and f1.jumps_left == f1.profile.max_air_jumps and f1.recovery_available and f1.air_dash_available)
	s.check("the snapshot shows the ledge state", f1.get_state_snapshot()["ledge_side"] == -1 and game.get_state_snapshot()["ledges"][0]["occupied"] == true)
	await s.frames(30)
	await s.screenshot("s5b_ledge_hang")
	var first_invuln := f1._invuln_timer.time_left
	var damage_before := f1.damage_percent
	Combat.apply_hit(f2, f1, 8.0, Vector2(200.0, -100.0))
	await s.frames(3)
	s.check("ledge invulnerability blocks hits", is_equal_approx(f1.damage_percent, damage_before) and s.state_of(f1) == "LedgeHang", "damage=%.1f state=%s" % [f1.damage_percent, s.state_of(f1)])
	await s.sim(1.0)
	Combat.apply_hit(f2, f1, 8.0, Vector2(200.0, -100.0))
	await s.frames(3)
	s.check("after the invulnerability a hit knocks the fighter off the leg", f1.damage_percent > damage_before and s.state_of(f1) == "Hurt" and f1.ledge_side == 0, "damage=%.1f state=%s" % [f1.damage_percent, s.state_of(f1)])
	await s.despawn(game)

	# --- zone limits ---
	var zone := await _setup(s)
	var zf: Fighter = zone[2]
	_drop_at(zone[0], zf, -1, 40.0, 200.0)
	await s.frames(3)
	s.check("no grab when too far from the leg", s.state_of(zf) != "LedgeHang")
	await s.despawn(zone[0])
	var low := await _setup(s)
	_drop_at(low[0], low[2], 1, 140.0)
	await s.frames(3)
	s.check("the leg can be grabbed lower down too, hanging where the fighter is", s.state_of(low[2]) == "LedgeHang" and low[2].ledge_side == 1 and low[2].position.y >= low[0].get_ledges()[1]["top"] + 130.0, "state=%s y=%.0f" % [s.state_of(low[2]), low[2].position.y])
	await s.despawn(low[0])
	var below := await _setup(s)
	_drop_at(below[0], below[2], -1, 400.0)
	await s.frames(3)
	s.check("no grab below the bottom of the legs", s.state_of(below[2]) != "LedgeHang", "state=%s" % s.state_of(below[2]))
	await s.despawn(below[0])
	var away := await _setup(s)
	away[1][0].move_x = -1.0
	_drop_at(away[0], away[2], -1, 40.0)
	await s.frames(3)
	s.check("pushing away from the table skips the grab", s.state_of(away[2]) != "LedgeHang")
	await s.despawn(away[0])
	var rising := await _setup(s)
	_drop_at(rising[0], rising[2], -1, 40.0)
	rising[2].velocity.y = -400.0
	rising[2].state_machine._change_state("Jump")
	await s.frames(2)
	s.check("a fighter rising fast does not grab", s.state_of(rising[2]) != "LedgeHang")
	await s.despawn(rising[0])

	# --- climb ---
	var climb := await _setup(s)
	var cf: Fighter = climb[2]
	_drop_at(climb[0], cf, 1, 60.0)
	await s.frames(15)
	climb[1][0].aim = FighterIntent.Aim.UP
	await s.frames(3)
	s.check("up climbs: the fighter is not hanging and is invulnerable", cf.ledge_side == 0 and cf.is_invulnerable and s.state_of(cf) == "LedgeHang")
	await s.sim(1.0)
	climb[1][0].aim = FighterIntent.Aim.NEUTRAL
	await s.frames(5)
	var climb_stage: Dictionary = climb[0].get_state_snapshot()["stage"]
	s.check("the climb lands on the tabletop", cf.is_on_floor() and cf.position.x > climb_stage["left"] and cf.position.x < climb_stage["right"] and cf.stocks == Fighter.MAX_STOCKS and s.state_of(cf) != "LedgeHang", "state=%s pos=(%.0f, %.0f)" % [s.state_of(cf), cf.position.x, cf.position.y])
	await s.despawn(climb[0])

	var toward := await _setup(s)
	_drop_at(toward[0], toward[2], 1, 60.0)
	await s.frames(15)
	toward[1][0].move_x = -1.0
	await s.sim(1.0)
	s.check("pushing toward the table also climbs", toward[2].is_on_floor() and s.state_of(toward[2]) != "LedgeHang")
	await s.despawn(toward[0])

	# --- ledge jump ---
	var jump := await _setup(s)
	var jf: Fighter = jump[2]
	_drop_at(jump[0], jf, -1, 40.0)
	await s.frames(15)
	jump[1][0].move_x = 1.0
	jump[1][0].jump_held_level = true
	jump[1][0].press_jump()
	await s.frames(3)
	s.check("jump from the leg is a ledge jump that keeps the air jump", s.state_of(jf) == "Jump" and jf.velocity.y < -400.0 and jf.jumps_left == jf.profile.max_air_jumps, "state=%s vy=%.0f jumps=%d" % [s.state_of(jf), jf.velocity.y, jf.jumps_left])
	jump[1][0].jump_held_level = false
	var landed: bool = await s.wait_grounded(jf, 240)
	var jump_stage: Dictionary = jump[0].get_state_snapshot()["stage"]
	s.check("the ledge jump gets back on the table", landed and jf.position.x > jump_stage["left"] and jf.stocks == Fighter.MAX_STOCKS, "pos=(%.0f, %.0f)" % [jf.position.x, jf.position.y])
	await s.despawn(jump[0])

	# --- drop, regrab lockout and the diminishing invulnerability ---
	var drop := await _setup(s)
	var df: Fighter = drop[2]
	var invulns: Array[float] = []
	for grab in 4:
		_drop_at(drop[0], df, -1, 40.0, 0.0, grab > 0)
		await s.frames(2)
		invulns.append(df._invuln_timer.time_left)
		if grab == 0:
			await s.frames(12)
			drop[1][0].aim = FighterIntent.Aim.DOWN
			await s.frames(3)
			s.check("down lets go of the leg", s.state_of(df) in ["Fall", "LedgeHang"] and df.ledge_side == 0 or s.state_of(df) == "Fall", "state=%s" % s.state_of(df))
			drop[1][0].aim = FighterIntent.Aim.NEUTRAL
			df.position = Vector2(stage["left"] - 34.0, stage["top"] + 40.0)
			await s.frames(8)
			s.check("the leg cannot be regrabbed right after letting go", s.state_of(df) != "LedgeHang", "state=%s" % s.state_of(df))
			continue
		await s.frames(12)
		drop[1][0].aim = FighterIntent.Aim.DOWN
		await s.frames(3)
		drop[1][0].aim = FighterIntent.Aim.NEUTRAL
	s.check("the invulnerability shrinks with every regrab", invulns[0] > invulns[1] and invulns[1] > invulns[2] and invulns[0] > 0.85, "invuln=%s" % [invulns])
	s.check("a late regrab has less than the first grab", invulns[3] < invulns[0] * 0.5, "invuln=%s" % [invulns])
	await s.despawn(drop[0])

	var reset := await _setup(s)
	var rf: Fighter = reset[2]
	_drop_at(reset[0], rf, -1, 40.0)
	await s.frames(2)
	reset[1][0].aim = FighterIntent.Aim.UP
	await s.sim(1.2)
	reset[1][0].aim = FighterIntent.Aim.NEUTRAL
	await s.frames(5)
	s.check("touching the ground resets the grab count", rf.is_on_floor() and rf.ledge_grabs == 0, "grabs=%d" % rf.ledge_grabs)
	await s.despawn(reset[0])

	# --- max hang ---
	var maxhang := await _setup(s)
	var mf: Fighter = maxhang[2]
	_drop_at(maxhang[0], mf, 1, 40.0)
	await s.sim(mf.profile.ledge_max_hang - 0.5)
	s.check("the fighter still hangs just before the maximum", s.state_of(mf) == "LedgeHang")
	await s.sim(1.0)
	s.check("hanging too long lets go", s.state_of(mf) != "LedgeHang" and mf.ledge_side == 0, "state=%s" % s.state_of(mf))
	await s.despawn(maxhang[0])

	# --- trump ---
	var trump := await _setup(s)
	var t1: Fighter = trump[2]
	var t2: Fighter = trump[3]
	_drop_at(trump[0], t1, -1, 40.0)
	await s.frames(3)
	_drop_at(trump[0], t2, -1, 40.0)
	await s.frames(3)
	s.check("a newcomer takes the leg and kicks the hanging fighter off", s.state_of(t2) == "LedgeHang" and t2.ledge_side == -1 and s.state_of(t1) == "Fall" and t1.ledge_side == 0, "t1=%s t2=%s" % [s.state_of(t1), s.state_of(t2)])
	s.check("the trumped fighter takes no damage", is_zero_approx(t1.damage_percent))
	await s.frames(10)
	s.check("the trumped fighter cannot regrab at once", s.state_of(t1) != "LedgeHang")
	await s.despawn(trump[0])

	# --- climb attack ---
	var attack := await _setup(s)
	var a1: Fighter = attack[2]
	var a2: Fighter = attack[3]
	_drop_at(attack[0], a1, -1, 60.0)
	await s.frames(2)
	var atk_stage: Dictionary = attack[0].get_state_snapshot()["stage"]
	a2.position.x = atk_stage["left"] + a1.profile.ledge_climb_land_x + 60.0
	a2.velocity = Vector2.ZERO
	await s.frames(15)
	attack[1][0].press_punch()
	await s.sim(1.0)
	s.check("punch from the leg is a climb attack that hits the waiting fighter", a2.damage_percent >= a1.profile.ledge_attack_damage - 0.1 and a1.is_on_floor(), "damage=%.1f f1 floor=%s" % [a2.damage_percent, a1.is_on_floor()])
	await s.despawn(attack[0])
	s.finish()
