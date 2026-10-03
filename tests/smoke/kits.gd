extends SceneTree
## Character kits (Rafael and Matilde), headless, in physics ticks:
##   - the Matilde launcher probe (design D10): up launcher, jump, air jab A1 scripted at
##     0 / 20 / 30 / 60 / 90 % on a Rafael victim, recording the hit tick and the gap;
##   - kit assignment by character (scene defaults, SceneManager.play_game, the
##     character_ui setter, the baseline of spawn_game) and the set_profile refresh;
##   - per-kit data in play: run speed, jump apex, recovery height, jab chains, air jabs,
##     directional attacks, the charged neutral and the infinite probe of each chain;
##   - the frame-advantage table of both kits (design D6).
## Tick numbers are observation indices: tick 0 is the tick the first press fires.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const Aim := FighterIntent.Aim
## Rafael is Fighter1, Matilde Fighter2 in game.tscn (the kits come from their characters).
const RAFAEL := 0
const MATILDE := 1

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self, 3000.0)
	await _probe_matilde_launcher(s)
	await _assignment(s)
	await _set_profile_refresh(s)
	await _kit_data(s)
	await _movement(s)
	await _jab_chains(s)
	await _frame_advantage(s)
	await _chain_vs_percent(s)
	await _infinite_probe(s)
	await _air_jabs(s)
	await _directional(s)
	await _charged_neutral(s)
	s.finish()

# ----------------------------------------------------------------- fixtures

## A game of both kits: Rafael (Fighter1) at `rafael_x`, Matilde (Fighter2) at
## `matilde_x`, scripted controllers, standing on the floor.
func _arena(s: RefCounted, rafael_x: float = 400.0, matilde_x: float = 470.0) -> Dictionary:
	var game: Node2D = s.spawn_game(rafael_x, matilde_x, false, true)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(90)
	return {"game": game, "ctrl": controllers, "fighters": [game.get_node("Fighter1"), game.get_node("Fighter2")]}

func _fighter(arena: Dictionary, index: int) -> Fighter:
	return arena["fighters"][index]

func _ctrl(arena: Dictionary, index: int):
	return arena["ctrl"][index]

## Runs `count` ticks of scripted presses by fighter `attacker`: `presses` maps a tick to
## the aim of the press made on it. Returns what the other fighter received.
func _swing(s: RefCounted, arena: Dictionary, attacker: int, count: int, presses: Dictionary, percent: float = 0.0) -> Dictionary:
	var fighter := _fighter(arena, attacker)
	var victim := _fighter(arena, 1 - attacker)
	var ctrl = _ctrl(arena, attacker)
	var punch = fighter.state_machine.state_map["Punch"]
	var hurt = victim.state_machine.state_map["Hurt"]
	victim.set_damage_percent(percent)
	var hits: Array = []
	var tick_ref := [0]
	var on_hit := func(hit: Hit, outcome: int) -> void:
		hits.append({"tick": tick_ref[0], "attack": hit.attack, "damage": hit.damage, "knockback": hit.knockback, "outcome": outcome, "vy": victim.velocity.y, "stun": hurt.ticks_left()})
	victim.hit_received.connect(on_hit)
	var max_step := 0
	var fires := 0
	var was_punch := false
	var punch_ticks := 0
	for tick in count:
		tick_ref[0] = tick
		ctrl.aim = Aim.NEUTRAL
		if presses.has(tick):
			ctrl.aim = presses[tick]
			ctrl.press_punch()
		await s.frames(1)
		max_step = maxi(max_step, punch.chain_step())
		var in_punch: bool = s.state_of(fighter) == "Punch"
		if in_punch and not was_punch:
			fires += 1
		if in_punch:
			punch_ticks += 1
		was_punch = in_punch
	victim.hit_received.disconnect(on_hit)
	ctrl.aim = Aim.NEUTRAL
	return {"hits": hits, "max_step": max_step, "fires": fires, "punch_ticks": punch_ticks, "damage": victim.damage_percent}

func _full_hits(run: Dictionary) -> Array:
	var full: Array = []
	for hit in run["hits"]:
		if hit["outcome"] == Combat.Outcome.FULL:
			full.append(hit)
	return full

# ------------------------------------------------------------ launcher probe

