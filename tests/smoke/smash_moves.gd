extends SceneTree
## S5b: charged smash, directional punches, up-recovery, helpless fall, fast fall.

const Smoke := preload("res://tests/smoke/smoke_util.gd")

func _initialize() -> void:
	_run()

# Two fighters `gap` apart on the floor, intent controllers attached. Fighter1
# (the attacker) is at x=400 facing right; Fighter2 stands `gap` to its right.
func _setup(s: RefCounted, gap: float = 70.0) -> Array:
	var game: Node2D = s.spawn_game(400.0, 400.0 + gap)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(60)
	return [game, controllers, game.get_node("Fighter1"), game.get_node("Fighter2")]

# One punch of Fighter1 with the given hold time (seconds, 0 = a plain tap) and
# aim; returns Fighter2's damage and launch velocity right after the hit.
func _hit(s: RefCounted, hold: float, aim: FighterIntent.Aim, gap: float = 70.0, target_height: float = 0.0) -> Dictionary:
	var setup := await _setup(s, gap)
	var attacker: Fighter = setup[2]
	var target: Fighter = setup[3]
	var ctl = setup[1][0]
	if target_height != 0.0:
		target.position.y -= target_height
		target.velocity = Vector2.ZERO
	var launch := Vector2.ZERO
	var captured := false
	var peak_charge := 0.0
	ctl.aim = aim
	if hold > 0.0:
		ctl.attack_held_level = true
	ctl.press_punch()
	var frames_held := int(hold * 60.0)
	for i in frames_held:
		await s.frames(1)
		peak_charge = maxf(peak_charge, attacker.charge_level)
	ctl.attack_held_level = false
	ctl.aim = aim
	for i in 60:
		await s.frames(1)
		if not captured and target.damage_percent > 0.0:
			launch = target.velocity
			captured = true
	var result := {
		"damage": target.damage_percent,
		"launch": launch,
		"peak_charge": peak_charge,
		"direction": attacker.last_attack_direction,
	}
	await s.despawn(setup[0])
	return result

