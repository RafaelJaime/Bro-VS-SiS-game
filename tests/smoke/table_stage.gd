extends SceneTree
## The stage is a gingham-covered table in front of the dimmed kitchen backdrop:
## the tabletop front edge is the floor, the cloth drapes over the front, legs
## stand on a room floor, and every fighter gets a ground shadow.

const Smoke := preload("res://tests/smoke/smoke_util.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	var game: Node2D = s.spawn_game()
	s.attach_controllers(game)
	await s.frames(150)

	var table := game.get_node_or_null("TableStage") as TableStage
	s.check("game has a TableStage", table != null)
	if table == null:
		s.finish()
		return
	var stage: Dictionary = game.get_state_snapshot()["stage"]
	s.check("the tabletop surface is the fight floor", is_equal_approx(table.top_y, stage["top"]), "table=%.1f floor=%.1f" % [table.top_y, stage["top"]])
	s.check("the table spans the whole floor (ring-out off both ends)", is_equal_approx(table.left_x, stage["left"]) and is_equal_approx(table.right_x, stage["right"]), "table=%.0f..%.0f floor=%.0f..%.0f" % [table.left_x, table.right_x, stage["left"], stage["right"]])
	s.check("the table is drawn behind the fighters", table.get_index() < game.get_node("Fighter1").get_index() and table.get_index() > game.get_node("Backdrop").get_index())
	s.check("the cloth uses the existing gingham art", table.cloth_texture != null and table.cloth_texture.resource_path.ends_with("plataformacuadrados.png"))
	s.check("the table has 2 to 4 wooden legs", table.leg_count >= 2 and table.leg_count <= 4, "legs=%d" % table.leg_count)
	s.check("the drape hangs 100-180 px and the legs reach a floor line below it", table.drape_height >= 100.0 and table.drape_height <= 180.0 and table.floor_y > table.top_y + table.drape_height + 60.0, "drape=%.0f floor_y=%.0f" % [table.drape_height, table.floor_y])
	s.check("the tabletop is a thin perspective band above the front edge", table.back_y < table.top_y and table.front_y > table.top_y - 1.0 and table.front_y - table.back_y < 50.0, "back=%.0f front=%.0f" % [table.back_y, table.front_y])

	var backdrop := game.get_node("Backdrop") as Sprite2D
	s.check("the backdrop is dimmed so the fighters and the table pop", backdrop.modulate.v < 0.9 and backdrop.modulate.a >= 0.99, "modulate=%s" % backdrop.modulate)

	var shadows := table.get_node_or_null("FighterShadows") as FighterShadows
	s.check("the table has a fighter ground-shadow layer", shadows != null)
	if shadows != null:
		for fighter_name in ["Fighter1", "Fighter2"]:
			var fighter: Fighter = game.get_node(fighter_name)
			var shadow := shadows.shadow_for(fighter)
			s.check("%s has a ground shadow on the tabletop" % fighter_name, not shadow.is_empty() and absf(shadow["center"].y - stage["top"]) <= 6.0 and absf(shadow["center"].x - fighter.position.x) <= 1.0, "shadow=%s" % [shadow])
		var runner: Fighter = game.get_node("Fighter1")
		var grounded := shadows.shadow_for(runner)
		var saved := runner.position
		runner.global_position = saved + Vector2(0.0, -220.0)
		var raised := shadows.shadow_for(runner)
		s.check("an airborne fighter's shadow is smaller and fainter", not raised.is_empty() and raised["radius"].x < grounded["radius"].x and raised["alpha"] < grounded["alpha"], "ground=%s air=%s" % [grounded, raised])
		runner.global_position = Vector2(stage["right"] + 120.0, saved.y)
		s.check("no shadow past the end of the table", shadows.shadow_for(runner).is_empty())
		runner.global_position = Vector2(saved.x, stage["top"] + 200.0)
		s.check("no shadow once a fighter fell below the tabletop", shadows.shadow_for(runner).is_empty())

	await s.frames(2)
	await s.screenshot("t_table_start")
	await s.despawn(game)

	var training_game: Node2D = load(Smoke.GAME_SCENE).instantiate()
	training_game.training = true
	root.add_child(training_game)
	await s.frames(3)
	s.check("training frees the decorative table", training_game.get_node_or_null("TableStage") == null)
	s.finish()
