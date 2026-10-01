extends SceneTree
## Camera framing against the HUD. During a CPU-vs-CPU match every fighter that
## is standing on the table (sampled every 0.5 s for 30 s) must be fully visible
## and never overlap a HUD panel, and the camera view stays inside its limits.
## A zoom sweep then checks the same at every zoom level.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const Level := CpuDifficulty.Level
const SAMPLE_EVERY := 0.5
const MATCH_SECONDS := 30.0
const EPSILON := 1.0
## Clear space kept between a fighter and a HUD panel.
const HUD_CLEARANCE := 8.0

func _initialize() -> void:
	_run()

# Screen-space bounds of a fighter: the union of the 120x171 hurtbox and the
# opaque pixels of the current sprite frame (what the player actually sees).
func _fighter_rect(fighter: Fighter) -> Rect2:
	var shape_node: CollisionShape2D = fighter.get_node("Hurtbox/CollisionShape2D")
	var half := (shape_node.shape as RectangleShape2D).size / 2.0
	var corners: Array[Vector2] = []
	var xf := shape_node.get_global_transform_with_canvas()
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		corners.append(xf * corner)
	var sprite := fighter.animated_sprite_2d
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	var used := texture.get_image().get_used_rect()
	var origin := Vector2(texture.get_size()) / 2.0 if sprite.centered else Vector2.ZERO
	var sprite_xf := sprite.get_global_transform_with_canvas()
	for corner in [used.position, Vector2(used.end.x, used.position.y), used.end, Vector2(used.position.x, used.end.y)]:
		corners.append(sprite_xf * (Vector2(corner) - origin + sprite.offset))
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in corners:
		low = low.min(point)
		high = high.max(point)
	return Rect2(low, high - low)

# On stage = above the tabletop and over the table, not falling off an end.
func _on_stage(s: RefCounted, fighter: Fighter, stage: Dictionary) -> bool:
	return fighter.stocks > 0 and fighter.position.x > stage["left"] and fighter.position.x < stage["right"] and s.body_bottom(fighter) <= stage["top"] + 4.0

# Checks the world rectangle that is actually rendered (the viewport canvas
# transform), not the camera properties, which lead the engine by one frame.
func _view_inside_limits(camera: Camera2D) -> bool:
	var to_world := camera.get_viewport().get_canvas_transform().affine_inverse()
	var top_left: Vector2 = to_world * Vector2.ZERO
	var bottom_right: Vector2 = to_world * Vector2(camera.get_viewport_rect().size)
	return top_left.x >= camera.limit_left - EPSILON \
			and bottom_right.x <= camera.limit_right + EPSILON \
			and top_left.y >= camera.limit_top - EPSILON \
			and bottom_right.y <= camera.limit_bottom + EPSILON

func _hud_rects(game: Node2D) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for fighter_name in ["Fighter1", "Fighter2"]:
		rects.append((game.get_node(fighter_name).get_node("PlayerUI") as FighterHud).panel.get_global_rect())
	return rects

