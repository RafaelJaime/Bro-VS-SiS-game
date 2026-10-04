extends SceneTree
## Tick-based Punch and Hurt timing plus the attack input buffer. A swing, its
## cooldown and the hitstun count physics ticks (never Timer nodes), so hit-stop and
## `Engine.time_scale` cannot stretch them; a punch pressed a few ticks early still
## fires on the first actionable tick, and one press yields exactly one action.
## Headless; every number is in physics ticks.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
## The baseline numbers of the legacy timers (press = tick 1): the hit lands on
## tick 6, the victim leaves Hurt on tick 25 and the next punch fires on tick 43.
const LEGACY_HIT := 6
const LEGACY_HURT_END := 25
const LEGACY_SECOND_PUNCH := 43

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	await _baseline_ticks(s)
	await _buffer_in_cooldown(s)
	await _buffer_in_endlag(s)
	await _not_buffered_states(s)
	await _hold_never_rearms(s)
	await _one_press_one_action(s)
	await _time_scale(s)
	s.finish()

func _setup(s: RefCounted, p1_x: float, p2_x: float) -> Array:
	var game: Node2D = s.spawn_game(p1_x, p2_x)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(90)
	return [game, controllers]

## Runs `count` ticks, pressing punch on the ticks listed in `presses`. Returns the
## ticks (0-based) on which a Punch started, plus the number of ticks spent in Punch.
func _drive(s: RefCounted, ctrl, fighter: Fighter, count: int, presses: Array) -> Dictionary:
	var fires: Array[int] = []
	var punch_ticks := 0
	var was_punch := false
	for i in count:
		if presses.has(i):
			ctrl.press_punch()
		await s.frames(1)
		var in_punch: bool = s.state_of(fighter) == "Punch"
		if in_punch and not was_punch:
			fires.append(i)
		if in_punch:
			punch_ticks += 1
		was_punch = in_punch
	return {"fires": fires, "punch_ticks": punch_ticks}

# Hit, hitstun end and the next punch of the baseline profile, within one tick of
# the legacy Timer numbers.
func _baseline_ticks(s: RefCounted) -> void:
	var setup := await _setup(s, 400.0, 470.0)
	var game: Node2D = setup[0]
	var ctrl = setup[1][0]
	var attacker: Fighter = game.get_node("Fighter1")
	var victim: Fighter = game.get_node("Fighter2")
	var hit := -1
	var hurt_end := -1
	var second := -1
	var seen_hurt := false
	var was_punch := false
	var fires := 0
	var punch_ticks := 0
	for i in 140:
		# Press on tick 0, then mash every tick: the second punch fires the first
		# tick the cooldown allows it.
		ctrl.press_punch()
		await s.frames(1)
		var t := i + 1
		if hit < 0 and victim.damage_percent > 0.0:
			hit = t
		var hurt: bool = s.state_of(victim) == "Hurt"
		seen_hurt = seen_hurt or hurt
		if seen_hurt and hurt_end < 0 and not hurt:
			hurt_end = t
		var in_punch: bool = s.state_of(attacker) == "Punch"
		if in_punch and not was_punch:
			fires += 1
			if fires == 2 and second < 0:
				second = t
		if in_punch and fires == 1:
			punch_ticks += 1
		was_punch = in_punch
	s.check("baseline: the hit lands within a tick of the legacy frame", absi(hit - LEGACY_HIT) <= 1, "hit=%d legacy=%d" % [hit, LEGACY_HIT])
	s.check("baseline: hitstun ends within a tick of the legacy frame", absi(hurt_end - LEGACY_HURT_END) <= 1, "end=%d legacy=%d" % [hurt_end, LEGACY_HURT_END])
	s.check("baseline: the next punch fires within a tick of the legacy frame", absi(second - LEGACY_SECOND_PUNCH) <= 1, "second=%d legacy=%d" % [second, LEGACY_SECOND_PUNCH])
	s.check("baseline: a 0.3 s swing lasts 18 ticks in Punch", punch_ticks == 18, "ticks=%d" % punch_ticks)
	await s.despawn(game)

