extends SceneTree
## S3 CPU recovery: a CPU placed or launched off the stage steers home, double
## jumps and air dashes back to the floor without losing a stock. Run headless
## (see run_all.sh).

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const Level := CpuDifficulty.Level
const RECOVERY_BUDGET := 4.0

func _initialize() -> void:
	_run()

# Spawns a game, makes Fighter2 a CPU of `level` and returns [game, cpu, human, stage].
func _setup(s: RefCounted, level: int) -> Array:
	var game: Node2D = s.spawn_game()
	s.attach_controllers(game)
	var human: Fighter = game.get_node("Fighter1")
	var cpu: Fighter = game.get_node("Fighter2")
	s.set_cpu(cpu, level, 3)
	await s.frames(60)
	return [game, cpu, human, game.get_state_snapshot()["stage"]]

func _feet_offset(s: RefCounted, fighter: Fighter) -> float:
	return s.body_bottom(fighter) - fighter.position.y

# Runs until the CPU stands on the stage again or the budget ends. Returns the
# seconds it took (-1 when it never made it) and whether it lost a stock.
func _watch(s: RefCounted, cpu: Fighter, stage: Dictionary) -> Dictionary:
	var elapsed := 0.0
	var step := 1.0 / 60.0
	var left_ground := false
	while elapsed < RECOVERY_BUDGET:
		await s.frames(1)
		elapsed += step
		if not cpu.is_on_floor():
			left_ground = true
		elif left_ground and cpu.position.x >= stage["left"] and cpu.position.x <= stage["right"]:
			return {"time": elapsed, "stocks": cpu.stocks}
		if cpu.stocks < Fighter.MAX_STOCKS:
			break
	return {"time": -1.0, "stocks": cpu.stocks}

func _placed(s: RefCounted, level: int, scenario: String, x_of: Callable, feet_of: Callable, velocity: Vector2) -> void:
	var level_name := "Normal" if level == Level.NORMAL else "Hard"
	var setup := await _setup(s, level)
	var game: Node2D = setup[0]
	var cpu: Fighter = setup[1]
	var stage: Dictionary = setup[3]
	cpu.position = Vector2(x_of.call(stage), feet_of.call(stage) - _feet_offset(s, cpu))
	cpu.velocity = velocity
	var result := await _watch(s, cpu, stage)
	s.check("CPU %s recovers: %s" % [level_name, scenario], result["time"] >= 0.0 and result["stocks"] == Fighter.MAX_STOCKS, "time=%.2f s stocks=%d pos=(%.0f, %.0f)" % [result["time"], result["stocks"], cpu.position.x, cpu.position.y])
	await s.despawn(game)

# Launches the CPU from the floor with a real hit, toward `side` (-1 left, 1 right).
func _launched(s: RefCounted, level: int, side: int) -> void:
	var level_name := "Normal" if level == Level.NORMAL else "Hard"
	var setup := await _setup(s, level)
	var game: Node2D = setup[0]
	var cpu: Fighter = setup[1]
	var human: Fighter = setup[2]
	var stage: Dictionary = setup[3]
	var edge: float = stage["right"] if side > 0 else stage["left"]
	cpu.position.x = edge - side * 110.0
	cpu.velocity = Vector2.ZERO
	# The knockback goes away from the attacker, so stand on the stage side.
	human.position.x = cpu.position.x - side * 90.0
	human.velocity = Vector2.ZERO
	await s.frames(20)
	Combat.apply_hit(human, cpu, 8.0, Vector2(300.0, -200.0))
	await s.frames(2)
	var launched_toward_edge := signf(cpu.velocity.x) == float(side)
	var result := await _watch(s, cpu, stage)
	s.check("CPU %s recovers after being launched %s" % [level_name, "right" if side > 0 else "left"], launched_toward_edge and result["time"] >= 0.0 and result["stocks"] == Fighter.MAX_STOCKS, "launched=%s time=%.2f s stocks=%d" % [launched_toward_edge, result["time"], result["stocks"]])
	await s.despawn(game)

func _run() -> void:
	var s := Smoke.new(self, 200.0)
	for level in [Level.NORMAL, Level.HARD]:
		await _placed(s, level, "beside the left edge, above the floor",
				func(st): return st["left"] - 70.0, func(st): return st["top"] - 150.0, Vector2.ZERO)
		await _placed(s, level, "beside the right edge, at floor level",
				func(st): return st["right"] + 70.0, func(st): return st["top"] - 10.0, Vector2.ZERO)
		await _placed(s, level, "below the left edge",
				func(st): return st["left"] - 45.0, func(st): return st["top"] + 70.0, Vector2.ZERO)
		await _placed(s, level, "below the right edge, falling",
				func(st): return st["right"] + 40.0, func(st): return st["top"] + 40.0, Vector2(60.0, 250.0))
		await _placed(s, level, "far out and drifting away",
				func(st): return st["right"] + 60.0, func(st): return st["top"] - 90.0, Vector2(250.0, -100.0))
		await _launched(s, level, 1)
		await _launched(s, level, -1)
	s.finish()
