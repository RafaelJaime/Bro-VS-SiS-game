extends SceneTree
## Shield meter, dizzy break and air dodge: the meter/clock/Hit units on synthetic
## ticks, then the real game.tscn driven through scripted intents. Every duration
## is counted in physics frames (ticks), so the checks also hold under a slowed
## Engine.time_scale (hit-stop).

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const PUNCH_DAMAGE := 8.0
const PUNCH_KNOCKBACK := Vector2(220.0, -120.0)

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self, 900.0)
	_clock_and_hit_units(s)
	_meter_units(s)
	await _hold_to_break(s)
	await _regen_after_release(s)
	await _blocked_hit(s)
	await _break_by_hit_and_dizzy(s)
	await _dizzy_ignores_input(s)
	await _punish_dizzy(s)
	await _unblockable_and_ignored(s)
	await _refill_on_respawn_and_reset(s)
	await _ground_only(s)
	await _air_dodge(s)
	await _air_dodge_resets(s)
	await _time_scale_independence(s)
	await _hit_stop_serialized(s)
	await _cues(s)
	await _snapshot_keys(s)
	s.finish()

func _setup(s: RefCounted, p1_x: float = 330.0, p2_x: float = 700.0) -> Array:
	var game: Node2D = s.spawn_game(p1_x, p2_x)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(90)
	return [game, controllers]

# ------------------------------------------------------------------ units

func _clock_and_hit_units(s: RefCounted) -> void:
	s.check("CombatClock: 0.5 s is 30 ticks", CombatClock.ticks(0.5) == 30, "ticks=%d" % CombatClock.ticks(0.5))
	s.check("CombatClock: 60 ticks are one second", is_equal_approx(CombatClock.seconds(60), 1.0))
	s.check("CombatClock: a negative duration is 0 ticks", CombatClock.ticks(-1.0) == 0)

	var punch := Hit.punch(null, 8.0, Vector2(220.0, -120.0))
	s.check("Hit.punch is a blockable PUNCH", punch.source == Hit.Source.PUNCH and not punch.unblockable and punch.shield_damage < 0.0)
	var ledge := Hit.punch(null, 10.0, Vector2.ONE, -1.0, Hit.Source.LEDGE)
	s.check("Hit.punch can carry the LEDGE source and stays blockable", ledge.source == Hit.Source.LEDGE and not ledge.unblockable)
	var bomb := Hit.bomb(Vector2(5.0, 6.0), 12.0, Vector2(120.0, -560.0))
	s.check("Hit.bomb is unblockable, has no attacker and keeps its position", bomb.unblockable and bomb.source == Hit.Source.BOMB and bomb.attacker == null and bomb.source_position == Vector2(5.0, 6.0))

func _meter_units(s: RefCounted) -> void:
	var profile := FighterProfile.new()
	var meter := ShieldMeter.new()
	meter.setup(profile)
	s.check("meter starts full", is_equal_approx(meter.value, profile.shield_max) and is_equal_approx(meter.ratio(), 1.0))

	var ticks := 0
	var monotonic := true
	var previous := meter.value
	var emptied := false
	while not emptied and ticks < 1000:
		emptied = meter.tick(true, false)
		ticks += 1
		monotonic = monotonic and meter.value <= previous
		previous = meter.value
	var break_ticks := CombatClock.ticks(profile.shield_break_time)
	s.check("a continuous hold empties the meter in break_time", emptied and absi(ticks - break_ticks) <= 1 and monotonic and meter.is_empty(), "ticks=%d wanted=%d" % [ticks, break_ticks])
	s.check("the meter never goes below 0", meter.value >= 0.0 and meter.tick(true, false) == false and meter.value == 0.0)

	# Release: nothing for the delay, then it refills from empty in regen_time.
	var delay := CombatClock.ticks(profile.shield_regen_delay)
	var grew_in_delay := false
	for i in delay:
		meter.tick(false, false)
		grew_in_delay = grew_in_delay or meter.value > 0.0
	s.check("no regeneration during the 30-tick delay", delay == 30 and not grew_in_delay)
	meter.tick(false, false)
	s.check("regeneration starts right after the delay", meter.value > 0.0)
	var regen_ticks := 1
	while meter.value < profile.shield_max and regen_ticks < 2000:
		meter.tick(false, false)
		regen_ticks += 1
	var wanted := CombatClock.ticks(profile.shield_regen_time)
	s.check("empty to full takes about regen_time", absi(regen_ticks - wanted) <= 2 and is_equal_approx(meter.value, profile.shield_max), "ticks=%d wanted=%d" % [regen_ticks, wanted])
	meter.tick(false, false)
	s.check("the meter never exceeds the maximum", meter.value <= profile.shield_max)

	# Suspended (dizzy): neither drains nor regenerates.
	meter.set_ratio(0.4)
	var before := meter.value
	for i in 120:
		meter.tick(true, true)
		meter.tick(false, true)
	s.check("a suspended meter holds its value", is_equal_approx(meter.value, before) and meter.held_ticks == 0)

	# Absorbing.
	meter.refill()
	s.check("absorb below the meter does not empty it", meter.absorb(30.0) == false and is_equal_approx(meter.value, 70.0))
	for i in 10:
		meter.tick(false, false)
	s.check("absorb restarts the regeneration delay", is_equal_approx(meter.value, 70.0))
	s.check("absorb returns true when it empties the meter", meter.absorb(500.0) == true and meter.value == 0.0)
	meter.refill()
	s.check("refill gives the full meter", is_equal_approx(meter.value, profile.shield_max))

	# Data driven: a shorter break time changes the break tick count with no code change.
	var quick := FighterProfile.new()
	quick.shield_break_time = 2.0
	var quick_meter := ShieldMeter.new()
	quick_meter.setup(quick)
	var quick_ticks := 0
	while not quick_meter.tick(true, false) and quick_ticks < 1000:
		quick_ticks += 1
	s.check("the break time is data (2 s edit breaks in about 120 ticks)", absi(quick_ticks + 1 - 120) <= 1, "ticks=%d" % (quick_ticks + 1))

