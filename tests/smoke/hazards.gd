extends SceneTree
## Sudden-death bombs: grace period and escalation counted in physics ticks, the
## spawn schedule, telegraph, unblockable lethal hits (once per bomb and fighter),
## Game-local behaviour, cleanup, the "sudden death always ends" guarantee, the
## double-KO restart, no cap in a real match and the training-only safety cap.

const Smoke := preload("res://tests/smoke/smoke_util.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self, 6000.0)
	await _grace_and_first_bomb(s)
	await _schedule_and_cap(s)
	await _snapshot_phases(s)
	await _telegraph(s)
	await _unblockable_against_shield(s)
	await _one_hit_per_bomb(s)
	await _respawn_invulnerability(s)
	await _lethal_at_300(s)
	await _two_games(s)
	await _forced_sudden_deaths(s)
	await _turtle(s)
	await _double_ko_restart(s)
	await _real_match_has_no_cap(s)
	await _training_cap(s)
	s.finish()

# A Game in regulation time, no random food, controllers attached.
func _game(s: RefCounted, p1_x: float = 330.0, p2_x: float = 700.0) -> Array:
	var game: Game = s.spawn_game(p1_x, p2_x)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(1)
	game.food_spawner.stop()
	# Let the fighters land, so a block is a shield and not an air dodge.
	await s.frames(60)
	return [game, controllers]

# A Game forced into sudden death with no intro, `grace` seconds of grace.
func _sd_game(s: RefCounted, grace: float, harmless: bool = false, p1_x: float = 330.0, p2_x: float = 700.0) -> Array:
	var setup := await _game(s, p1_x, p2_x)
	var game: Game = setup[0]
	game.sudden_death_intro = 0.0
	game.hazards.grace_time = grace
	if harmless:
		game.hazards.bomb_damage = 0.0
		game.hazards.bomb_knockback = Vector2.ZERO
	game.force_sudden_death()
	return setup

func _leave(s: RefCounted, game: Node) -> void:
	Combat.cancel_hit_stop()
	paused = false
	await s.despawn(game)

func _bombs(game: Game) -> int:
	return game.hazards.alive_count()

# ------------------------------------------------------------------ timing

func _first_bomb_ticks(s: RefCounted, wobble: bool) -> int:
	var setup := await _sd_game(s, 20.0, true)
	var game: Game = setup[0]
	var start := Engine.get_physics_frames()
	var no_bomb_during_grace := true
	var guard := 0
	while game.hazards.bombs_spawned == 0 and guard < 4000:
		await s.frames(1)
		guard += 1
		if wobble:
			# Hit-stop style: the clock keeps changing under the grace period.
			Engine.time_scale = 0.3 if (guard / 100) % 2 == 0 else 1.0
		var ticks := Engine.get_physics_frames() - start
		if ticks < 1195 and game.hazards.bombs_spawned > 0:
			no_bomb_during_grace = false
	var ticks := Engine.get_physics_frames() - start
	Engine.time_scale = 1.0
	s.check("no bomb falls during the grace period", no_bomb_during_grace and game.get_state_snapshot()["bombs"].size() <= 1)
	await _leave(s, game)
	return ticks

func _grace_and_first_bomb(s: RefCounted) -> void:
	var setup := await _game(s)
	var game: Game = setup[0]
	await s.frames(900)
	s.check("no bombs exist in regulation time", game.hazards.bombs_spawned == 0 and game.hazards.alive_count() == 0 and not game.hazards.is_active() and game.hazards.phase() == 0)
	await _leave(s, game)

	var plain: int = await _first_bomb_ticks(s, false)
	s.check("the first bomb spawns after the 20 s grace (1200 ticks)", absi(plain - 1200) <= 1, "ticks=%d" % plain)
	var wobbling: int = await _first_bomb_ticks(s, true)
	s.check("the first-bomb tick count is the same with the clock changing (hit-stop)", wobbling == plain, "plain=%d wobbling=%d" % [plain, wobbling])

func _schedule_and_cap(s: RefCounted) -> void:
	var setup := await _sd_game(s, 1.0, true)
	var game: Game = setup[0]
	var hazards: SuddenDeathHazards = game.hazards
	var most_alive := 0
	for i in 3000:
		await s.frames(1)
		most_alive = maxi(most_alive, hazards.alive_count())
	var intervals := hazards.spawn_intervals
	var monotonic := true
	var floor_ok := true
	for i in intervals.size():
		floor_ok = floor_ok and intervals[i] >= CombatClock.ticks(hazards.min_interval)
		if i > 0:
			monotonic = monotonic and intervals[i] <= intervals[i - 1]
	s.check("the first gap is about 2 s and the intervals never grow", intervals.size() > 10 and intervals[0] == CombatClock.ticks(hazards.start_interval) and monotonic, "intervals=%s" % [intervals.slice(0, 12)])
	s.check("the interval never goes below the 24-tick floor and reaches it", floor_ok and intervals[-1] == 24, "last=%d" % intervals[-1])
	s.check("at most max_alive (6) bombs at once", most_alive <= 6 and most_alive >= 3, "most=%d" % most_alive)
	await _leave(s, game)

	var capped_setup := await _sd_game(s, 1.0, true)
	var capped: Game = capped_setup[0]
	capped.hazards.max_alive = 2
	var capped_most := 0
	for i in 1500:
		await s.frames(1)
		capped_most = maxi(capped_most, capped.hazards.alive_count())
	s.check("the simultaneous cap binds (never more than 2, and 2 is reached)", capped_most == 2, "most=%d" % capped_most)
	await _leave(s, capped)

func _snapshot_phases(s: RefCounted) -> void:
	var setup := await _game(s)
	var game: Game = setup[0]
	var idle: Dictionary = game.get_state_snapshot()
	s.check("regulation snapshot: phase 0, elapsed 0, no bombs", idle["sudden_death_phase"] == 0 and idle["sudden_death_elapsed"] == 0.0 and idle["bombs"] == [])
	game.sudden_death_intro = 0.0
	game.hazards.grace_time = 1.0
	game.hazards.bomb_damage = 0.0
	game.hazards.bomb_knockback = Vector2.ZERO
	game.force_sudden_death()
	await s.frames(30)
	var grace: Dictionary = game.get_state_snapshot()
	s.check("grace snapshot: phase 1, positive elapsed, no bombs", grace["sudden_death_phase"] == 1 and grace["sudden_death_elapsed"] > 0.0 and grace["bombs"] == [], "phase=%d elapsed=%.2f" % [grace["sudden_death_phase"], grace["sudden_death_elapsed"]])
	await s.frames(45)
	var live: Dictionary = game.get_state_snapshot()
	var bomb_ok: bool = live["bombs"].size() >= 1 and live["bombs"][0].has("position") and live["bombs"][0].has("velocity") and is_equal_approx(live["bombs"][0]["velocity"].y, game.hazards.fall_speed)
	s.check("bomb snapshot: phase 2 and entries with Game-local position and velocity", live["sudden_death_phase"] == 2 and bomb_ok, "phase=%d bombs=%s" % [live["sudden_death_phase"], live["bombs"]])
	var before: Array = game.get_state_snapshot()["bombs"].duplicate(true)
	var again: Array = game.get_state_snapshot()["bombs"]
	s.check("the bomb snapshot is read-only (two reads agree)", before == again)
	await _leave(s, game)

func _telegraph(s: RefCounted) -> void:
	var setup := await _game(s)
	var game: Game = setup[0]
	var hazards: SuddenDeathHazards = game.hazards
	s.check("the default telegraph is at least 1 s", hazards.telegraph_seconds() >= hazards.min_telegraph, "telegraph=%.2f" % hazards.telegraph_seconds())
	var bomb := hazards.spawn_bomb(520.0)
	var table_top: float = game.get_stage_bounds()["top"]
	s.check("a bomb spawns far above the table, so its fall is the telegraph", bomb.position.y <= table_top - 700.0 and bomb.position.y < game.get_node("Fighter1").position.y - 500.0, "y=%.0f top=%.0f" % [bomb.position.y, table_top])
	var start := Engine.get_physics_frames()
	var guard := 0
	while is_instance_valid(bomb) and not bomb.is_queued_for_deletion() and guard < 400:
		await s.frames(1)
		guard += 1
	var fall_ticks := Engine.get_physics_frames() - start
	s.check("a bomb is visible falling for at least a second before it lands", fall_ticks >= 60, "ticks=%d" % fall_ticks)
	await _leave(s, game)

# --------------------------------------------------------------------- hits

func _bomb_hits(fighter: Fighter) -> Array:
	var hits: Array = []
	fighter.hit_received.connect(func(hit: Hit, outcome: int) -> void:
		if hit.source == Hit.Source.BOMB:
			hits.append(outcome))
	return hits

func _unblockable_against_shield(s: RefCounted) -> void:
	var setup := await _game(s, 400.0, 700.0)
	var game: Game = setup[0]
	var shielder: Fighter = game.get_node("Fighter1")
	var ctrl = setup[1][0]
	var hits := _bomb_hits(shielder)
	ctrl.block_held_level = true
	ctrl.press_block()
	await s.frames(4)
	var meter := shielder.shield.value
	game.hazards.spawn_bomb(shielder.position.x, shielder.position.y - 140.0)
	await s.frames(30)
	s.check("a bomb hits a shielding fighter in full (FULL, not BLOCKED)", hits == [Combat.Outcome.FULL], "hits=%s" % [hits])
	s.check("the shield does not stop the bomb: full damage, no meter drain from it", shielder.damage_percent >= 12.0 and meter - shielder.shield.value < 2.0, "damage=%.1f meter %.1f -> %.1f" % [shielder.damage_percent, meter, shielder.shield.value])
	await _leave(s, game)

func _one_hit_per_bomb(s: RefCounted) -> void:
	var setup := await _game(s, 400.0, 700.0)
	var game: Game = setup[0]
	var target: Fighter = game.get_node("Fighter1")
	var hits := _bomb_hits(target)
	# Spawned right on the hurtbox, so it overlaps for as long as it could.
	game.hazards.spawn_bomb(target.position.x, target.position.y)
	await s.frames(60)
	s.check("a bomb on a fighter hits it exactly once", hits.size() == 1, "hits=%s" % [hits])
	s.check("the bomb is gone after it went off", _bombs(game) == 0)
	await _leave(s, game)

func _respawn_invulnerability(s: RefCounted) -> void:
	var setup := await _game(s, 400.0, 700.0)
	var game: Game = setup[0]
	var target: Fighter = game.get_node("Fighter1")
	var hits := _bomb_hits(target)
	target.grant_invulnerability(3.0)
	game.hazards.spawn_bomb(target.position.x, target.position.y - 140.0)
	await s.frames(40)
	s.check("an invulnerable fighter is not hit by a bomb", hits == [Combat.Outcome.IGNORED] and target.damage_percent == 0.0 and s.state_of(target) != "Hurt", "hits=%s damage=%.1f" % [hits, target.damage_percent])
	await _leave(s, game)

func _lethal_at_300(s: RefCounted) -> void:
	var setup := await _sd_game(s, 100.0, false, 400.0, 700.0)
	var game: Game = setup[0]
	var victim: Fighter = game.get_node("Fighter1")
	await s.frames(5)
	s.check("sudden death sets 300% and one stock", is_equal_approx(victim.damage_percent, 300.0) and victim.stocks == 1)
	game.hazards.spawn_bomb(victim.position.x, victim.position.y - 140.0)
	var ticks := 0
	while victim.stocks > 0 and ticks < 240:
		await s.frames(1)
		ticks += 1
	s.check("a bomb on a 300% fighter with no input is a KO within 3 s", victim.stocks == 0 and ticks <= 180, "ticks=%d" % ticks)
	await s.frames(3)
	s.check("the KO ends the match and clears the bombs", game.phase == Game.Phase.OVER and game.winner == game.get_node("Fighter2") and game.hazards.get_child_count() == 0 and not game.hazards.is_active(), "phase=%d children=%d" % [game.phase, game.hazards.get_child_count()])
	await _leave(s, game)

# ------------------------------------------------------------- Game-local

func _two_games(s: RefCounted) -> void:
	var a := await _sd_game(s, 0.5, true)
	var game_a: Game = a[0]
	var b := await _sd_game(s, 0.5, true)
	var game_b: Game = b[0]
	game_b.position = Vector2(2400.0, 900.0)
	game_a.hazards.seed_rng(777)
	game_b.hazards.seed_rng(777)
	# Both have been in sudden death for the same ticks (forced within one frame).
	game_a.force_sudden_death()
	game_b.force_sudden_death()
	game_a.hazards.seed_rng(777)
	game_b.hazards.seed_rng(777)
	var same := true
	var in_bounds := true
	var compared := 0
	var hits_a := _bomb_hits(game_a.get_node("Fighter1"))
	var hits_b := _bomb_hits(game_b.get_node("Fighter1"))
	for i in 600:
		await s.frames(1)
		var bombs_a: Array = game_a.get_state_snapshot()["bombs"]
		var bombs_b: Array = game_b.get_state_snapshot()["bombs"]
		if bombs_a.size() != bombs_b.size():
			same = false
		else:
			for j in bombs_a.size():
				compared += 1
				if not (bombs_a[j]["position"] as Vector2).is_equal_approx(bombs_b[j]["position"]) and (bombs_a[j]["position"] as Vector2).distance_to(bombs_b[j]["position"]) > 0.05:
					same = false
		for child in game_b.hazards.get_children():
			if child is Bomb and (child.global_position.x < 2400.0 or child.global_position.y < 900.0 - 900.0):
				in_bounds = false
		for child in game_a.hazards.get_children():
			if child is Bomb and child.global_position.x > 1500.0:
				in_bounds = false
	s.check("two Games at different offsets drop identical Game-local bombs", same and compared > 20, "compared=%d" % compared)
	s.check("each Game's bombs stay inside its own bounds", in_bounds)
	s.check("each Game's bombs only hit its own fighters (the same hit sequence)", hits_a == hits_b and hits_a.size() > 0, "a=%s b=%s" % [hits_a, hits_b])
	await _leave(s, game_a)
	await _leave(s, game_b)

# ----------------------------------------------------------- always ends

func _forced_sudden_deaths(s: RefCounted) -> void:
	var ended := 0
	var total_after_grace := 0
	var worst := 0
	for i in 20:
		var setup := await _sd_game(s, 2.0)
		var game: Game = setup[0]
		var grace_ticks := CombatClock.ticks(game.hazards.grace_time)
		var last_elapsed := 0
		var guard := 0
		while game.phase == Game.Phase.SUDDEN_DEATH and guard < 4000:
			last_elapsed = game.hazards.elapsed_ticks
			await s.frames(1)
			guard += 1
		if game.phase == Game.Phase.OVER and game.winner != null:
			ended += 1
			total_after_grace += last_elapsed - grace_ticks
			worst = maxi(worst, last_elapsed - grace_ticks)
		await _leave(s, game)
	s.check("20 forced sudden deaths between idle fighters all end in a KO", ended == 20, "ended=%d" % ended)
	var mean_seconds := CombatClock.seconds(total_after_grace) / 20.0
	s.check("the mean time from the first bomb to the KO is well under 20 s", mean_seconds < 20.0, "mean=%.1f s worst=%.1f s" % [mean_seconds, CombatClock.seconds(worst)])

func _turtle(s: RefCounted) -> void:
	var setup := await _sd_game(s, 2.0)
	var game: Game = setup[0]
	var outcomes: Array = []
	for fighter_name in ["Fighter1", "Fighter2"]:
		(game.get_node(fighter_name) as Fighter).hit_received.connect(func(hit: Hit, outcome: int) -> void:
			if hit.source == Hit.Source.BOMB:
				outcomes.append(outcome))
	setup[1][0].block_held_level = true
	setup[1][1].block_held_level = true
	setup[1][0].press_block()
	setup[1][1].press_block()
	var guard := 0
	while game.phase == Game.Phase.SUDDEN_DEATH and guard < 5000:
		# Keep the shield up whenever a break let it drop.
		if guard % 30 == 0:
			setup[1][0].press_block()
			setup[1][1].press_block()
		await s.frames(1)
		guard += 1
	s.check("two fighters holding the shield cannot stall: bombs end it in a KO", game.phase == Game.Phase.OVER and game.winner != null, "phase=%d ticks=%d" % [game.phase, guard])
	s.check("no bomb was ever blocked or drained a shield", outcomes.all(func(o): return o == Combat.Outcome.FULL or o == Combat.Outcome.IGNORED) and outcomes.size() > 0, "outcomes=%s" % [outcomes])
	await _leave(s, game)

func _double_ko_restart(s: RefCounted) -> void:
	var setup := await _sd_game(s, 1.0, true)
	var game: Game = setup[0]
	var f1: Fighter = game.get_node("Fighter1")
	var f2: Fighter = game.get_node("Fighter2")
	var guard := 0
	while game.hazards.bombs_spawned < 2 and guard < 400:
		await s.frames(1)
		guard += 1
	s.check("bombs are falling before the double KO", game.hazards.alive_count() > 0 and game.hazards.phase() == 2)
	f1.position = Vector2(f1.blast_zone.position.x - 80.0, 300.0)
	f2.position = Vector2(f2.blast_zone.position.x - 80.0, 300.0)
	await s.frames(4)
	s.check("a double KO restarts sudden death instead of ending the match", game.phase == Game.Phase.SUDDEN_DEATH and game.winner == null and not game.game_over.visible)
	s.check("both fighters are back at 1 stock and 300%", f1.stocks == 1 and f2.stocks == 1 and is_equal_approx(f1.damage_percent, 300.0) and is_equal_approx(f2.damage_percent, 300.0), "%d/%d" % [f1.stocks, f2.stocks])
	s.check("the bombs are cleared and the grace period restarted", game.hazards.alive_count() == 0 and game.hazards.phase() == 1 and game.hazards.elapsed_ticks < 30, "alive=%d phase=%d elapsed=%d" % [game.hazards.alive_count(), game.hazards.phase(), game.hazards.elapsed_ticks])
	await s.frames(CombatClock.ticks(game.hazards.grace_time) + 10)
	s.check("the escalation runs again after the restart", game.hazards.bombs_spawned >= 1 and game.hazards.phase() == 2)
	await _leave(s, game)

func _real_match_has_no_cap(s: RefCounted) -> void:
	var setup := await _sd_game(s, 1.0, true)
	var game: Game = setup[0]
	var caps: Array = []
	var finished: Array = []
	game.hazards.training_cap_reached.connect(func() -> void: caps.append(true))
	game.match_over.connect(func(_winner: Fighter) -> void: finished.append(true))
	await s.frames(7200)
	s.check("a real sudden death 120 s in is still running with bombs falling", game.phase == Game.Phase.SUDDEN_DEATH and game.winner == null and finished.is_empty() and game.hazards.phase() == 2 and game.hazards.bombs_spawned > 50, "phase=%d spawned=%d" % [game.phase, game.hazards.bombs_spawned])
	s.check("no safety cap fires in a real match", caps.is_empty())
	await _leave(s, game)

func _training_cap(s: RefCounted) -> void:
	var game: Game = load(Smoke.GAME_SCENE).instantiate()
	game.training = true
	root.add_child(game)
	s.attach_controllers(game)
	await s.frames(3)
	game.food_spawner.stop()
	game.hazards.bomb_damage = 0.0
	game.hazards.bomb_knockback = Vector2.ZERO
	var caps: Array = []
	var episodes: Array = []
	game.hazards.training_cap_reached.connect(func() -> void: caps.append(Engine.get_physics_frames()))
	game.training_episode_ended.connect(func(winner: Fighter) -> void: episodes.append(winner))
	game.force_sudden_death()
	var start := Engine.get_physics_frames()
	s.check("a training sudden death starts at once, without an intro", game.phase == Game.Phase.SUDDEN_DEATH and game.hazards.is_active() and game.hazards.phase() == 1)
	await s.frames(3500)
	s.check("the training cap has not fired before 3600 ticks", caps.is_empty())
	await s.frames(200)
	s.check("the training cap fires once at 3600 ticks", caps.size() == 1 and absi((caps[0] - start) - 3600) <= 2, "caps=%s start=%d" % [caps, start])
	s.check("the cap ends the episode as a draw with the sd_cap reason", episodes.size() == 1 and episodes[0] == null and game.last_episode_end_reason == &"sd_cap", "episodes=%s reason=%s" % [episodes, game.last_episode_end_reason])
	s.check("the row is reset: back to PLAYING, no bombs, no sudden death", game.phase == Game.Phase.PLAYING and not game.hazards.is_active() and game.hazards.get_child_count() == 0 and not game.get_state_snapshot()["sudden_death"])
	await s.frames(600)
	s.check("the cap does not fire again after the reset", caps.size() == 1 and episodes.size() == 1)
	await _leave(s, game)
