extends SceneTree
## Food that matters: every weight class beats a neutral punch, shield damage by
## class (heavy breaks a weak shield, a full one survives one heavy, two break it),
## the item-identity tags, the wider feet-centred pickup reach, the faster spawner
## and the throw priority while holding food.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const PUNCH_DAMAGE := 8.0
const PUNCH_KNOCKBACK := Vector2(220.0, -120.0)

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self, 600.0)
	_catalog_units(s)
	await _hits_and_shields(s)
	await _tag_effects(s)
	await _pickup_reach(s)
	await _throw_priority(s)
	await _spawner(s)
	s.finish()

# A game with no random food: the spawner is stopped and anything it dropped removed.
func _setup(s: RefCounted, p1_x: float = 330.0, p2_x: float = 700.0) -> Array:
	var game: Node2D = s.spawn_game(p1_x, p2_x)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(1)
	game.food_spawner.stop()
	for child in game.get_children():
		if child is FoodPickup:
			child.queue_free()
	await s.frames(60)
	return [game, controllers]

func _drop_food(s: RefCounted, game: Node2D, food_name: String, x: float) -> FoodPickup:
	var pickup: FoodPickup = load("res://game/food/food_pickup.tscn").instantiate()
	pickup.food_name = food_name
	game.add_child(pickup)
	pickup.position = Vector2(x, s.floor_top(game) - 40.0)
	return pickup

func _projectiles(game: Node2D) -> int:
	var count := 0
	for child in game.get_children():
		if child is FoodProjectile and not child.is_queued_for_deletion():
			count += 1
	return count

# ------------------------------------------------------------------ catalog

func _catalog_units(s: RefCounted) -> void:
	var beats := true
	var detail := ""
	for weight in FoodCatalog.WEIGHT_STATS:
		var stats: Dictionary = FoodCatalog.WEIGHT_STATS[weight]
		if not (stats["damage"] > PUNCH_DAMAGE and (stats["knockback"] as Vector2).length() > PUNCH_KNOCKBACK.length() and stats["knockback"].x > PUNCH_KNOCKBACK.x):
			beats = false
			detail += " class %d: dmg %.1f kb %s" % [weight, stats["damage"], stats["knockback"]]
	s.check("every weight class beats a neutral punch in damage and knockback", beats, detail)

	var light: float = FoodCatalog.WEIGHT_STATS[FoodCatalog.WeightClass.LIGHT]["shield_damage"]
	var medium: float = FoodCatalog.WEIGHT_STATS[FoodCatalog.WeightClass.MEDIUM]["shield_damage"]
	var heavy: float = FoodCatalog.WEIGHT_STATS[FoodCatalog.WeightClass.HEAVY]["shield_damage"]
	s.check("shield damage is ordered light <= medium <= heavy, strictly somewhere", light <= medium and medium <= heavy and (light < medium or medium < heavy), "%.0f / %.0f / %.0f" % [light, medium, heavy])

	var profile := FighterProfile.new()
	var worst := 0.0
	for food_name in FoodCatalog.FOOD_ITEMS:
		worst = maxf(worst, FoodCatalog.get_shield_damage(food_name))
	s.check("no food, tags included, breaks a full shield in one hit", worst < profile.shield_max, "worst=%.1f max=%.1f" % [worst, profile.shield_max])
	s.check("the invariant 1.4 * heavy < shield max holds", 1.4 * heavy < profile.shield_max and 2.0 * heavy >= profile.shield_max)

	s.check("a hot food launches farther than an untagged one of its class", is_equal_approx(FoodCatalog.get_hit_knockback("soup").x, FoodCatalog.get_hit_knockback("pizza").x * 1.25) and FoodCatalog.get_weight_class("soup") == FoodCatalog.get_weight_class("pizza"))
	s.check("a hard food drains a shield more than an untagged one of its class", is_equal_approx(FoodCatalog.get_shield_damage("cheese"), FoodCatalog.get_shield_damage("pizza") * 1.4))
	s.check("an untagged food is exactly its class", FoodCatalog.get_hit_knockback("pizza") == FoodCatalog.get_knockback("pizza") and is_equal_approx(FoodCatalog.get_shield_damage("pizza"), 35.0))
	var tagged := 0
	for food_name in FoodCatalog.TAGS:
		tagged += 1
		s.check("tagged food exists in the catalog: %s" % food_name, FoodCatalog.FOOD_ITEMS.has(food_name))
	var effects: Array = FoodCatalog.TAG_EFFECTS.keys()
	s.check("exactly two identity effects, hot and hard", effects.size() == 2 and "hot" in effects and "hard" in effects and tagged == 6, "effects=%s" % [effects])

	var hit := Hit.food(null, "soup", Vector2(1.0, 2.0))
	s.check("Hit.food carries the catalog values, is blockable and keeps its source", hit.source == Hit.Source.FOOD and not hit.unblockable and hit.food_name == "soup" and hit.knockback == FoodCatalog.get_hit_knockback("soup") and is_equal_approx(hit.shield_damage, FoodCatalog.get_shield_damage("soup")) and hit.source_position == Vector2(1.0, 2.0))