# ------------------------------------------------------------ integration

func _hold_to_break(s: RefCounted) -> void:
	var setup := await _setup(s)
	var game: Node2D = setup[0]
	var fighter: Fighter = game.get_node("Fighter1")
	var ctrl = setup[1][0]
	var causes: Array = []
	fighter.shield_broken.connect(func(cause: Hit) -> void: causes.append(cause))
	ctrl.block_held_level = true
	ctrl.press_block()
	await s.frames(2)
	s.check("block on the floor enters Protect", s.state_of(fighter) == "Protect", "state=%s" % s.state_of(fighter))
	var ticks := 0
	var monotonic := true
	var previous := fighter.shield.value
	while s.state_of(fighter) == "Protect" and ticks < 600:
		await s.frames(1)
		ticks += 1
		monotonic = monotonic and fighter.shield.value <= previous
		previous = fighter.shield.value
	s.check("holding block breaks the shield in about 5 s (300 ticks)", s.state_of(fighter) == "Dizzy" and absi(ticks - 300) <= 30, "ticks=%d state=%s" % [ticks, s.state_of(fighter)])
	s.check("the meter only drains while held", monotonic)
	s.check("a hold break reports no causing hit", causes.size() == 1 and causes[0] == null, "emits=%d" % causes.size())
	await s.despawn(game)

func _regen_after_release(s: RefCounted) -> void:
	var setup := await _setup(s)
	var game: Node2D = setup[0]
	var fighter: Fighter = game.get_node("Fighter1")
	var ctrl = setup[1][0]
	ctrl.block_held_level = true
	ctrl.press_block()
	await s.frames(60)
	var held_value := fighter.shield.value
	ctrl.block_held_level = false
	await s.frames(3)
	# Intentional change (shield drop lag): letting go enters ShieldDrop, and the
	# fighter is neutral again once the lag is over.
	s.check("released: in the drop lag", s.state_of(fighter) == "ShieldDrop", "state=%s" % s.state_of(fighter))
	var at_release := fighter.shield.value
	await s.frames(25)
	s.check("released: back in a neutral state after the lag", s.state_of(fighter) == "Idle", "state=%s" % s.state_of(fighter))
	s.check("no regeneration inside the 30-tick delay", is_equal_approx(fighter.shield.value, at_release) and at_release < 100.0, "value=%.2f at_release=%.2f held=%.2f" % [fighter.shield.value, at_release, held_value])
	await s.frames(120)
	s.check("after the delay the meter regenerates but never exceeds the maximum", fighter.shield.value > at_release and fighter.shield.value <= fighter.shield.max_value, "value=%.2f" % fighter.shield.value)
	await s.despawn(game)

func _raise_shield(s: RefCounted, ctrl) -> void:
	ctrl.block_held_level = true
	ctrl.press_block()
	await s.frames(3)

