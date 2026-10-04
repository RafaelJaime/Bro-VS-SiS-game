extends SceneTree
## Per-attack frame data and jab chains, headless, in physics ticks.
##   - the baseline attack resolves to the legacy 3 / 9 / 6 / 42 ticks;
##   - a code-built chain: one press per step, holding never chains, an early press
##     queues and fires when the link opens, a press after the link closes does not
##     chain, the finisher launches, a non-neutral press is left for a new attack,
##     the Hit carries the attack and its hit-stop scale;
##   - a frame-advantage probe that measures the engine's hit latency and the slack
##     of every link (design D6: slack = stun - active - next startup - 2).
## Tick numbers are observation indices: tick 0 is the tick the first press fires.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const Aim := FighterIntent.Aim

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	_baseline_frames(s)
	await _chain_rules(s)
	await _frame_advantage(s)
	s.finish()

# ----------------------------------------------------------------- fixtures

func _attack(damage: float, knockback: Vector2) -> AttackProfile:
	return AttackProfile.make(damage, knockback, Vector2(75.0, -10.0), Vector2(110.0, 40.0), &"neutral")

## Rafael's 2-hit jab (design D10): the jab links with a slack of 2 ticks.
func _rafael_chain(link: int = 10) -> Array[AttackProfile]:
	var chain: Array[AttackProfile] = []
	chain.append(AttackProfile.frames(_attack(4.0, Vector2(70.0, -30.0)), 4, 2, 10, link, 0, 11, 0.0, 0.5))
	chain.append(AttackProfile.frames(_attack(8.0, Vector2(260.0, -180.0)), 5, 3, 16, 0, 0, -1, 0.0, 1.0))
	return chain

## Matilde's 3-hit jab: slack 4 and 3 ticks.
func _matilde_chain() -> Array[AttackProfile]:
	var chain: Array[AttackProfile] = []
	chain.append(AttackProfile.frames(_attack(2.5, Vector2(50.0, -20.0)), 3, 2, 9, 9, 0, 11, 0.0, 0.5))
	chain.append(AttackProfile.frames(_attack(2.5, Vector2(50.0, -20.0)), 3, 2, 9, 9, 0, 11, 0.0, 0.5))
	chain.append(AttackProfile.frames(_attack(4.0, Vector2(240.0, -200.0)), 4, 3, 14, 0, 0, -1, 0.0, 1.0))
	return chain

func _setup(s: RefCounted, chain: Array[AttackProfile]) -> Array:
	var game: Node2D = s.spawn_game(400.0, 470.0)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(90)
	var attacker: Fighter = game.get_node("Fighter1")
	attacker.profile.jab_chain = chain
	return [game, controllers, attacker, game.get_node("Fighter2")]

## Runs `count` ticks. `presses` maps a tick to the aim held for that press. Returns
## per-tick traces: the attacker's chain step and state, the victim's damage and
## state, plus the hits the victim received.
func _trace(s: RefCounted, setup: Array, count: int, presses: Dictionary, hold_from: int = -1) -> Dictionary:
	var ctrl = setup[1][0]
	var attacker: Fighter = setup[2]
	var victim: Fighter = setup[3]
	var punch = attacker.state_machine.state_map["Punch"]
	var hits: Array = []
	var on_hit := func(hit: Hit, outcome: int) -> void:
		hits.append({"attack": hit.attack, "scale": hit.hitstop_scale, "outcome": outcome, "vy": victim.velocity.y})
	victim.hit_received.connect(on_hit)
	var steps: Array[int] = []
	var states: Array[String] = []
	var victim_states: Array[String] = []
	var damage: Array[float] = []
	var vy_after_hit: Array[float] = []
	for i in count:
		if hold_from >= 0 and i >= hold_from:
			ctrl.attack_held_level = true
		if presses.has(i):
			ctrl.aim = presses[i]
			ctrl.press_punch()
		else:
			ctrl.aim = Aim.NEUTRAL
		await s.frames(1)
		steps.append(punch.chain_step())
		states.append(s.state_of(attacker))
		victim_states.append(s.state_of(victim))
		damage.append(victim.damage_percent)
		vy_after_hit.append(victim.velocity.y)
	victim.hit_received.disconnect(on_hit)
	ctrl.attack_held_level = false
	ctrl.aim = Aim.NEUTRAL
	return {"steps": steps, "states": states, "victim_states": victim_states, "damage": damage, "hits": hits, "vy": vy_after_hit}