# ----------------------------------------------------------------- in game

func _hits_and_shields(s: RefCounted) -> void:
	# Food does more than a punch to an open target.
	var setup := await _setup(s, 400.0, 470.0)
	var game: Node2D = setup[0]
	var attacker: Fighter = game.get_node("Fighter1")
	var target: Fighter = game.get_node("Fighter2")
	Combat.resolve(Hit.food(attacker, "pizza", attacker.global_position), target)
	var food_damage := target.damage_percent
	var food_speed: float = target.state_machine.velocity.length() / target.get_knockback_scale()
	s.check("a thrown pizza hurts more than a punch", food_damage > PUNCH_DAMAGE and food_speed > PUNCH_KNOCKBACK.length(), "damage=%.1f launch=%.0f" % [food_damage, food_speed])
	await s.despawn(game)

	# A heavy food breaks a weakened shield; a full one survives one heavy and breaks on two.
	var shield_setup := await _setup(s, 400.0, 470.0)
	var shield_game: Node2D = shield_setup[0]
	var thrower: Fighter = shield_game.get_node("Fighter1")
	var shielder: Fighter = shield_game.get_node("Fighter2")
	shield_setup[1][1].block_held_level = true
	shield_setup[1][1].press_block()
	await s.frames(3)
	var outcomes: Array = []
	# Raising the shield spent shield_raise_cost meter before the hit landed.
	var cost := shielder.profile.shield_raise_cost
	shielder.hit_received.connect(func(hit: Hit, outcome: int) -> void: outcomes.append([hit.source, outcome]))
	var first := Combat.resolve(Hit.food(thrower, "turkey", thrower.global_position), shielder)
	s.check("one heavy food does not break a full shield", first == Combat.Outcome.BLOCKED and shielder.shield.value > 0.0 and s.state_of(shielder) == "Protect", "outcome=%d meter=%.1f" % [first, shielder.shield.value])
	s.check("food does not pierce the shield: chip damage only, meter drained by its shield damage", shielder.damage_percent > 0.0 and shielder.damage_percent < 18.0 and shielder.shield.value <= 45.0 - cost and shielder.shield.value > 42.0 - cost, "damage=%.2f meter=%.1f" % [shielder.damage_percent, shielder.shield.value])
	var second := Combat.resolve(Hit.food(thrower, "turkey", thrower.global_position), shielder)
	s.check("two heavy foods in a row break a full shield", second == Combat.Outcome.BROKE and s.state_of(shielder) == "Dizzy", "outcome=%d" % second)
	s.check("the signal reports a FOOD source with the outcome", outcomes.size() == 2 and outcomes[0] == [Hit.Source.FOOD, Combat.Outcome.BLOCKED] and outcomes[1] == [Hit.Source.FOOD, Combat.Outcome.BROKE], "outcomes=%s" % [outcomes])
	await s.despawn(shield_game)

	var weak_setup := await _setup(s, 400.0, 470.0)
	var weak_game: Node2D = weak_setup[0]
	var weak_thrower: Fighter = weak_game.get_node("Fighter1")
	var weak: Fighter = weak_game.get_node("Fighter2")
	weak_setup[1][1].block_held_level = true
	weak_setup[1][1].press_block()
	await s.frames(3)
	weak.shield.absorb(weak.shield.value - 45.0)
	var broke := Combat.resolve(Hit.food(weak_thrower, "turkey", weak_thrower.global_position), weak)
	s.check("a heavy food breaks a weakened shield (45) in one hit", broke == Combat.Outcome.BROKE and weak.is_dizzy(), "outcome=%d" % broke)
	await s.despawn(weak_game)

	# A real throw, end to end: Fighter1 throws, the projectile reaches a shielding Fighter2.
	var throw_setup := await _setup(s, 400.0, 480.0)
	var throw_game: Node2D = throw_setup[0]
	var real_thrower: Fighter = throw_game.get_node("Fighter1")
	var real_target: Fighter = throw_game.get_node("Fighter2")
	var landed: Array = []
	real_target.hit_received.connect(func(hit: Hit, outcome: int) -> void: landed.append([hit.source, outcome, hit.food_name]))
	throw_setup[1][1].block_held_level = true
	throw_setup[1][1].press_block()
	real_thrower.held_food = "pizza"
	await s.frames(3)
	throw_setup[1][0].press_throw()
	await s.frames(40)
	s.check("a thrown projectile follows the shielded path", landed.size() == 1 and landed[0] == [Hit.Source.FOOD, Combat.Outcome.BLOCKED, "pizza"], "landed=%s" % [landed])
	await s.despawn(throw_game)

