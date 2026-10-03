extends SceneTree
## Victim-side combo tracking and every anti-infinite safeguard, headless, in physics
## ticks: hitstun decay from hit 4, knockback growth, the hard cap on hit 6, the time
## cap, the kept post-hitstun invulnerability, bombs, blocked hits, and the infinite
## probe (a zero-knockback victim and an attacker mashing at the maximum rate).
## The hits of most scenarios are resolved directly through Combat so each number is
## exact; the infinite probe uses real swings. Hit-stop is cancelled after every hit
## so the Timer-based invulnerability is not stretched by the headless frame rate.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const Aim := FighterIntent.Aim

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	await _scaling(s)
	await _time_cap(s)
	await _post_hitstun_invulnerability(s)
	await _bomb_blocked_and_dizzy(s)
	await _infinite_probe(s)
	s.finish()

# ----------------------------------------------------------------- fixtures

class Recorder extends RefCounted:
	var updated: Array = []
	var ended: Array = []
	func on_updated(hits: int, damage: float, attacker: Fighter) -> void:
		updated.append({"hits": hits, "damage": damage, "attacker": attacker})
	func on_ended(hits: int, damage: float, attacker: Fighter) -> void:
		ended.append({"hits": hits, "damage": damage, "attacker": attacker})

func _setup(s: RefCounted, p1_x: float = 400.0, p2_x: float = 470.0) -> Array:
	var game: Node2D = s.spawn_game(p1_x, p2_x)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(90)
	var recorder := Recorder.new()
	var victim: Fighter = game.get_node("Fighter2")
	victim.combo_updated.connect(recorder.on_updated)
	victim.combo_ended.connect(recorder.on_ended)
	return [game, controllers, game.get_node("Fighter1"), victim, recorder]

# A jab-like attack: short swing, fixed hitstun in ticks, no knockback growth.
func _attack(stun: int, knockback: Vector2 = Vector2(100.0, -50.0)) -> AttackProfile:
	return AttackProfile.frames(AttackProfile.make(2.0, knockback, Vector2(75.0, -10.0), Vector2(110.0, 40.0), &"neutral"), 2, 2, 2, 0, 0, stun, 0.0, 0.5)

## One hit through the real resolver; the hit-stop it starts is cancelled at once.
func _hit(attacker: Fighter, victim: Fighter, attack: AttackProfile) -> int:
	var outcome := Combat.resolve(Hit.punch(attacker, attack.damage, attack.knockback, -1.0, Hit.Source.PUNCH, attack), victim)
	Combat.cancel_hit_stop()
	return outcome

func _stun(victim: Fighter) -> int:
	return victim.state_machine.state_map["Hurt"].ticks_left()

# ------------------------------------------------------------- scaling, caps

