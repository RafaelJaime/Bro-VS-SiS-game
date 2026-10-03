extends SceneTree
## The CPU under combat depth: it lets go of the shield at its release ratio (with
## hysteresis) and never breaks it by its own hold, punishes a dizzy opponent at the
## difficulty's rate, pressures a shielding opponent with food and fetches food from
## farther away against a turtle, Hard steps out of falling bombs and air dodges,
## Easy never uses aim or special, and nobody holds a button. Headless: it simulates
## minutes of game time (see run_all.sh).

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const Level := CpuDifficulty.Level
const PUNISH_TRIALS := 60
const SURVIVAL_TRIALS := 6
const SURVIVAL_CAP_TICKS := 2400

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self, 6000.0)
	_ordering(s)
	await _release_threshold(s)
	await _never_self_breaks(s)
	await _punish_dizzy(s)
	await _food_pressure(s)
	await _fetch_against_a_turtle(s)
	await _bomb_dodge(s)
	await _bomb_survival(s)
	await _air_dodge(s)
	await _easy_and_taps(s)
	s.finish()

# Fighter1 is a scripted-by-the-test human (an IntentController), Fighter2 the CPU.
# The food spawner is stopped and the fighters have landed.
func _world(s: RefCounted, difficulty: CpuDifficulty, enemy_x: float, cpu_x: float, rng_seed: int = 5) -> Dictionary:
	var game: Game = s.spawn_game(enemy_x, cpu_x)
	var controllers: Array = s.attach_controllers(game)
	var cpu_fighter: Fighter = game.get_node("Fighter2")
	var cpu := ScriptedController.new(difficulty, rng_seed)
	cpu_fighter.set_controller(cpu)
	await s.frames(1)
	game.food_spawner.stop()
	await s.frames(60)
	return {"game": game, "enemy": game.get_node("Fighter1"), "enemy_ctrl": controllers[0], "fighter": cpu_fighter, "cpu": cpu}

func _leave(s: RefCounted, game: Node) -> void:
	Combat.cancel_hit_stop()
	paused = false
	await s.despawn(game)

func _decision(s: RefCounted, difficulty: CpuDifficulty) -> void:
	await s.sim(difficulty.decision_interval + 0.1)

# A difficulty with every personality value neutral except the ones a test sets.
func _custom(throw_chance: float = 0.0, pressure: float = 0.0, punish: float = 0.0) -> CpuDifficulty:
	var d := CpuDifficulty.preset(Level.NORMAL)
	d.throw_chance = throw_chance
	d.food_pressure_chance = pressure
	d.punish_dizzy_chance = punish
	d.block_chance = 0.0
	d.decision_interval = 0.15
	return d

# ---------------------------------------------------------------- ordering

func _ordering(s: RefCounted) -> void:
	var easy := CpuDifficulty.preset(Level.EASY)
	var normal := CpuDifficulty.preset(Level.NORMAL)
	var hard := CpuDifficulty.preset(Level.HARD)
	s.check("the shield release ratios are 0.45 / 0.35 / 0.25", is_equal_approx(easy.shield_release_ratio, 0.45) and is_equal_approx(normal.shield_release_ratio, 0.35) and is_equal_approx(hard.shield_release_ratio, 0.25))
	s.check("punish-dizzy chance is ordered Easy <= Normal <= Hard, Normal < Hard", easy.punish_dizzy_chance <= normal.punish_dizzy_chance and normal.punish_dizzy_chance <= hard.punish_dizzy_chance and normal.punish_dizzy_chance < hard.punish_dizzy_chance and easy.punish_dizzy_chance == 0.0)
	s.check("food-pressure chance is ordered Easy <= Normal <= Hard, Normal < Hard", easy.food_pressure_chance <= normal.food_pressure_chance and normal.food_pressure_chance <= hard.food_pressure_chance and normal.food_pressure_chance < hard.food_pressure_chance and easy.food_pressure_chance == 0.0)
	s.check("only Hard dodges bombs, with the 0.9 s lookahead and 40 px margin", hard.bomb_dodge and not normal.bomb_dodge and not easy.bomb_dodge and is_equal_approx(hard.bomb_lookahead, 0.9) and is_equal_approx(hard.bomb_margin, 40.0))
	s.check("the turtle time is 1.5 s", is_equal_approx(normal.turtle_time, 1.5))
	s.check("the earlier orderings still hold", easy.decision_interval > normal.decision_interval and normal.decision_interval > hard.decision_interval and easy.action_accuracy < normal.action_accuracy and normal.action_accuracy < hard.action_accuracy)