## One scripted attempt: Matilde (Fighter2) throws the up launcher at tick 0, presses
## jump at `jump_tick` and the neutral air jab `jab_offset` ticks after the jump press.
## Returns what the Rafael victim received: the launcher hit, the air jab hit (tick and
## the vertical gap between the fighters at that tick) and the combo length.
func _attempt(s: RefCounted, percent: float, jump_tick: int, jab_offset: int) -> Dictionary:
	var arena := await _arena(s)
	var victim := _fighter(arena, RAFAEL)
	var attacker := _fighter(arena, MATILDE)
	victim.set_damage_percent(percent)
	var ctrl = _ctrl(arena, MATILDE)
	var result := {"launcher": -1, "jab": -1, "gap": 0.0, "combo": 0}
	var tick_ref := [0]
	var on_hit := func(hit: Hit, outcome: int) -> void:
		if outcome != Combat.Outcome.FULL or hit.attack == null:
			return
		if hit.attack.direction == &"up" and result["launcher"] < 0:
			result["launcher"] = tick_ref[0]
		elif hit.attack.direction == &"neutral" and result["jab"] < 0 and not attacker.is_on_floor():
			result["jab"] = tick_ref[0]
			result["gap"] = attacker.position.y - victim.position.y
			result["combo"] = victim.combo.hits
	victim.hit_received.connect(on_hit)
	for tick in 46:
		tick_ref[0] = tick
		ctrl.aim = Aim.NEUTRAL
		if tick == 0:
			ctrl.aim = Aim.UP
			ctrl.press_punch()
		if tick == jump_tick:
			ctrl.press_jump()
			ctrl.jump_held_level = true
		if tick == jump_tick + 8:
			ctrl.jump_held_level = false
		if tick == jump_tick + jab_offset:
			ctrl.press_punch()
		await s.frames(1)
	victim.hit_received.disconnect(on_hit)
	await s.despawn(arena["game"])
	return result

# Matilde's up launcher into her air jab on a Rafael victim: the jab has to connect at
# low damage (a window of several ticks), thin out as the launch grows with the damage
# and whiff at 90 %.
func _probe_matilde_launcher(s: RefCounted) -> void:
	var windows := {}
	for percent in [0.0, 20.0, 30.0, 60.0, 90.0]:
		var offsets: Array[int] = []
		var ticks: Array[int] = []
		var gaps: Array[int] = []
		var combo_ok := true
		var launched := true
		for jab_offset in range(3, 14):
			var r: Dictionary = await _attempt(s, percent, 22, jab_offset)
			launched = launched and r["launcher"] >= 0
			if r["jab"] >= 0:
				offsets.append(jab_offset)
				ticks.append(r["jab"])
				gaps.append(int(r["gap"]))
				combo_ok = combo_ok and r["combo"] >= 2
		windows[int(percent)] = offsets.size()
		print("INFO launcher probe %d%%: the air jab connects for %d of 11 press offsets (hit ticks %s, vertical gap %s px)" % [int(percent), offsets.size(), ticks, gaps])
		s.check("launcher probe %d%%: the up launcher lands" % int(percent), launched)
		if offsets.size() > 0:
			s.check("launcher probe %d%%: every air jab hit is the second hit of the combo" % int(percent), combo_ok)
	s.check("launcher probe: the air jab connects at 0 to 30 % with a window of at least 5 press ticks", windows[0] >= 5 and windows[20] >= 5 and windows[30] >= 5, "windows=%s" % [windows])
	s.check("launcher probe: the window thins out at 60 %% and the follow-up whiffs at 90 %%", windows[60] < windows[20] and windows[90] == 0, "windows=%s" % [windows])

# --------------------------------------------------------------- assignment

