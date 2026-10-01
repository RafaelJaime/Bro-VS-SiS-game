extends SceneTree
## (b) Punch hits what is in front, mirrors with facing, hits once per swing,
## never moves its owner, and ignores an enemy behind or out of reach.

const Smoke := preload("res://tests/smoke/smoke_util.gd")

func _initialize() -> void:
	_run()

# Spawns a fresh game with the given x positions, lets both fighters settle and
# returns [game, controllers].
func _setup(s: RefCounted, p1_x: float, p2_x: float) -> Array:
	var game: Node2D = s.spawn_game(p1_x, p2_x)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(90)
	return [game, controllers]

# Fighter1 throws one punch; returns the damage Fighter2 took and Fighter1's x drift.
func _punch_once(s: RefCounted, p1_x: float, p2_x: float) -> Dictionary:
	var setup := await _setup(s, p1_x, p2_x)
	var game: Node2D = setup[0]
	var punching: Fighter = game.get_node("Fighter1")
	var target: Fighter = game.get_node("Fighter2")
	var start_x := punching.position.x
	var facing_before := punching.facing
	setup[1][0].press_punch()
	await s.frames(60)
	var result := {
		"damage": target.damage_percent,
		"drift": absf(punching.position.x - start_x),
		"facing": facing_before,
	}
	await s.despawn(game)
	return result

func _run() -> void:
	var s := Smoke.new(self)
	var swing_damage := FighterProfile.new().punch_damage

	var front := await _punch_once(s, 400.0, 470.0)
	s.check("punch facing right at close range deals exactly one hit", is_equal_approx(front["damage"], swing_damage), "damage=%.1f expected=%.1f" % [front["damage"], swing_damage])
	s.check("owner is not teleported by the punch", front["drift"] < 3.0, "drift=%.1f" % front["drift"])

	var mirrored := await _punch_once(s, 500.0, 430.0)
	s.check("punch facing left at close range hits (mirrored)", is_equal_approx(mirrored["damage"], swing_damage), "facing=%d damage=%.1f" % [mirrored["facing"], mirrored["damage"]])

	# Enemy behind: Fighter1 faces right (turned by walking right), the enemy
	# stands to its left, clear of the mirrored hitbox.
	var setup := await _setup(s, 300.0, 700.0)
	var game: Node2D = setup[0]
	var controllers: Array = setup[1]
	var punching: Fighter = game.get_node("Fighter1")
	var target: Fighter = game.get_node("Fighter2")
	controllers[0].move_x = 1.0
	await s.frames(25)
	controllers[0].move_x = 0.0
	await s.frames(30)
	target.position.x = punching.position.x - 100.0
	target.velocity = Vector2.ZERO
	await s.frames(5)
	s.check("fighter faces right after walking right", punching.facing == 1, "facing=%d" % punching.facing)
	var hitbox_shape: CollisionShape2D = punching.punch_area.get_node("CollisionShape2D")
	s.check("hitbox is off while idle", not punching.punch_area.monitoring)
	controllers[0].press_punch()
	await s.frames(8)
	s.check("hitbox is live during the active window, in front of the facing", punching.punch_area.monitoring and hitbox_shape.position.x > 0.0, "monitoring=%s x=%.0f" % [punching.punch_area.monitoring, hitbox_shape.position.x])
	await s.frames(60)
	s.check("hitbox is off again after the swing", not punching.punch_area.monitoring)
	s.check("punch with the enemy behind deals no damage", is_zero_approx(target.damage_percent), "damage=%.1f" % target.damage_percent)
	await s.despawn(game)

	var far := await _punch_once(s, 330.0, 630.0)
	s.check("punch out of reach deals no damage", is_zero_approx(far["damage"]), "damage=%.1f" % far["damage"])

	# Thrown food hits through the hurtbox and goes the way the thrower faces.
	var throw_setup := await _setup(s, 330.0, 560.0)
	var throw_game: Node2D = throw_setup[0]
	var thrower: Fighter = throw_game.get_node("Fighter1")
	var victim: Fighter = throw_game.get_node("Fighter2")
	thrower.held_food = FoodCatalog.get_random_food_name()
	throw_setup[1][0].press_throw()
	await s.frames(90)
	s.check("thrown food damages the fighter it flies at", victim.damage_percent > 0.0, "damage=%.1f held=%s" % [victim.damage_percent, thrower.held_food])
	var strays := 0
	for child in throw_game.get_children():
		if child is FoodProjectile:
			strays += 1
	s.check("the projectile is consumed by the hit", strays == 0, "projectiles left=%d" % strays)
	await s.despawn(throw_game)

	s.finish()
