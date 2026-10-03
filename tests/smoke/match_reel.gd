extends SceneTree
## Final integration reel, windowed: a CPU Hard vs CPU Normal match started from
## the real character select runs countdown, fight, GAME! and the results while
## this script saves a screenshot every 2 game seconds (reel_000.png, ...) into
## SHOT_DIR, and checks the whole run:
##   - no script error (run_all.sh also greps the engine output),
##   - while a fighter is inside the blast zones it is on screen (center, and its
##     head with a margin), sampled every physics frame; only a launched (Hurt)
##     fighter that the camera shows with its off-screen bubble may be out of view,
##   - no stray pixels: no saturated blue specks in the top band of any gameplay
##     frame, and no particle emitter running during play except the hit sparks,
##   - the match flow reaches the results with a winner.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const SELECT_SCENE := "res://ui/character_select/character_select.tscn"
const Level := CpuDifficulty.Level
## Match clock in seconds: long enough for many exchanges, short for CI.
const MATCH_CLOCK := 60.0
const SHOT_EVERY := 2.0
## Screen margin (px) around the viewport a fighter must stay inside, and the
## art height above a fighter's origin that counts as its head.
const SCREEN_MARGIN := 4.0
const HEAD_HEIGHT := 70.0
## The top band of the screen that holds nothing but the timer.
const TOP_BAND := 70

var s: RefCounted
var shot_index: int = 0
var samples: int = 0
var off_screen: int = 0
var bubbled: int = 0
var head_clipped: int = 0
var first_off: String = ""
var first_clipped: String = ""
var worst_clip: float = 0.0
var stray_hits: Array[String] = []
var emitter_hits: Array[String] = []

func _initialize() -> void:
	_run()

func _reel_shot(top_band_check: bool) -> void:
	var path: String = await s.screenshot("reel_%03d" % shot_index)
	shot_index += 1
	if top_band_check:
		var image := Image.load_from_file(path)
		var found := _blue_specks(image)
		if found != "":
			stray_hits.append("%s %s" % [path.get_file(), found])

# Saturated blue pixels in the top band: nothing legitimate is drawn there during
# play, so any is a stray dot (a leftover particle, a progress node, ...).
func _blue_specks(image: Image) -> String:
	var found: Array[String] = []
	for y in mini(TOP_BAND, image.get_height()):
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.b > 0.55 and c.r < 0.3 and c.g < 0.3 and c.b - maxf(c.r, c.g) > 0.4:
				found.append("(%d,%d)" % [x, y])
				if found.size() >= 6:
					return " ".join(found)
	return " ".join(found)

# Which GPU/CPU particle emitters are running and visible right now. The intentional
# effects of combat depth are not strays: the fire trail of a hot food in flight, the
# one-shot fire puff where it hits and the sudden-death bomb effects.
func _running_emitters(game: Node) -> Array[String]:
	var names: Array[String] = []
	for node in game.find_children("*", "", true, false):
		if node.get_parent() is FoodProjectile or node.get_parent() is SuddenDeathHazards or node.get_parent() is Bomb:
			continue
		if node is CPUParticles2D and node.one_shot:
			continue
		var running := false
		if node is GPUParticles2D:
			running = node.emitting
		elif node is CPUParticles2D:
			running = node.emitting
		if running and node.is_visible_in_tree() and node.name != &"HurtParticles":
			names.append(String(node.get_path()))
	return names

func _sample(game: Game) -> void:
	if game.phase != Game.Phase.PLAYING:
		return
	var canvas := game.get_viewport().get_canvas_transform()
	var size := game.get_viewport().get_visible_rect().size
	var zone := Rect2(game.blast_left, game.blast_top, game.blast_right - game.blast_left, game.blast_bottom - game.blast_top)
	for index in 2:
		var fighter: Fighter = game.get_node("Fighter%d" % (index + 1))
		if fighter.stocks <= 0 or not zone.has_point(fighter.position):
			continue
		samples += 1
		var screen := canvas * fighter.position
		var inside := screen.x >= -SCREEN_MARGIN and screen.x <= size.x + SCREEN_MARGIN and screen.y >= -SCREEN_MARGIN and screen.y <= size.y + SCREEN_MARGIN
		var bubble: bool = fighter.state_machine.current_state.name == &"Hurt" and (game.get_node("Camera2D") as MatchCamera).is_indicating(fighter)
		if bubble:
			bubbled += 1
		if not inside and not bubble:
			off_screen += 1
			if first_off == "":
				first_off = "fighter %d at t=%.1f pos=%s screen=%s" % [index + 1, game.timer.wait_time - game.timer.time_left, fighter.position, screen]
		var head: float = (canvas * (fighter.position + Vector2(0.0, -HEAD_HEIGHT))).y
		if head < 0.0:
			head_clipped += 1
			worst_clip = maxf(worst_clip, -head)
			if first_clipped == "":
				first_clipped = "fighter %d pos=%s head screen y=%.0f zoom=%.2f" % [index + 1, fighter.position, head, game.get_node("Camera2D").zoom.x]

