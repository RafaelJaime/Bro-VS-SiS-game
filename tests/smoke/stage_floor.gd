extends SceneTree
## (a) Both fighters land and stand on the counter floor, feet on the counter line.

const Smoke := preload("res://tests/smoke/smoke_util.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	var game := s.spawn_game()
	s.attach_controllers(game)
	await s.frames(150)

	var snapshot: Dictionary = game.get_state_snapshot()
	var top: float = snapshot["stage"]["top"]
	s.check("stage has a single floor and no platforms", snapshot["platforms"].is_empty(), "platforms=%s" % [snapshot["platforms"]])
	s.check("floor node path StaticBody2D/Floor exists", game.get_node_or_null("StaticBody2D/Floor") != null)
	var backdrop := game.get_node_or_null("Backdrop") as Sprite2D
	s.check("game owns a native-scale backdrop (1176x902 at the origin)", backdrop != null and backdrop.scale == Vector2.ONE and not backdrop.centered and backdrop.position == Vector2.ZERO and backdrop.texture.get_size() == Vector2(1176, 902))
	s.check("shared menu background is not instanced in the game", game.get_node_or_null("background") == null)

	for fighter_name in ["Fighter1", "Fighter2"]:
		var fighter: Fighter = game.get_node(fighter_name)
		s.check("%s is on the floor" % fighter_name, fighter.is_on_floor())
		var bottom := s.body_bottom(fighter)
		s.check("%s body bottom within 4px of floor top" % fighter_name, absf(bottom - top) <= 4.0, "bottom=%.1f top=%.1f" % [bottom, top])
		var feet := s.sprite_feet(fighter)
		s.check("%s sprite feet within 6px of floor top" % fighter_name, absf(feet - top) <= 6.0, "feet=%.1f top=%.1f" % [feet, top])
		s.check("%s is within the floor span" % fighter_name, fighter.position.x > snapshot["stage"]["left"] and fighter.position.x < snapshot["stage"]["right"])

	s.finish()