func _blocked_hit(s: RefCounted) -> void:
	var setup := await _setup(s, 400.0, 470.0)
	var game: Node2D = setup[0]
	var attacker: Fighter = game.get_node("Fighter1")
	var target: Fighter = game.get_node("Fighter2")
	await _raise_shield(s, setup[1][1])
	s.check("the target is shielding", s.state_of(target) == "Protect")
	var meter_before := target.shield.value
	var outcome := Combat.resolve(Hit.punch(attacker, PUNCH_DAMAGE, PUNCH_KNOCKBACK), target)
	var expected_drain := PUNCH_DAMAGE * target.profile.shield_damage_scale
	s.check("a blocked punch is BLOCKED", outcome == Combat.Outcome.BLOCKED, "outcome=%d" % outcome)
	s.check("the meter drops by damage times the shield-damage scale", is_equal_approx(meter_before - target.shield.value, expected_drain), "drop=%.2f wanted=%.2f" % [meter_before - target.shield.value, expected_drain])
	s.check("chip damage is more than 0 and less than the punch damage", target.damage_percent > 0.0 and target.damage_percent < PUNCH_DAMAGE, "damage=%.2f" % target.damage_percent)
	s.check("a blocked hit never starts hitstun", s.state_of(target) == "Protect")
	var open_knockback := PUNCH_KNOCKBACK.length() * target.get_knockback_scale()
	var blocked_speed: float = target.state_machine.velocity.length()
	s.check("a blocked hit slides the fighter back without lifting it", target.state_machine.velocity.y == 0.0 and target.state_machine.velocity.x > 0.0, "v=%s" % target.state_machine.velocity)
	s.check("blocked knockback is lower than the unshielded one", blocked_speed < open_knockback, "blocked=%.1f open=%.1f" % [blocked_speed, open_knockback])
	await s.frames(2)
	s.check("the target is still shielding afterwards", s.state_of(target) == "Protect")

	# Higher damage drains more.
	var light_target := target
	light_target.shield.refill()
	var before_light := light_target.shield.value
	Combat.resolve(Hit.punch(attacker, 8.0, PUNCH_KNOCKBACK), light_target)
	var light_drop := before_light - light_target.shield.value
	light_target.shield.refill()
	var before_heavy := light_target.shield.value
	Combat.resolve(Hit.punch(attacker, 16.0, PUNCH_KNOCKBACK), light_target)
	var heavy_drop := before_heavy - light_target.shield.value
	s.check("more damage drains more meter", heavy_drop > light_drop, "light=%.1f heavy=%.1f" % [light_drop, heavy_drop])

	# A shield-damage override replaces the derived drain.
	light_target.shield.refill()
	var before_override := light_target.shield.value
	Combat.resolve(Hit.punch(attacker, 8.0, PUNCH_KNOCKBACK, 40.0), light_target)
	s.check("an explicit shield_damage replaces the derived drain", is_equal_approx(before_override - light_target.shield.value, 40.0), "drop=%.1f" % (before_override - light_target.shield.value))
	await s.despawn(game)

func _break_by_hit_and_dizzy(s: RefCounted) -> void:
	var setup := await _setup(s, 400.0, 470.0)
	var game: Node2D = setup[0]
	var attacker: Fighter = game.get_node("Fighter1")
	var target: Fighter = game.get_node("Fighter2")
	var causes: Array = []
	target.shield_broken.connect(func(cause: Hit) -> void: causes.append(cause))
	await _raise_shield(s, setup[1][1])
	target.shield.absorb(target.shield.value - 5.0)
	var hit := Hit.punch(attacker, PUNCH_DAMAGE, PUNCH_KNOCKBACK)
	var outcome := Combat.resolve(hit, target)
	s.check("a hit that empties the shield is BROKE", outcome == Combat.Outcome.BROKE, "outcome=%d" % outcome)
	s.check("the meter is 0 and the target is dizzy", target.shield.value == 0.0 and s.state_of(target) == "Dizzy" and target.is_dizzy())
	s.check("the breaking hit is reported", causes.size() == 1 and causes[0] == hit)
	s.check("dizzy lasts about 2 s", absf(target.dizzy_seconds_left() - 2.0) < 0.1, "left=%.2f" % target.dizzy_seconds_left())

	var frames_dizzy := 0
	while s.state_of(target) == "Dizzy" and frames_dizzy < 400:
		await s.frames(1)
		frames_dizzy += 1
	s.check("dizzy ends after 120 ticks", absi(frames_dizzy - 120) <= 2, "frames=%d" % frames_dizzy)
	s.check("the fighter is controllable again", s.state_of(target) in ["Idle", "Fall"], "state=%s" % s.state_of(target))
	s.check("the meter wakes up at 50%", absf(target.shield.ratio() - 0.5) < 0.01, "ratio=%.3f" % target.shield.ratio())
	await s.despawn(game)