# --------------------------------------------------------- release threshold

func _release_threshold(s: RefCounted) -> void:
	for level in [Level.EASY, Level.NORMAL, Level.HARD]:
		var difficulty := CpuDifficulty.preset(level)
		var world := await _world(s, difficulty, 100.0, 700.0)
		var fighter: Fighter = world["fighter"]
		var cpu: ScriptedController = world["cpu"]
		var release := difficulty.shield_release_ratio
		var label := "Easy" if level == Level.EASY else ("Normal" if level == Level.NORMAL else "Hard")

		fighter.shield.set_ratio(release + 0.30)
		cpu._block_left = 5.0
		await s.frames(2)
		var above: bool = fighter.intent.block_held
		fighter.shield.set_ratio(release - 0.01)
		cpu._block_left = 5.0
		await s.frames(2)
		var below: bool = fighter.intent.block_held
		fighter.shield.set_ratio(release + 0.10)
		cpu._block_left = 5.0
		await s.frames(2)
		var in_band: bool = fighter.intent.block_held
		fighter.shield.set_ratio(release + 0.20)
		cpu._block_left = 5.0
		await s.frames(2)
		var recovered: bool = fighter.intent.block_held
		s.check("CPU %s holds the shield above its release ratio %.2f" % [label, release], above)
		s.check("CPU %s lets go at the release ratio" % label, not below)
		s.check("CPU %s stays off inside the 0.15 hysteresis band" % label, not in_band)
		s.check("CPU %s raises it again once the meter is above the band" % label, recovered)
		await _leave(s, world["game"])

# ----------------------------------------------------------- never self-breaks

func _never_self_breaks(s: RefCounted) -> void:
	for level in [Level.EASY, Level.NORMAL, Level.HARD]:
		var difficulty := CpuDifficulty.preset(level)
		var world := await _world(s, difficulty, 430.0, 520.0, 11)
		var game: Game = world["game"]
		var fighter: Fighter = world["fighter"]
		var enemy: Fighter = world["enemy"]
		var label := "Easy" if level == Level.EASY else ("Normal" if level == Level.NORMAL else "Hard")
		var hold_breaks := [0]
		var protect_frames := 0
		fighter.shield_broken.connect(func(cause: Hit) -> void:
			if cause == null:
				hold_breaks[0] += 1)
		# A human who keeps punching, and keeps its distance close.
		for i in 1200:
			await s.frames(1)
			if i % 40 == 0:
				enemy.damage_percent = 0.0
				world["enemy_ctrl"].press_punch()
			if s.state_of(fighter) == "Protect":
				protect_frames += 1
			if absf(enemy.position.x - fighter.position.x) > 160.0:
				enemy.position.x = fighter.position.x - 90.0
		s.check("CPU %s never breaks its own shield by holding it (20 s of play)" % label, hold_breaks[0] == 0, "hold breaks=%d protect frames=%d" % [hold_breaks[0], protect_frames])
		await _leave(s, game)

	# Against a passive human the CPU shield stays whole too.
	var passive := await _world(s, CpuDifficulty.preset(Level.HARD), 430.0, 520.0, 12)
	var passive_fighter: Fighter = passive["fighter"]
	var passive_breaks := [0]
	passive_fighter.shield_broken.connect(func(cause: Hit) -> void:
		if cause == null:
			passive_breaks[0] += 1)
	await s.sim(20.0)
	s.check("a CPU facing a passive opponent for 20 s never breaks its shield", passive_breaks[0] == 0)
	await _leave(s, passive["game"])

# ---------------------------------------------------------------- punish dizzy

func _punish_rate(s: RefCounted, difficulty: CpuDifficulty, trials: int) -> int:
	var world := await _world(s, difficulty, 380.0, 460.0, 21)
	var fighter: Fighter = world["fighter"]
	var enemy: Fighter = world["enemy"]
	var cpu: ScriptedController = world["cpu"]
	enemy.grant_invulnerability(100000.0, false)
	var punished := 0
	for i in trials:
		enemy.break_shield(null)
		await _decision(s, difficulty)
		await _decision(s, difficulty)
		if cpu.plan == ScriptedController.Plan.PUNISH:
			punished += 1
		enemy.state_machine._change_state("Idle")
		await _decision(s, difficulty)
		await s.frames(3)
		# Keep the pair close and the fighters in a neutral state for the next trial.
		enemy.position.x = fighter.position.x - 80.0
		enemy.velocity = Vector2.ZERO
	await _leave(s, world["game"])
	return punished

