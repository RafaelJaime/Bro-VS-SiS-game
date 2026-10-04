extends SceneTree
## CPU combos by difficulty (cpu-opponent spec), headless, on the real kits of
## game.tscn (Fighter1 Rafael, Fighter2 Matilde):
##   - Easy throws single jabs only: no chain step, no launcher follow-up, no aim, no
##     special, no charge, in any situation of a long seeded match;
##   - Normal chains, Hard chains and follows the up launcher with an air jab: seeded CPU
##     matches count the 2+ hit combos per minute and the longest combo of each level;
##   - the launcher follow-up rate (Hard against Normal) on a victim held above Matilde;
##   - the chain press works at a 0.40 s decision interval (it is event driven);
##   - no CPU ever holds attack, and it takes no action in ShieldDrop.
## Combos are read from the victim's combo_ended signal (hits, damage, attacker).

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const Level := CpuDifficulty.Level
const Aim := FighterIntent.Aim
const MATCH_SECONDS := 45
const SEEDS := [11, 12, 13]
const LEVEL_NAMES := {Level.EASY: "Easy", Level.NORMAL: "Normal", Level.HARD: "Hard"}

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self, 6000.0)
	_ordering(s)
	var stats := {}
	for level in [Level.EASY, Level.NORMAL, Level.HARD]:
		stats[level] = await _match_stats(s, level)
	_check_stats(s, stats)
	await _followup_trials(s)
	await _buffer_bridges_interval(s)
	await _shield_drop(s)
	s.finish()

# --------------------------------------------------------------- difficulty

func _ordering(s: RefCounted) -> void:
	var easy := CpuDifficulty.preset(Level.EASY)
	var normal := CpuDifficulty.preset(Level.NORMAL)
	var hard := CpuDifficulty.preset(Level.HARD)
	s.check("chain chance: Easy 0, Normal 0.75, Hard 0.95", is_zero_approx(easy.chain_chance) and is_equal_approx(normal.chain_chance, 0.75) and is_equal_approx(hard.chain_chance, 0.95))
	s.check("chain press delay: Normal 0.05 s, Hard 0.017 s", is_equal_approx(normal.chain_press_delay, 0.05) and is_equal_approx(hard.chain_press_delay, 0.017))
	s.check("launcher follow-up chance: Easy 0, Normal 0, Hard 0.8", is_zero_approx(easy.launcher_followup_chance) and is_zero_approx(normal.launcher_followup_chance) and is_equal_approx(hard.launcher_followup_chance, 0.8))
	s.check("combo difficulty ordering Easy <= Normal <= Hard, Normal < Hard for the follow-up", easy.chain_chance <= normal.chain_chance and normal.chain_chance <= hard.chain_chance and easy.launcher_followup_chance <= normal.launcher_followup_chance and normal.launcher_followup_chance < hard.launcher_followup_chance)
	s.check("Easy keeps the restrictions (no directional, no up recovery)", not easy.use_directional and not easy.use_up_recovery)

# ------------------------------------------------------------- seeded matches

## Two CPUs of `level` (Rafael against Matilde) for MATCH_SECONDS per seed, with stocks
## refilled so the match never ends. Returns the combo statistics and what the intents
## contained.
func _match_stats(s: RefCounted, level: int) -> Dictionary:
	var stats := {"seconds": 0.0, "combos": 0, "multi": 0, "max_combo": 0, "histogram": {}, "chain_hits": 0, "followups": 0, "launchers_matilde": 0, "followups_matilde": 0, "max_step": 0, "held": 0, "aim": 0, "special": 0, "shield_raises": 0, "launchers": 0}
	for rng_seed in SEEDS:
		GameRng.seed_all(Smoke.GAME_SEED + rng_seed)
		var game: Node2D = s.spawn_game(300.0, 560.0, false, true)
		var fighters: Array[Fighter] = [game.get_node("Fighter1"), game.get_node("Fighter2")]
		for side in 2:
			s.set_cpu(fighters[side], level, rng_seed * 10 + side)
		var log := Smoke.MatchLog.new(game, true)
		var raises_before := [fighters[0].shield_raises, fighters[1].shield_raises]
		for victim in fighters:
			victim.combo_ended.connect(func(hits: int, _damage: float, _by: Fighter) -> void:
				stats["combos"] += 1
				stats["multi"] += 1 if hits >= 2 else 0
				stats["max_combo"] = maxi(stats["max_combo"], hits)
				var key := str(hits) if hits < 7 else "7+"
				stats["histogram"][key] = int(stats["histogram"].get(key, 0)) + 1)
			victim.hit_received.connect(func(hit: Hit, outcome: int) -> void:
				if outcome != Combat.Outcome.FULL or hit.attack == null or hit.attacker == null:
					return
				var kit: FighterProfile = hit.attacker.profile
				var idx := kit.jab_chain.find(hit.attack)
				var air_idx := kit.air_jab_chain.find(hit.attack)
				if idx >= 1 or air_idx >= 1:
					stats["chain_hits"] += 1
				if hit.attack.direction == &"up":
					stats["launchers"] += 1
					stats["launchers_matilde"] += 1 if kit.kit_id == 1 else 0
				# An air jab thrown right after the attacker's own launcher: a follow-up.
				if air_idx == 0 and not hit.attacker.is_on_floor() and victim.combo.hits >= 2:
					stats["followups"] += 1
					stats["followups_matilde"] += 1 if kit.kit_id == 1 else 0)
		var ticks := MATCH_SECONDS * 60
		for tick in ticks:
			await s.frames(1)
			for fighter in fighters:
				var intent := fighter.intent
				stats["held"] += 1 if intent.attack_held else 0
				stats["aim"] += 1 if intent.aim != Aim.NEUTRAL else 0
				stats["special"] += 1 if intent.special_pressed else 0
				stats["max_step"] = maxi(stats["max_step"], fighter.state_machine.state_map["Punch"].chain_step())
		stats["seconds"] += float(ticks) / 60.0
		stats["shield_raises"] += (fighters[0].shield_raises - raises_before[0]) + (fighters[1].shield_raises - raises_before[1])
		await s.despawn(game)
	return stats