func _dizzy_ignores_input(s: RefCounted) -> void:
	var setup := await _setup(s, 400.0, 700.0)
	var game: Node2D = setup[0]
	var fighter: Fighter = game.get_node("Fighter1")
	var ctrl = setup[1][0]
	fighter.break_shield(null)
	await s.frames(2)
	s.check("break_shield enters Dizzy", s.state_of(fighter) == "Dizzy")
	await s.wait_grounded(fighter)
	var start_x := fighter.position.x
	var punch_cooldown: float = fighter.get_state_snapshot()["cooldowns"]["punch"]
	ctrl.move_x = 1.0
	for i in 20:
		ctrl.press_jump()
		ctrl.press_punch()
		ctrl.press_block()
		ctrl.press_throw()
		ctrl.press_dash()
		await s.frames(1)
	s.check("dizzy ignores move, jump, attack, throw, dash and block", s.state_of(fighter) == "Dizzy" and absf(fighter.position.x - start_x) < 2.0, "state=%s dx=%.1f" % [s.state_of(fighter), fighter.position.x - start_x])
	s.check("dizzy never starts a punch", fighter.get_state_snapshot()["cooldowns"]["punch"] == punch_cooldown)
	ctrl.move_x = 0.0
	await s.despawn(game)

func _punish_dizzy(s: RefCounted) -> void:
	var setup := await _setup(s, 400.0, 470.0)
	var game: Node2D = setup[0]
	var attacker: Fighter = game.get_node("Fighter1")
	var target: Fighter = game.get_node("Fighter2")
	target.break_shield(null)
	await s.frames(3)
	var outcome := Combat.resolve(Hit.punch(attacker, PUNCH_DAMAGE, PUNCH_KNOCKBACK), target)
	s.check("a hit on a dizzy fighter is FULL", outcome == Combat.Outcome.FULL, "outcome=%d" % outcome)
	s.check("the punish takes the full damage", is_equal_approx(target.damage_percent, PUNCH_DAMAGE), "damage=%.1f" % target.damage_percent)
	s.check("the punish ends dizzy through Hurt", s.state_of(target) == "Hurt")
	var wanted := PUNCH_KNOCKBACK.length() * target.get_knockback_scale()
	s.check("the punish applies the full knockback", is_equal_approx(target.state_machine.velocity.length(), wanted), "speed=%.1f wanted=%.1f" % [target.state_machine.velocity.length(), wanted])
	s.check("leaving dizzy through a hit still wakes the meter at 50%", absf(target.shield.ratio() - 0.5) < 0.01, "ratio=%.3f" % target.shield.ratio())
	await s.despawn(game)

func _unblockable_and_ignored(s: RefCounted) -> void:
	var setup := await _setup(s, 400.0, 470.0)
	var game: Node2D = setup[0]
	var attacker: Fighter = game.get_node("Fighter1")
	var target: Fighter = game.get_node("Fighter2")
	await _raise_shield(s, setup[1][1])
	var hit := Hit.punch(attacker, PUNCH_DAMAGE, PUNCH_KNOCKBACK)
	hit.unblockable = true
	var meter_before := target.shield.value
	var outcome := Combat.resolve(hit, target)
	s.check("an unblockable hit overrides the shield (FULL)", outcome == Combat.Outcome.FULL and s.state_of(target) == "Hurt", "outcome=%d state=%s" % [outcome, s.state_of(target)])
	s.check("an unblockable hit applies the full damage and leaves the meter alone", is_equal_approx(target.damage_percent, PUNCH_DAMAGE) and is_equal_approx(target.shield.value, meter_before), "damage=%.1f meter=%.1f" % [target.damage_percent, target.shield.value])
	await s.despawn(game)

	var invuln_setup := await _setup(s, 400.0, 470.0)
	var invuln_game: Node2D = invuln_setup[0]
	var invuln_attacker: Fighter = invuln_game.get_node("Fighter1")
	var invuln_target: Fighter = invuln_game.get_node("Fighter2")
	invuln_target.grant_invulnerability(2.0)
	var ignored := Combat.resolve(Hit.punch(invuln_attacker, PUNCH_DAMAGE, PUNCH_KNOCKBACK), invuln_target)
	s.check("an invulnerable target gets IGNORED", ignored == Combat.Outcome.IGNORED and invuln_target.damage_percent == 0.0 and s.state_of(invuln_target) != "Hurt")
	var bomb_hit := Hit.bomb(invuln_target.global_position, 12.0, Vector2(120.0, -560.0))
	s.check("invulnerability also stops a bomb", Combat.resolve(bomb_hit, invuln_target) == Combat.Outcome.IGNORED)
	await s.despawn(invuln_game)