func _tag_effects(s: RefCounted) -> void:
	var setup := await _setup(s, 400.0, 470.0)
	var game: Node2D = setup[0]
	var attacker: Fighter = game.get_node("Fighter1")
	var target: Fighter = game.get_node("Fighter2")
	Combat.resolve(Hit.food(attacker, "soup", attacker.global_position), target)
	var hot_speed: float = target.state_machine.velocity.length()
	var hot_damage := target.damage_percent
	target.set_damage_percent(0.0)
	# Back to neutral first: a second hit during hitstun would be the 2nd hit of a
	# combo and carry its x1.1 knockback growth, which is not what this compares.
	target.state_machine._change_state("Idle")
	Combat.resolve(Hit.food(attacker, "pizza", attacker.global_position), target)
	var plain_speed: float = target.state_machine.velocity.length()
	s.check("a hot food launches 1.25 times harder than an untagged one at the same damage", is_equal_approx(hot_damage, target.damage_percent) and is_equal_approx(hot_speed, plain_speed * 1.25), "hot=%.1f plain=%.1f" % [hot_speed, plain_speed])
	s.check("an untagged food keeps its class damage", is_equal_approx(target.damage_percent, 13.0), "damage=%.1f" % target.damage_percent)

	# VFX: fire only on hot food, spin only on hard food, none in training.
	var hot_projectile: FoodProjectile = load("res://game/food/food_projectile.tscn").instantiate()
	hot_projectile.food_name = "soup"
	game.add_child(hot_projectile)
	var plain_projectile: FoodProjectile = load("res://game/food/food_projectile.tscn").instantiate()
	plain_projectile.food_name = "pizza"
	game.add_child(plain_projectile)
	var hard_projectile: FoodProjectile = load("res://game/food/food_projectile.tscn").instantiate()
	hard_projectile.food_name = "cheese"
	game.add_child(hard_projectile)
	await s.frames(20)
	s.check("a hot food flies with a fire trail", hot_projectile.get_children().any(func(n): return n is CPUParticles2D))
	s.check("an untagged food has no fire", not plain_projectile.get_children().any(func(n): return n is CPUParticles2D))
	s.check("a hard food spins", absf(hard_projectile.sprite.rotation) > 0.1 and plain_projectile.sprite.rotation == 0.0, "hard=%.2f plain=%.2f" % [hard_projectile.sprite.rotation, plain_projectile.sprite.rotation])
	game.training = true
	var training_projectile: FoodProjectile = load("res://game/food/food_projectile.tscn").instantiate()
	training_projectile.food_name = "soup"
	game.add_child(training_projectile)
	await s.frames(3)
	s.check("no food VFX in training", not training_projectile.get_children().any(func(n): return n is CPUParticles2D))
	game.training = false
	await s.despawn(game)