func _punish_dizzy(s: RefCounted) -> void:
	var easy: int = await _punish_rate(s, CpuDifficulty.preset(Level.EASY), PUNISH_TRIALS)
	var normal: int = await _punish_rate(s, CpuDifficulty.preset(Level.NORMAL), PUNISH_TRIALS)
	var hard: int = await _punish_rate(s, CpuDifficulty.preset(Level.HARD), PUNISH_TRIALS)
	print("INFO punish-dizzy commits over %d trials: Easy %d, Normal %d, Hard %d" % [PUNISH_TRIALS, easy, normal, hard])
	s.check("Easy never commits to a punish (probability 0)", easy == 0, "easy=%d" % easy)
	s.check("Normal punishes at a rate consistent with 0.7 (and above 0)", normal > 0 and float(normal) / PUNISH_TRIALS > 0.5 and float(normal) / PUNISH_TRIALS < 0.9, "normal=%d/%d" % [normal, PUNISH_TRIALS])
	s.check("Hard punishes every dizzy opponent (probability 1.0)", hard == PUNISH_TRIALS, "hard=%d/%d" % [hard, PUNISH_TRIALS])
	s.check("the punish rate is ordered Easy <= Normal <= Hard", easy <= normal and normal <= hard)

	# Hard turns it into a tap punch within its reaction time, never a held button.
	var hard_difficulty := CpuDifficulty.preset(Level.HARD)
	var world := await _world(s, hard_difficulty, 380.0, 460.0, 22)
	var fighter: Fighter = world["fighter"]
	var enemy: Fighter = world["enemy"]
	enemy.grant_invulnerability(100000.0, false)
	enemy.break_shield(null)
	var punched := false
	var held := false
	for i in 90:
		await s.frames(1)
		punched = punched or s.state_of(fighter) == "Punch"
		held = held or fighter.intent.attack_held
	s.check("CPU Hard punches a dizzy opponent in range after its reaction delay", punched)
	s.check("the punish is a tap (attack held never set)", not held)
	await _leave(s, world["game"])

# --------------------------------------------------------------- food pressure

func _throws(s: RefCounted, difficulty: CpuDifficulty, enemy_shields: bool, seconds: float) -> int:
	var world := await _world(s, difficulty, 330.0, 450.0, 31)
	var fighter: Fighter = world["fighter"]
	var thrown := [0]
	fighter.food_thrown.connect(func(_food: String) -> void: thrown[0] += 1)
	if enemy_shields:
		world["enemy_ctrl"].block_held_level = true
		world["enemy_ctrl"].press_block()
	fighter.held_food = "turkey"
	fighter.held_food_sprite.texture = FoodCatalog.get_texture("turkey")
	fighter.held_food_sprite.visible = true
	await s.sim(seconds)
	await _leave(s, world["game"])
	return thrown[0]

func _food_pressure(s: RefCounted) -> void:
	var pressure_on: int = await _throws(s, _custom(0.0, 1.0), true, 1.5)
	var pressure_off: int = await _throws(s, _custom(0.0, 0.0), true, 1.5)
	var open_target: int = await _throws(s, _custom(0.0, 1.0), false, 1.5)
	s.check("with pressure 1.0 the CPU throws held food at a shielding opponent", pressure_on == 1, "throws=%d" % pressure_on)
	s.check("with no throw chance and no pressure it does not throw", pressure_off == 0, "throws=%d" % pressure_off)
	s.check("pressure only applies to a shielding opponent", open_target == 0, "throws=%d" % open_target)
	s.check("a Hard CPU throws at a shielder", await _throws(s, CpuDifficulty.preset(Level.HARD), true, 2.0) >= 1)

# ---------------------------------------------------------- fetch from a turtle