func _refill_on_respawn_and_reset(s: RefCounted) -> void:
	var setup := await _setup(s)
	var game: Node2D = setup[0]
	var fighter: Fighter = game.get_node("Fighter1")
	fighter.shield.absorb(90.0)
	s.check("the meter is depleted", fighter.shield.value < 20.0)
	fighter._lose_stock()
	s.check("respawn refills the meter", is_equal_approx(fighter.shield.ratio(), 1.0), "ratio=%.2f" % fighter.shield.ratio())

	fighter.break_shield(null)
	await s.frames(2)
	s.check("the fighter is dizzy before the reset", s.state_of(fighter) == "Dizzy")
	fighter.reset_player()
	s.check("reset_player refills the meter even from Dizzy", is_equal_approx(fighter.shield.ratio(), 1.0) and s.state_of(fighter) == "Fall", "ratio=%.2f state=%s" % [fighter.shield.ratio(), s.state_of(fighter)])

	fighter.break_shield(null)
	await s.frames(2)
	fighter.prepare_sudden_death(300.0)
	s.check("sudden death refills the meter even from Dizzy", is_equal_approx(fighter.shield.ratio(), 1.0) and s.state_of(fighter) == "Fall")
	await s.despawn(game)

func _ground_only(s: RefCounted) -> void:
	var setup := await _setup(s, 330.0, 700.0)
	var game: Node2D = setup[0]
	var fighter: Fighter = game.get_node("Fighter1")
	var ctrl = setup[1][0]
	fighter.position.y -= 300.0
	fighter.velocity = Vector2.ZERO
	await s.frames(3)
	s.check("the fighter is airborne", not fighter.is_on_floor())
	s.check("Protect cannot be entered in the air", not fighter.state_machine.state_map["Protect"].can_enter())
	var before := fighter.shield.value
	var saw_protect := false
	ctrl.block_held_level = true
	for i in 30:
		await s.frames(1)
		saw_protect = saw_protect or s.state_of(fighter) == "Protect"
	ctrl.block_held_level = false
	s.check("holding block in the air never raises a shield or drains the meter", not saw_protect and is_equal_approx(fighter.shield.value, before), "meter=%.2f" % fighter.shield.value)
	await s.despawn(game)

func _airborne(s: RefCounted, fighter: Fighter, height: float) -> void:
	fighter.position.y -= height
	fighter.velocity = Vector2.ZERO
	fighter.state_machine.velocity = Vector2.ZERO
	await s.frames(3)

func _air_dodge(s: RefCounted) -> void:
	var setup := await _setup(s, 330.0, 700.0)
	var game: Node2D = setup[0]
	var fighter: Fighter = game.get_node("Fighter1")
	var ctrl = setup[1][0]
	await _airborne(s, fighter, 600.0)
	var meter_before := fighter.shield.value
	s.check("the dodge is available", fighter.air_dodge_available)
	ctrl.press_block()
	await s.frames(1)
	s.check("block in the air starts an AirDodge", s.state_of(fighter) == "AirDodge" and not fighter.is_on_floor(), "state=%s" % s.state_of(fighter))
	var intangible_ticks := 0
	var cooldown_set := fighter.air_dodge_cooldown_left > 0
	for i in 40:
		if fighter.is_intangible():
			intangible_ticks += 1
		await s.frames(1)
	s.check("the intangible window is 18 ticks (0.3 s)", absi(intangible_ticks - 18) <= 1, "ticks=%d" % intangible_ticks)
	s.check("the dodge costs no shield meter", is_equal_approx(fighter.shield.value, meter_before))
	s.check("the dodge starts a cooldown", cooldown_set)
	s.check("the fighter is back in an air state after the end lag", s.state_of(fighter) == "Fall" and not fighter.is_on_floor(), "state=%s" % s.state_of(fighter))
	s.check("the allowance is spent", not fighter.air_dodge_available)
	fighter.air_dodge_cooldown_left = 0
	ctrl.press_block()
	await s.frames(2)
	s.check("no second dodge in the same airtime", s.state_of(fighter) != "AirDodge", "state=%s" % s.state_of(fighter))
	await s.despawn(game)

	# The window really protects: a punch during it does nothing, after it does.
	var hit_setup := await _setup(s, 330.0, 360.0)
	var hit_game: Node2D = hit_setup[0]
	var dodger: Fighter = hit_game.get_node("Fighter1")
	var striker: Fighter = hit_game.get_node("Fighter2")
	await _airborne(s, dodger, 600.0)
	hit_setup[1][0].press_block()
	await s.frames(3)
	var outcome := Combat.resolve(Hit.punch(striker, PUNCH_DAMAGE, PUNCH_KNOCKBACK), dodger)
	s.check("a punch during the dodge is IGNORED", outcome == Combat.Outcome.IGNORED and dodger.damage_percent == 0.0 and s.state_of(dodger) == "AirDodge")
	var thrown := Hit.punch(striker, 13.0, Vector2(290.0, -150.0), 35.0, Hit.Source.FOOD)
	s.check("thrown food during the dodge is IGNORED too", Combat.resolve(thrown, dodger) == Combat.Outcome.IGNORED)
	await s.frames(30)
	var late := Combat.resolve(Hit.punch(striker, PUNCH_DAMAGE, PUNCH_KNOCKBACK), dodger)
	s.check("after the window a hit lands", late == Combat.Outcome.FULL and dodger.damage_percent > 0.0, "outcome=%d" % late)
	await s.despawn(hit_game)