func _run() -> void:
	var s := Smoke.new(self)
	var profile := FighterProfile.new()

	# --- charge ---
	var tap := await _hit(s, 0.0, FighterIntent.Aim.NEUTRAL)
	s.check("tap punch deals the base damage", is_equal_approx(tap["damage"], profile.punch_damage), "damage=%.1f" % tap["damage"])
	var short := await _hit(s, 0.1, FighterIntent.Aim.NEUTRAL)
	s.check("a hold shorter than the tap threshold is a normal punch", is_equal_approx(short["damage"], profile.punch_damage) and is_zero_approx(short["peak_charge"]), "damage=%.1f charge=%.2f" % [short["damage"], short["peak_charge"]])
	var full := await _hit(s, 1.2, FighterIntent.Aim.NEUTRAL)
	s.check("full charge deals more than 1.5x the tap damage", full["damage"] > tap["damage"] * 1.5, "full=%.1f tap=%.1f" % [full["damage"], tap["damage"]])
	s.check("full charge launches harder than a tap", (full["launch"] as Vector2).length() > (tap["launch"] as Vector2).length() * 1.3, "full=%.0f tap=%.0f" % [(full["launch"] as Vector2).length(), (tap["launch"] as Vector2).length()])
	var long_hold := await _hit(s, 3.0, FighterIntent.Aim.NEUTRAL)
	s.check("a 3 s hold is capped: same damage as a 1.2 s hold", is_equal_approx(long_hold["damage"], full["damage"]) and is_equal_approx(long_hold["peak_charge"], 1.0), "3s=%.1f 1.2s=%.1f charge=%.2f" % [long_hold["damage"], full["damage"], long_hold["peak_charge"]])
	var half := await _hit(s, 0.6, FighterIntent.Aim.NEUTRAL)
	s.check("half charge lands between tap and full", half["damage"] > tap["damage"] and half["damage"] < full["damage"] and half["peak_charge"] > 0.3 and half["peak_charge"] < 0.7, "half=%.1f charge=%.2f" % [half["damage"], half["peak_charge"]])

	# Glow, snapshot and cancel on hit.
	var setup := await _setup(s)
	var attacker: Fighter = setup[2]
	var victim: Fighter = setup[3]
	var ctl = setup[1][0]
	s.check("no glow before charging", not attacker.charge_glow.visible)
	ctl.attack_held_level = true
	ctl.press_punch()
	await s.frames(6)
	s.check("no glow inside the tap threshold", not attacker.charge_glow.visible)
	await s.frames(40)
	var scale_a := attacker.charge_glow.scale.x
	var snap_charge: float = attacker.get_state_snapshot()["charge_level"]
	s.check("glow shows while charging and the snapshot has the charge", attacker.charge_glow.visible and snap_charge > 0.2 and snap_charge < 0.8, "visible=%s charge=%.2f" % [attacker.charge_glow.visible, snap_charge])
	# Smash-like: the fighter keeps its own colors (a brightening flash, never a
	# solid color), a small glow sits in front of the fist.
	var sprite := attacker.animated_sprite_2d
	var flash_min := 99.0
	var flash_max := 0.0
	var hue_kept := true
	var glow_bounded := true
	for i in 30:
		await s.frames(1)
		var m := sprite.modulate
		flash_min = minf(flash_min, m.r)
		flash_max = maxf(flash_max, m.r)
		hue_kept = hue_kept and is_equal_approx(m.r, m.g) and is_equal_approx(m.g, m.b)
		glow_bounded = glow_bounded and attacker.charge_glow.scale.x <= 0.4 and attacker.charge_glow.global_position.x > attacker.global_position.x + 20.0
	s.check("charging flashes the sprite brighter without tinting it", hue_kept and flash_max > 1.2 and flash_min <= 1.001, "modulate r %.2f..%.2f" % [flash_min, flash_max])
	s.check("the charge never replaces the sprite colors (no material, no self_modulate)", sprite.self_modulate == Color.WHITE and sprite.modulate.a == 1.0 and attacker.charge_glow.modulate.r > 0.7 and attacker.charge_glow.modulate.g > 0.7 and attacker.charge_glow.modulate.b > 0.7, "glow=%s" % attacker.charge_glow.modulate)
	s.check("the glow is small and sits in front of the fist", glow_bounded and attacker.charge_glow.scale.x < 0.4, "scale=%.2f x=%.0f fighter x=%.0f" % [attacker.charge_glow.scale.x, attacker.charge_glow.global_position.x, attacker.global_position.x])
	await s.screenshot("s5b_charging_glow")
	await s.frames(40)
	s.check("the glow grows with the charge", attacker.charge_glow.scale.x > scale_a * 0.95, "%.2f -> %.2f" % [scale_a, attacker.charge_glow.scale.x])
	Combat.apply_hit(victim, attacker, 5.0, Vector2(200.0, -100.0))
	await s.frames(3)
	s.check("being hit cancels the charge and hides the glow", not attacker.charge_glow.visible and is_zero_approx(attacker.charge_level) and s.state_of(attacker) == "Hurt" and attacker.animated_sprite_2d.offset == Vector2.ZERO, "state=%s" % s.state_of(attacker))
	await s.despawn(setup[0])

	var released := await _setup(s)
	var rel_fighter: Fighter = released[2]
	released[1][0].attack_held_level = true
	released[1][0].press_punch()
	await s.frames(50)
	released[1][0].attack_held_level = false
	await s.frames(3)
	s.check("the glow hides after the release", not rel_fighter.charge_glow.visible)
	s.check("the flash and shake reset after the release", rel_fighter.animated_sprite_2d.modulate == Color.WHITE and rel_fighter.animated_sprite_2d.offset == Vector2.ZERO, "modulate=%s offset=%s" % [rel_fighter.animated_sprite_2d.modulate, rel_fighter.animated_sprite_2d.offset])
	await s.despawn(released[0])

	# No air charge.
	var air := await _setup(s)
	var air_fighter: Fighter = air[2]
	air[1][0].jump_held_level = true
	air[1][0].press_jump()
	await s.frames(12)
	air[1][0].attack_held_level = true
	air[1][0].press_punch()
	await s.frames(14)
	s.check("an air punch with the key held does not charge", not air_fighter.charge_glow.visible and is_zero_approx(air_fighter.charge_level) and air_fighter.last_attack_direction == &"neutral" and not air_fighter.is_on_floor(), "state=%s charge=%.2f" % [s.state_of(air_fighter), air_fighter.charge_level])
	await s.despawn(air[0])

	# --- directional punches ---
	var up := await _hit(s, 0.0, FighterIntent.Aim.UP)
	var down := await _hit(s, 0.0, FighterIntent.Aim.DOWN)
	var side := await _hit(s, 0.0, FighterIntent.Aim.SIDE)
	var neutral := tap
	var up_kb: Vector2 = up["launch"]
	var down_kb: Vector2 = down["launch"]
	var side_kb: Vector2 = side["launch"]
	s.check("up punch connects and launches mostly upward", up["damage"] > 0.0 and up_kb.y < 0.0 and absf(up_kb.y) > absf(up_kb.x) * 3.0, "damage=%.1f kb=%s" % [up["damage"], up_kb])
	s.check("down punch (ground) connects and launches low", down["damage"] > 0.0 and down_kb.y < 0.0 and absf(down_kb.y) < absf(up_kb.y) * 0.8, "damage=%.1f kb=%s" % [down["damage"], down_kb])
	s.check("side punch launches mostly horizontally", side["damage"] > 0.0 and absf(side_kb.x) > absf(side_kb.y) * 2.0, "damage=%.1f kb=%s" % [side["damage"], side_kb])
	s.check("the angles are clearly different", up_kb.angle_to(side_kb) != 0.0 and absf(rad_to_deg(Vector2(absf(up_kb.x), -up_kb.y).angle()) - rad_to_deg(Vector2(absf(side_kb.x), -side_kb.y).angle())) > 30.0 and absf(rad_to_deg(Vector2(absf(down_kb.x), -down_kb.y).angle()) - rad_to_deg(Vector2(absf(side_kb.x), -side_kb.y).angle())) > 12.0)
	s.check("side punch hits harder than the neutral punch", side["damage"] > neutral["damage"] and absf(side_kb.x) > absf((neutral["launch"] as Vector2).x), "side=%.1f neutral=%.1f" % [side["damage"], neutral["damage"]])
	s.check("last attack direction is recorded", up["direction"] == &"up" and down["direction"] == &"down" and side["direction"] == &"side" and neutral["direction"] == &"neutral", "%s %s %s %s" % [up["direction"], down["direction"], side["direction"], neutral["direction"]])
	var up_full := await _hit(s, 1.2, FighterIntent.Aim.UP)
	s.check("a charged up punch keeps its angle and scales", up_full["damage"] > up["damage"] * 1.5 and (up_full["launch"] as Vector2).y < up_kb.y and absf((up_full["launch"] as Vector2).y) > absf((up_full["launch"] as Vector2).x) * 3.0, "kb=%s" % up_full["launch"])

	# Spike: a down punch in the air sends the target down.
	var spike_setup := await _setup(s, 0.0)
	var spiker: Fighter = spike_setup[2]
	var spiked: Fighter = spike_setup[3]
	spiked.position.x = spiker.position.x + 20.0
	spike_setup[1][0].press_jump()
	await s.frames(14)
	spiked.position = Vector2(spiker.position.x + 30.0, spiker.position.y + 120.0)
	spiked.velocity = Vector2.ZERO
	spike_setup[1][0].aim = FighterIntent.Aim.DOWN
	spike_setup[1][0].press_punch()
	var spike_kb := Vector2.ZERO
	var spike_hit := false
	for i in 40:
		await s.frames(1)
		if not spike_hit and spiked.damage_percent > 0.0:
			spike_kb = spiked.velocity
			spike_hit = true
	s.check("a down punch in the air spikes the target downward", spike_hit and spike_kb.y > 200.0, "hit=%s kb=%s" % [spike_hit, spike_kb])
	await s.despawn(spike_setup[0])

	# --- up-recovery ---
	var rec := await _setup(s, 400.0)
	var fighter: Fighter = rec[2]
	var rc = rec[1][0]
	s.check("recovery starts available", fighter.recovery_available)
	rc.jump_held_level = true
	rc.press_jump()
	await s.frames(25)
	rc.jump_held_level = false
	var before_y := fighter.position.y
	var before_vy := fighter.velocity.y
	rc.press_special()
	rc.aim = FighterIntent.Aim.NEUTRAL
	await s.frames(2)
	s.check("up + punch in the air bursts upward", s.state_of(fighter) == "Recovery" and fighter.velocity.y < -700.0 and not fighter.recovery_available, "state=%s vy=%.0f (was %.0f)" % [s.state_of(fighter), fighter.velocity.y, before_vy])
	await s.frames(6)
	await s.screenshot("s5b_up_recovery")
	var min_y := fighter.position.y
	for i in 70:
		await s.frames(1)
		min_y = minf(min_y, fighter.position.y)
		if s.state_of(fighter) == "Helpless":
			break
	s.check("the recovery gains real height", before_y - min_y > 150.0, "rose %.0f px" % (before_y - min_y))
	await s.screenshot("s5b_up_recovery") if false else null
	s.check("after the burst the fighter is helpless", s.state_of(fighter) == "Helpless", "state=%s" % s.state_of(fighter))
	var helpless_vy := fighter.velocity.y
	rc.press_special()
	rc.aim = FighterIntent.Aim.NEUTRAL
	rc.press_jump()
	rc.press_punch()
	rc.press_dash()
	await s.frames(3)
	s.check("a second recovery, jumps, punches and dashes do nothing while helpless", s.state_of(fighter) == "Helpless" and fighter.velocity.y >= helpless_vy, "state=%s" % s.state_of(fighter))
	var landed: bool = await s.wait_grounded(fighter, 300)
	await s.frames(3)
	s.check("landing ends helplessness and refills recovery", landed and s.state_of(fighter) != "Helpless" and fighter.recovery_available, "state=%s available=%s" % [s.state_of(fighter), fighter.recovery_available])
	await s.despawn(rec[0])

	# Recovery returns after a hit.
	var hit_rec := await _setup(s, 400.0)
	var hr: Fighter = hit_rec[2]
	hit_rec[1][0].jump_held_level = true
	hit_rec[1][0].press_jump()
	await s.frames(25)
	hit_rec[1][0].press_special()
	await s.frames(3)
	var used := not hr.recovery_available
	Combat.apply_hit(hit_rec[3], hr, 5.0, Vector2(100.0, -100.0))
	await s.frames(3)
	s.check("being hit refills the recovery", used and hr.recovery_available, "used=%s available=%s" % [used, hr.recovery_available])
	await s.despawn(hit_rec[0])

	# Without recovery the same chord is an ordinary air punch.
	var chord := await _setup(s, 400.0)
	var cf: Fighter = chord[2]
	chord[1][0].jump_held_level = true
	chord[1][0].press_jump()
	await s.frames(25)
	cf.recovery_available = false
	chord[1][0].press_special()
	await s.frames(3)
	s.check("with the recovery spent, up + punch in the air is a punch", s.state_of(cf) == "Punch", "state=%s" % s.state_of(cf))
	await s.despawn(chord[0])

	# Ground special is not a recovery: up + punch on the floor is an up punch.
	var ground := await _setup(s, 400.0)
	var gf: Fighter = ground[2]
	ground[1][0].press_special()
	await s.frames(3)
	s.check("on the ground up + punch is an up punch, not a recovery", s.state_of(gf) == "Punch" and gf.last_attack_direction == &"up" and gf.recovery_available, "state=%s dir=%s" % [s.state_of(gf), gf.last_attack_direction])
	await s.despawn(ground[0])

	# --- fast fall ---
	var normal := await _fall_trial(s, false)
	var fast := await _fall_trial(s, true)
	s.check("fast fall raises the fall speed", fast["max_vy"] > normal["max_vy"] + 150.0, "fast=%.0f normal=%.0f" % [fast["max_vy"], normal["max_vy"]])
	s.check("a fast faller lands sooner", fast["frames"] < normal["frames"], "fast=%d normal=%d frames" % [fast["frames"], normal["frames"]])
	s.check("fast fall ends on landing", not fast["still_fast"])

	# --- inputs and the instructions screen ---
	var seen := {}
	var unique := true
	for action in InputMap.get_actions():
		if action.begins_with("ui_"):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				var key := (event as InputEventKey).physical_keycode
				if seen.has(key) and seen[key] != action:
					unique = false
				seen[key] = action
	var keys_ok := true
	for action in ["P1_up", "P1_down", "P2_up", "P2_down"]:
		keys_ok = keys_ok and InputMap.has_action(action)
	s.check("the four up/down actions exist and no key is bound twice", keys_ok and unique)
	s.check("up/down keys are E, C, I and Comma", seen.get(KEY_E) == "P1_up" and seen.get(KEY_C) == "P1_down" and seen.get(KEY_I) == "P2_up" and seen.get(KEY_COMMA) == "P2_down")
	var instructions: Node = load("res://ui/instructions/instructions.tscn").instantiate()
	var more: Label = instructions.get_node("MoreControls")
	var text := more.text
	s.check("the instructions describe the aim keys, charge, recovery, fast fall and the ledge", text.contains("E (up)") and text.contains("charge") and text.contains("recovery") and text.contains("fast fall") and text.contains("grab the leg"))
	instructions.free()
	s.finish()

# Jumps and falls from the apex, optionally holding down; returns the highest
# fall speed and the frames from the apex to the floor.
func _fall_trial(s: RefCounted, hold_down: bool) -> Dictionary:
	var setup := await _setup(s, 400.0)
	var fighter: Fighter = setup[2]
	var ctl = setup[1][0]
	ctl.jump_held_level = true
	ctl.press_jump()
	var guard := 0
	while fighter.velocity.y <= 0.0 and guard < 120:
		await s.frames(1)
		guard += 1
	if hold_down:
		ctl.aim = FighterIntent.Aim.DOWN
	var max_vy := 0.0
	var count := 0
	while not fighter.is_on_floor() and count < 240:
		await s.frames(1)
		count += 1
		max_vy = maxf(max_vy, fighter.velocity.y)
	await s.frames(2)
	var result := {"max_vy": max_vy, "frames": count, "still_fast": fighter.fast_falling}
	await s.despawn(setup[0])
	return result
