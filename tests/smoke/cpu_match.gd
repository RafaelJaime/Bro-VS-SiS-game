extends SceneTree
## S3 CPU-vs-CPU: no self-destruction over a long match, and a full match reaches
## game over without script errors. Run headless (see run_all.sh).
##
## Self-inflicted = a stock lost with no damage taken in the previous 3 s. The
## tolerance is zero: the bot has an edge guard on the floor and a recovery plan
## in the air, so any such fall is a bug.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const Level := CpuDifficulty.Level
const LONG_RUN_SECONDS := 85.0
const FULL_MATCH_LIMIT := 110.0

func _initialize() -> void:
	_run()

func _cpu_pair(s: RefCounted, level_1: int, level_2: int, rng_seed: int, refill: bool) -> Array:
	var game: Node2D = s.spawn_game()
	s.set_cpu(game.get_node("Fighter1"), level_1, rng_seed)
	s.set_cpu(game.get_node("Fighter2"), level_2, rng_seed + 1)
	return [game, Smoke.MatchLog.new(game, refill)]

# (b) Long CPU-vs-CPU runs; stocks are refilled so the match never ends early.
func _long_run(s: RefCounted, label: String, level_1: int, level_2: int, rng_seed: int) -> void:
	var pair := await _cpu_pair(s, level_1, level_2, rng_seed, true)
	var game: Node2D = pair[0]
	var mlog = pair[1]
	await s.sim(LONG_RUN_SECONDS)
	var total_hits: int = mlog.hits_taken[0] + mlog.hits_taken[1]
	var total_losses: int = mlog.losses[0] + mlog.losses[1]
	var total_self: int = mlog.self_inflicted[0] + mlog.self_inflicted[1]
	print("INFO %s: hits=%d stock losses=%d self-inflicted=%d over %.0f s" % [label, total_hits, total_losses, total_self, mlog.now()])
	s.check("%s fight each other (hits landed)" % label, total_hits >= 10, "hits=%d" % total_hits)
	s.check("%s never self-destruct over %.0f s" % [label, LONG_RUN_SECONDS], total_self == 0, "self-inflicted=%d %s" % [total_self, str(mlog.notes)])
	await s.despawn(game)

func _full_match(s: RefCounted) -> void:
	var pair := await _cpu_pair(s, Level.HARD, Level.NORMAL, 21, false)
	var game: Node2D = pair[0]
	var mlog = pair[1]
	var over := false
	while mlog.now() < FULL_MATCH_LIMIT:
		await s.sim(1.0)
		if game.game_over.visible:
			over = true
			break
	var fighter_1: Fighter = game.get_node("Fighter1")
	var fighter_2: Fighter = game.get_node("Fighter2")
	s.check("a full CPU-vs-CPU match reaches game over", over, "t=%.0f s stocks=%d/%d paused=%s" % [mlog.now(), fighter_1.stocks, fighter_2.stocks, str(paused)])
	s.check("game over follows a defeat or the timer", fighter_1.stocks == 0 or fighter_2.stocks == 0 or game.timer.is_stopped() or game.timer.time_left <= 0.5, "stocks=%d/%d timer_left=%.1f" % [fighter_1.stocks, fighter_2.stocks, game.timer.time_left])
	paused = false
	await s.despawn(game)

# The opponent hovers off the stage (held there every frame). A chasing bot would
# walk off the edge; this one has to stop at it and keep its stocks.
func _edge_guard(s: RefCounted, level: int, side: int) -> void:
	var game: Node2D = s.spawn_game()
	s.attach_controllers(game)
	var human: Fighter = game.get_node("Fighter1")
	var cpu: Fighter = game.get_node("Fighter2")
	s.set_cpu(cpu, level, 12)
	await s.frames(30)
	var stage: Dictionary = game.get_state_snapshot()["stage"]
	var edge: float = stage["right"] if side > 0 else stage["left"]
	var farthest := -INF
	for i in 600:
		human.position = Vector2(edge + side * 80.0, stage["top"] - 250.0)
		human.velocity = Vector2.ZERO
		await s.frames(1)
		farthest = maxf(farthest, (cpu.position.x - edge) * side)
	var level_name := "Hard" if level == Level.HARD else "Normal"
	s.check("CPU %s never follows an off-stage opponent over the %s edge" % [level_name, "right" if side > 0 else "left"], cpu.stocks == Fighter.MAX_STOCKS and human.stocks == Fighter.MAX_STOCKS and farthest < 0.0, "stocks=%d/%d farthest past the edge=%.0f" % [cpu.stocks, human.stocks, farthest])
	await s.despawn(game)

func _run() -> void:
	var s := Smoke.new(self, 700.0)
	await _long_run(s, "CPU Hard vs Hard", Level.HARD, Level.HARD, 5)
	await _long_run(s, "CPU Normal vs Normal", Level.NORMAL, Level.NORMAL, 9)
	for level in [Level.NORMAL, Level.HARD]:
		await _edge_guard(s, level, 1)
		await _edge_guard(s, level, -1)
	await _full_match(s)
	s.finish()
