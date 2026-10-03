extends SceneTree
## Shield spam: leaving the shield costs a drop lag (a one-tick tap still pays it),
## the lag locks every action but is a normal hit target, the CPU respects it and
## an input script that alternates punch and block raises far fewer shields than
## before. Everything is counted in physics ticks, so the checks hold at any frame
## rate.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
## Shield raises per second of the alternating script measured before the drop lag
## existed (punch/block every 4 ticks, 10 s): the reference of the "far fewer" check.
const RAISES_PER_SECOND_BEFORE := 4.9

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self, 400.0)
	_meter_units(s)
	await _tap_pays_the_lag(s)
	await _lag_locks_everything(s)
	await _hit_during_the_lag(s)
	await _hold_and_jump_out(s)
	await _alternating_inputs(s)
	await _cpu_respects_the_lag(s)
	s.finish()

func _setup(s: RefCounted, p1_x: float = 330.0, p2_x: float = 900.0) -> Array:
	var game: Node2D = s.spawn_game(p1_x, p2_x)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(90)
	return [game, controllers]

func _meter_units(s: RefCounted) -> void:
	var profile := FighterProfile.new()
	s.check("drop lag defaults to 11 ticks and the minimum hold to 4", CombatClock.ticks(profile.shield_drop_lag) == 11 and CombatClock.ticks(profile.shield_min_hold) == 4, "lag=%d hold=%d" % [CombatClock.ticks(profile.shield_drop_lag), CombatClock.ticks(profile.shield_min_hold)])
	var meter := ShieldMeter.new()
	meter.setup(profile)
	meter.pay_raise(profile.shield_raise_cost)
	s.check("a raise costs the configured meter", is_equal_approx(meter.value, profile.shield_max - profile.shield_raise_cost), "value=%.1f" % meter.value)
	meter.set_ratio(0.005)
	meter.pay_raise(50.0)
	s.check("a raise never empties the meter by itself", not meter.is_empty(), "value=%.3f" % meter.value)

func _tap_pays_the_lag(s: RefCounted) -> void:
	var setup := await _setup(s)
	var game: Node2D = setup[0]
	var f: Fighter = game.get_node("Fighter1")
	var ctrl = setup[1][0]
	var min_hold := CombatClock.ticks(f.profile.shield_min_hold)
	var lag := CombatClock.ticks(f.profile.shield_drop_lag)

	ctrl.press_block()
	await s.frames(1)
	s.check("a one-tick tap raises the shield", s.state_of(f) == "Protect" and f.shield_raises == 1, "state=%s raises=%d" % [s.state_of(f), f.shield_raises])
	s.check("raising the shield spends the raise cost", f.shield.value < f.shield.max_value - f.profile.shield_raise_cost + 0.5, "value=%.2f" % f.shield.value)

	# Mash punch every tick: the first punch only starts when the lock is over.
	var ticks := 0
	var saw_drop := false
	var punched := false
	while ticks < 60 and not punched:
		ctrl.press_punch()
		await s.frames(1)
		ticks += 1
		saw_drop = saw_drop or s.state_of(f) == "ShieldDrop"
		punched = s.state_of(f) == "Punch"
	var wanted := min_hold + lag
	s.check("the tap held the shield for the minimum and then dropped it", saw_drop)
	s.check("a tapped shield locks the fighter for min hold + drop lag (%d ticks)" % wanted, punched and ticks >= wanted and ticks <= wanted + 3, "ticks=%d" % ticks)
	await s.despawn(game)

func _lag_locks_everything(s: RefCounted) -> void:
	var setup := await _setup(s)
	var game: Node2D = setup[0]
	var f: Fighter = game.get_node("Fighter1")
	var ctrl = setup[1][0]
	var lag := CombatClock.ticks(f.profile.shield_drop_lag)

	ctrl.block_held_level = true
	ctrl.press_block()
	await s.frames(10)
	ctrl.block_held_level = false
	var guard := 0
	while s.state_of(f) != "ShieldDrop" and guard < 30:
		await s.frames(1)
		guard += 1
	s.check("letting go of a held shield enters the drop lag", s.state_of(f) == "ShieldDrop", "state=%s" % s.state_of(f))
	var raises := f.shield_raises
	var states := {}
	var max_speed := 0.0
	var start_x := f.position.x
	ctrl.move_x = 1.0
	for i in lag - 2:
		ctrl.press_block()
		ctrl.press_punch()
		ctrl.press_throw()
		ctrl.press_dash()
		await s.frames(1)
		states[s.state_of(f)] = true
		max_speed = maxf(max_speed, absf(f.velocity.x))
	s.check("attack, shield, throw, dash and run are all ignored during the lag", states.keys() == ["ShieldDrop"] and f.shield_raises == raises, "states=%s raises=%d->%d" % [states.keys(), raises, f.shield_raises])
	s.check("the fighter does not move during the lag", max_speed < 1.0 and absf(f.position.x - start_x) < 1.0, "speed=%.1f dx=%.1f" % [max_speed, f.position.x - start_x])
	ctrl.move_x = 0.0
	await s.frames(4)
	s.check("the lag ends in Idle and the shield cannot be re-raised by a held key alone", s.state_of(f) == "Idle", "state=%s" % s.state_of(f))
	ctrl.press_block()
	await s.frames(2)
	s.check("a fresh press after the lag raises the shield again", s.state_of(f) == "Protect", "state=%s" % s.state_of(f))
	await s.despawn(game)