func _first(values: Array, wanted) -> int:
	return values.find(wanted)

## Observation indices on which the victim's damage went up.
func _hit_ticks(damage: Array) -> Array[int]:
	var ticks: Array[int] = []
	var previous := 0.0
	for i in damage.size():
		if damage[i] > previous:
			ticks.append(i)
		previous = damage[i]
	return ticks

# ----------------------------------------------------------------- baseline

func _baseline_frames(s: RefCounted) -> void:
	var fighter := FighterProfile.new()
	var legacy := AttackProfile.make(8.0, Vector2(220.0, -120.0), Vector2(75.0, -10.0), Vector2(110.0, 40.0), &"neutral").resolved_frames(fighter)
	s.check("baseline: the neutral punch resolves to startup 3, active 9, endlag 6", legacy["startup"] == 3 and legacy["active"] == 9 and legacy["endlag"] == 6, "frames=%s" % [legacy])
	s.check("baseline: the cooldown is 42 ticks from the press and there is no link window", legacy["cooldown"] == 42 and legacy["link_window"] == 0, "frames=%s" % [legacy])
	var side := fighter.attack_side.resolved_frames(fighter)
	s.check("baseline: every directional punch has the same legacy frames", side["startup"] == 3 and side["active"] == 9 and side["endlag"] == 6 and side["cooldown"] == 42, "frames=%s" % [side])
	var overridden := fighter.attack_up.resolved_frames(fighter, 0.5, 0.0)
	s.check("baseline: the node overrides (duration 0.5 s, cooldown 0) still work", overridden["startup"] == 5 and overridden["active"] == 15 and overridden["endlag"] == 10 and overridden["cooldown"] == 0, "frames=%s" % [overridden])
	var chain := _rafael_chain()
	var first := chain[0].resolved_frames(fighter)
	s.check("an attack with frame data uses it, not the legacy numbers", first["startup"] == 4 and first["active"] == 2 and first["endlag"] == 10 and first["cooldown"] == 0 and first["link_window"] == 10, "frames=%s" % [first])
	s.check("the baseline profile has no chain and no kit single", fighter.jab_chain.is_empty() and fighter.air_jab_chain.is_empty() and fighter.neutral_single == null and fighter.kit_id == -1 and fighter.launcher_followup == &"none")

# ------------------------------------------------------------------- chains