func _run() -> void:
	var s := Smoke.new(self, 300.0)
	var game: Node2D = s.spawn_game()
	s.set_cpu(game.get_node("Fighter1"), Level.HARD, 5)
	s.set_cpu(game.get_node("Fighter2"), Level.NORMAL, 6)
	var mlog := Smoke.MatchLog.new(game, true)
	await s.frames(2)
	var camera: Camera2D = game.get_node("Camera2D")
	var stage: Dictionary = game.get_state_snapshot()["stage"]
	var screen := Vector2(root.get_visible_rect().size)
	var hud_rects := _hud_rects(game)
	var fighters: Array[Fighter] = [game.get_node("Fighter1"), game.get_node("Fighter2")]

	s.check("both HUD panels are compact (at most 100 px tall)", hud_rects[0].size.y <= 100.0 and hud_rects[1].size.y <= 100.0, "p1=%s p2=%s" % [hud_rects[0], hud_rects[1]])

	var samples := 0
	var on_stage_samples := 0
	var overlaps: Array[String] = []
	var clipped: Array[String] = []
	var limit_breaks := 0
	var first_break := ""
	var lowest_feet := 0.0
	var zoom_min := INF
	var zoom_max := -INF
	var steps := int(MATCH_SECONDS / SAMPLE_EVERY)
	for step in steps:
		await s.sim(SAMPLE_EVERY)
		samples += 1
		if not _view_inside_limits(camera):
			limit_breaks += 1
			if first_break == "":
				first_break = "t=%.1f view_origin=%s pos=%s screen_center=%s zoom=%.4f limits=%d,%d,%d,%d" % [mlog.now(), camera.get_viewport().get_canvas_transform(), camera.position, camera.get_screen_center_position(), camera.zoom.x, camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom]
		zoom_min = minf(zoom_min, camera.zoom.x)
		zoom_max = maxf(zoom_max, camera.zoom.x)
		for i in 2:
			if not _on_stage(s, fighters[i], stage):
				continue
			on_stage_samples += 1
			var rect := _fighter_rect(fighters[i])
			lowest_feet = maxf(lowest_feet, rect.end.y)
			# A launched fighter (Hurt) may outrun the camera for a moment; every
			# other on-stage pose must stay inside the screen. Above the top edge is
			# a high jump, not an occlusion.
			if s.state_of(fighters[i]) != "Hurt" and (rect.position.x < -1.0 or rect.end.x > screen.x + 1.0 or rect.end.y > screen.y + 1.0):
				clipped.append("t=%.1f f%d rect=%s" % [mlog.now(), i + 1, rect])
			for hud_rect in hud_rects:
				if rect.intersects(hud_rect.grow(HUD_CLEARANCE)):
					overlaps.append("t=%.1f f%d rect=%s hud=%s" % [mlog.now(), i + 1, rect, hud_rect])
	print("INFO %d samples, %d on-stage fighter samples, lowest on-stage foot at screen y=%.0f, zoom %.2f..%.2f, hits=%d" % [samples, on_stage_samples, lowest_feet, zoom_min, zoom_max, mlog.hits_taken[0] + mlog.hits_taken[1]])
	s.check("sampled the match every 0.5 s for 30 s", samples == int(MATCH_SECONDS / SAMPLE_EVERY))
	s.check("fighters stood on the table most of the match", on_stage_samples >= samples, "on_stage=%d samples=%d" % [on_stage_samples, samples])
	s.check("an on-stage fighter never overlaps a HUD panel", overlaps.is_empty(), "%d overlaps, first: %s" % [overlaps.size(), overlaps.slice(0, 3)])
	s.check("an on-stage fighter is never clipped by the screen edges", clipped.is_empty(), "%d clipped, first: %s" % [clipped.size(), clipped.slice(0, 3)])
	s.check("the camera view stays inside its limits", limit_breaks == 0, "%d breaks, first %s" % [limit_breaks, first_break])
	await s.despawn(game)

	await _zoom_sweep(s)
	s.finish()

# Fighters stand at growing distances (so the camera visits every zoom level);
# the tabletop must stay above the HUD band, with the fighters clear of the panels.
func _zoom_sweep(s: RefCounted) -> void:
	var game: Node2D = s.spawn_game()
	var controllers: Array = s.attach_controllers(game)
	var camera: Camera2D = game.get_node("Camera2D")
	var stage: Dictionary = game.get_state_snapshot()["stage"]
	var hud_rects := _hud_rects(game)
	var fighters: Array[Fighter] = [game.get_node("Fighter1"), game.get_node("Fighter2")]
	var band_top := Vector2(root.get_visible_rect().size).y - 130.0
	var worst_overlap := ""
	var worst_table := ""
	var zooms: Array[float] = []
	for gap in [60.0, 200.0, 400.0, 600.0, 760.0]:
		fighters[0].position.x = 430.0 - gap / 2.0
		fighters[1].position.x = 430.0 + gap / 2.0
		await s.frames(240)
		zooms.append(camera.zoom.x)
		for i in 2:
			controllers[i].move_x = 0.0
			var rect := _fighter_rect(fighters[i])
			for hud_rect in hud_rects:
				if rect.intersects(hud_rect.grow(HUD_CLEARANCE)):
					worst_overlap = "gap=%.0f zoom=%.2f rect=%s hud=%s" % [gap, camera.zoom.x, rect, hud_rect]
		var table_screen_y: float = (get_root_canvas_y(game, stage["top"]))
		if table_screen_y > band_top:
			worst_table = "gap=%.0f zoom=%.2f tabletop y=%.0f band top=%.0f" % [gap, camera.zoom.x, table_screen_y, band_top]
	print("INFO sweep zooms: %s" % [zooms])
	s.check("the sweep covers at least 0.2 of zoom range", zooms.max() - zooms.min() >= 0.2, "zooms=%s" % [zooms])
	s.check("fighters never overlap the HUD at any zoom", worst_overlap == "", worst_overlap)
	s.check("the tabletop sits above the 130 px HUD band at every zoom", worst_table == "", worst_table)
	await s.despawn(game)

func get_root_canvas_y(game: Node2D, world_y: float) -> float:
	var xf := game.get_viewport().get_canvas_transform()
	return (xf * Vector2(0.0, world_y)).y