func _hit_during_the_lag(s: RefCounted) -> void:
	var setup := await _setup(s, 330.0, 400.0)
	var game: Node2D = setup[0]
	var f1: Fighter = game.get_node("Fighter1")
	var f2: Fighter = game.get_node("Fighter2")
	var ctrl = setup[1][0]
	ctrl.press_block()
	await s.frames(8)
	var guard := 0
	while s.state_of(f1) != "ShieldDrop" and guard < 30:
		await s.frames(1)
		guard += 1
	var before := f1.damage_percent
	var outcome := Combat.resolve(Hit.punch(f2, 8.0, Vector2(220.0, -120.0)), f1)
	s.check("a hit during the drop lag is a normal full hit", outcome == Combat.Outcome.FULL and f1.damage_percent > before and s.state_of(f1) == "Hurt", "outcome=%d damage=%.1f state=%s" % [outcome, f1.damage_percent - before, s.state_of(f1)])
	await s.despawn(game)

func _hold_and_jump_out(s: RefCounted) -> void:
	var setup := await _setup(s)
	var game: Node2D = setup[0]
	var f: Fighter = game.get_node("Fighter1")
	var ctrl = setup[1][0]
	ctrl.block_held_level = true
	ctrl.press_block()
	await s.frames(30)
	s.check("a held shield stays up (the min hold changes nothing for a hold)", s.state_of(f) == "Protect", "state=%s" % s.state_of(f))
	ctrl.jump_held_level = true
	ctrl.press_jump()
	await s.frames(2)
	s.check("jumping out of the shield is allowed and skips the drop lag", s.state_of(f) == "Jump" and f.velocity.y < -300.0, "state=%s vy=%.0f" % [s.state_of(f), f.velocity.y])
	ctrl.block_held_level = false
	ctrl.jump_held_level = false
	await s.despawn(game)

# Punch and block alternate every `period` ticks for 10 s (the user's "pega, escudo,
# pega, escudo"). Returns the shield raises per second.
func _raises_per_second(s: RefCounted, period: int) -> float:
	var setup := await _setup(s)
	var game: Node2D = setup[0]
	var f: Fighter = game.get_node("Fighter1")
	var ctrl = setup[1][0]
	var start := f.shield_raises
	for i in 600:
		if i % period == 0:
			if (i / period) % 2 == 0:
				ctrl.press_punch()
			else:
				ctrl.press_block()
		await s.frames(1)
	var rate := float(f.shield_raises - start) / 10.0
	await s.despawn(game)
	return rate

func _alternating_inputs(s: RefCounted) -> void:
	var rate4 := await _raises_per_second(s, 4)
	var rate2 := await _raises_per_second(s, 2)
	var rate8 := await _raises_per_second(s, 8)
	print("METRIC shield raises/s with alternating punch/block: every 2 ticks=%.2f, every 4 ticks=%.2f (before %.2f), every 8 ticks=%.2f" % [rate2, rate4, RAISES_PER_SECOND_BEFORE, rate8])
	s.check("alternating punch/block every 4 ticks raises far fewer shields than before", rate4 <= RAISES_PER_SECOND_BEFORE * 0.65, "%.2f/s vs %.2f/s before" % [rate4, RAISES_PER_SECOND_BEFORE])
	s.check("the faster the alternation, the same lock: every 2 ticks is no worse", rate2 <= rate4 + 0.5, "%.2f/s" % rate2)

# Two shield-happy CPUs fight for 40 s: no fighter ever leaves ShieldDrop into a
# state that needs a free body (Protect, Punch, Shoot, Dash, Run, Recovery).
func _cpu_respects_the_lag(s: RefCounted) -> void:
	var game: Node2D = s.spawn_game(420.0, 560.0)
	var fighters: Array[Fighter] = [game.get_node("Fighter1"), game.get_node("Fighter2")]
	var difficulty := CpuDifficulty.preset(CpuDifficulty.Level.HARD)
	difficulty.block_chance = 1.0
	difficulty.block_hold = 0.1
	for i in 2:
		fighters[i].set_controller(ScriptedController.new(difficulty, 7 + i))
	var bad := 0
	var lags := 0
	var prev := ["", ""]
	var notes: Array[String] = []
	var forbidden := ["Protect", "Punch", "Shoot", "Dash", "Run", "Recovery"]
	for t in 2400:
		await s.frames(1)
		for i in 2:
			var now: String = s.state_of(fighters[i])
			if prev[i] == "ShieldDrop" and now != "ShieldDrop":
				lags += 1
				if forbidden.has(now):
					bad += 1
					notes.append("fighter %d went ShieldDrop -> %s at tick %d" % [i + 1, now, t])
			prev[i] = now
		for fighter in fighters:
			fighter.stocks = Fighter.MAX_STOCKS
	s.check("the CPU drops shields and never acts out of the lag", lags >= 3 and bad == 0, "lags=%d bad=%d %s" % [lags, bad, notes])
	await s.despawn(game)
