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

	s.check("limits cover the 1176x902 world (backdrop at x=-158)", camera.limit_left == -158 and camera.limit_top == 0 and camera.limit_right == 1018 and camera.limit_bottom == 902, "limits=%d,%d,%d,%d" % [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom])

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
	s.check("zoom stays within 0.75..1.15", far_zoom >= 0.749 and far_zoom <= 1.151 and near_zoom >= 0.749 and near_zoom <= 1.151, "near=%.3f far=%.3f" % [near_zoom, far_zoom])
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

	var snapshot: Dictionary = game.get_state_snapshot()
	s.check("snapshot has a camera key with center and zoom", snapshot.has("camera") and snapshot["camera"].has("center") and snapshot["camera"].has("zoom"))
	s.finish()
