extends SceneTree
## S5b CPU: Normal and Hard recover from off-stage with the double jump, the
## up-recovery and the table legs; Easy never uses directional or special input;
## Normal and Hard throw directional punches. Run headless (see run_all.sh).

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const Level := CpuDifficulty.Level
const TRIALS := 20
const RECOVERY_BUDGET := 6.0

func _initialize() -> void:
	_run()

func _setup(s: RefCounted, level: int, rng_seed: int) -> Array:
	var game: Node2D = s.spawn_game()
	s.attach_controllers(game)
	var cpu: Fighter = game.get_node("Fighter2")
	var human: Fighter = game.get_node("Fighter1")
	s.set_cpu(cpu, level, rng_seed)
	await s.frames(60)
	return [game, cpu, human, game.get_state_snapshot()["stage"]]

func _level_name(level: int) -> String:
	return ["Easy", "Normal", "Hard"][level]

# Runs until the CPU is back on the stage or the budget ends. Returns whether it
# made it, and which recovery tools it used on the way.
func _watch(s: RefCounted, cpu: Fighter, stage: Dictionary) -> Dictionary:
	var used := {"ledge": false, "recovery": false, "special_intent": false, "aim_intent": false}
	var left_ground := false
	for i in int(RECOVERY_BUDGET * 60.0):
		await s.frames(1)
		var state: String = s.state_of(cpu)
		used["ledge"] = used["ledge"] or state == "LedgeHang"
		used["recovery"] = used["recovery"] or state == "Recovery"
		used["special_intent"] = used["special_intent"] or cpu.intent.special_pressed
		used["aim_intent"] = used["aim_intent"] or cpu.intent.aim != FighterIntent.Aim.NEUTRAL
		if not cpu.is_on_floor():
			left_ground = true
		elif left_ground and cpu.position.x >= stage["left"] and cpu.position.x <= stage["right"]:
			used["ok"] = cpu.stocks == Fighter.MAX_STOCKS
			return used
		if cpu.stocks < Fighter.MAX_STOCKS:
			break
	used["ok"] = false
	return used

func _feet_offset(s: RefCounted, fighter: Fighter) -> float:
	return s.body_bottom(fighter) - fighter.position.y

