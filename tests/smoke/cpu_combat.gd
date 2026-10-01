extends SceneTree
## S3 CPU offence: presets are ordered, the CPU approaches and lands hits on an
## idle human at Normal and Hard, a data-driven override reaches the bot, and
## Easy deals clearly less damage than Hard. Run headless: it simulates minutes
## of game time (see run_all.sh).

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const Level := CpuDifficulty.Level
const FIGHT_SECONDS := 90.0

func _initialize() -> void:
	_run()

# Fighter1 is an idle human (it never presses anything, and is refilled after a
# ring-out); Fighter2 is the CPU. Returns the log and the CPU's closest approach.
func _cpu_vs_idle(s: RefCounted, level: int, seconds: float, rng_seed: int) -> Dictionary:
	var game: Node2D = s.spawn_game()
	s.attach_controllers(game)
	var human: Fighter = game.get_node("Fighter1")
	var cpu: Fighter = game.get_node("Fighter2")
	s.set_cpu(cpu, level, rng_seed)
	var mlog := Smoke.MatchLog.new(game, true)
	var start_gap := absf(cpu.position.x - human.position.x)
	var closest := start_gap
	var first_hit := -1.0
	var steps := int(seconds)
	for i in steps:
		await s.sim(1.0)
		closest = minf(closest, absf(cpu.position.x - human.position.x))
		if first_hit < 0.0 and mlog.hits_taken[0] > 0:
			first_hit = mlog.now()
	var result := {
		"mlog": mlog,
		"damage": mlog.damage_taken[0],
		"hits": mlog.hits_taken[0],
		"closest": closest,
		"start_gap": start_gap,
		"first_hit": first_hit,
		"cpu_self_inflicted": mlog.self_inflicted[1],
	}
	await s.despawn(game)
	return result