# Six hits four ticks apart: no decay for hits 1-3, then x0.8 and x0.64, knockback
# x1.1 per hit, and the 6th hit launches and makes the victim untouchable.
func _scaling(s: RefCounted) -> void:
	var setup := await _setup(s)
	var attacker: Fighter = setup[2]
	var victim: Fighter = setup[3]
	var recorder: Recorder = setup[4]
	var attack := _attack(20)
	var stuns: Array[int] = []
	var speeds: Array[float] = []
	var invulnerable_after: Array[bool] = []
	var outcomes: Array[int] = []
	for i in 6:
		victim.damage_percent = 0.0
		outcomes.append(_hit(attacker, victim, attack))
		stuns.append(_stun(victim))
		speeds.append(victim.state_machine.velocity.length())
		invulnerable_after.append(victim.is_invulnerable)
		if i < 5:
			await s.frames(4)
	s.check("every hit during hitstun lands in full", outcomes.all(func(o): return o == Combat.Outcome.FULL), "outcomes=%s" % [outcomes])
	s.check("combo_updated counts 1..6 hits with the summed damage and the attacker", recorder.updated.size() == 6 and recorder.updated[5]["hits"] == 6 and is_equal_approx(recorder.updated[2]["damage"], 6.0) and recorder.updated[0]["attacker"] == attacker, "updates=%d" % recorder.updated.size())
	s.check("a Hurt-to-Hurt re-entry keeps the combo alive (no combo_ended yet)", recorder.ended.is_empty() and victim.combo.hits == 6, "ended=%d hits=%d" % [recorder.ended.size(), victim.combo.hits])
	s.check("hitstun is not decayed for hits 1 to 3", stuns[0] == 20 and stuns[1] == 20 and stuns[2] == 20, "stuns=%s" % [stuns])
	s.check("hit 4 stuns x0.8 and hit 5 x0.64", stuns[3] == 16 and stuns[4] == 13, "stuns=%s" % [stuns])
	var growth_ok := true
	for i in range(1, 5):
		growth_ok = growth_ok and absf(speeds[i] / speeds[0] - pow(1.1, i)) < 0.01
	s.check("knockback grows x1.1 per combo hit at equal damage %", growth_ok, "speeds=%s" % [speeds])
	var cap: Vector2 = victim.combo.rules.cap_launch_knockback
	s.check("the 6th hit launches with at least the cap knockback", speeds[5] >= cap.length() and victim.state_machine.velocity.y < 0.0, "speed=%.0f cap=%.0f vy=%.0f" % [speeds[5], cap.length(), victim.state_machine.velocity.y])
	s.check("the 6th hit makes the victim invulnerable at once, the earlier ones do not", invulnerable_after[5] and not invulnerable_after.slice(0, 5).has(true), "invulnerable=%s" % [invulnerable_after])
	var damage_before := victim.damage_percent
	await s.frames(2)
	var seventh := _hit(attacker, victim, attack)
	s.check("a 7th hit does nothing (no damage, no knockback)", seventh == Combat.Outcome.IGNORED and is_equal_approx(victim.damage_percent, damage_before), "outcome=%d damage=%.1f" % [seventh, victim.damage_percent])
	# combo_ended arrives one tick after the victim leaves hitstun.
	var left_hurt := -1
	var ended_at := -1
	for i in 120:
		await s.frames(1)
		if left_hurt < 0 and s.state_of(victim) != "Hurt":
			left_hurt = i
		if ended_at < 0 and not recorder.ended.is_empty():
			ended_at = i
	s.check("combo_ended fires one tick after the hitstun ends", left_hurt >= 0 and ended_at == left_hurt + 1, "left Hurt at %d, ended at %d" % [left_hurt, ended_at])
	s.check("the finished combo reports 6 hits and 12 damage", recorder.ended.size() == 1 and recorder.ended[0]["hits"] == 6 and is_equal_approx(recorder.ended[0]["damage"], 12.0), "ended=%s" % [recorder.ended])
	s.check("the tracker is empty after the combo", not victim.combo.is_active() and victim.combo.attacker == null)
	await s.despawn(setup[0])

# Hits spaced so the combo reaches the 1.5 s cap: the stun is clamped to what is
# left and the hit that reaches the cap launches and grants invulnerability.
func _time_cap(s: RefCounted) -> void:
	var setup := await _setup(s)
	var attacker: Fighter = setup[2]
	var victim: Fighter = setup[3]
	var attack := _attack(40)
	var hurt_run := 0
	var longest := 0
	var stun_at_70 := -1
	var capped_at_88 := false
	for i in 140:
		if i == 0 or i == 35 or i == 70 or i == 85 or i == 88:
			victim.damage_percent = 0.0
			_hit(attacker, victim, attack)
			if i == 70:
				stun_at_70 = _stun(victim)
			if i == 88:
				capped_at_88 = victim.is_invulnerable
		await s.frames(1)
		if s.state_of(victim) == "Hurt":
			hurt_run += 1
			longest = maxi(longest, hurt_run)
		else:
			hurt_run = 0
	s.check("a hit 70 ticks into a combo is clamped to the 20 ticks left of the cap", stun_at_70 > 0 and stun_at_70 <= 20, "stun=%d" % stun_at_70)
	s.check("the hit that reaches the time cap launches and grants invulnerability", capped_at_88)
	s.check("no combo keeps the victim in hitstun longer than 1.5 s (90 ticks)", longest <= 91, "longest=%d" % longest)
	await s.despawn(setup[0])

# A single hit: when its hitstun ends the victim is invulnerable and nothing lands.
func _post_hitstun_invulnerability(s: RefCounted) -> void:
	var setup := await _setup(s)
	var attacker: Fighter = setup[2]
	var victim: Fighter = setup[3]
	_hit(attacker, victim, _attack(12))
	var guard := 0
	while s.state_of(victim) == "Hurt" and guard < 100:
		await s.frames(1)
		guard += 1
	s.check("hitstun ends into the 0.5 s invulnerability (kept)", victim.is_invulnerable, "state=%s" % s.state_of(victim))
	await s.frames(10)
	var damage := victim.damage_percent
	var outcome := _hit(attacker, victim, _attack(12))
	s.check("a hit within the next 30 ticks does nothing", outcome == Combat.Outcome.IGNORED and is_equal_approx(victim.damage_percent, damage) and s.state_of(victim) != "Hurt", "outcome=%d" % outcome)
	await s.frames(40)
	var later := _hit(attacker, victim, _attack(12))
	s.check("after the window a hit lands and starts a new combo at 1 hit", later == Combat.Outcome.FULL and victim.combo.hits == 1, "outcome=%d hits=%d" % [later, victim.combo.hits])
	await s.despawn(setup[0])

