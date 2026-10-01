extends SceneTree
## S2 hit rules: air punch, hitstun that scales with knockback and blocks
## actions, post-hit invulnerability, invulnerability timer race (F4) and
## serialized hit-stop (F5).

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const SMALL_KNOCKBACK := Vector2(220.0, -120.0)
const BIG_KNOCKBACK := Vector2(700.0, -150.0)

func _initialize() -> void:
	_run()

func _setup(s: RefCounted, p1_x: float, p2_x: float) -> Array:
	var game: Node2D = s.spawn_game(p1_x, p2_x)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(90)
	return [game, controllers]

func _run() -> void:
	var s := Smoke.new(self)
	await _air_actions(s)
	await _hitstun(s)
	await _post_hit_invulnerability(s)
	await _invulnerability_race(s)
	await _hit_stop(s)
	s.finish()

func _air_actions(s: RefCounted) -> void:
	var setup := await _setup(s, 400.0, 470.0)
	var game: Node2D = setup[0]
	var attacker: Fighter = game.get_node("Fighter1")
	var target: Fighter = game.get_node("Fighter2")
	attacker.position.y -= 40.0
	attacker.velocity = Vector2.ZERO
	await s.frames(2)
	s.check("attacker is airborne", not attacker.is_on_floor())
	setup[1][0].press_punch()
	await s.frames(2)
	s.check("air punch starts a Punch", s.state_of(attacker) == "Punch", "state=%s" % s.state_of(attacker))
	await s.frames(40)
	s.check("air punch hits the enemy", is_equal_approx(target.damage_percent, attacker.profile.punch_damage), "damage=%.1f" % target.damage_percent)
	await s.despawn(game)

	var block_setup := await _setup(s, 330.0, 700.0)
	var blocker: Fighter = block_setup[0].get_node("Fighter1")
	block_setup[1][0].jump_held_level = true
	block_setup[1][0].press_jump()
	await s.frames(6)
	block_setup[1][0].jump_held_level = false
	block_setup[1][0].block_held_level = true
	block_setup[1][0].press_block()
	await s.frames(3)
	s.check("air block enters Protect while airborne", s.state_of(blocker) == "Protect" and not blocker.is_on_floor(), "state=%s" % s.state_of(blocker))
	block_setup[1][0].block_held_level = false
	await s.frames(3)
	s.check("releasing block leaves Protect", s.state_of(blocker) != "Protect", "state=%s" % s.state_of(blocker))
	await s.despawn(block_setup[0])

	var throw_setup := await _setup(s, 330.0, 700.0)
	var thrower: Fighter = throw_setup[0].get_node("Fighter1")
	thrower.position.y -= 300.0
	thrower.velocity = Vector2.ZERO
	thrower.held_food = FoodCatalog.get_random_food_name()
	await s.frames(2)
	throw_setup[1][0].press_throw()
	await s.frames(3)
	var projectiles := 0
	for child in throw_setup[0].get_children():
		if child is FoodProjectile:
			projectiles += 1
	s.check("air throw releases the food", projectiles == 1 and thrower.held_food == "", "projectiles=%d held=%s" % [projectiles, thrower.held_food])
	await s.frames(25)
	s.check("after an air throw the fighter is still in an air state, not Idle", not thrower.is_on_floor() and s.state_of(thrower) == "Fall", "state=%s onfloor=%s" % [s.state_of(thrower), thrower.is_on_floor()])
	await s.despawn(throw_setup[0])

# Physics frames the fighter stays in Hurt while mashing punch and jump.
func _hurt_frames(s: RefCounted, victim: Fighter, controller) -> int:
	var count := 0
	while s.state_of(victim) == "Hurt" and count < 240:
		controller.press_punch()
		controller.press_jump()
		await s.frames(1)
		count += 1
	return count

func _hitstun(s: RefCounted) -> void:
	# The victim stands close enough that the big launch stays inside the blast zone.
	var setup := await _setup(s, 400.0, 560.0)
	var attacker: Fighter = setup[0].get_node("Fighter1")
	var victim: Fighter = setup[0].get_node("Fighter2")
	Combat.apply_hit(attacker, victim, 8.0, SMALL_KNOCKBACK)
	s.check("a hit puts the victim in Hurt", s.state_of(victim) == "Hurt")
	var small: int = await _hurt_frames(s, victim, setup[1][1])
	s.check("hitstun blocks every action for roughly 0.3 s", small >= 14 and small <= 45, "frames=%d" % small)
	await s.frames(60)

	var big_attacker: Fighter = attacker
	Combat.apply_hit(big_attacker, victim, 8.0, BIG_KNOCKBACK)
	var big: int = await _hurt_frames(s, victim, setup[1][1])
	s.check("a harder knockback means longer hitstun", big >= small + 10, "small=%d big=%d" % [small, big])
	await s.despawn(setup[0])