# Random launches from beside the table ends, above and below the tabletop.
func _random_trials(s: RefCounted, level: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + level
	var recovered := 0
	var ledge_uses := 0
	var recovery_uses := 0
	var aim_or_special := 0
	var failures: Array[String] = []
	for trial in TRIALS:
		var setup := await _setup(s, level, 400 + trial)
		var cpu: Fighter = setup[1]
		var stage: Dictionary = setup[3]
		var side := -1 if rng.randf() < 0.5 else 1
		var edge: float = stage["right"] if side > 0 else stage["left"]
		var feet := float(stage["top"]) + rng.randf_range(-120.0, 90.0)
		cpu.position = Vector2(edge + side * rng.randf_range(50.0, 170.0), feet - _feet_offset(s, cpu))
		cpu.velocity = Vector2(side * rng.randf_range(0.0, 180.0), rng.randf_range(-200.0, 250.0))
		cpu.state_machine._change_state("Fall")
		var used := await _watch(s, cpu, stage)
		if used["ok"]:
			recovered += 1
		else:
			failures.append("trial %d side=%d feet=%.0f v=%s" % [trial, side, feet, cpu.velocity])
		ledge_uses += 1 if used["ledge"] else 0
		recovery_uses += 1 if used["recovery"] else 0
		aim_or_special += 1 if (used["special_intent"] or used["aim_intent"]) else 0
		await s.despawn(setup[0])
	var rate := float(recovered) / TRIALS
	s.check("CPU %s recovers from off-stage launches (>= 90%%)" % _level_name(level), rate >= 0.9, "%d/%d recovered, ledge in %d, recovery in %d, failures=%s" % [recovered, TRIALS, ledge_uses, recovery_uses, failures])
	s.check("CPU %s uses the table legs" % _level_name(level), ledge_uses > 0, "ledge grabs in %d trials" % ledge_uses)
	if level == Level.EASY:
		s.check("CPU Easy never uses the up-recovery, aim or special", recovery_uses == 0 and aim_or_special == 0, "recovery=%d aim/special=%d" % [recovery_uses, aim_or_special])

# Far out and below with the double jump gone: only the up-recovery (or a late
# air dash) can still reach the table.
func _needs_recovery(s: RefCounted, level: int) -> void:
	var uses := 0
	var recovered := 0
	for trial in 6:
		var setup := await _setup(s, level, 700 + trial)
		var cpu: Fighter = setup[1]
		var stage: Dictionary = setup[3]
		cpu.position = Vector2(float(stage["left"]) - 195.0, float(stage["top"]) + 80.0 - _feet_offset(s, cpu))
		cpu.velocity = Vector2(0.0, 150.0)
		cpu.state_machine._change_state("Fall")
		# The teleport leaves a stale floor contact that refills the air actions.
		cpu.controls_locked = true
		await s.frames(2)
		cpu.jumps_left = 0
		cpu.air_dash_available = false
		cpu.controls_locked = false
		var used := await _watch(s, cpu, stage)
		uses += 1 if used["recovery"] else 0
		recovered += 1 if used["ok"] else 0
		await s.despawn(setup[0])
	s.check("CPU %s uses the up-recovery when the double jump is gone" % _level_name(level), uses >= 4, "recovery in %d/6, recovered %d/6" % [uses, recovered])

# Directional punches against a frozen target.
func _directional(s: RefCounted, level: int) -> void:
	# Up punch: the opponent hovers above.
	var up_setup := await _setup(s, level, 31)
	var cpu: Fighter = up_setup[1]
	var target: Fighter = up_setup[2]
	target.position.x = cpu.position.x - 30.0
	var up_hit := false
	for i in 300:
		target.position.y = cpu.position.y - 115.0
		target.velocity = Vector2.ZERO
		await s.frames(1)
		if cpu.last_attack_direction == &"up":
			up_hit = true
			break
	s.check("CPU %s throws an up punch at an opponent above" % _level_name(level), up_hit, "last=%s" % cpu.last_attack_direction)
	await s.despawn(up_setup[0])

	# Side punch: a damaged opponent near the table end.
	var side_setup := await _setup(s, level, 32)
	var side_cpu: Fighter = side_setup[1]
	var side_target: Fighter = side_setup[2]
	var stage: Dictionary = side_setup[3]
	side_target.set_damage_percent(110.0)
	side_target.position.x = float(stage["right"]) - 70.0
	side_cpu.position.x = float(stage["right"]) - 150.0
	var side_hit := false
	for i in 400:
		side_target.velocity = Vector2.ZERO
		side_target.position.x = float(stage["right"]) - 70.0
		await s.frames(1)
		if side_cpu.last_attack_direction == &"side":
			side_hit = true
			break
	s.check("CPU %s throws a side punch at a damaged opponent near the edge" % _level_name(level), side_hit, "last=%s" % side_cpu.last_attack_direction)
	await s.despawn(side_setup[0])

func _spike(s: RefCounted, level: int) -> void:
	var spikes := 0
	for trial in 10:
		var setup := await _setup(s, level, 50 + trial)
		var cpu: Fighter = setup[1]
		var target: Fighter = setup[2]
		target.position.x = cpu.position.x - 20.0
		cpu.position.y -= 260.0 + 10.0 * trial
		cpu.velocity = Vector2.ZERO
		cpu.state_machine._change_state("Fall")
		for i in 90:
			target.velocity = Vector2.ZERO
			await s.frames(1)
			if cpu.last_attack_direction == &"down":
				spikes += 1
				break
		await s.despawn(setup[0])
	s.check("CPU %s uses the down-air spike on an opponent below" % _level_name(level), spikes >= 1, "%d/10 trials" % spikes)

# Easy plays a whole fight without a single directional or special intent.
func _easy_plain(s: RefCounted) -> void:
	var game: Node2D = s.spawn_game()
	var a: Fighter = game.get_node("Fighter1")
	var b: Fighter = game.get_node("Fighter2")
	s.set_cpu(a, Level.EASY, 71)
	s.set_cpu(b, Level.EASY, 72)
	var log := Smoke.MatchLog.new(game, true)
	var offending := 0
	for i in int(45.0 * 60.0):
		await s.frames(1)
		for fighter in [a, b]:
			if fighter.intent.special_pressed or fighter.intent.aim != FighterIntent.Aim.NEUTRAL:
				offending += 1
	s.check("CPU Easy never emits directional aim or special over 45 s", offending == 0, "offending frames=%d" % offending)
	await s.despawn(game)

# Two bots fight for 60 s with every move available: nobody may fall without a hit.
func _bot_vs_bot(s: RefCounted, level_a: int, level_b: int, rng_seed: int) -> void:
	var game: Node2D = s.spawn_game()
	var a: Fighter = game.get_node("Fighter1")
	var b: Fighter = game.get_node("Fighter2")
	s.set_cpu(a, level_a, rng_seed)
	s.set_cpu(b, level_b, rng_seed + 1)
	var log := Smoke.MatchLog.new(game, true)
	var dirs := {}
	var states := {}
	for i in int(60.0 * 60.0):
		await s.frames(1)
		for fighter in [a, b]:
			dirs[fighter.last_attack_direction] = true
			states[s.state_of(fighter)] = true
	s.check("CPU %s vs CPU %s for 60 s: no self-destructs" % [_level_name(level_a), _level_name(level_b)], log.self_inflicted[0] + log.self_inflicted[1] == 0 and log.hits_taken[0] + log.hits_taken[1] > 0, "self=%s hits=%s notes=%s attacks=%s" % [log.self_inflicted, log.hits_taken, log.notes, dirs.keys()])
	await s.despawn(game)

func _run() -> void:
	var s := Smoke.new(self, 900.0)
	var easy := CpuDifficulty.preset(Level.EASY)
	var normal := CpuDifficulty.preset(Level.NORMAL)
	var hard := CpuDifficulty.preset(Level.HARD)
	s.check("presets: Easy has no directional or up-recovery, Normal and Hard have both", not easy.use_directional and not easy.use_up_recovery and normal.use_directional and normal.use_up_recovery and hard.use_directional and hard.use_up_recovery)
	for level in [Level.EASY, Level.NORMAL, Level.HARD]:
		await _random_trials(s, level)
	for level in [Level.NORMAL, Level.HARD]:
		await _needs_recovery(s, level)
		await _directional(s, level)
	await _spike(s, Level.HARD)
	await _easy_plain(s)
	await _bot_vs_bot(s, Level.HARD, Level.HARD, 11)
	await _bot_vs_bot(s, Level.NORMAL, Level.HARD, 21)
	await _bot_vs_bot(s, Level.EASY, Level.NORMAL, 31)
	s.finish()