# A bomb is not a combo, a blocked hit never counts, and a dizzy punish starts one.
func _bomb_blocked_and_dizzy(s: RefCounted) -> void:
	var setup := await _setup(s)
	var attacker: Fighter = setup[2]
	var victim: Fighter = setup[3]
	var recorder: Recorder = setup[4]
	var attack := _attack(20)
	_hit(attacker, victim, attack)
	await s.frames(3)
	_hit(attacker, victim, attack)
	var updates := recorder.updated.size()
	var bomb_outcome := Combat.resolve(Hit.bomb(victim.global_position + Vector2(40.0, 0.0), 5.0, Vector2(100.0, -100.0)), victim)
	Combat.cancel_hit_stop()
	s.check("a bomb hits in full and clears the combo silently", bomb_outcome == Combat.Outcome.FULL and victim.combo.hits == 0 and recorder.ended.is_empty() and recorder.updated.size() == updates, "hits=%d ended=%d" % [victim.combo.hits, recorder.ended.size()])
	await s.despawn(setup[0])

	setup = await _setup(s)
	attacker = setup[2]
	victim = setup[3]
	recorder = setup[4]
	victim.state_machine._change_state("Protect")
	await s.frames(2)
	var blocked := _hit(attacker, victim, attack)
	s.check("a blocked hit starts no combo and no hitstun", blocked == Combat.Outcome.BLOCKED and victim.combo.hits == 0 and recorder.updated.is_empty() and s.state_of(victim) == "Protect", "outcome=%d hits=%d" % [blocked, victim.combo.hits])
	await s.despawn(setup[0])

	setup = await _setup(s)
	attacker = setup[2]
	victim = setup[3]
	victim.break_shield(null)
	await s.frames(2)
	var punish := _hit(attacker, victim, attack)
	s.check("a hit on a dizzy fighter is full and starts a combo", punish == Combat.Outcome.FULL and victim.combo.hits == 1 and s.state_of(victim) == "Hurt", "outcome=%d hits=%d" % [punish, victim.combo.hits])
	await s.despawn(setup[0])

# ---------------------------------------------------------- infinite probe

# A zero-knockback victim and an attacker mashing every tick for 4 s. Returns the
# combos that ended, the longest continuous Hurt (ticks) and the most hits seen.
func _mash(s: RefCounted, rules: ComboRules) -> Dictionary:
	var setup := await _setup(s)
	var attacker: Fighter = setup[2]
	var victim: Fighter = setup[3]
	var recorder: Recorder = setup[4]
	victim.profile.knockback_scale = 0.0
	attacker.profile.neutral_single = _attack(20)
	if rules != null:
		victim.combo.rules = rules
	var ctrl = setup[1][0]
	var run := 0
	var longest := 0
	var most := 0
	for i in 240:
		ctrl.press_punch()
		await s.frames(1)
		Combat.cancel_hit_stop()
		most = maxi(most, victim.combo.hits)
		if s.state_of(victim) == "Hurt":
			run += 1
			longest = maxi(longest, run)
		else:
			run = 0
	var ended_hits: Array[int] = []
	for entry in recorder.ended:
		ended_hits.append(entry["hits"])
	await s.despawn(setup[0])
	return {"ended": ended_hits, "longest": longest, "most": most}

func _infinite_probe(s: RefCounted) -> void:
	var guarded := await _mash(s, null)
	s.check("infinite probe: no combo exceeds 6 hits while mashing for 4 s", guarded["most"] <= 6 and guarded["ended"].size() >= 1, "most=%d ended=%s" % [guarded["most"], guarded["ended"]])
	s.check("infinite probe: no victim stays in hitstun longer than 90 ticks", guarded["longest"] <= 90, "longest=%d" % guarded["longest"])
	# Control: with the safeguards off the same probe really is infinite, so the
	# probe above can tell a safeguard from luck.
	var loose := ComboRules.new()
	loose.hard_cap_hits = 100000
	loose.time_cap = 1000.0
	loose.hitstun_decay = 1.0
	loose.knockback_growth = 1.0
	var open := await _mash(s, loose)
	s.check("control: without the safeguards the probe chains past 6 hits and 90 ticks", open["most"] > 6 and open["longest"] > 90, "most=%d longest=%d" % [open["most"], open["longest"]])