func _post_hit_invulnerability(s: RefCounted) -> void:
	var setup := await _setup(s, 400.0, 700.0)
	var attacker: Fighter = setup[0].get_node("Fighter1")
	var victim: Fighter = setup[0].get_node("Fighter2")
	Combat.apply_hit(attacker, victim, 8.0, SMALL_KNOCKBACK)
	await s.frames(3)
	Combat.apply_hit(attacker, victim, 8.0, SMALL_KNOCKBACK)
	s.check("a second hit during hitstun still lands (combos stay possible)", is_equal_approx(victim.damage_percent, 16.0), "damage=%.1f" % victim.damage_percent)
	var waited := 0
	while s.state_of(victim) == "Hurt" and waited < 240:
		await s.frames(1)
		waited += 1
	s.check("hitstun ends into post-hit invulnerability", victim.is_invulnerable)
	var damage := victim.damage_percent
	Combat.apply_hit(attacker, victim, 8.0, SMALL_KNOCKBACK)
	await s.frames(2)
	s.check("a hit during post-hit invulnerability does nothing", is_equal_approx(victim.damage_percent, damage) and s.state_of(victim) != "Hurt", "damage=%.1f state=%s" % [victim.damage_percent, s.state_of(victim)])
	waited = 0
	while victim.is_invulnerable and waited < 120:
		await s.frames(1)
		waited += 1
	s.check("invulnerability ends on its own", not victim.is_invulnerable and victim.animated_sprite_2d.visible, "frames=%d" % waited)
	Combat.apply_hit(attacker, victim, 8.0, SMALL_KNOCKBACK)
	s.check("after the window a hit applies normally again", is_equal_approx(victim.damage_percent, damage + 8.0), "damage=%.1f" % victim.damage_percent)
	await s.despawn(setup[0])

func _invulnerability_race(s: RefCounted) -> void:
	var setup := await _setup(s, 330.0, 700.0)
	var fighter: Fighter = setup[0].get_node("Fighter1")
	fighter.grant_invulnerability(0.3)
	s.check("grant_invulnerability turns it on", fighter.is_invulnerable)
	await s.frames(9)
	fighter.grant_invulnerability(0.6)
	await s.frames(15)
	s.check("an older grant never ends a newer one early", fighter.is_invulnerable)
	await s.frames(40)
	s.check("the newer grant ends and visuals are restored", not fighter.is_invulnerable and fighter.animated_sprite_2d.visible)

	var stocks := fighter.stocks
	fighter._lose_stock()
	s.check("respawn grants invulnerability", fighter.stocks == stocks - 1 and fighter.is_invulnerable)
	await s.frames(150)
	s.check("respawn blink ends cleanly", not fighter.is_invulnerable and fighter.animated_sprite_2d.visible)
	await s.despawn(setup[0])

func _hit_stop(s: RefCounted) -> void:
	s.check("time scale starts at 1.0", is_equal_approx(Engine.time_scale, 1.0))
	Combat._trigger_hit_stop(0.1, 0.05)
	await s.real_wait(0.05)
	Combat._trigger_hit_stop(0.3, 0.3)
	await s.real_wait(0.15)
	s.check("an older hit-stop never restores the clock while a newer one runs", is_equal_approx(Engine.time_scale, 0.3), "time_scale=%.2f" % Engine.time_scale)
	await s.real_wait(0.4)
	s.check("overlapping hit-stops end at exactly 1.0", is_equal_approx(Engine.time_scale, 1.0), "time_scale=%.2f" % Engine.time_scale)

	Combat._trigger_hit_stop(0.4, 0.05)
	Combat.cancel_hit_stop()
	s.check("cancel_hit_stop restores 1.0 at once", is_equal_approx(Engine.time_scale, 1.0))
	Combat._trigger_hit_stop(0.1, 0.5)
	await s.real_wait(0.3)
	s.check("a stale hit-stop never fires after a cancel", is_equal_approx(Engine.time_scale, 1.0))