# A press made in the 6 ticks before the cooldown ends fires the first tick the
# cooldown allows; one made earlier has expired by then.
func _buffer_in_cooldown(s: RefCounted) -> void:
	var setup := await _setup(s, 400.0, 900.0)
	var ctrl = setup[1][0]
	var attacker: Fighter = setup[0].get_node("Fighter1")
	var cooldown := CombatClock.ticks(attacker.profile.punch_cooldown)
	var on_time: Dictionary = await _drive(s, ctrl, attacker, cooldown + 10, [0, cooldown])
	s.check("a press on the first allowed tick fires at once", on_time["fires"] == [0, cooldown], "fires=%s cooldown=%d" % [on_time["fires"], cooldown])
	await s.despawn(setup[0])

	setup = await _setup(s, 400.0, 900.0)
	ctrl = setup[1][0]
	attacker = setup[0].get_node("Fighter1")
	var early: Dictionary = await _drive(s, ctrl, attacker, cooldown + 10, [0, cooldown - 5])
	s.check("a press 5 ticks early is buffered and fires on the first allowed tick", early["fires"] == [0, cooldown], "fires=%s" % [early["fires"]])
	await s.despawn(setup[0])

	setup = await _setup(s, 400.0, 900.0)
	ctrl = setup[1][0]
	attacker = setup[0].get_node("Fighter1")
	var late: Dictionary = await _drive(s, ctrl, attacker, cooldown + 10, [0, cooldown - 6])
	s.check("a press 6 ticks early has expired and fires nothing", late["fires"] == [0], "fires=%s" % [late["fires"]])
	await s.despawn(setup[0])

# With no cooldown the swing's end lag is the only lock: a press during it fires on
# the first tick Idle can act, and a press made more than 6 ticks before it expires.
func _buffer_in_endlag(s: RefCounted) -> void:
	var setup := await _setup(s, 400.0, 900.0)
	var ctrl = setup[1][0]
	var attacker: Fighter = setup[0].get_node("Fighter1")
	var punch = attacker.state_machine.state_map["Punch"]
	punch.punch_cooldown = 0.0
	var plain: Dictionary = await _drive(s, ctrl, attacker, 40, [0, 19])
	var swing: int = CombatClock.ticks(attacker.profile.punch_duration)
	s.check("with no cooldown the next punch fires the tick after the swing", plain["fires"] == [0, swing + 1], "fires=%s swing=%d" % [plain["fires"], swing])
	await s.despawn(setup[0])

	setup = await _setup(s, 400.0, 900.0)
	ctrl = setup[1][0]
	attacker = setup[0].get_node("Fighter1")
	punch = attacker.state_machine.state_map["Punch"]
	punch.punch_cooldown = 0.0
	var buffered: Dictionary = await _drive(s, ctrl, attacker, 40, [0, swing - 4])
	s.check("a press in the end lag fires on the first actionable tick", buffered["fires"] == [0, swing + 1], "fires=%s" % [buffered["fires"]])
	await s.despawn(setup[0])

	setup = await _setup(s, 400.0, 900.0)
	ctrl = setup[1][0]
	attacker = setup[0].get_node("Fighter1")
	punch = attacker.state_machine.state_map["Punch"]
	punch.punch_cooldown = 0.0
	var expired: Dictionary = await _drive(s, ctrl, attacker, 40, [0, swing - 6])
	s.check("a press made 7 ticks before the first actionable tick has expired", expired["fires"] == [0], "fires=%s" % [expired["fires"]])
	await s.despawn(setup[0])

# Presses in these states are edges and are not remembered.
func _not_buffered_states(s: RefCounted) -> void:
	var setup := await _setup(s, 400.0, 900.0)
	var ctrl = setup[1][0]
	var f: Fighter = setup[0].get_node("Fighter1")
	var ground := f.position
	for state_name in ["Hurt", "ShieldDrop", "Protect", "Dizzy", "AirDodge", "LedgeHang", "Dash", "Recovery", "Helpless"]:
		f.attack_buffer_ticks = 0
		f.ledge_anchor = ground
		f.state_machine._change_state(state_name)
		ctrl.press_punch()
		await s.frames(1)
		s.check("a press in %s is not buffered" % state_name, f.attack_buffer_ticks == 0, "buffer=%d" % f.attack_buffer_ticks)
		# Back to a clean, grounded state for the next one.
		f.ledge_side = 0
		f.facing = 1
		f.ledge_anchor = ground
		f.state_machine._change_state("Idle")
		f.position = ground
		f.velocity = Vector2.ZERO
		f.state_machine.velocity = Vector2.ZERO
		await s.frames(2)
		f.attack_buffer_ticks = 0
		f.attack_cooldown_ticks = 0
	await s.despawn(setup[0])

	setup = await _setup(s, 400.0, 900.0)
	ctrl = setup[1][0]
	f = setup[0].get_node("Fighter1")
	f.attack_cooldown_ticks = 30
	ctrl.press_punch()
	await s.frames(1)
	s.check("a press in Idle is buffered", f.attack_buffer_ticks == f.profile.attack_buffer_ticks, "buffer=%d" % f.attack_buffer_ticks)
	await s.frames(1)
	s.check("the buffer counts down every tick", f.attack_buffer_ticks == f.profile.attack_buffer_ticks - 1, "buffer=%d" % f.attack_buffer_ticks)
	await s.despawn(setup[0])