func _air_dodge_resets(s: RefCounted) -> void:
	# Landing refills it.
	var setup := await _setup(s, 330.0, 700.0)
	var game: Node2D = setup[0]
	var fighter: Fighter = game.get_node("Fighter1")
	var ctrl = setup[1][0]
	await _airborne(s, fighter, 300.0)
	ctrl.press_block()
	await s.frames(2)
	s.check("the dodge was used", s.state_of(fighter) == "AirDodge" and not fighter.air_dodge_available)
	await s.wait_grounded(fighter, 400)
	await s.frames(2)
	s.check("landing refills the air dodge", fighter.air_dodge_available)
	await s.despawn(game)

	# Being hit refills it.
	var hit_setup := await _setup(s, 330.0, 360.0)
	var hit_game: Node2D = hit_setup[0]
	var dodger: Fighter = hit_game.get_node("Fighter1")
	var striker: Fighter = hit_game.get_node("Fighter2")
	await _airborne(s, dodger, 600.0)
	hit_setup[1][0].press_block()
	await s.frames(40)
	s.check("the dodge is spent and the fighter is still airborne", not dodger.air_dodge_available and not dodger.is_on_floor())
	Combat.resolve(Hit.punch(striker, PUNCH_DAMAGE, PUNCH_KNOCKBACK), dodger)
	s.check("being hit refills the air dodge", dodger.air_dodge_available)
	await s.despawn(hit_game)

	# A ledge grab refills it.
	var ledge_setup := await _setup(s, 330.0, 700.0)
	var ledge_game: Node2D = ledge_setup[0]
	var hanger: Fighter = ledge_game.get_node("Fighter1")
	hanger.air_dodge_available = false
	var ledge: Dictionary = ledge_game.get_ledges()[0]
	hanger._grab_ledge(ledge["side"], Vector2(ledge["x"] + ledge["side"] * hanger.profile.ledge_hang_offset, ledge["top"] + hanger.profile.ledge_hang_depth))
	await s.frames(2)
	s.check("grabbing the ledge refills the air dodge", s.state_of(hanger) == "LedgeHang" and hanger.air_dodge_available, "state=%s" % s.state_of(hanger))
	await s.despawn(ledge_game)

func _measure_dizzy_ticks(s: RefCounted, time_scale: float) -> int:
	var setup := await _setup(s, 400.0, 700.0)
	var game: Node2D = setup[0]
	var fighter: Fighter = game.get_node("Fighter1")
	fighter.break_shield(null)
	await s.frames(2)
	Engine.time_scale = time_scale
	var start := Engine.get_physics_frames()
	var guard := 0
	while s.state_of(fighter) == "Dizzy" and guard < 600:
		await s.frames(1)
		guard += 1
	var ticks := Engine.get_physics_frames() - start
	Engine.time_scale = 1.0
	await s.despawn(game)
	return ticks

func _measure_dodge_ticks(s: RefCounted, time_scale: float) -> int:
	var setup := await _setup(s, 330.0, 700.0)
	var game: Node2D = setup[0]
	var fighter: Fighter = game.get_node("Fighter1")
	await _airborne(s, fighter, 600.0)
	setup[1][0].press_block()
	await s.frames(1)
	Engine.time_scale = time_scale
	var ticks := 0
	var guard := 0
	while s.state_of(fighter) == "AirDodge" and guard < 200:
		if fighter.is_intangible():
			ticks += 1
		await s.frames(1)
		guard += 1
	Engine.time_scale = 1.0
	await s.despawn(game)
	return ticks