func _assignment(s: RefCounted) -> void:
	# Scene defaults: Rafael is Fighter1, Matilde Fighter2.
	var arena := await _arena(s)
	var rafael := _fighter(arena, RAFAEL)
	var matilde := _fighter(arena, MATILDE)
	s.check("Rafael gets his kit at spawn", rafael.profile.kit_id == 0 and rafael.profile.kit_name == &"rafael" and is_equal_approx(rafael.profile.run_speed, 270.0))
	s.check("Matilde gets her kit at spawn", matilde.profile.kit_id == 1 and matilde.profile.kit_name == &"matilde" and is_equal_approx(matilde.profile.run_speed, 340.0))
	var rafael_ui: CharacterUI = rafael.character_ui
	var matilde_ui: CharacterUI = matilde.character_ui

	# The character_ui setter (what SceneManager.play_game does after add_child).
	rafael.character_ui = matilde_ui
	s.check("changing the character swaps the kit (setter path)", rafael.profile.kit_id == 1 and is_equal_approx(rafael.profile.run_speed, 340.0))
	rafael.character_ui = rafael_ui
	s.check("changing it back restores the Rafael kit", rafael.profile.kit_id == 0)
	await s.despawn(arena["game"])

	# The baseline of spawn_game: both fighters keep the default profile.
	var baseline: Node2D = s.spawn_game(400.0, 470.0)
	var b1: Fighter = baseline.get_node("Fighter1")
	var b2: Fighter = baseline.get_node("Fighter2")
	s.check("spawn_game without kits keeps the baseline profile on both fighters", b1.profile.kit_id == -1 and b2.profile.kit_id == -1 and is_equal_approx(b1.profile.run_speed, 300.0) and b1.profile.jab_chain.is_empty())
	b1.character_ui = matilde_ui
	s.check("a baseline fighter (kit_from_character off) keeps its profile when the character changes", b1.profile.kit_id == -1)
	await s.despawn(baseline)

	# SceneManager.play_game: a mirror match, both Rafael, independent fighters.
	var manager: Node = root.get_node("SceneManager")
	var holder := Node.new()
	root.add_child(holder)
	manager.scene_container = holder
	manager.play_game(rafael_ui, rafael_ui)
	await s.frames(3)
	var mirror: Node = manager.current_scene
	var m1: Fighter = mirror.get_node("Fighter1")
	var m2: Fighter = mirror.get_node("Fighter2")
	s.check("play_game gives a mirror match the Rafael kit on both sides", m1.profile.kit_id == 0 and m2.profile.kit_id == 0 and is_equal_approx(m2.profile.run_speed, 270.0))
	s.check("the mirror fighters keep independent shield meters and combo trackers", m1.shield != m2.shield and m1.combo != m2.combo)
	mirror.queue_free()
	await s.frames(2)
	manager.play_game(matilde_ui, rafael_ui)
	await s.frames(3)
	var swapped: Node = manager.current_scene
	s.check("play_game follows the characters, not the side", swapped.get_node("Fighter1").profile.kit_id == 1 and swapped.get_node("Fighter2").profile.kit_id == 0)
	swapped.queue_free()
	holder.queue_free()
	await s.frames(2)

	# Registry: unknown characters fall back, ids are stable.
	var unknown := CharacterUI.new()
	unknown.name = "Nobody"
	var fallback := FighterKits.for_character(unknown)
	s.check("a character without a kit gets the default profile", fallback.kit_id == -1 and fallback.kit_name == &"default" and FighterKits.for_character(null).kit_id == -1)
	s.check("FighterKits lists the shipped ids and resolves them", FighterKits.ids() == PackedInt32Array([0, 1]) and FighterKits.by_id(0).kit_name == &"rafael" and FighterKits.by_id(1).kit_name == &"matilde" and FighterKits.by_id(7).kit_id == -1)
	s.check("kits are cached and shared by reference", FighterKits.by_id(1) == FighterKits.by_id(1) and FighterKits.for_character(matilde_ui) == FighterKits.by_id(1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 40:
		seen[FighterKits.random(rng).kit_id] = true
	s.check("random draws cover both kits", seen.has(0) and seen.has(1) and seen.size() == 2, "seen=%s" % [seen.keys()])

# ------------------------------------------------------------- set_profile

func _set_profile_refresh(s: RefCounted) -> void:
	var arena := await _arena(s)
	var fighter := _fighter(arena, RAFAEL)
	fighter.shield.set_ratio(0.2)
	fighter.jumps_left = 0
	fighter.air_dash_available = false
	var custom := FighterKits.by_id(1).duplicate(true) as FighterProfile
	custom.pickup_reach_x = 150.0
	custom.pickup_reach_height = 120.0
	fighter.set_profile(custom)
	var shape := fighter.pickup_area.get_node("CollisionShape2D") as CollisionShape2D
	var size := (shape.shape as RectangleShape2D).size
	s.check("set_profile refills the shield", is_equal_approx(fighter.shield.ratio(), 1.0), "ratio=%.2f" % fighter.shield.ratio())
	s.check("set_profile restores the air jump and the air dash", fighter.jumps_left == custom.max_air_jumps and fighter.air_dash_available)
	s.check("set_profile rebuilds the pickup area from the new profile", is_equal_approx(size.x, 300.0) and is_equal_approx(size.y, 120.0), "size=%s" % [size])
	s.check("set_profile makes the fighter read the new numbers at once", fighter.profile == custom and is_equal_approx(fighter.get_knockback_scale(), 1.1))
	fighter.set_profile(null)
	s.check("set_profile(null) falls back to the default profile", fighter.profile.kit_id == -1)
	await s.despawn(arena["game"])

# ---------------------------------------------------------------- kit data

func _kit_data(s: RefCounted) -> void:
	var r := FighterKits.by_id(0)
	var m := FighterKits.by_id(1)
	s.check("Rafael: heavy and slow (run 270, jumps -820 / -720, knockback scale 0.9)", is_equal_approx(r.run_speed, 270.0) and is_equal_approx(r.jump_velocity, -820.0) and is_equal_approx(r.double_jump_velocity, -720.0) and is_equal_approx(r.knockback_scale, 0.9))
	s.check("Matilde: light and fast (run 340, jumps -900 / -780, knockback scale 1.1)", is_equal_approx(m.run_speed, 340.0) and is_equal_approx(m.jump_velocity, -900.0) and is_equal_approx(m.double_jump_velocity, -780.0) and is_equal_approx(m.knockback_scale, 1.1))
	s.check("Rafael: 2-hit jab (4 then the 8 damage finisher), single air jab, single 10", r.jab_chain.size() == 2 and is_equal_approx(r.jab_chain[0].damage, 4.0) and is_equal_approx(r.jab_chain[1].damage, 8.0) and r.air_jab_chain.size() == 1 and is_equal_approx(r.neutral_single.damage, 10.0))
	s.check("Matilde: 3-hit jab (2.5, 2.5, finisher 4), 2-hit air jab, single 6", m.jab_chain.size() == 3 and is_equal_approx(m.jab_chain[0].damage, 2.5) and is_equal_approx(m.jab_chain[1].damage, 2.5) and is_equal_approx(m.jab_chain[2].damage, 4.0) and m.air_jab_chain.size() == 2 and is_equal_approx(m.neutral_single.damage, 6.0))
	s.check("Rafael: heavy up launcher (9) with a 0.55 s endlag, side 13 (360, -90), spike 11 (40, 460)", is_equal_approx(r.attack_up.damage, 9.0) and r.attack_up.resolved_frames(r)["endlag"] == CombatClock.ticks(0.55) and is_equal_approx(r.attack_side.damage, 13.0) and r.attack_side.knockback == Vector2(360.0, -90.0) and is_equal_approx(r.attack_down_air.damage, 11.0) and r.attack_down_air.knockback == Vector2(40.0, 460.0))
	s.check("Matilde: combo launcher (6, hitstun 0.55 s, endlag 0.30 s), side 8 (260, -90), spike 7 (30, 380)", is_equal_approx(m.attack_up.damage, 6.0) and m.attack_up.hitstun_ticks == CombatClock.ticks(0.55) and m.attack_up.resolved_frames(m)["endlag"] == CombatClock.ticks(0.30) and is_equal_approx(m.attack_side.damage, 8.0) and m.attack_side.knockback == Vector2(260.0, -90.0) and is_equal_approx(m.attack_down_air.damage, 7.0) and m.attack_down_air.knockback == Vector2(30.0, 380.0))
	s.check("the kits chain only on a neutral press and never past 3 steps", r.jab_chain.back().link_window_ticks == 0 and m.jab_chain.back().link_window_ticks == 0 and m.jab_chain.size() <= 3 and m.air_jab_chain.back().link_window_ticks == 0)
	var every_attack_free := true
	for kit in [r, m]:
		var attacks: Array[AttackProfile] = [kit.attack_up, kit.attack_side, kit.attack_down_ground, kit.attack_down_air, kit.neutral_single]
		attacks.append_array(kit.jab_chain)
		attacks.append_array(kit.air_jab_chain)
		for attack in attacks:
			every_attack_free = every_attack_free and attack.cooldown_ticks == 0
		every_attack_free = every_attack_free and kit.attack_buffer_ticks == 6
	s.check("every kit attack is actionable at the end of its swing, with a 6-tick buffer", every_attack_free)
	s.check("only Matilde's launcher hints at a CPU follow-up", r.launcher_followup == &"none" and m.launcher_followup == &"air_jab")

# ---------------------------------------------------------------- movement

# Both kits run, jump, double jump and recover side by side (far apart, same floor).
func _movement(s: RefCounted) -> void:
	var arena := await _arena(s, 300.0, 600.0)
	var r := _fighter(arena, RAFAEL)
	var m := _fighter(arena, MATILDE)
	_ctrl(arena, RAFAEL).move_x = 1.0
	_ctrl(arena, MATILDE).move_x = -1.0
	await s.frames(22)
	var run_r := absf(r.velocity.x)
	var run_m := absf(m.velocity.x)
	s.check("run speed per kit: Rafael 270, Matilde 340", absf(run_r - 270.0) < 3.0 and absf(run_m - 340.0) < 3.0, "rafael=%.0f matilde=%.0f" % [run_r, run_m])
	_ctrl(arena, RAFAEL).move_x = 0.0
	_ctrl(arena, MATILDE).move_x = 0.0
	await s.frames(30)
	await s.despawn(arena["game"])

	# A full hop with the jump held: first-frame speed and apex.
	arena = await _arena(s, 300.0, 600.0)
	r = _fighter(arena, RAFAEL)
	m = _fighter(arena, MATILDE)
	var start := [r.position.y, m.position.y]
	var apex := [0.0, 0.0]
	var launch := [0.0, 0.0]
	for i in 2:
		_ctrl(arena, i).jump_held_level = true
		_ctrl(arena, i).press_jump()
	await s.frames(2)
	launch[0] = r.velocity.y
	launch[1] = m.velocity.y
	for tick in 70:
		await s.frames(1)
		apex[0] = maxf(apex[0], start[0] - r.position.y)
		apex[1] = maxf(apex[1], start[1] - m.position.y)
	s.check("jump velocity per kit: about -820 and -900 (one or two ticks of gravity applied)", absf(launch[0] + 820.0) < 70.0 and absf(launch[1] + 900.0) < 70.0, "rafael=%.0f matilde=%.0f" % [launch[0], launch[1]])
	var expected_r := 820.0 * 820.0 / (2.0 * 1800.0)
	var expected_m := 900.0 * 900.0 / (2.0 * 1800.0)
	s.check("jump apex per kit follows the jump velocity (Matilde jumps higher)", apex[1] > apex[0] and absf(apex[0] - expected_r) < expected_r * 0.12 and absf(apex[1] - expected_m) < expected_m * 0.12, "rafael=%.0f (%.0f) matilde=%.0f (%.0f)" % [apex[0], expected_r, apex[1], expected_m])
	await s.frames(60)
	await s.despawn(arena["game"])

	# Double jump speed and the up-recovery height, from the same hop.
	arena = await _arena(s, 300.0, 600.0)
	r = _fighter(arena, RAFAEL)
	m = _fighter(arena, MATILDE)
	for i in 2:
		_ctrl(arena, i).jump_held_level = true
		_ctrl(arena, i).press_jump()
	await s.frames(30)
	for i in 2:
		_ctrl(arena, i).press_jump()
	await s.frames(2)
	var double := [r.velocity.y, m.velocity.y]
	s.check("double jump velocity per kit: about -720 and -780", absf(double[0] + 720.0) < 90.0 and absf(double[1] + 780.0) < 90.0, "rafael=%.0f matilde=%.0f" % [double[0], double[1]])
	await s.despawn(arena["game"])

	arena = await _arena(s, 300.0, 600.0)
	r = _fighter(arena, RAFAEL)
	m = _fighter(arena, MATILDE)
	for i in 2:
		_ctrl(arena, i).jump_held_level = true
		_ctrl(arena, i).press_jump()
	await s.frames(25)
	var before := [r.position.y, m.position.y]
	var best := [r.position.y, m.position.y]
	for i in 2:
		_ctrl(arena, i).jump_held_level = false
		_ctrl(arena, i).press_special()
	for tick in 80:
		await s.frames(1)
		_ctrl(arena, RAFAEL).aim = Aim.NEUTRAL
		_ctrl(arena, MATILDE).aim = Aim.NEUTRAL
		best[0] = minf(best[0], r.position.y)
		best[1] = minf(best[1], m.position.y)
	var gain_r: float = before[0] - best[0]
	var gain_m: float = before[1] - best[1]
	s.check("recovery height: Matilde's up recovery gains more than Rafael's", gain_m > gain_r and gain_r > 100.0, "rafael=%.0f px matilde=%.0f px" % [gain_r, gain_m])
	await s.despawn(arena["game"])

# -------------------------------------------------------------- jab chains

## The jab presses of a kit: one at tick 0, one a tick later (it queues until the link
## opens) and one a tick after each later step fired.
func _chain_presses(kit: int) -> Dictionary:
	if kit == RAFAEL:
		return {0: Aim.NEUTRAL, 1: Aim.NEUTRAL}
	return {0: Aim.NEUTRAL, 1: Aim.NEUTRAL, 7: Aim.NEUTRAL}

func _jab_chains(s: RefCounted) -> void:
	for kit in [RAFAEL, MATILDE]:
		var label := "Rafael" if kit == RAFAEL else "Matilde"
		var length := 2 if kit == RAFAEL else 3
		var arena := await _arena(s)
		var run := await _swing(s, arena, kit, 60, _chain_presses(kit))
		var full := _full_hits(run)
		var attacker := _fighter(arena, kit)
		var finisher: AttackProfile = attacker.profile.jab_chain[length - 1]
		var expected := 0.0
		for step in attacker.profile.jab_chain:
			expected += step.damage
		s.check("%s: the jab is exactly %d steps and every one links at 0%%" % [label, length], run["max_step"] == length and full.size() == length, "steps=%d hits=%d" % [run["max_step"], full.size()])
		s.check("%s: the jab deals %.1f damage and the last step is the finisher" % [label, expected], is_equal_approx(run["damage"], expected) and full.size() == length and full[length - 1]["attack"] == finisher, "damage=%.1f" % run["damage"])
		s.check("%s: the finisher launches the victim upward" % label, full.size() == length and full[length - 1]["vy"] < -150.0, "vy=%.0f" % (full[length - 1]["vy"] if full.size() == length else 0.0))
		print("INFO %s jab at 0%%: hit ticks %s, finisher vy %.0f" % [label, full.map(func(h): return h["tick"]), full[full.size() - 1]["vy"] if not full.is_empty() else 0.0])
		await s.despawn(arena["game"])

# The frame-advantage table of both kits at 0 % (design D6): every link's slack is the
# number of ticks the next hit lands before the victim leaves hitstun. Rafael's is
# tighter than Matilde's; each is read from the real game, not from the formula.
func _frame_advantage(s: RefCounted) -> void:
	var slacks := {}
	for kit in [RAFAEL, MATILDE]:
		var label := "Rafael" if kit == RAFAEL else "Matilde"
		var arena := await _arena(s)
		var attacker := _fighter(arena, kit)
		var run := await _swing(s, arena, kit, 60, _chain_presses(kit))
		var full := _full_hits(run)
		var chain: Array[AttackProfile] = attacker.profile.jab_chain
		var row: Array[int] = []
		for k in full.size() - 1:
			var leaves: int = int(full[k]["tick"]) + int(full[k]["stun"])
			var slack: int = leaves - 1 - int(full[k + 1]["tick"])
			var formula: int = int(full[k]["stun"]) - chain[k].active_ticks - chain[k + 1].startup_ticks - 2
			row.append(slack)
			print("INFO frame advantage %s step %d -> %d: hit at tick %d, stun %d, next hit at tick %d, slack %d ticks (formula %d)" % [label, k + 1, k + 2, full[k]["tick"], full[k]["stun"], full[k + 1]["tick"], slack, formula])
			s.check("%s: link %d -> %d has %d ticks of slack, equal to the design formula" % [label, k + 1, k + 2, slack], slack >= 0 and slack == formula, "slack=%d formula=%d" % [slack, formula])
		slacks[kit] = row
		await s.despawn(arena["game"])
	var tightest_m: int = slacks[MATILDE].min() if not slacks[MATILDE].is_empty() else 0
	var loosest_r: int = slacks[RAFAEL].max() if not slacks[RAFAEL].is_empty() else 99
	s.check("Rafael's links are tighter than Matilde's (2 to 3 ticks against 3 to 4)", loosest_r <= tightest_m and loosest_r >= 2 and loosest_r <= 3, "rafael=%s matilde=%s" % [slacks[RAFAEL], slacks[MATILDE]])

# The %-window of every link: how many ticks of slack the link has
# at 0 % and how it changes with the victim's damage (the knockback grows, the stun of a
# jab shrinks with it) until the chain stops linking.
func _chain_vs_percent(s: RefCounted) -> void:
	var linking := {}
	for kit in [RAFAEL, MATILDE]:
		var label := "Rafael" if kit == RAFAEL else "Matilde"
		var length := 2 if kit == RAFAEL else 3
		var row := ""
		var last_link := -1
		var first_whiff := -1
		for percent in [0, 20, 40, 50, 60, 70, 80, 90, 100, 120]:
			var arena := await _arena(s)
			var run := await _swing(s, arena, kit, 70, _chain_presses(kit), float(percent))
			var count := _full_hits(run).size()
			var stuns: Array = _full_hits(run).map(func(h): return h["stun"])
			row += " %d%%:%d/%d(stun %s)" % [percent, mini(count, length), length, stuns]
			if count >= length:
				last_link = percent
			elif first_whiff < 0:
				first_whiff = percent
			await s.despawn(arena["game"])
		linking[kit] = {"last": last_link, "first_whiff": first_whiff}
		print("INFO %s chain connects (hits/steps) by victim damage:%s" % [label, row])
	var r_whiff: int = linking[RAFAEL]["first_whiff"]
	var m_whiff: int = linking[MATILDE]["first_whiff"]
	s.check("Rafael's chain links at 0 % and stops linking by 90 %", linking[RAFAEL]["last"] >= 0 and r_whiff > 0 and r_whiff <= 90, "linking=%s" % [linking[RAFAEL]])
	s.check("Matilde's chain links at 0 % and stops linking by 100 %", linking[MATILDE]["last"] >= 0 and m_whiff > 0 and m_whiff <= 100, "linking=%s" % [linking[MATILDE]])

# The infinite probe on the real kits: the attacker mashes at the maximum rate, the
# safeguards keep every combo to 6 hits and every hitstun run to 90 ticks.
func _infinite_probe(s: RefCounted) -> void:
	for kit in [RAFAEL, MATILDE]:
		var label := "Rafael" if kit == RAFAEL else "Matilde"
		var arena := await _arena(s)
		var attacker := _fighter(arena, kit)
		var victim := _fighter(arena, 1 - kit)
		var ctrl = _ctrl(arena, kit)
		var longest := [0]
		var run := [0]
		var biggest := [0]
		victim.combo_updated.connect(func(hits: int, _damage: float, _by: Fighter) -> void:
			biggest[0] = maxi(biggest[0], hits))
		for tick in 240:
			ctrl.press_punch()
			await s.frames(1)
			victim.stocks = Fighter.MAX_STOCKS
			if s.state_of(victim) == "Hurt":
				run[0] += 1
				longest[0] = maxi(longest[0], run[0])
			else:
				run[0] = 0
		s.check("%s: mashing the jab for 4 s never makes a combo longer than 6 hits" % label, biggest[0] >= 2 and biggest[0] <= 6, "biggest=%d" % biggest[0])
		s.check("%s: no hitstun run lasts more than 90 ticks" % label, longest[0] <= 90, "longest=%d" % longest[0])
		await s.despawn(arena["game"])

# --------------------------------------------------------------- air jabs

# Both kits jump and press the air jab twice. Matilde's second press starts step 2;
# Rafael has no second step, so a press inside the swing is not chained, and a press made
# after it is a new single air jab.
func _air_jabs(s: RefCounted) -> void:
	var arena := await _arena(s, 300.0, 600.0)
	var counters := [{"max_step": 0, "fires": 0, "was": false}, {"max_step": 0, "fires": 0, "was": false}]
	for i in 2:
		_ctrl(arena, i).jump_held_level = true
		_ctrl(arena, i).press_jump()
	for tick in 60:
		for i in 2:
			var ctrl = _ctrl(arena, i)
			if tick == 12 or tick == 13:
				ctrl.press_punch()
			# Rafael's air jab lasts 19 ticks: a press 16 ticks into it is buffered and
			# fires the moment it ends.
			if i == RAFAEL and tick == 28:
				ctrl.press_punch()
		await s.frames(1)
		for i in 2:
			var fighter := _fighter(arena, i)
			var punch = fighter.state_machine.state_map["Punch"]
			counters[i]["max_step"] = maxi(counters[i]["max_step"], punch.chain_step())
			var in_punch: bool = s.state_of(fighter) == "Punch"
			if in_punch and not counters[i]["was"]:
				counters[i]["fires"] += 1
			counters[i]["was"] = in_punch
	s.check("Matilde: two presses in the link window start the second air jab step", counters[MATILDE]["max_step"] == 2, "max step=%d" % counters[MATILDE]["max_step"])
	s.check("Rafael: the air jab is a single hit (no step 2) and a later press starts a new air jab", counters[RAFAEL]["max_step"] == 1 and counters[RAFAEL]["fires"] == 2, "max step=%d fires=%d" % [counters[RAFAEL]["max_step"], counters[RAFAEL]["fires"]])
	await s.despawn(arena["game"])

# ------------------------------------------------------------- directional

func _directional(s: RefCounted) -> void:
	# Grounded side and up punches, read from the Hit.
	for kit in [RAFAEL, MATILDE]:
		var label := "Rafael" if kit == RAFAEL else "Matilde"
		var profile := FighterKits.by_id(kit)
		var arena := await _arena(s)
		var run := await _swing(s, arena, kit, 40, {0: Aim.SIDE})
		var full := _full_hits(run)
		s.check("%s: the side punch hits for %.0f damage with knockback %s" % [label, profile.attack_side.damage, profile.attack_side.knockback], full.size() == 1 and is_equal_approx(full[0]["damage"], profile.attack_side.damage) and full[0]["knockback"] == profile.attack_side.knockback, "hits=%d" % full.size())
		await s.despawn(arena["game"])
		arena = await _arena(s)
		run = await _swing(s, arena, kit, 70, {0: Aim.UP})
		full = _full_hits(run)
		var up: AttackProfile = profile.attack_up
		var frames := up.resolved_frames(profile)
		s.check("%s: the up punch is a launcher (%.0f damage) and its swing lasts startup + active + endlag ticks" % [label, up.damage], full.size() == 1 and full[0]["vy"] < -250.0 and run["punch_ticks"] == int(frames["startup"]) + int(frames["active"]) + int(frames["endlag"]), "hits=%d punch ticks=%d vy=%.0f" % [full.size(), run["punch_ticks"], full[0]["vy"] if not full.is_empty() else 0.0])
		await s.despawn(arena["game"])

	# The down-air spike: the attacker jumps over the victim, presses down + punch near
	# the apex and the victim is sent down.
	for kit in [RAFAEL, MATILDE]:
		var label := "Rafael" if kit == RAFAEL else "Matilde"
		var profile := FighterKits.by_id(kit)
		var spiked := false
		var damage := 0.0
		var knockback := Vector2.ZERO
		var vy := 0.0
		for press_tick in [24, 27, 30, 33]:
			var arena := await _arena(s, 400.0, 420.0)
			var attacker := _fighter(arena, kit)
			var victim := _fighter(arena, 1 - kit)
			var ctrl = _ctrl(arena, kit)
			var seen := []
			victim.hit_received.connect(func(hit: Hit, outcome: int) -> void:
				if outcome == Combat.Outcome.FULL and hit.attack != null and hit.attack.direction == &"down":
					seen.append({"damage": hit.damage, "knockback": hit.knockback, "vy": victim.velocity.y}))
			ctrl.jump_held_level = true
			ctrl.press_jump()
			for tick in 60:
				ctrl.aim = Aim.NEUTRAL
				if tick == press_tick:
					ctrl.aim = Aim.DOWN
					ctrl.press_punch()
				await s.frames(1)
				if tick == 12:
					ctrl.jump_held_level = false
			if not seen.is_empty():
				spiked = true
				damage = seen[0]["damage"]
				knockback = seen[0]["knockback"]
				vy = seen[0]["vy"]
			await s.despawn(arena["game"])
			if spiked:
				break
		s.check("%s: the down-air spike hits for %.0f with knockback %s and sends the victim down" % [label, profile.attack_down_air.damage, profile.attack_down_air.knockback], spiked and is_equal_approx(damage, profile.attack_down_air.damage) and knockback == profile.attack_down_air.knockback and vy > 250.0, "spiked=%s damage=%.1f vy=%.0f" % [spiked, damage, vy])

# --------------------------------------------------------- charged neutral

# A grounded neutral held past the tap threshold throws the kit's single punch (human
# path: only a held key charges), a tap throws step 1 of the chain.
func _charged_neutral(s: RefCounted) -> void:
	for kit in [RAFAEL, MATILDE]:
		var label := "Rafael" if kit == RAFAEL else "Matilde"
		var profile := FighterKits.by_id(kit)
		var arena := await _arena(s)
		var ctrl = _ctrl(arena, kit)
		var victim := _fighter(arena, 1 - kit)
		var hits: Array = []
		victim.hit_received.connect(func(hit: Hit, outcome: int) -> void:
			if outcome == Combat.Outcome.FULL:
				hits.append({"attack": hit.attack, "damage": hit.damage}))
		ctrl.attack_held_level = true
		ctrl.press_punch()
		await s.frames(24)
		ctrl.attack_held_level = false
		await s.frames(40)
		s.check("%s: a charged grounded neutral throws the kit's single punch, boosted by the charge" % label, hits.size() == 1 and hits[0]["attack"] == profile.neutral_single and hits[0]["damage"] > profile.neutral_single.damage, "hits=%d damage=%.2f" % [hits.size(), hits[0]["damage"] if not hits.is_empty() else 0.0])
		await s.despawn(arena["game"])
		arena = await _arena(s)
		var tap := await _swing(s, arena, kit, 40, {0: Aim.NEUTRAL})
		var tap_hits := _full_hits(tap)
		s.check("%s: a tap throws step 1 of the jab chain, not the single punch" % label, tap_hits.size() == 1 and tap_hits[0]["attack"] == profile.jab_chain[0])
		await s.despawn(arena["game"])
