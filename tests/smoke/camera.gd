extends SceneTree
## (f) The camera follows the fighters, zooms with their distance and keeps its
## view inside the Camera2D limits.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const EPSILON := 1.0

func _initialize() -> void:
	_run()

func _view_inside_limits(camera: Camera2D) -> bool:
	var half := camera.get_viewport_rect().size / (2.0 * camera.zoom)
	var center := camera.get_screen_center_position()
	return center.x - half.x >= camera.limit_left - EPSILON \
			and center.x + half.x <= camera.limit_right + EPSILON \
			and center.y - half.y >= camera.limit_top - EPSILON \
			and center.y + half.y <= camera.limit_bottom + EPSILON

func _run() -> void:
	var s := Smoke.new(self)
	var game: Node2D = s.spawn_game()
	s.attach_controllers(game)
	# Nodes added during _initialize get their _ready on the first frame.
	await s.frames(2)
	var camera := game.get_node_or_null("Camera2D") as Camera2D
	s.check("game has a Camera2D", camera != null)
	if camera == null:
		s.finish()
		return
	var fighter_1: Fighter = game.get_node("Fighter1")
	var fighter_2: Fighter = game.get_node("Fighter2")

	s.check("limits cover the backdrop plus its wall extension (-300,-300 to 1160,902)", camera.limit_left == -300 and camera.limit_top == -300 and camera.limit_right == 1160 and camera.limit_bottom == 902, "limits=%d,%d,%d,%d" % [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom])

	await s.frames(180)
	var near_zoom := camera.zoom.x
	var near_center := camera.get_screen_center_position()
	var near_gap := absf(fighter_2.position.x - fighter_1.position.x)

	fighter_1.position.x = 60.0
	fighter_2.position.x = 800.0
	var inside := true
	for i in 240:
		await s.frames(1)
		inside = inside and _view_inside_limits(camera)
	var far_zoom := camera.zoom.x
	var far_center := camera.get_screen_center_position()
	s.check("zoom shrinks (zooms out) when the fighters separate", far_zoom < near_zoom - 0.05, "near=%.3f far=%.3f gap %.0f -> %.0f" % [near_zoom, far_zoom, near_gap, absf(fighter_2.position.x - fighter_1.position.x)])
	s.check("zoom stays within 0.75..1.15 for fighters on the table", far_zoom >= 0.749 and far_zoom <= 1.151 and near_zoom >= 0.749 and near_zoom <= 1.151, "near=%.3f far=%.3f" % [near_zoom, far_zoom])
	s.check("view never leaves the camera limits while fighters separate", inside)

	fighter_1.position.x = 700.0
	fighter_2.position.x = 790.0
	for i in 300:
		await s.frames(1)
		inside = inside and _view_inside_limits(camera)
	var right_center := camera.get_screen_center_position()
	s.check("camera center follows the fighters to the right", right_center.x > far_center.x + 40.0, "far=%.0f right=%.0f" % [far_center.x, right_center.x])
	s.check("zoom grows again when the fighters come together", camera.zoom.x > far_zoom + 0.05, "far=%.3f close=%.3f" % [far_zoom, camera.zoom.x])
	s.check("view stays inside the limits at the right edge", inside and _view_inside_limits(camera))
	s.check("camera center moved from the start", near_center.distance_to(right_center) > 40.0)

	# --- high launches and the up-recovery apex stay in view ---
	var controllers := s.attach_controllers(game)
	fighter_1.position = Vector2(430.0, 440.0)
	fighter_1.velocity = Vector2.ZERO
	fighter_2.position = Vector2(500.0, 440.0)
	fighter_2.velocity = Vector2.ZERO
	await s.frames(120)
	var ctl = controllers[0]
	ctl.jump_held_level = true
	ctl.press_jump()
	await s.frames(18)
	ctl.press_jump()
	await s.frames(14)
	ctl.jump_held_level = false
	ctl.press_special()
	var apex := fighter_1.position.y
	var shot_taken := false
	var clipped := 0
	var worst := 0.0
	var offscreen := 0
	var lowest_view_top := INF
	for i in 80:
		await s.frames(1)
		apex = minf(apex, fighter_1.position.y)
		if not shot_taken and fighter_1.position.y < -150.0:
			shot_taken = true
			await s.screenshot("final_recovery_apex")
		var canvas := game.get_viewport().get_canvas_transform()
		var head := (canvas * (fighter_1.position + Vector2(0.0, -70.0))).y
		var feet := canvas * fighter_1.position
		if head < 0.0:
			clipped += 1
			worst = maxf(worst, -head)
		if feet.y < 0.0 or feet.y > 600.0 or feet.x < 0.0 or feet.x > 800.0:
			offscreen += 1
		inside = inside and _view_inside_limits(camera)
		lowest_view_top = minf(lowest_view_top, camera.get_screen_center_position().y - 300.0 / camera.zoom.x)
	s.check("the up-recovery rises well above the table", apex < 200.0, "apex y=%.0f" % apex)
	s.check("the camera keeps the fighter and its head in view over the recovery apex", clipped == 0 and offscreen == 0, "%d frames head cut (worst %.0f px), %d off screen, apex y=%.0f zoom=%.2f" % [clipped, worst, offscreen, apex, camera.zoom.x])
	s.check("the camera followed above the old top of the backdrop or zoomed out", lowest_view_top < 40.0 or camera.zoom.x < 0.9, "view top %.0f zoom %.2f" % [lowest_view_top, camera.zoom.x])
	s.check("the view stays inside the extended world", inside)
	await s.wait_grounded(fighter_1, 300)
	await s.frames(2)

	# A launch far above the table: the camera zooms out (below the normal minimum
	# if it must) so the fighter stays visible, and the table stays above the HUD.
	fighter_1.position = Vector2(430.0, -120.0)
	fighter_1.velocity = Vector2.ZERO
	fighter_1.set_physics_process(false)
	var high_ok := true
	for i in 90:
		await s.frames(1)
		fighter_1.position = Vector2(430.0, -120.0)
		fighter_1.velocity = Vector2.ZERO
		inside = inside and _view_inside_limits(camera)
	var canvas_high := game.get_viewport().get_canvas_transform()
	var head_high := (canvas_high * (fighter_1.position + Vector2(0.0, -70.0))).y
	var table_screen := (canvas_high * Vector2(0.0, camera.stage_top + camera.sprite_overhang)).y
	await s.screenshot("final_high_launch")
	s.check("a fighter at y=-120 is fully in view", head_high >= 0.0 and (canvas_high * fighter_1.position).y <= 600.0, "head screen y=%.0f zoom=%.2f" % [head_high, camera.zoom.x])
	s.check("zooming out for a high fighter may go below 0.75 but not below the floor", camera.zoom.x >= camera.min_view_zoom - 0.001 and camera.zoom.x < 0.75, "zoom=%.3f" % camera.zoom.x)
	s.check("the tabletop still stays above the HUD band", table_screen <= 600.0 - camera.hud_reserve + 1.0, "table at screen y=%.0f" % table_screen)
	s.check("the view stays inside the extended world after a high launch", inside)
	fighter_1.set_physics_process(true)

	await _framing_and_bubble(s, game, camera, fighter_1, fighter_2)

	var snapshot: Dictionary = game.get_state_snapshot()
	s.check("snapshot has a camera key with center and zoom", snapshot.has("camera") and snapshot["camera"].has("center") and snapshot["camera"].has("zoom"))
	s.finish()