func _fetch_against_a_turtle(s: RefCounted) -> void:
	var difficulty := _custom(0.0, 1.0)
	difficulty.pickup_seek_distance = 220.0
	var world := await _world(s, difficulty, 700.0, 150.0, 41)
	var game: Game = world["game"]
	var fighter: Fighter = world["fighter"]
	var cpu: ScriptedController = world["cpu"]
	var picked := [0]
	fighter.food_picked_up.connect(func(_food: String) -> void: picked[0] += 1)
	var pickup: FoodPickup = load("res://game/food/food_pickup.tscn").instantiate()
	pickup.food_name = "turkey"
	game.add_child(pickup)
	pickup.position = Vector2(fighter.position.x + 330.0, game.get_stage_bounds()["top"] - 30.0)
	await s.sim(1.0)
	var start_x := fighter.position.x
	var chased_early := cpu.plan == ScriptedController.Plan.PICKUP
	s.check("food beyond the normal seek distance is ignored while the opponent is open", not chased_early and fighter.held_food == "", "plan=%d x=%.0f" % [cpu.plan, fighter.position.x])

	world["enemy_ctrl"].block_held_level = true
	world["enemy_ctrl"].press_block()
	await s.sim(0.8)
	var early_plan := cpu.plan
	s.check("before the turtle time has passed the CPU still ignores it", early_plan != ScriptedController.Plan.PICKUP, "plan=%d" % early_plan)
	await s.sim(1.2)
	var seeking := cpu.plan == ScriptedController.Plan.PICKUP or fighter.held_food != ""
	s.check("after the opponent shielded for the turtle time the seek distance doubles and the CPU goes for the food", seeking and (fighter.position.x > start_x + 30.0 or fighter.held_food != ""), "plan=%d x=%.0f start=%.0f held=%s" % [cpu.plan, fighter.position.x, start_x, fighter.held_food])
	await s.sim(2.5)
	s.check("it fetches the heavy food", picked[0] == 1 and (fighter.held_food == "turkey" or fighter.held_food == ""), "picked=%d held=%s" % [picked[0], fighter.held_food])
	await _leave(s, game)

# ------------------------------------------------------------------- bombs

# A sudden-death game: CPU `difficulty` on Fighter2, an invulnerable idle opponent
# next to it. The grace period is long, bombs are dropped by hand.
func _bomb_world(s: RefCounted, difficulty: CpuDifficulty, grace: float, enemy_x: float = 380.0, cpu_x: float = 450.0, rng_seed: int = 51) -> Dictionary:
	var world := await _world(s, difficulty, enemy_x, cpu_x, rng_seed)
	var game: Game = world["game"]
	game.sudden_death_intro = 0.0
	game.hazards.grace_time = grace
	game.force_sudden_death()
	(world["enemy"] as Fighter).grant_invulnerability(100000.0, false)
	await s.frames(40)
	return world

func _bomb_hits(fighter: Fighter) -> Array:
	var hits: Array = []
	fighter.hit_received.connect(func(hit: Hit, outcome: int) -> void:
		if hit.source == Hit.Source.BOMB and outcome != Combat.Outcome.IGNORED:
			hits.append(outcome))
	return hits

func _bomb_dodge(s: RefCounted) -> void:
	var results := {}
	for level in [Level.HARD, Level.EASY]:
		var difficulty := CpuDifficulty.preset(level)
		var world := await _bomb_world(s, difficulty, 1000.0)
		var game: Game = world["game"]
		var fighter: Fighter = world["fighter"]
		var hits := _bomb_hits(fighter)
		var column := fighter.position.x
		game.hazards.spawn_bomb(column)
		for i in 150:
			await s.frames(1)
		results[level] = {"hits": hits.size(), "gap": absf(fighter.position.x - column), "stocks": fighter.stocks}
		await _leave(s, game)
	var hard_result: Dictionary = results[Level.HARD]
	var easy_result: Dictionary = results[Level.EASY]
	s.check("Hard steps out of the impact column and is not hit by a bomb that falls on it", hard_result["hits"] == 0 and hard_result["gap"] > 100.0 and hard_result["stocks"] == 1, "hits=%d gap=%.0f" % [hard_result["hits"], hard_result["gap"]])
	s.check("Easy does not dodge: the same bomb hits it", easy_result["hits"] >= 1, "hits=%d" % easy_result["hits"])

func _first_bomb_hit_ticks(s: RefCounted, level: int, trial: int) -> int:
	var difficulty := CpuDifficulty.preset(level)
	var world := await _bomb_world(s, difficulty, 1.0, 300.0, 560.0, 100 + trial)
	var game: Game = world["game"]
	var fighter: Fighter = world["fighter"]
	var hits := _bomb_hits(fighter)
	var ticks := 0
	while hits.is_empty() and ticks < SURVIVAL_CAP_TICKS and fighter.stocks > 0:
		await s.frames(1)
		ticks += 1
	await _leave(s, game)
	return ticks