func _pickup_reach(s: RefCounted) -> void:
	var setup := await _setup(s, 330.0, 700.0)
	var game: Node2D = setup[0]
	var fighter: Fighter = game.get_node("Fighter1")
	var ctrl = setup[1][0]
	s.check("the default reach is wider than the old 70 px", fighter.profile.pickup_reach_x > 70.0 and fighter.profile.pickup_reach_x >= 100.0, "reach=%.0f" % fighter.profile.pickup_reach_x)
	var shape_node := fighter.pickup_area.get_node("CollisionShape2D") as CollisionShape2D
	var rect := shape_node.shape as RectangleShape2D
	s.check("the pickup area is a rectangle sized from the profile, bottom at the feet", rect != null and rect.size == Vector2(2.0 * fighter.profile.pickup_reach_x, fighter.profile.pickup_reach_height) and is_equal_approx(shape_node.position.y + rect.size.y / 2.0, fighter._feet_offset), "pos=%s" % shape_node.position)

	# 100 px away (in front) is picked up.
	var picked: Array = []
	fighter.food_picked_up.connect(func(item: String) -> void: picked.append(item))
	var near := _drop_food(s, game, "pizza", fighter.position.x + 100.0)
	await s.frames(40)
	ctrl.press_throw()
	await s.frames(4)
	s.check("food 100 px away is picked up (and announced)", fighter.held_food == "pizza" and picked == ["pizza"], "held=%s picked=%s" % [fighter.held_food, picked])
	s.check("the picked up food is gone from the stage", not is_instance_valid(near) or near.is_queued_for_deletion())
	await s.despawn(game)

	# Behind the fighter, 40 px away: feet-centred, picked up.
	var behind_setup := await _setup(s, 330.0, 700.0)
	var behind_game: Node2D = behind_setup[0]
	var behind: Fighter = behind_game.get_node("Fighter1")
	_drop_food(s, behind_game, "sandwich", behind.position.x - 40.0)
	await s.frames(40)
	behind_setup[1][0].press_throw()
	await s.frames(4)
	s.check("food 40 px behind the fighter is picked up", behind.held_food == "sandwich", "held=%s" % behind.held_food)
	await s.despawn(behind_game)

	# Out of reach: nothing.
	var far_setup := await _setup(s, 330.0, 700.0)
	var far_game: Node2D = far_setup[0]
	var far: Fighter = far_game.get_node("Fighter1")
	_drop_food(s, far_game, "bread", far.position.x + far.profile.pickup_reach_x + 80.0)
	await s.frames(40)
	far_setup[1][0].press_throw()
	await s.frames(4)
	s.check("food beyond the reach is not picked up", far.held_food == "", "held=%s" % far.held_food)
	await s.despawn(far_game)

	# The nearest of two wins.
	var two_setup := await _setup(s, 330.0, 700.0)
	var two_game: Node2D = two_setup[0]
	var chooser: Fighter = two_game.get_node("Fighter1")
	_drop_food(s, two_game, "turkey", chooser.position.x + 90.0)
	_drop_food(s, two_game, "popcorn", chooser.position.x + 25.0)
	await s.frames(40)
	two_setup[1][0].press_throw()
	await s.frames(4)
	s.check("with two foods in reach the nearest is picked up", chooser.held_food == "popcorn", "held=%s" % chooser.held_food)
	await s.despawn(two_game)

func _holding_setup(s: RefCounted) -> Array:
	var setup := await _setup(s, 330.0, 700.0)
	var fighter: Fighter = setup[0].get_node("Fighter1")
	fighter.held_food = "pizza"
	fighter.held_food_sprite.visible = true
	return setup