# Holding the key never re-arms the buffer: one press, one swing.
func _hold_never_rearms(s: RefCounted) -> void:
	var setup := await _setup(s, 400.0, 900.0)
	var ctrl = setup[1][0]
	var f: Fighter = setup[0].get_node("Fighter1")
	f.attack_cooldown_ticks = 0
	ctrl.attack_held_level = true
	ctrl.press_punch()
	var fires := 0
	var was_punch := false
	var max_buffer := 0
	for i in 150:
		if i == 70:
			ctrl.attack_held_level = false
		await s.frames(1)
		max_buffer = maxi(max_buffer, f.attack_buffer_ticks)
		var in_punch: bool = s.state_of(f) == "Punch"
		if in_punch and not was_punch:
			fires += 1
		was_punch = in_punch
	s.check("holding the key never re-arms the buffer", max_buffer == 0, "max=%d" % max_buffer)
	s.check("a held key is one punch, not a stream of them", fires == 1, "fires=%d" % fires)
	await s.despawn(setup[0])

# Jump + punch on one frame is a jump only; the recovery chord is a recovery only.
func _one_press_one_action(s: RefCounted) -> void:
	var setup := await _setup(s, 400.0, 900.0)
	var ctrl = setup[1][0]
	var f: Fighter = setup[0].get_node("Fighter1")
	ctrl.press_jump()
	ctrl.press_punch()
	var punched := false
	for i in 12:
		await s.frames(1)
		punched = punched or s.state_of(f) == "Punch"
	s.check("jump + punch on the same frame yields the jump only", not punched and f.attack_cooldown_ticks == 0 and f.attack_buffer_ticks == 0 and not f.is_on_floor(), "punched=%s cd=%d buffer=%d" % [punched, f.attack_cooldown_ticks, f.attack_buffer_ticks])
	await s.despawn(setup[0])

	setup = await _setup(s, 400.0, 900.0)
	ctrl = setup[1][0]
	f = setup[0].get_node("Fighter1")
	f.position.y -= 250.0
	f.velocity = Vector2.ZERO
	await s.frames(3)
	ctrl.press_special()
	await s.frames(1)
	ctrl.aim = FighterIntent.Aim.NEUTRAL
	var recovered: bool = s.state_of(f) == "Recovery"
	var punched_in_chord := false
	for i in 10:
		await s.frames(1)
		punched_in_chord = punched_in_chord or s.state_of(f) == "Punch"
	s.check("the recovery chord (attack + special) yields the recovery only", recovered and not punched_in_chord and f.attack_cooldown_ticks == 0, "recovery=%s punched=%s" % [recovered, punched_in_chord])
	await s.despawn(setup[0])

# A swing lasts the same number of ticks at any time scale.
func _time_scale(s: RefCounted) -> void:
	var swings := {}
	var stuns := {}
	for scale in [1.0, 0.3]:
		var setup := await _setup(s, 400.0, 900.0)
		var ctrl = setup[1][0]
		var attacker: Fighter = setup[0].get_node("Fighter1")
		Engine.time_scale = scale
		var drive: Dictionary = await _drive(s, ctrl, attacker, 40, [0])
		swings[scale] = drive["punch_ticks"]
		var victim: Fighter = setup[0].get_node("Fighter2")
		Combat._apply_full(Hit.punch(attacker, 8.0, Vector2(220.0, -120.0)), victim)
		var hurt_ticks := 0
		for i in 120:
			await s.frames(1)
			if s.state_of(victim) != "Hurt":
				break
			hurt_ticks += 1
		stuns[scale] = hurt_ticks
		Engine.time_scale = 1.0
		await s.despawn(setup[0])
	s.check("a swing is the same ticks at time scale 0.3 and 1.0", swings[1.0] == swings[0.3] and swings[1.0] == 18, "normal=%d slowed=%d" % [swings[1.0], swings[0.3]])
	s.check("hitstun is the same ticks at time scale 0.3 and 1.0", stuns[1.0] == stuns[0.3] and stuns[1.0] > 0, "normal=%d slowed=%d" % [stuns[1.0], stuns[0.3]])