func _check_stats(s: RefCounted, stats: Dictionary) -> void:
	var rates := {}
	for level in stats:
		var st: Dictionary = stats[level]
		var minutes: float = st["seconds"] / 60.0 * 2.0
		rates[level] = float(st["multi"]) / (st["seconds"] / 60.0)
		print("INFO CPU %s (%d s, both fighters, %d seeds): %d combos, %d with 2+ hits (%.1f per match-minute), longest %d hits, histogram %s, chain-step hits %d, launchers %d (Matilde %d), air-jab follow-ups %d, shield raises per fighter-minute %.1f" % [LEVEL_NAMES[level], int(st["seconds"]), SEEDS.size(), st["combos"], st["multi"], rates[level], st["max_combo"], st["histogram"], st["chain_hits"], st["launchers"], st["launchers_matilde"], st["followups"], float(st["shield_raises"]) / minutes])
	var easy: Dictionary = stats[Level.EASY]
	s.check("Easy never throws a chain step or a launcher follow-up", easy["chain_hits"] == 0 and easy["max_step"] <= 1 and easy["followups"] == 0, "chain hits=%d max step=%d follow-ups=%d" % [easy["chain_hits"], easy["max_step"], easy["followups"]])
	s.check("Easy never uses directional aim, special or a held attack", easy["aim"] == 0 and easy["special"] == 0 and easy["held"] == 0, "aim=%d special=%d held=%d" % [easy["aim"], easy["special"], easy["held"]])
	s.check("no difficulty ever holds attack (taps only)", stats[Level.NORMAL]["held"] == 0 and stats[Level.HARD]["held"] == 0)
	s.check("Normal chains: its jab steps connect and it lands 2+ hit combos", stats[Level.NORMAL]["chain_hits"] > 0 and rates[Level.NORMAL] > 0.0, "chain hits=%d rate=%.2f" % [stats[Level.NORMAL]["chain_hits"], rates[Level.NORMAL]])
	s.check("Hard chains too", stats[Level.HARD]["chain_hits"] > 0 and rates[Level.HARD] > 0.0, "chain hits=%d rate=%.2f" % [stats[Level.HARD]["chain_hits"], rates[Level.HARD]])
	s.check("combo rate ordering: Easy <= Normal <= Hard", rates[Level.EASY] <= rates[Level.NORMAL] and rates[Level.NORMAL] <= rates[Level.HARD], "easy=%.2f normal=%.2f hard=%.2f" % [rates[Level.EASY], rates[Level.NORMAL], rates[Level.HARD]])
	s.check("no combo of any difficulty exceeds the 6-hit cap", stats[Level.EASY]["max_combo"] <= 6 and stats[Level.NORMAL]["max_combo"] <= 6 and stats[Level.HARD]["max_combo"] <= 6)

# -------------------------------------------------------- launcher follow-up

## Matilde (CPU of `level`) against a Rafael dummy held just above her, so the CPU throws
## the up launcher: how often the launcher is followed by a connecting air jab.
func _followup_trial(s: RefCounted, level: int, rng_seed: int) -> Dictionary:
	GameRng.seed_all(Smoke.GAME_SEED + rng_seed)
	var game: Node2D = s.spawn_game(400.0, 470.0, false, true)
	game.get_node("Fighter1").set_controller(Smoke.IntentController.new())
	var matilde: Fighter = game.get_node("Fighter2")
	var dummy: Fighter = game.get_node("Fighter1")
	s.set_cpu(matilde, level, rng_seed)
	await s.frames(90)
	var result := {"launcher": false, "followup": false, "combo": 0}
	dummy.hit_received.connect(func(hit: Hit, outcome: int) -> void:
		if outcome != Combat.Outcome.FULL or hit.attack == null:
			return
		if hit.attack.direction == &"up":
			result["launcher"] = true
		elif result["launcher"] and not matilde.is_on_floor() and matilde.profile.air_jab_chain.has(hit.attack):
			result["followup"] = true
			result["combo"] = maxi(result["combo"], dummy.combo.hits))
	var anchor := Vector2(matilde.position.x - 45.0, matilde.position.y - 110.0)
	for tick in 240:
		# The dummy hangs above Matilde until the launcher connects.
		if not result["launcher"]:
			dummy.position = anchor
			dummy.velocity = Vector2.ZERO
			dummy.state_machine.velocity = Vector2.ZERO
		await s.frames(1)
	await s.despawn(game)
	return result