func _run() -> void:
	var s := Smoke.new(self, 600.0)

	# Presets: Easy is the slowest and least accurate, Hard the opposite.
	var easy := CpuDifficulty.preset(Level.EASY)
	var normal := CpuDifficulty.preset(Level.NORMAL)
	var hard := CpuDifficulty.preset(Level.HARD)
	s.check("reaction delay is ordered Easy > Normal > Hard", easy.decision_interval > normal.decision_interval and normal.decision_interval > hard.decision_interval, "%.2f %.2f %.2f" % [easy.decision_interval, normal.decision_interval, hard.decision_interval])
	s.check("accuracy is ordered Easy < Normal < Hard", easy.action_accuracy < normal.action_accuracy and normal.action_accuracy < hard.action_accuracy, "%.2f %.2f %.2f" % [easy.action_accuracy, normal.action_accuracy, hard.action_accuracy])
	s.check("block and throw chances are ordered Easy < Normal < Hard", easy.block_chance < normal.block_chance and normal.block_chance < hard.block_chance and easy.throw_chance < normal.throw_chance and normal.throw_chance < hard.throw_chance)

	# (a) The CPU approaches an idle human and lands hits.
	for level in [Level.NORMAL, Level.HARD]:
		var level_name := "Normal" if level == Level.NORMAL else "Hard"
		var run := await _cpu_vs_idle(s, level, 20.0, 7)
		s.check("CPU %s closes the distance to an idle human" % level_name, run["closest"] < 120.0, "start gap=%.0f closest=%.0f" % [run["start_gap"], run["closest"]])
		s.check("CPU %s lands hits on an idle human within 20 s" % level_name, run["damage"] > 0.0 and run["first_hit"] >= 0.0, "damage=%.0f hits=%d first hit at %.1f s" % [run["damage"], run["hits"], run["first_hit"]])
		s.check("CPU %s never falls on its own while attacking" % level_name, run["cpu_self_inflicted"] == 0, "self-inflicted=%d %s" % [run["cpu_self_inflicted"], str(run["mlog"].notes)])

	# The difficulty Resource really is data: a custom one changes the bot.
	var custom_game: Node2D = s.spawn_game()
	var custom_cpu: Fighter = custom_game.get_node("Fighter2")
	var custom := CpuDifficulty.new()
	custom.decision_interval = 0.77
	var config := ControllerConfig.cpu(Level.HARD)
	config.difficulty_resource = custom
	var built := config.build(custom_cpu) as ScriptedController
	s.check("a difficulty_resource overrides the preset", built != null and is_equal_approx(built.difficulty.decision_interval, 0.77))
	var preset_built := ControllerConfig.cpu(Level.EASY).build(custom_cpu) as ScriptedController
	s.check("a CPU config without a resource builds the level's preset", preset_built != null and is_equal_approx(preset_built.difficulty.decision_interval, easy.decision_interval))
	await s.despawn(custom_game)

	# Food: the CPU walks to a food item on the counter, picks it up and throws it.
	var food_game: Node2D = s.spawn_game()
	s.attach_controllers(food_game)
	var food_human: Fighter = food_game.get_node("Fighter1")
	var food_cpu: Fighter = food_game.get_node("Fighter2")
	var spawner := food_game.get_node_or_null("FoodSpawner")
	if spawner:
		spawner.queue_free()
	s.set_cpu(food_cpu, Level.HARD, 5)
	await s.frames(30)
	var pickup: FoodPickup = load("res://game/food/food_pickup.tscn").instantiate()
	pickup.food_name = FoodCatalog.get_random_food_name()
	food_game.add_child(pickup)
	pickup.position = Vector2(food_cpu.position.x - 130.0, food_game.get_state_snapshot()["stage"]["top"] - 30.0)
	var picked := false
	var thrown := false
	for i in 600:
		await s.frames(1)
		if food_cpu.held_food != "":
			picked = true
		for child in food_game.get_children():
			if child is FoodProjectile and child.shooter == food_cpu:
				thrown = true
		if thrown:
			break
	s.check("the CPU picks up food that is closer than the opponent", picked)
	s.check("the CPU throws the food it picked up", thrown)
	await s.despawn(food_game)

	# Defence: a human who keeps punching at a Hard CPU gets blocked sometimes.
	var block_game: Node2D = s.spawn_game(430.0, 500.0)
	var block_controllers: Array = s.attach_controllers(block_game)
	var puncher: Fighter = block_game.get_node("Fighter1")
	var blocker: Fighter = block_game.get_node("Fighter2")
	s.set_cpu(blocker, Level.HARD, 8)
	var blocked_frames := 0
	for i in 1200:
		await s.frames(1)
		if i % 50 == 0:
			puncher.damage_percent = 0.0
			block_controllers[0].press_punch()
		if s.state_of(blocker) == "Protect":
			blocked_frames += 1
		if puncher.position.x > blocker.position.x - 30.0:
			puncher.position.x = 430.0
	s.check("CPU Hard blocks incoming punches", blocked_frames > 0, "frames in Protect=%d" % blocked_frames)
	await s.despawn(block_game)

	# (d) Easy deals clearly less damage per minute than Hard. An idle target cannot
	# tell them apart (hitstun and post-hit invulnerability cap the hit rate), so
	# they fight each other, once on each side, and the damage they deal is compared.
	var fights := [[Level.EASY, Level.HARD], [Level.HARD, Level.EASY]]
	var easy_damage := 0.0
	var hard_damage := 0.0
	var minutes := 0.0
	for pairing in fights:
		var game: Node2D = s.spawn_game()
		s.set_cpu(game.get_node("Fighter1"), pairing[0], 31)
		s.set_cpu(game.get_node("Fighter2"), pairing[1], 32)
		var mlog := Smoke.MatchLog.new(game, true)
		await s.sim(FIGHT_SECONDS)
		for i in 2:
			if pairing[i] == Level.EASY:
				hard_damage += mlog.damage_taken[i] # Hard dealt what Easy took.
			else:
				easy_damage += mlog.damage_taken[i]
		minutes += FIGHT_SECONDS / 60.0
		await s.despawn(game)
	var easy_dpm := easy_damage / minutes
	var hard_dpm := hard_damage / minutes
	print("INFO Easy vs Hard head to head: Easy dealt %.0f/min, Hard dealt %.0f/min" % [easy_dpm, hard_dpm])
	s.check("Easy deals noticeably less damage per minute than Hard", easy_dpm < hard_dpm * 0.7, "easy=%.0f hard=%.0f" % [easy_dpm, hard_dpm])
	s.check("Easy still hits sometimes (it is not idle)", easy_dpm > 0.0, "easy=%.0f" % easy_dpm)
	s.finish()
