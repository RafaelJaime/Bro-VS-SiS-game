extends SceneTree
## The aerial punch keeps the jump: pressing punch while rising does not stop the
## jump (the apex stays the same) nor the horizontal momentum (air control), and
## the punch still hits. Counted in physics ticks.

const Smoke := preload("res://tests/smoke/smoke_util.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	await _air_punch_keeps_the_jump(s)
	await _air_punch_hits(s)
	s.finish()

func _setup(s: RefCounted, p1_x: float = 330.0, p2_x: float = 900.0) -> Array:
	var game: Node2D = s.spawn_game(p1_x, p2_x)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(90)
	return [game, controllers]

# One jump (optionally with a punch `punch_at` ticks in) with a held jump key and
# a held direction. Returns the apex height, its tick and the horizontal travel.
func _jump_run(s: RefCounted, punch_at: int, move: float) -> Dictionary:
	var setup := await _setup(s)
	var game: Node2D = setup[0]
	var f: Fighter = game.get_node("Fighter1")
	var ctrl = setup[1][0]
	ctrl.move_x = move
	ctrl.jump_held_level = true
	ctrl.press_jump()
	var y0 := f.position.y
	var x0 := f.position.x
	var min_y := y0
	var apex_tick := 0
	var states := {}
	for i in 70:
		if i == punch_at:
			ctrl.press_punch()
		await s.frames(1)
		states[s.state_of(f)] = true
		if f.position.y < min_y:
			min_y = f.position.y
			apex_tick = i
	var result := {"apex": y0 - min_y, "tick": apex_tick, "dx": f.position.x - x0, "states": states}
	await s.despawn(game)
	return result

func _air_punch_keeps_the_jump(s: RefCounted) -> void:
	var plain := await _jump_run(s, -1, 1.0)
	var punch_tick: int = plain["tick"] - 6
	var punched := await _jump_run(s, punch_tick, 1.0)
	var apex_ratio: float = punched["apex"] / plain["apex"]
	var dx_ratio: float = punched["dx"] / plain["dx"]
	s.check("an air punch pressed 0.1 s before the apex really punches", punched["states"].has("Punch"), "states=%s" % [punched["states"].keys()])
	s.check("a punch before the apex keeps the jump height (within 5%)", absf(apex_ratio - 1.0) <= 0.05, "apex %.0f vs %.0f px" % [punched["apex"], plain["apex"]])
	s.check("a punch in the air keeps the horizontal momentum (within 5%)", dx_ratio >= 0.95, "dx %.0f vs %.0f px" % [punched["dx"], plain["dx"]])
	var standing := await _jump_run(s, 8, 0.0)
	var standing_plain := await _jump_run(s, -1, 0.0)
	s.check("an early air punch keeps the height of a straight jump too", absf(standing["apex"] / standing_plain["apex"] - 1.0) <= 0.05, "apex %.0f vs %.0f px" % [standing["apex"], standing_plain["apex"]])

func _air_punch_hits(s: RefCounted) -> void:
	# Both fighters jump together so the target hangs in front of the puncher.
	var setup := await _setup(s, 330.0, 400.0)
	var game: Node2D = setup[0]
	var f2: Fighter = game.get_node("Fighter2")
	var ctrl = setup[1][0]
	var other = setup[1][1]
	var hits: Array = []
	f2.hit_received.connect(func(_hit: Hit, outcome: int) -> void: hits.append(outcome))
	for c in [ctrl, other]:
		c.jump_held_level = true
		c.press_jump()
	await s.frames(14)
	ctrl.press_punch()
	await s.frames(24)
	s.check("an air punch still hits", hits.has(Combat.Outcome.FULL) or hits.has(Combat.Outcome.BLOCKED), "outcomes=%s" % [hits])
	await s.despawn(game)