func _chain_rules(s: RefCounted) -> void:
	# One press: the first jab and nothing else.
	var setup := await _setup(s, _rafael_chain())
	var single := await _trace(s, setup, 30, {0: Aim.NEUTRAL})
	var jab_ticks: int = single["states"].count("Punch")
	s.check("one press throws only the first jab (4 + 2 + 10 ticks)", jab_ticks == 16 and single["steps"].max() == 1, "punch ticks=%d max step=%d" % [jab_ticks, single["steps"].max()])
	s.check("the first jab's Hit carries its attack and the jab hit-stop scale 0.5", single["hits"].size() == 1 and single["hits"][0]["attack"] == setup[2].profile.jab_chain[0] and is_equal_approx(single["hits"][0]["scale"], 0.5), "hits=%d" % single["hits"].size())
	await s.real_wait(0.3)
	s.check("the jab hit-stop ends and the clock returns to 1.0", is_equal_approx(Engine.time_scale, 1.0), "time_scale=%.2f" % Engine.time_scale)
	await s.despawn(setup[0])

	# A second press inside the link window: the second step, the finisher.
	setup = await _setup(s, _rafael_chain())
	var chained := await _trace(s, setup, 40, {0: Aim.NEUTRAL, 8: Aim.NEUTRAL})
	s.check("a press inside the link window starts step 2", chained["steps"].max() == 2 and _first(chained["steps"], 2) == 8, "first step 2 at %d" % _first(chained["steps"], 2))
	s.check("both steps connect: 4 + 8 damage", is_equal_approx(setup[3].damage_percent, 12.0), "damage=%.1f" % setup[3].damage_percent)
	var second_attack: AttackProfile = setup[2].profile.jab_chain[1]
	s.check("the second hit carries the finisher's attack and full hit-stop", chained["hits"].size() == 2 and chained["hits"][1]["attack"] == second_attack and is_equal_approx(chained["hits"][1]["scale"], 1.0))
	var launch_index: int = _hit_ticks(chained["damage"])[1]
	s.check("the finisher launches the victim upward", chained["vy"][launch_index] < -150.0, "vy=%.0f" % chained["vy"][launch_index])
	await s.despawn(setup[0])

	# An early press queues and fires the moment the link opens (tick 4 + 2 + 1).
	setup = await _setup(s, _rafael_chain())
	var early := await _trace(s, setup, 40, {0: Aim.NEUTRAL, 1: Aim.NEUTRAL})
	s.check("an early press queues and fires when the link opens", _first(early["steps"], 2) == 7, "step 2 at %d (open at 7)" % _first(early["steps"], 2))
	await s.despawn(setup[0])

	# Holding the key after the press never chains.
	setup = await _setup(s, _rafael_chain())
	var held := await _trace(s, setup, 40, {0: Aim.NEUTRAL}, 1)
	s.check("holding the key never chains", held["steps"].max() == 1 and held["states"].count("Punch") == 16, "max step=%d punch ticks=%d" % [held["steps"].max(), held["states"].count("Punch")])
	await s.despawn(setup[0])

	# A press after the link closed (window 7..12 here) is a new attack, not step 2.
	setup = await _setup(s, _rafael_chain(6))
	var late := await _trace(s, setup, 50, {0: Aim.NEUTRAL, 14: Aim.NEUTRAL})
	var restarted: bool = late["steps"].slice(16).has(1)
	s.check("a press after the link window does not chain", late["steps"].max() == 1 and restarted, "max step=%d restarted=%s" % [late["steps"].max(), restarted])
	await s.despawn(setup[0])

	# A press with another aim is not consumed by the chain: it fires a new attack.
	setup = await _setup(s, _rafael_chain())
	var other := await _trace(s, setup, 45, {0: Aim.NEUTRAL, 12: Aim.UP})
	s.check("an up press during a step is not consumed by the chain", other["steps"].max() == 1 and setup[2].last_attack_direction == &"up", "max step=%d last=%s" % [other["steps"].max(), setup[2].last_attack_direction])
	await s.despawn(setup[0])

# -------------------------------------------------------- frame advantage

# Presses at tick 0 and one tick after each step fired (the earliest queue), so each
# step fires the moment its link opens. Measures the hit latency and every slack.
func _frame_advantage(s: RefCounted) -> void:
	await _probe(s, "rafael", _rafael_chain(), [2], [0, 1])
	await _probe(s, "matilde", _matilde_chain(), [4, 3], [0, 1, 7])

func _probe(s: RefCounted, label: String, chain: Array[AttackProfile], predicted: Array, press_ticks: Array) -> void:
	var setup := await _setup(s, chain)
	var presses := {}
	for tick in press_ticks:
		presses[tick] = Aim.NEUTRAL
	var run := await _trace(s, setup, 70, presses)
	var hit_ticks := _hit_ticks(run["damage"])
	s.check("%s: every chain step connects at 0%%" % label, hit_ticks.size() == chain.size(), "hits at %s" % [hit_ticks])
	if hit_ticks.size() != chain.size():
		await s.despawn(setup[0])
		return
	var latency: int = hit_ticks[0] - chain[0].startup_ticks
	s.check("%s: the first hit lands 2 ticks after the startup ends (engine latency)" % label, latency == 2, "latency=%d" % latency)
	for k in chain.size() - 1:
		var stun: int = chain[k].hitstun_ticks
		var leaves: int = hit_ticks[k] + stun
		var slack: int = leaves - 1 - hit_ticks[k + 1]
		var formula: int = stun - chain[k].active_ticks - chain[k + 1].startup_ticks - 2
		var still_hurt: bool = run["victim_states"][hit_ticks[k + 1] - 1] == "Hurt"
		print("INFO %s step %d -> %d: hit at tick %d, stun %d, next hit at tick %d, slack %d ticks (formula %d, predicted %d)" % [label, k + 1, k + 2, hit_ticks[k], stun, hit_ticks[k + 1], slack, formula, predicted[k]])
		s.check("%s: step %d links into step %d with slack %d (a true combo at the earliest press)" % [label, k + 1, k + 2, predicted[k]], slack == predicted[k] and slack == formula and still_hurt, "slack=%d formula=%d predicted=%d still_hurt=%s" % [slack, formula, predicted[k], still_hurt])
	await s.despawn(setup[0])