func _followup_trials(s: RefCounted) -> void:
	var rates := {}
	for level in [Level.NORMAL, Level.HARD]:
		var launchers := 0
		var followups := 0
		for trial in 24:
			var r: Dictionary = await _followup_trial(s, level, 100 + trial)
			launchers += 1 if r["launcher"] else 0
			followups += 1 if r["followup"] else 0
		rates[level] = float(followups) / float(maxi(1, launchers))
		print("INFO CPU %s launcher follow-up: %d launchers, %d followed by a connecting air jab (%.0f%%)" % [LEVEL_NAMES[level], launchers, followups, rates[level] * 100.0])
		rates["launchers_%d" % level] = launchers
	s.check("the CPU lands the up launcher on a victim above it", rates["launchers_%d" % Level.HARD] >= 8, "hard launchers=%d" % rates["launchers_%d" % Level.HARD])
	s.check("Hard follows the launcher with an air jab at a rate greater than Normal's", rates[Level.HARD] > rates[Level.NORMAL] and rates[Level.HARD] > 0.3, "hard=%.2f normal=%.2f" % [rates[Level.HARD], rates[Level.NORMAL]])
	s.check("Normal has no follow-up at all", is_zero_approx(rates[Level.NORMAL]))

# ------------------------------------------------- the buffer bridges the interval

# A CPU that reads the match 2.5 times a second still chains: the press follows the
# connecting hit (event driven), and waits in the attack buffer for the link window.
func _buffer_bridges_interval(s: RefCounted) -> void:
	var slow := CpuDifficulty.preset(Level.NORMAL)
	slow.decision_interval = 0.40
	slow.chain_chance = 1.0
	slow.chain_press_delay = 0.017
	slow.action_accuracy = 1.0
	var steps := 0
	# Lambdas capture locals by value: the counter lives in a Dictionary.
	var seen := {"chain_hits": 0}
	var held := 0
	for trial in 6:
		GameRng.seed_all(Smoke.GAME_SEED + trial)
		var game: Node2D = s.spawn_game(400.0, 470.0, false, true)
		game.get_node("Fighter2").set_controller(Smoke.IntentController.new())
		var rafael: Fighter = game.get_node("Fighter1")
		rafael.set_controller(ScriptedController.new(slow, 50 + trial))
		var victim: Fighter = game.get_node("Fighter2")
		victim.hit_received.connect(func(hit: Hit, outcome: int) -> void:
			if outcome == Combat.Outcome.FULL and rafael.profile.jab_chain.find(hit.attack) >= 1:
				seen["chain_hits"] += 1)
		await s.frames(90)
		for tick in 150:
			await s.frames(1)
			steps = maxi(steps, rafael.state_machine.state_map["Punch"].chain_step())
			held += 1 if rafael.intent.attack_held else 0
			victim.stocks = Fighter.MAX_STOCKS
		await s.despawn(game)
	s.check("a 0.40 s decision interval still chains (the press is event driven)", steps == 2 and seen["chain_hits"] >= 3, "max step=%d step-2 hits=%d" % [steps, seen["chain_hits"]])
	s.check("the chain press is a tap, never a held attack", held == 0)

# ------------------------------------------------------------- shield drop lag

# A CPU in ShieldDrop emits no action intent until the lag ends.
func _shield_drop(s: RefCounted) -> void:
	for level in [Level.NORMAL, Level.HARD]:
		var game: Node2D = s.spawn_game(400.0, 470.0, false, true)
		var fighter: Fighter = game.get_node("Fighter1")
		s.set_cpu(fighter, level, 5)
		game.get_node("Fighter2").set_controller(Smoke.IntentController.new())
		await s.frames(90)
		fighter.state_machine._change_state("ShieldDrop")
		var drop_ticks := 0
		var presses := 0
		for tick in 20:
			await s.frames(1)
			if s.state_of(fighter) != "ShieldDrop":
				break
			drop_ticks += 1
			var intent := fighter.intent
			presses += 1 if (intent.attack_pressed or intent.jump_pressed or intent.block_pressed or intent.dash_pressed or intent.throw_pressed or intent.special_pressed) else 0
		s.check("%s CPU takes no action in ShieldDrop" % LEVEL_NAMES[level], drop_ticks >= 5 and presses == 0, "ticks in drop lag=%d presses=%d" % [drop_ticks, presses])
		await s.despawn(game)
