extends SceneTree
## The final KO (left side, right side and bottom blast zones): the defeated
## fighter must fall to the room floor drawn by the table stage and lie there with
## the defeated sprite, inside the camera view, without losing another stock, and
## the results screen must still come up.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const FLOOR_TOLERANCE := 4.0

var s: RefCounted
var _stock_events: int = 0

func _initialize() -> void:
	_run()

func _on_stocks(_fighter: Fighter, _left: int) -> void:
	_stock_events += 1

# World-space view rectangle of the match camera.
func _view_rect(game: Node2D) -> Rect2:
	var camera := game.get_node("Camera2D") as Camera2D
	var size := game.get_viewport_rect().size / camera.zoom
	return Rect2(camera.get_screen_center_position() - size / 2.0, size)

func _knock_out(game: Node2D, case_name: String) -> Fighter:
	var loser: Fighter = game.get_node("Fighter2")
	loser.set_stocks(1)
	var zone := loser.blast_zone
	match case_name:
		"left":
			loser.position = Vector2(zone.position.x - 40.0, 300.0)
		"right":
			loser.position = Vector2(zone.end.x + 40.0, 300.0)
		"bottom":
			loser.position = Vector2(-120.0, zone.end.y + 40.0)
	return loser

func _case(case_name: String, shoot: bool) -> void:
	var game: Node2D = s.spawn_game()
	var table := game.get_node("TableStage") as TableStage
	var loser := _knock_out(game, case_name)
	var winner: Fighter = game.get_node("Fighter1")
	loser.stocks_changed.connect(_on_stocks)
	_stock_events = 0
	var floor_line: float = table.floor_y - (s.body_bottom(loser) - loser.position.y)
	var min_vy := 0.0
	var reached_at := -1.0
	var saw_state := false
	var t := 0.0
	for i in 120:
		await s.real_wait(0.05)
		t += 0.05
		if game.game_over.visible:
			break
		saw_state = saw_state or s.state_of(loser) == "Defeated"
		min_vy = minf(min_vy, loser.velocity.y)
		if reached_at < 0.0 and absf(loser.position.y - floor_line) <= FLOOR_TOLERANCE:
			reached_at = t
			if shoot:
				await s.frames(6)
				await s.screenshot("defeat_%s" % case_name)
	var tag := "KO through the %s" % case_name
	s.check("%s: the loser is in the Defeated state with the defeated sprite" % tag, saw_state and loser.animated_sprite_2d.animation == &"Defeated", loser.animated_sprite_2d.animation)
	s.check("%s: it never rises while it falls" % tag, min_vy >= -0.01, "min vy=%.1f" % min_vy)
	s.check("%s: it reaches the room floor line (y=%.1f, got %.1f)" % [tag, floor_line, loser.position.y], reached_at >= 0.0, "t=%.2f" % reached_at)
	s.check("%s: and stays there" % tag, absf(loser.position.y - floor_line) <= FLOOR_TOLERANCE and absf(loser.velocity.y) < 1.0)
	var view := _view_rect(game)
	s.check("%s: its body is inside the camera view" % tag, view.has_point(Vector2(loser.position.x, floor_line)) and view.has_point(loser.position), "pos=%s view=%s" % [loser.position, view])
	s.check("%s: no extra stock was lost (a single stocks_changed, to 0)" % tag, _stock_events == 1 and loser.stocks == 0, "events=%d stocks=%d" % [_stock_events, loser.stocks])
	s.check("%s: the match is decided for the other fighter" % tag, game.winner == winner)
	for i in 60:
		if game.game_over.visible:
			break
		await s.real_wait(0.1)
	s.check("%s: the results screen still appears" % tag, game.game_over.visible)
	paused = false
	await s.despawn(game)

func _run() -> void:
	s = Smoke.new(self)
	await s.frames(3)
	await _case("left", true)
	await _case("right", true)
	await _case("bottom", true)
	s.finish()
