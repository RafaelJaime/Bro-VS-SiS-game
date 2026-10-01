extends SceneTree
## S2 food readability: pickups, projectiles and held food are about 48-64 px
## on screen at camera zoom 1.0 and their collision shapes match the sprite.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const MIN_SIZE := 48.0
const MAX_SIZE := 64.0

func _initialize() -> void:
	_run()

func _sprite_size(sprite: Sprite2D) -> float:
	return maxf(sprite.texture.get_size().x, sprite.texture.get_size().y) * sprite.global_scale.x

func _run() -> void:
	var s := Smoke.new(self)
	var game: Node2D = s.spawn_game(330.0, 700.0)
	s.attach_controllers(game)
	await s.frames(30)
	var fighter: Fighter = game.get_node("Fighter1")

	var worst_pickup_low := INF
	var worst_pickup_high := 0.0
	var worst_projectile_low := INF
	var worst_projectile_high := 0.0
	var shape_mismatch := 0
	for food_name in FoodCatalog.FOOD_ITEMS.keys():
		var pickup: FoodPickup = load("res://game/food/food_pickup.tscn").instantiate()
		pickup.food_name = food_name
		game.add_child(pickup)
		var size := _sprite_size(pickup.sprite)
		worst_pickup_low = minf(worst_pickup_low, size)
		worst_pickup_high = maxf(worst_pickup_high, size)
		var radius: float = (pickup.get_node("CollisionShape2D").shape as CircleShape2D).radius
		if absf(radius * 2.0 - size) > size * 0.25:
			shape_mismatch += 1
		pickup.queue_free()

		var projectile: FoodProjectile = load("res://game/food/food_projectile.tscn").instantiate()
		projectile.food_name = food_name
		game.add_child(projectile)
		var projectile_size := _sprite_size(projectile.sprite)
		worst_projectile_low = minf(worst_projectile_low, projectile_size)
		worst_projectile_high = maxf(worst_projectile_high, projectile_size)
		var projectile_radius: float = (projectile.get_node("CollisionShape2D").shape as CircleShape2D).radius
		if absf(projectile_radius * 2.0 - projectile_size) > projectile_size * 0.25:
			shape_mismatch += 1
		projectile.queue_free()
	s.check("pickup sprites are 48-64 px", worst_pickup_low >= MIN_SIZE and worst_pickup_high <= MAX_SIZE, "range=%.1f..%.1f" % [worst_pickup_low, worst_pickup_high])
	s.check("projectile sprites are 48-64 px", worst_projectile_low >= MIN_SIZE and worst_projectile_high <= MAX_SIZE, "range=%.1f..%.1f" % [worst_projectile_low, worst_projectile_high])
	s.check("collision shapes match the sprites", shape_mismatch == 0, "mismatches=%d" % shape_mismatch)

	var held_low := INF
	var held_high := 0.0
	for food_name in FoodCatalog.FOOD_ITEMS.keys():
		var pickup: FoodPickup = load("res://game/food/food_pickup.tscn").instantiate()
		pickup.food_name = food_name
		game.add_child(pickup)
		fighter.pick_up_food(pickup)
		var size := _sprite_size(fighter.held_food_sprite)
		held_low = minf(held_low, size)
		held_high = maxf(held_high, size)
		fighter.clear_held_food()
	s.check("held food is 48-64 px", held_low >= MIN_SIZE and held_high <= MAX_SIZE, "range=%.1f..%.1f" % [held_low, held_high])

	fighter.held_food = "pizza"
	fighter.held_food_sprite.texture = FoodCatalog.get_texture("pizza")
	fighter.held_food_sprite.visible = true
	var head_top: float = fighter.hurtbox.get_node("CollisionShape2D").global_position.y - (fighter.hurtbox.get_node("CollisionShape2D").shape as RectangleShape2D).size.y / 2.0
	var food_bottom: float = fighter.held_food_sprite.global_position.y + _sprite_size(fighter.held_food_sprite) / 2.0
	s.check("held food floats above the head", food_bottom <= head_top + 2.0, "food_bottom=%.1f head_top=%.1f" % [food_bottom, head_top])

	var floor_pickup: FoodPickup = load("res://game/food/food_pickup.tscn").instantiate()
	floor_pickup.food_name = "steak"
	game.add_child(floor_pickup)
	floor_pickup.position = Vector2(500.0, s.floor_top(game) - 80.0)
	await s.frames(60)
	await s.screenshot("s2_food_sizes")
	s.finish()