func _time_scale_independence(s: RefCounted) -> void:
	var normal_dizzy: int = await _measure_dizzy_ticks(s, 1.0)
	var slowed_dizzy: int = await _measure_dizzy_ticks(s, 0.3)
	s.check("dizzy lasts the same ticks at time scale 0.3 and 1.0", normal_dizzy == slowed_dizzy and normal_dizzy >= 118, "normal=%d slowed=%d" % [normal_dizzy, slowed_dizzy])
	var normal_dodge: int = await _measure_dodge_ticks(s, 1.0)
	var slowed_dodge: int = await _measure_dodge_ticks(s, 0.3)
	s.check("the dodge window is the same ticks at time scale 0.3 and 1.0", normal_dodge == slowed_dodge and normal_dodge >= 17, "normal=%d slowed=%d" % [normal_dodge, slowed_dodge])

	# The regeneration delay is counted in ticks too.
	var setup := await _setup(s)
	var game: Node2D = setup[0]
	var fighter: Fighter = game.get_node("Fighter1")
	fighter.shield.absorb(50.0)
	var value := fighter.shield.value
	Engine.time_scale = 0.3
	await s.frames(28)
	var still_waiting: bool = is_equal_approx(fighter.shield.value, value)
	await s.frames(10)
	Engine.time_scale = 1.0
	s.check("the regeneration delay is 30 ticks at time scale 0.3", still_waiting and fighter.shield.value > value, "value=%.2f start=%.2f" % [fighter.shield.value, value])
	await s.despawn(game)

func _hit_stop_serialized(s: RefCounted) -> void:
	var setup := await _setup(s, 400.0, 470.0)
	var game: Node2D = setup[0]
	var attacker: Fighter = game.get_node("Fighter1")
	var target: Fighter = game.get_node("Fighter2")
	await _raise_shield(s, setup[1][1])
	target.shield.absorb(target.shield.value - 5.0)
	Combat.resolve(Hit.punch(attacker, PUNCH_DAMAGE, PUNCH_KNOCKBACK), target)
	Combat.resolve(Hit.punch(attacker, PUNCH_DAMAGE, PUNCH_KNOCKBACK), target)
	s.check("a shield break triggers a hit-stop", Engine.time_scale < 1.0, "scale=%.2f" % Engine.time_scale)
	await s.real_wait(0.6)
	s.check("overlapping break and punch hit-stops end at exactly 1.0", is_equal_approx(Engine.time_scale, 1.0), "scale=%.2f" % Engine.time_scale)
	await s.despawn(game)

# The bubble and the dizzy stars are only on the fighter while their state lasts,
# and neither touches the sprite's visibility (Fighter._apply_visibility owns it).
func _cues(s: RefCounted) -> void:
	var setup := await _setup(s, 330.0, 700.0)
	var game: Node2D = setup[0]
	var fighter: Fighter = game.get_node("Fighter1")
	var ctrl = setup[1][0]
	var bubble: ShieldBubble = fighter.get_node("ShieldBubble")
	var stars: DizzyStars = fighter.get_node("DizzyStars")
	s.check("no bubble and no stars while idle", not bubble.visible and not stars.visible)
	ctrl.block_held_level = true
	ctrl.press_block()
	await s.frames(4)
	# The raise cost (shield_raise_cost) takes a few meter points, so the bubble is
	# a hair under its full size.
	s.check("the bubble shows while shielding, near its full size", bubble.visible and absf(bubble.scale.x - bubble.scale_full) < 0.03, "scale=%.3f" % bubble.scale.x)
	fighter.shield.set_ratio(0.5)
	await s.frames(2)
	var half := lerpf(bubble.scale_empty, bubble.scale_full, fighter.shield.ratio())
	s.check("the bubble shrinks with the meter", bubble.visible and absf(bubble.scale.x - half) < 0.01 and bubble.scale.x < bubble.scale_full, "scale=%.3f half=%.3f" % [bubble.scale.x, half])
	s.check("the bubble never hides the fighter sprite", fighter.animated_sprite_2d.visible)
	fighter.shield.set_ratio(0.18)
	await s.frames(2)
	ctrl.block_held_level = false
	await s.frames(3)
	# Intentional change (shield drop lag): the bubble shrinks away during the lag
	# and is hidden once it is over (the shrink itself is checked in shield_look).
	s.check("the bubble is still shrinking in the drop lag", bubble.visible and fighter.shield_drop_progress() >= 0.0)
	await s.frames(12)
	s.check("the bubble hides when the shield drops", not bubble.visible)

	fighter.break_shield(null)
	await s.frames(6)
	s.check("the stars show while dizzy", stars.visible and fighter.is_dizzy())
	var wobbled := false
	for i in 20:
		wobbled = wobbled or fighter.animated_sprite_2d.offset.x != 0.0
		await s.frames(1)
	s.check("the sprite wobbles while dizzy and stays visible", wobbled and fighter.animated_sprite_2d.visible)
	var guard := 0
	while fighter.is_dizzy() and guard < 400:
		await s.frames(1)
		guard += 1
	await s.frames(3)
	s.check("the stars and the wobble end with the dizzy", not stars.visible and fighter.animated_sprite_2d.offset == Vector2.ZERO)
	await s.despawn(game)

