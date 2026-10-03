extends SceneTree
## Combat-depth screenshots for visual review (windowed only): the shield bubble at
## a high and a low meter, the dizzy cue and the HUD shield bar. The checks are only
## that the cue is on screen; the pictures are what a person looks at.

const Smoke := preload("res://tests/smoke/smoke_util.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	await _shield_and_dizzy(s)
	await _bombs(s)
	await _hot_food(s)
	s.finish()

func _shield_and_dizzy(s: RefCounted) -> void:
	var game: Node2D = s.spawn_game(330.0, 560.0)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(90)
	var fighter: Fighter = game.get_node("Fighter1")
	var ctrl = controllers[0]
	var bubble: ShieldBubble = fighter.get_node("ShieldBubble")
	var stars: DizzyStars = fighter.get_node("DizzyStars")
	ctrl.block_held_level = true
	ctrl.press_block()
	await s.frames(6)
	await s.screenshot("cd_shield_bubble_high")
	s.check("the high bubble is on screen", bubble.visible)
	fighter.shield.set_ratio(0.18)
	await s.frames(3)
	await s.screenshot("cd_shield_bubble_low")
	s.check("the low bubble is on screen and smaller", bubble.visible and bubble.scale.x < bubble.scale_full * 0.6, "scale=%.3f" % bubble.scale.x)
	ctrl.block_held_level = false
	await s.frames(4)
	fighter.break_shield(null)
	await s.frames(14)
	await s.screenshot("cd_dizzy")
	s.check("the dizzy stars are on screen", stars.visible)
	await s.despawn(game)

# Sudden-death bombs: three falling above the table (the shadows grow on the table
# top), then one going off beside a fighter.
func _bombs(s: RefCounted) -> void:
	var game: Game = s.spawn_game(300.0, 560.0)
	s.attach_controllers(game)
	await s.frames(60)
	game.food_spawner.stop()
	game.sudden_death_intro = 0.0
	game.hazards.grace_time = 600.0
	game.hazards.bomb_damage = 0.0
	game.hazards.bomb_knockback = Vector2.ZERO
	game.force_sudden_death()
	await s.frames(5)
	var top: float = game.get_stage_bounds()["top"]
	game.hazards.spawn_bomb(430.0, top - 330.0)
	game.hazards.spawn_bomb(720.0, top - 230.0)
	game.hazards.spawn_bomb(190.0, top - 280.0)
	await s.frames(6)
	await s.screenshot("cd_bombs_falling")
	s.check("three bombs are falling", game.hazards.alive_count() == 3, "alive=%d" % game.hazards.alive_count())
	await s.screenshot("cd_bombs_falling_2")
	var blast_x: float = game.get_node("Fighter2").position.x + 70.0
	game.hazards.spawn_bomb(blast_x, top - 60.0)
	var seen_burst := false
	for i in 14:
		await s.frames(1)
		seen_burst = seen_burst or game.hazards.get_children().any(func(n): return n is CPUParticles2D)
	await s.screenshot("cd_bomb_explosion")
	s.check("an explosion burst was on screen", seen_burst)
	await s.despawn(game)

# A hot food in flight (fire trail) and the fire puff on impact.
func _hot_food(s: RefCounted) -> void:
	var game: Game = s.spawn_game(300.0, 620.0)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(60)
	game.food_spawner.stop()
	var thrower: Fighter = game.get_node("Fighter1")
	thrower.held_food = "soup"
	thrower.held_food_sprite.texture = FoodCatalog.get_texture("soup")
	thrower.held_food_sprite.visible = true
	controllers[0].press_throw()
	await s.frames(12)
	await s.screenshot("cd_hot_food_flight")
	var puff := false
	for i in 40:
		await s.frames(1)
		puff = puff or game.get_children().any(func(n): return n is CPUParticles2D)
		if puff:
			break
	await s.screenshot("cd_hot_food_impact")
	s.check("a hot food leaves a fire puff where it hits", puff)
	await s.despawn(game)