func _bomb_survival(s: RefCounted) -> void:
	var hard_total := 0
	var easy_total := 0
	for trial in SURVIVAL_TRIALS:
		hard_total += await _first_bomb_hit_ticks(s, Level.HARD, trial)
		easy_total += await _first_bomb_hit_ticks(s, Level.EASY, trial)
	var hard_mean := CombatClock.seconds(hard_total) / SURVIVAL_TRIALS
	var easy_mean := CombatClock.seconds(easy_total) / SURVIVAL_TRIALS
	print("INFO mean time to the first bomb hit (cap %.0f s): Hard %.1f s, Easy %.1f s" % [CombatClock.seconds(SURVIVAL_CAP_TICKS), hard_mean, easy_mean])
	s.check("under sudden death Hard survives longer than Easy before the first bomb hit", hard_mean > easy_mean, "hard=%.1f easy=%.1f" % [hard_mean, easy_mean])

func _air_dodge(s: RefCounted) -> void:
	var difficulty := CpuDifficulty.preset(Level.HARD)
	var world := await _bomb_world(s, difficulty, 1000.0, 100.0, 450.0, 61)
	var game: Game = world["game"]
	var fighter: Fighter = world["fighter"]
	var hits := _bomb_hits(fighter)
	fighter.position.y -= 480.0
	fighter.velocity = Vector2.ZERO
	fighter.state_machine.velocity = Vector2.ZERO
	await s.frames(4)
	# A bomb right above its head (a falling fighter outruns a bomb, so it is dropped
	# close) and a decision at once.
	game.hazards.spawn_bomb(fighter.position.x, fighter.position.y - 120.0)
	var cpu: ScriptedController = world["cpu"]
	cpu._think()
	var dodged := false
	for i in 60:
		await s.frames(1)
		dodged = dodged or s.state_of(fighter) == "AirDodge"
	s.check("an airborne CPU Hard air dodges a bomb that is about to hit it", dodged, "hits=%d" % hits.size())
	await _leave(s, game)

# --------------------------------------------------- Easy restrictions, taps

func _easy_and_taps(s: RefCounted) -> void:
	for level in [Level.EASY, Level.NORMAL, Level.HARD]:
		var difficulty := CpuDifficulty.preset(level)
		var label := "Easy" if level == Level.EASY else ("Normal" if level == Level.NORMAL else "Hard")
		var world := await _world(s, difficulty, 360.0, 500.0, 71)
		var game: Game = world["game"]
		var fighter: Fighter = world["fighter"]
		var enemy: Fighter = world["enemy"]
		var ctrl = world["enemy_ctrl"]
		game.sudden_death_intro = 0.0
		game.hazards.grace_time = 3.0
		game.force_sudden_death()
		enemy.grant_invulnerability(100000.0, false)
		var aim_or_special := 0
		var held := 0
		var stuck := 0
		var last_attack := false
		var last_block := false
		var last_throw := false
		for i in 1800:
			# The opponent cycles: shield, dizzy, shield again; food drops now and then.
			if i % 300 == 0:
				ctrl.block_held_level = true
				ctrl.press_block()
			elif i % 300 == 120:
				ctrl.block_held_level = false
				enemy.break_shield(null)
			if i % 450 == 10:
				var pickup: FoodPickup = load("res://game/food/food_pickup.tscn").instantiate()
				pickup.food_name = FoodCatalog.get_random_food_name()
				game.add_child(pickup)
				pickup.position = Vector2(fighter.position.x + 150.0, game.get_stage_bounds()["top"] - 30.0)
			await s.frames(1)
			var intent := fighter.intent
			if intent.aim != FighterIntent.Aim.NEUTRAL or intent.special_pressed:
				aim_or_special += 1
			if intent.attack_held:
				held += 1
			if (intent.attack_pressed and last_attack) or (intent.block_pressed and last_block) or (intent.throw_pressed and last_throw):
				stuck += 1
			last_attack = intent.attack_pressed
			last_block = intent.block_pressed
			last_throw = intent.throw_pressed
			if game.phase != Game.Phase.SUDDEN_DEATH:
				break
		if level == Level.EASY:
			s.check("CPU Easy never emits aim or special through shields, dizzies, food and bombs", aim_or_special == 0, "frames=%d" % aim_or_special)
		s.check("CPU %s never holds the attack key (taps only)" % label, held == 0, "frames=%d" % held)
		s.check("CPU %s never leaves a press stuck on for two frames" % label, stuck == 0, "frames=%d" % stuck)
		await _leave(s, game)