# The fighter snapshot carries the shield state, additively and read-only.
func _snapshot_keys(s: RefCounted) -> void:
	var setup := await _setup(s, 400.0, 700.0)
	var game: Node2D = setup[0]
	var fighter: Fighter = game.get_node("Fighter1")
	var snap: Dictionary = fighter.get_state_snapshot()
	var new_keys := ["shield", "shield_max", "dizzy", "dizzy_left", "air_dodge_available", "intangible"]
	s.check("the fighter snapshot has every shield key", new_keys.all(func(key): return snap.has(key)), "keys=%s" % [snap.keys()])
	s.check("a healthy fighter: full meter, not dizzy, 0 s left, dodge available, tangible", is_equal_approx(snap["shield"], snap["shield_max"]) and is_equal_approx(snap["shield_max"], 100.0) and snap["dizzy"] == false and snap["dizzy_left"] == 0.0 and snap["air_dodge_available"] == true and snap["intangible"] == false, "snap=%s" % [snap])

	# Every key the frozen schema 2 reads is still there, with its type.
	var v2_ok := true
	var v2_missing: Array = []
	for key in BvsSchemaV2.FIGHTER_KEYS:
		if not snap.has(key):
			v2_ok = false
			v2_missing.append(key)
	for key in BvsSchemaV2.COOLDOWN_KEYS:
		if not (snap["cooldowns"] as Dictionary).has(key):
			v2_ok = false
			v2_missing.append(key)
	s.check("every key schema 2 reads is still present on the fighter", v2_ok, "missing=%s" % [v2_missing])
	var game_snap: Dictionary = (game as Game).get_state_snapshot()
	var game_missing: Array = []
	for key in BvsSchemaV2.GAME_KEYS:
		if not game_snap.has(key):
			game_missing.append(key)
	s.check("every Game key schema 2 reads is still present", game_missing.is_empty(), "missing=%s" % [game_missing])
	s.check("the existing values are untouched (position, damage, stocks, state)", snap["position"] == fighter.position and snap["damage_percent"] == fighter.damage_percent and snap["stocks"] == fighter.stocks and snap["state"] == StringName(s.state_of(fighter)) and snap["on_floor"] == fighter.is_on_floor())

	# A dizzy fighter with an empty meter.
	fighter.break_shield(null)
	await s.frames(3)
	var dizzy: Dictionary = fighter.get_state_snapshot()
	s.check("a dizzy fighter reports dizzy, time left and an empty meter", dizzy["dizzy"] == true and dizzy["dizzy_left"] > 1.5 and dizzy["dizzy_left"] <= 2.0 and dizzy["shield"] == 0.0, "snap=%s" % [dizzy])
	s.check("taking the snapshot twice with no frame between gives the same result", fighter.get_state_snapshot() == fighter.get_state_snapshot())
	await _leave_game(s, game)

	# An air dodge shows as intangible.
	var air_setup := await _setup(s, 330.0, 700.0)
	var air_game: Node2D = air_setup[0]
	var dodger: Fighter = air_game.get_node("Fighter1")
	await _airborne(s, dodger, 600.0)
	air_setup[1][0].press_block()
	await s.frames(3)
	var dodging: Dictionary = dodger.get_state_snapshot()
	s.check("an air-dodging fighter reports intangible and a spent dodge", dodging["intangible"] == true and dodging["air_dodge_available"] == false and dodging["state"] == &"AirDodge", "snap=%s" % [dodging])
	await _leave_game(s, air_game)

func _leave_game(s: RefCounted, game: Node) -> void:
	Combat.cancel_hit_stop()
	await s.despawn(game)