# Hard fit: fighters standing at the far ends of the table are fully inside the
# screen (the whole rectangle, not just the center). Then a fighter launched
# beyond what any zoom can frame gets the off-screen bubble, and only then.
func _framing_and_bubble(s: RefCounted, game: Node2D, camera: MatchCamera, fighter_1: Fighter, fighter_2: Fighter) -> void:
	var stage: Dictionary = game.get_state_snapshot()["stage"]
	fighter_1.set_physics_process(false)
	fighter_2.set_physics_process(false)
	var size := camera.get_viewport_rect().size
	var worst_out := 0.0
	var bubble_seen := false
	for i in 120:
		fighter_1.position = Vector2(stage["left"] + 20.0, camera.stage_top - 90.0)
		fighter_2.position = Vector2(stage["right"] - 20.0, camera.stage_top - 90.0)
		fighter_1.velocity = Vector2.ZERO
		fighter_2.velocity = Vector2.ZERO
		await s.frames(1)
		bubble_seen = bubble_seen or camera.is_indicating(fighter_1) or camera.is_indicating(fighter_2)
	var canvas := game.get_viewport().get_canvas_transform()
	for fighter in [fighter_1, fighter_2]:
		var rect := camera.fighter_rect(fighter)
		var low: Vector2 = canvas * rect.position
		var high: Vector2 = canvas * rect.end
		worst_out = maxf(worst_out, maxf(maxf(-low.x, -low.y), maxf(high.x - size.x, high.y - size.y)))
	s.check("fighters at both ends of the table are fully on screen", worst_out <= 0.0 and not bubble_seen, "worst overshoot=%.1f px zoom=%.2f bubble=%s" % [worst_out, camera.zoom.x, str(bubble_seen)])

	# One fighter far beyond the left blast zone, the other at the right end.
	var shown := false
	for i in 120:
		fighter_1.position = Vector2(camera.world_rect.position.x - 700.0, camera.stage_top - 90.0)
		fighter_2.position = Vector2(stage["right"] - 20.0, camera.stage_top - 90.0)
		await s.frames(1)
		shown = shown or camera.is_indicating(fighter_1)
	var indicator := camera.get_node("OffscreenLayer/OffscreenIndicator") as OffscreenIndicator
	await s.screenshot("offscreen_indicator")
	s.check("a fighter no zoom can frame gets the off-screen bubble", shown and indicator.visible and not camera.is_indicating(fighter_2), "indicating f1=%s f2=%s" % [str(camera.is_indicating(fighter_1)), str(camera.is_indicating(fighter_2))])
	var bubble_pos := OffscreenIndicator.bubble_position(Vector2(-900.0, 300.0), size, camera.hud_reserve)
	s.check("the bubble sits on the screen edge, inside the screen", bubble_pos.x < 80.0 and bubble_pos.x >= 0.0 and bubble_pos.y >= 0.0 and bubble_pos.y <= size.y - camera.hud_reserve, "pos=%s" % [bubble_pos])
	fighter_1.set_physics_process(true)
	fighter_2.set_physics_process(true)