func _throw_priority(s: RefCounted) -> void:
	# Throw beats punch pressed in the same frame.
	var setup := await _holding_setup(s)
	var fighter: Fighter = setup[0].get_node("Fighter1")
	setup[1][0].press_punch()
	setup[1][0].press_throw()
	await s.frames(3)
	s.check("holding food, attack + throw in one frame throws and does not punch", _projectiles(setup[0]) == 1 and fighter.held_food == "" and s.state_of(fighter) == "Shoot", "projectiles=%d state=%s" % [_projectiles(setup[0]), s.state_of(fighter)])
	await s.despawn(setup[0])

	# Throw beats protect.
	var block_setup := await _holding_setup(s)
	var blocker: Fighter = block_setup[0].get_node("Fighter1")
	block_setup[1][0].block_held_level = true
	block_setup[1][0].press_block()
	block_setup[1][0].press_throw()
	await s.frames(3)
	s.check("holding food, block + throw throws and does not raise the shield", _projectiles(block_setup[0]) == 1 and s.state_of(blocker) != "Protect", "projectiles=%d state=%s" % [_projectiles(block_setup[0]), s.state_of(blocker)])
	await s.despawn(block_setup[0])

	# Jump and dash outrank the throw.
	var jump_setup := await _holding_setup(s)
	var jumper: Fighter = jump_setup[0].get_node("Fighter1")
	jump_setup[1][0].press_jump()
	jump_setup[1][0].press_throw()
	await s.frames(3)
	s.check("jump outranks the throw", s.state_of(jumper) == "Jump" and jumper.held_food == "pizza" and _projectiles(jump_setup[0]) == 0, "state=%s held=%s" % [s.state_of(jumper), jumper.held_food])
	await s.despawn(jump_setup[0])

	var dash_setup := await _holding_setup(s)
	var dasher: Fighter = dash_setup[0].get_node("Fighter1")
	dash_setup[1][0].press_dash()
	dash_setup[1][0].press_throw()
	await s.frames(3)
	s.check("dash outranks the throw", s.state_of(dasher) == "Dash" and dasher.held_food == "pizza", "state=%s held=%s" % [s.state_of(dasher), dasher.held_food])
	await s.despawn(dash_setup[0])

	var recovery_setup := await _holding_setup(s)
	var flyer: Fighter = recovery_setup[0].get_node("Fighter1")
	flyer.position.y -= 400.0
	flyer.velocity = Vector2.ZERO
	await s.frames(3)
	recovery_setup[1][0].press_special()
	recovery_setup[1][0].press_throw()
	await s.frames(3)
	s.check("recovery outranks the throw", s.state_of(flyer) == "Recovery" and flyer.held_food == "pizza", "state=%s held=%s" % [s.state_of(flyer), flyer.held_food])
	await s.despawn(recovery_setup[0])

	# Throw alone is not masked.
	var alone_setup := await _holding_setup(s)
	var alone: Fighter = alone_setup[0].get_node("Fighter1")
	alone_setup[1][0].press_throw()
	await s.frames(3)
	s.check("throw alone throws", _projectiles(alone_setup[0]) == 1 and alone.held_food == "", "projectiles=%d" % _projectiles(alone_setup[0]))
	await s.despawn(alone_setup[0])

	# No food: nothing is thrown and punch / protect keep their priority.
	var empty_setup := await _setup(s, 330.0, 700.0)
	var empty: Fighter = empty_setup[0].get_node("Fighter1")
	empty_setup[1][0].press_punch()
	empty_setup[1][0].press_throw()
	await s.frames(3)
	s.check("empty-handed, attack + throw is a punch", s.state_of(empty) == "Punch" and _projectiles(empty_setup[0]) == 0, "state=%s" % s.state_of(empty))
	await s.despawn(empty_setup[0])

	var empty_block := await _setup(s, 330.0, 700.0)
	var empty_blocker: Fighter = empty_block[0].get_node("Fighter1")
	empty_block[1][0].block_held_level = true
	empty_block[1][0].press_block()
	empty_block[1][0].press_throw()
	await s.frames(3)
	s.check("empty-handed, block + throw raises the shield", s.state_of(empty_blocker) == "Protect", "state=%s" % s.state_of(empty_blocker))
	await s.despawn(empty_block[0])

func _spawner(s: RefCounted) -> void:
	var setup := await _setup(s)
	var game: Node2D = setup[0]
	var spawner: FoodSpawner = game.food_spawner
	s.check("the default spawn interval is shorter than the old 3-5 s", spawner.spawn_min_interval < 3.0 and spawner.spawn_max_interval < 5.0 and (spawner.spawn_min_interval + spawner.spawn_max_interval) / 2.0 < 4.0, "%.1f-%.1f" % [spawner.spawn_min_interval, spawner.spawn_max_interval])
	s.check("the default cap is 5 foods", spawner.max_alive == 5)

	spawner.max_alive = 2
	for i in 8:
		spawner._on_spawn_timer_timeout()
	spawner.stop()
	await s.frames(2)
	var foods := 0
	for child in game.get_children():
		if child is FoodPickup:
			foods += 1
	s.check("the cap is respected: no new food while N are alive", foods == 2 and spawner.alive_food.size() == 2, "foods=%d" % foods)
	await s.despawn(game)
