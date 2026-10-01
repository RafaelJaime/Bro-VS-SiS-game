extends SceneTree
## (c) fighters walk through each other, (d) food does not block fighters,
## (e) walking off the edge falls, crosses the blast zone, loses a stock, respawns.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const FOOD_SCENE := "res://game/food/food_pickup.tscn"

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	await _fighters_pass_through(s)
	await _food_is_not_solid(s)
	await _ring_out_and_respawn(s)
	s.finish()

func _fighters_pass_through(s: RefCounted) -> void:
	var game: Node2D = s.spawn_game(400.0, 450.0)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(90)
	var walker: Fighter = game.get_node("Fighter1")
	var other: Fighter = game.get_node("Fighter2")
	var start_gap := other.position.x - walker.position.x
	controllers[0].move_x = 1.0
	await s.frames(90)
	controllers[0].move_x = 0.0
	s.check("fighter walks through the other (ends on the far side)", walker.position.x > other.position.x, "walker=%.1f other=%.1f startGap=%.1f" % [walker.position.x, other.position.x, start_gap])
	await s.frames(60)
	s.check("fighters do not stand on each other's heads", absf(s.body_bottom(walker) - s.floor_top(game)) <= 4.0 and absf(s.body_bottom(other) - s.floor_top(game)) <= 4.0)
	await s.despawn(game)

func _food_is_not_solid(s: RefCounted) -> void:
	var game: Node2D = s.spawn_game(300.0, 700.0)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(60)
	var walker: Fighter = game.get_node("Fighter1")
	var top: float = s.floor_top(game)
	var food: FoodPickup = load(FOOD_SCENE).instantiate()
	food.food_name = FoodCatalog.get_random_food_name()
	game.add_child(food)
	food.position = Vector2(walker.position.x + 100.0, top - 60.0)
	await s.frames(60)
	s.check("food lands on the floor", absf(food.position.y - (top - 28.0)) <= 6.0, "food.y=%.1f expected~%.1f" % [food.position.y, top - 28.0])
	controllers[0].move_x = 1.0
	await s.frames(70)
	controllers[0].move_x = 0.0
	s.check("food does not block the walking fighter", walker.position.x > food.position.x + 20.0, "walker=%.1f food=%.1f" % [walker.position.x, food.position.x])

	var head_food: FoodPickup = load(FOOD_SCENE).instantiate()
	head_food.food_name = FoodCatalog.get_random_food_name()
	game.add_child(head_food)
	head_food.position = Vector2(walker.position.x, walker.position.y - 250.0)
	await s.frames(90)
	s.check("food dropped on a fighter falls through to the floor", head_food.position.y > walker.position.y + 40.0, "food.y=%.1f fighter.y=%.1f" % [head_food.position.y, walker.position.y])
	await s.despawn(game)

func _ring_out_and_respawn(s: RefCounted) -> void:
	var game: Node2D = s.spawn_game()
	var controllers: Array = s.attach_controllers(game)
	await s.frames(60)
	var runner: Fighter = game.get_node("Fighter1")
	var start_stocks := runner.stocks
	var edge: float = game.get_state_snapshot()["stage"]["left"]

	# Walk off the left edge, then let go so the fighter falls straight down.
	controllers[0].move_x = -1.0
	var frames_waited := 0
	while runner.position.x > edge - 40.0 and runner.stocks == start_stocks and frames_waited < 300:
		await s.frames(1)
		frames_waited += 1
	controllers[0].move_x = 0.0
	s.check("fighter walks off the edge and is no longer grounded", not runner.is_on_floor() and runner.stocks == start_stocks, "x=%.0f edge=%.0f" % [runner.position.x, edge])

	var deepest := runner.position.y
	frames_waited = 0
	while runner.stocks == start_stocks and frames_waited < 600:
		await s.frames(1)
		deepest = maxf(deepest, runner.position.y)
		frames_waited += 1
	var bottom: float = runner.blast_zone.end.y
	s.check("fall crosses the bottom blast zone", deepest > bottom - 30.0, "deepest=%.0f bottom=%.0f" % [deepest, bottom])
	s.check("crossing the blast zone loses exactly one stock", runner.stocks == start_stocks - 1, "stocks=%d" % runner.stocks)
	await s.frames(2)
	s.check("fighter respawns above the stage inside the blast zone", runner.blast_zone.has_point(runner.position) and runner.position.y < s.floor_top(game), "pos=%s" % [runner.position])
	await s.frames(240)
	s.check("respawned fighter lands on the floor again", runner.is_on_floor() and absf(s.body_bottom(runner) - s.floor_top(game)) <= 4.0)

	# Ring-out through the side blast zone (walking on in the air) also costs a stock.
	var side_start := runner.stocks
	runner.position = Vector2(snappedf(0.0, 1.0), 200.0)
	runner.velocity = Vector2(-900.0, 0.0)
	await s.frames(120)
	s.check("side blast zone costs a stock", runner.stocks == side_start - 1, "stocks=%d" % runner.stocks)
	await s.despawn(game)