func _run() -> void:
	s = Smoke.new(self, 600.0)
	var scene_manager: Node = root.get_node("SceneManager")
	var holder := Node.new()
	root.add_child(holder)
	scene_manager.scene_container = holder

	scene_manager.change_scene(SELECT_SCENE)
	var select: Control = scene_manager.current_scene
	await s.frames(3)
	select.select_player1(select.characters[0])
	select.select_player2(select.characters[1])
	var ai: Control = select.get_node("AIController")
	ai.get_node("ControlP1/ControllerOption").select(3)
	ai.get_node("ControlP2/ControllerOption").select(2)
	await s.real_wait(0.8)
	await _reel_shot(false)
	select._on_play_button_pressed()
	await s.frames(3)
	var game: Game = scene_manager.current_scene
	s.check("reel: the match is a Game opened by the character select", game != null and game.phase == Game.Phase.COUNTDOWN)
	if game == null:
		s.finish()
		return
	var fighter_1: Fighter = game.get_node("Fighter1")
	var fighter_2: Fighter = game.get_node("Fighter2")
	s.check("reel: P1 is CPU Hard and P2 CPU Normal", fighter_1.controller is ScriptedController and fighter_2.controller is ScriptedController and is_equal_approx(fighter_1.controller.difficulty.action_accuracy, CpuDifficulty.preset(Level.HARD).action_accuracy) and is_equal_approx(fighter_2.controller.difficulty.action_accuracy, CpuDifficulty.preset(Level.NORMAL).action_accuracy))

	# Countdown frames.
	await _reel_shot(false)
	var waited := 0.0
	while game.phase == Game.Phase.COUNTDOWN and waited < 10.0:
		await s.sim(0.5)
		waited += 0.5
		if game.phase == Game.Phase.COUNTDOWN:
			await _reel_shot(false)
	s.check("reel: the countdown hands over to PLAYING", game.phase == Game.Phase.PLAYING)
	game.timer.start(MATCH_CLOCK)

	var since_shot := 0
	var total_frames := 0
	var shot_frames := int(SHOT_EVERY * Engine.physics_ticks_per_second)
	while not game.game_over.visible and total_frames < int((MATCH_CLOCK + 60.0) * Engine.physics_ticks_per_second):
		await s.frames(1)
		total_frames += 1
		since_shot += 1
		_sample(game)
		if game.phase == Game.Phase.PLAYING:
			for emitter in _running_emitters(game):
				if emitter not in emitter_hits:
					emitter_hits.append(emitter)
		if since_shot >= shot_frames:
			since_shot = 0
			await _reel_shot(game.phase == Game.Phase.PLAYING)

	s.check("reel: the match reaches the results screen", game.game_over.visible, "phase=%d after %.0f game s" % [game.phase, total_frames / 60.0])
	s.check("reel: the match has a winner", game.winner != null)
	await s.real_wait(0.6)
	await _reel_shot(false)
	await s.real_wait(2.0)
	await _reel_shot(false)

	s.check("reel: both fighters stayed on screen whenever inside the blast zones", off_screen == 0, "%d of %d samples off screen; first: %s" % [off_screen, samples, first_off])
	s.check("reel: no fighter head was cut off by the top of the screen", head_clipped == 0, "%d of %d samples, worst %.0f px; first: %s" % [head_clipped, samples, worst_clip, first_clipped])
	s.check("reel: no stray blue specks in the top band of any gameplay frame", stray_hits.is_empty(), " | ".join(stray_hits))
	s.check("reel: no stray particle emitter ran during play", emitter_hits.is_empty(), ", ".join(emitter_hits))
	s.check("reel: a screenshot was saved every 2 game seconds", shot_index >= int(MATCH_CLOCK / SHOT_EVERY) - 3, "%d frames" % shot_index)
	print("INFO reel frames=%d samples=%d bubble samples=%d" % [shot_index, samples, bubbled])
	s.finish()
