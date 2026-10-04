extends SceneTree
## Keyboard playtest, windowed: plays the game like a person would, through the
## real input path only. Everything the player does is an InputEventKey (keys
## read from the InputMap, never hardcoded) or a mouse click on a button, sent
## with Input.parse_input_event; the controller intent seam is never touched.
##
## Flow: main scene -> main menu -> character select (P1 Human, P2 CPU Hard) ->
## countdown -> match -> results -> Rematch -> results -> Characters -> local 2P.
## Inside the first match P2 is parked as a training dummy (`controls_locked`)
## while each P1 control is asserted, then released as the CPU Hard opponent and
## P1 plays a simple strategy (approach, punch, block, recover) to the results.
##
##   PLAYTEST_FRAMES=1 SHOT_DIR=/some/dir   save a PNG every game second
## Record: Godot --write-movie out.avi --fixed-fps 60 --resolution 800x600 --script ...

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const MENU_SCENE := "res://ui/main_menu/main_menu.tscn"
const SELECT_SCENE := "res://ui/character_select/character_select.tscn"
const Level := CpuDifficulty.Level
## CPU Hard is entry 3 of the controller option (Human, Easy, Normal, Hard).
const OPTION_CPU_HARD := 3
## Game seconds on the match clock once the control checks are done, so the
## strategy phase ends in a short, bounded time (the flow itself is the real one).
const STRATEGY_CLOCK := 30.0

var s: RefCounted
var scene_manager: Node
var p1: Fighter
var p2: Fighter
var game: Game
var mlog: RefCounted

var _down: Dictionary = {}
var _frame_count: int = 0
var _dump_frames: bool = false
var _dump_dir: String = ""

func _initialize() -> void:
	_run()

# --------------------------------------------------------------- frame dump

func _process(_delta: float) -> bool:
	_frame_count += 1
	if _dump_frames and _frame_count % 60 == 0:
		var image := root.get_texture().get_image()
		image.save_png(_dump_dir.path_join("frame_%05d.png" % (_frame_count / 60)))
	return false

# -------------------------------------------------------------- input helpers

## A key event for `action`, copied from the first InputEventKey bound to it.
func _key_event(action: StringName, pressed: bool) -> InputEventKey:
	for bound in InputMap.action_get_events(action):
		var key := bound as InputEventKey
		if key != null:
			var event := key.duplicate() as InputEventKey
			event.pressed = pressed
			return event
	push_error("no key bound to %s" % action)
	return null

func press(action: StringName) -> void:
	if _down.has(action):
		return
	_down[action] = true
	Input.parse_input_event(_key_event(action, true))

func release(action: StringName) -> void:
	if not _down.has(action):
		return
	_down.erase(action)
	Input.parse_input_event(_key_event(action, false))

func release_all() -> void:
	for action in _down.keys():
		release(action)

func tap(action: StringName, hold_frames: int = 3) -> void:
	if _down.has(action):
		release(action)
		await s.frames(1)
	press(action)
	await s.frames(hold_frames)
	release(action)

func hold_for(action: StringName, seconds: float) -> void:
	press(action)
	await s.sim(seconds)
	release(action)

## A raw keycode (UI navigation: the popup list is not a gameplay action).
func raw_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await s.frames(2)

## A real mouse click at the center of `control`: move, press, release.
func click(control: Control) -> void:
	var pos := control.get_global_transform_with_canvas() * (control.size / 2.0)
	# Controls inside an embedded popup/dialog are positioned in that window.
	var window := control.get_window()
	if window != root:
		pos += Vector2(window.position)
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await s.frames(3)
	for pressed in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.position = pos
		button.global_position = pos
		button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(button)
		await s.frames(3)

func wait_until(condition: Callable, max_frames: int = 300) -> bool:
	for i in max_frames:
		if condition.call():
			return true
		await s.frames(1)
	return condition.call()

# ---------------------------------------------------------------- match helpers

func _bind(match_game: Game) -> void:
	game = match_game
	p1 = game.get_node("Fighter1")
	p2 = game.get_node("Fighter2")

func _state(fighter: Fighter) -> String:
	return s.state_of(fighter)

func _stage() -> Dictionary:
	return game.get_state_snapshot()["stage"]

## Walks P1 to `target_x` with the left/right keys.
func walk_to(target_x: float, tolerance: float = 6.0) -> void:
	for i in 360:
		var dx := target_x - p1.position.x
		if absf(dx) <= tolerance + (14.0 if p1.velocity.x != 0.0 else 0.0):
			break
		press(&"P1_right" if dx > 0.0 else &"P1_left")
		release(&"P1_left" if dx > 0.0 else &"P1_right")
		await s.frames(1)
	release(&"P1_left")
	release(&"P1_right")
	# 20 frames (> the 18-frame double-tap window) so the next step is no dash.
	await s.frames(20)

## Puts P1 `gap` px from P2, facing it, by walking.
func set_gap(gap: float) -> void:
	for attempt in 6:
		var dx := p2.position.x - p1.position.x
		var distance := absf(dx)
		var toward: StringName = &"P1_right" if dx > 0.0 else &"P1_left"
		var away: StringName = &"P1_left" if dx > 0.0 else &"P1_right"
		if distance > gap + 14.0:
			press(toward)
			while absf(p2.position.x - p1.position.x) > gap + 14.0:
				await s.frames(1)
			release(toward)
		elif distance < gap - 14.0:
			press(away)
			while absf(p2.position.x - p1.position.x) < gap - 14.0:
				await s.frames(1)
			release(away)
		await s.frames(20)
		var now_dx := p2.position.x - p1.position.x
		if absf(absf(now_dx) - gap) <= 24.0:
			# Face the dummy: a one-frame step toward it turns the fighter.
			if p1.facing != int(signf(now_dx)):
				await tap(&"P1_right" if now_dx > 0.0 else &"P1_left", 2)
				await s.frames(20)
			return

## Waits for the dummy to be standing and vulnerable, clears its damage, puts it
## at `x` and leaves P1 standing in the middle of the table.
func reset_scene(dummy_x: float = 620.0, p1_x: float = 380.0) -> void:
	release_all()
	await wait_until(func(): return p1.is_on_floor() and _state(p1) in ["Idle", "Run"], 240)
	await wait_until(func(): return p2.is_on_floor() and _state(p2) == "Idle" and not p2.is_invulnerable, 300)
	p1.set_damage_percent(0.0)
	p2.set_damage_percent(0.0)
	p2.velocity = Vector2.ZERO
	p2.position.x = dummy_x
	await s.frames(10)
	await walk_to(p1_x)

## Samples the lowest y (the apex) of P1 over `frames` physics frames.
func apex_over(frames: int) -> float:
	var top := p1.position.y
	for i in frames:
		await s.frames(1)
		top = minf(top, p1.position.y)
	return top

func _hits(fighter: Fighter) -> float:
	return fighter.damage_percent

# ------------------------------------------------------------------------- run

func _run() -> void:
	_dump_frames = OS.get_environment("PLAYTEST_FRAMES") == "1"
	_dump_dir = OS.get_environment("SHOT_DIR")
	if _dump_dir == "":
		_dump_dir = ProjectSettings.globalize_path("user://")
	DirAccess.make_dir_recursive_absolute(_dump_dir)
	s = Smoke.new(self, 1500.0)
	scene_manager = root.get_node("SceneManager")

	await _ui_to_match()
	await _controls()
	await _cpu_fights_back_and_strategy()
	await _results_rematch_characters()
	await _local_two_player()
	release_all()
	s.finish()

# ------------------------------------------------------------------ ui flow

func _ui_to_match() -> void:
	# A throwaway first-launch flag, so the test never touches the real one.
	MainMenu.flag_path = "user://smoke_intro_seen.cfg"
	DirAccess.remove_absolute(MainMenu.flag_path)
	s.check("KB ui: the intro flag is unset on a first launch", not MainMenu.intro_seen())
	var main_scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var main := main_scene.instantiate()
	root.add_child(main)
	await s.frames(10)
	s.check("KB ui: the main scene opens the main menu", scene_manager.current_scene_path == MENU_SCENE, scene_manager.current_scene_path)
	await s.real_wait(0.5)
	await s.screenshot("kb_01_main_menu")

	var menu: Node = scene_manager.current_scene
	# The "What is this game?" dialog greets a new player once: dismiss it first.
	var dialog: AcceptDialog = menu.get_node("AcceptDialog")
	s.check("KB ui: the intro dialog is open on the first launch", dialog.visible)
	s.check("KB ui: the first launch records the intro flag", MainMenu.intro_seen())
	await click(dialog.get_ok_button())
	await s.real_wait(0.4)
	s.check("KB ui: the OK button closes the intro dialog", not dialog.visible)
	await click(menu.get_node("InfoButton"))
	await s.real_wait(0.4)
	s.check("KB ui: the info button reopens the intro dialog", dialog.visible)
	await click(dialog.get_ok_button())
	await s.real_wait(0.4)
	s.check("KB ui: the reopened dialog closes again", not dialog.visible)
	# A second launch (a fresh menu instance, the flag now set) stays quiet.
	var second: Control = load(MENU_SCENE).instantiate()
	root.add_child(second)
	await s.frames(5)
	s.check("KB ui: a later launch does not open the intro dialog", not (second.get_node("AcceptDialog") as AcceptDialog).visible)
	second.queue_free()
	await s.frames(2)
	await s.screenshot("kb_01b_main_menu_clear")
	await click(menu.get_node("MainMenuButtons/PlayButton"))
	await s.frames(10)
	s.check("KB ui: clicking Play opens the character select", scene_manager.current_scene_path == SELECT_SCENE, scene_manager.current_scene_path)
	await s.real_wait(0.6)
	await _pick_characters(scene_manager.current_scene, OPTION_CPU_HARD)

	var select: Control = scene_manager.current_scene
	await click(select.play_button)
	await s.frames(10)
	s.check("KB ui: Play starts the match scene", scene_manager.current_scene is Game, str(scene_manager.current_scene))
	_bind(scene_manager.current_scene)
	s.check("KB ui: P1 is the human, P2 the scripted CPU", p1.controller is HumanController and p2.controller is ScriptedController, "%s / %s" % [p1.controller.kind_name(), p2.controller.kind_name()])

## Clicks two character cards and picks `p2_option` in P2's controller dropdown.
func _pick_characters(select: Control, p2_option: int) -> void:
	var items: Array = select.characters_container.get_children().filter(func(node): return node is CharacterSelectItem)
	s.check("KB ui: the character select lists at least two fighters", items.size() >= 2, str(items.size()))
	await click(items[0])
	await s.real_wait(0.8)
	s.check("KB ui: clicking a card picks P1", select.player1_selected != null)
	await s.screenshot("kb_02_select_p1")
	await click(items[1])
	await s.real_wait(0.8)
	s.check("KB ui: the next click picks P2 and shows Play", select.player2_selected != null and select.play_button.visible)
	var option: OptionButton = select.ai_controller.controller_option_p2
	await pick_option(option, p2_option)
	s.check("KB ui: P2 controller set to %s from the dropdown" % option.get_item_text(p2_option), option.selected == p2_option, "selected=%d" % option.selected)
	await s.screenshot("kb_03_select_ready")

## Opens a dropdown with a mouse click and moves to `index` with the arrow keys.
func pick_option(option: OptionButton, index: int) -> void:
	await click(option)
	await s.frames(8)
	var popup := option.get_popup()
	for i in 8:
		var focused := popup.get_focused_item()
		if focused == index:
			break
		await raw_key(KEY_DOWN if focused < index else KEY_UP)
	await raw_key(KEY_ENTER)
	await s.frames(6)

# ----------------------------------------------------------------- controls

func _controls() -> void:
	# Countdown: the keys do nothing until GO.
	s.check("KB countdown: the match opens in COUNTDOWN", game.phase == Game.Phase.COUNTDOWN)
	var start_x := p1.position.x
	press(&"P1_right")
	for i in 40:
		await s.frames(1)
		if i == 10:
			await tap(&"P1_punch", 2)
			await tap(&"P1_jump", 2)
	release_all()
	s.check("KB countdown: walk, punch and jump keys are ignored", absf(p1.position.x - start_x) < 1.0 and _state(p1) in ["Idle", "Fall"], "dx=%.1f state=%s" % [p1.position.x - start_x, _state(p1)])
	await wait_until(func(): return game.phase == Game.Phase.PLAYING, 400)
	s.check("KB countdown: GO opens the match", game.phase == Game.Phase.PLAYING and not p1.controls_locked)
	mlog = Smoke.MatchLog.new(game)
	# P2 becomes a training dummy for the isolated control checks.
	p2.controls_locked = true
	await s.sim(0.5)
	await s.screenshot("kb_04_match_start")

	await _locomotion()
	await _punches()
	await _press_time_aim()
	await _recovery_and_fall()
	await _block()
	await _shield_and_dizzy()
	await _air_dodge_keys()
	await _food()
	await _throw_priority_keys()
	await _pause()
	await _ledge()

func _locomotion() -> void:
	await reset_scene(700.0, 330.0)
	var x0 := p1.position.x
	await hold_for(&"P1_right", 0.5)
	await s.frames(20)
	s.check("KB walk right: D moves P1 right and faces right", p1.position.x - x0 > 100.0 and p1.facing == 1, "dx=%.0f facing=%d" % [p1.position.x - x0, p1.facing])
	x0 = p1.position.x
	await hold_for(&"P1_left", 0.6)
	s.check("KB walk left: A moves P1 left and faces left", x0 - p1.position.x > 100.0 and p1.facing == -1, "dx=%.0f facing=%d" % [x0 - p1.position.x, p1.facing])
	await s.frames(20)

	# Full hop, short hop, double jump (apex heights above the floor position).
	var ground_y := p1.position.y
	press(&"P1_jump")
	var full_apex := await apex_over(40)
	release(&"P1_jump")
	await wait_until(func(): return p1.is_on_floor())
	var full_height := ground_y - full_apex
	s.check("KB jump: holding W makes a full hop", full_height > 140.0, "height=%.0f" % full_height)
	await s.frames(20)
	await tap(&"P1_jump", 3)
	var short_apex := await apex_over(40)
	var short_height := ground_y - short_apex
	await wait_until(func(): return p1.is_on_floor())
	s.check("KB short hop: a quick W tap hops lower than the full jump", short_height > 15.0 and short_height < full_height * 0.6, "short=%.0f full=%.0f" % [short_height, full_height])
	await s.frames(20)
	press(&"P1_jump")
	await s.frames(14)
	var before_second := p1.position.y
	# Let go and press again, as a hand does for the second jump.
	release(&"P1_jump")
	await s.frames(2)
	press(&"P1_jump")
	await s.frames(3)
	var jumps_after := p1.jumps_left
	var state_after := _state(p1)
	var vy_after := p1.velocity.y
	var double_apex := await apex_over(50)
	release(&"P1_jump")
	await wait_until(func(): return p1.is_on_floor())
	s.check("KB double jump: a second W press in the air jumps again", jumps_after == 0 and state_after == "Jump" and vy_after < -300.0 and ground_y - double_apex > full_height + 40.0, "jumps_left=%d state=%s vy=%.0f apex=%.0f (single %.0f, was at %.0f)" % [jumps_after, state_after, vy_after, ground_y - double_apex, full_height, ground_y - before_second])
	await s.frames(20)

	# Dash: a double tap of the direction key (about 0.12 s apart).
	x0 = p1.position.x
	var peak_speed := 0.0
	var dashed := false
	await tap(&"P1_right", 2)
	await s.frames(3)
	press(&"P1_right")
	for i in 20:
		await s.frames(1)
		peak_speed = maxf(peak_speed, absf(p1.velocity.x))
		dashed = dashed or _state(p1) == "Dash"
	release(&"P1_right")
	s.check("KB dash: double-tapping D dashes", dashed and peak_speed > 450.0, "dashed=%s peak=%.0f dx=%.0f" % [dashed, peak_speed, p1.position.x - x0])
	await s.frames(30)

func _punches() -> void:
	await reset_scene(620.0, 400.0)
	await set_gap(90.0)
	var base := _hits(p2)
	await tap(&"P1_punch", 3)
	await s.frames(25)
	s.check("KB punch tap: F punches and damages the CPU in reach", _hits(p2) - base > 3.0 and p1.last_attack_direction == &"neutral", "damage=%.1f dir=%s" % [_hits(p2) - base, p1.last_attack_direction])
	await s.screenshot("kb_05_punch")

	# Charged smash: hold F, the charge builds, the release hits harder.
	await reset_scene(620.0, 400.0)
	await set_gap(90.0)
	base = _hits(p2)
	press(&"P1_punch")
	await s.sim(0.9)
	var charge_seen := p1.charge_level
	var charging_state := _state(p1)
	await s.screenshot("kb_06_charge")
	release(&"P1_punch")
	await s.frames(30)
	var smash_damage := _hits(p2) - base
	s.check("KB charged smash: holding F charges, releasing hits harder than a tap", charge_seen > 0.5 and charging_state == "Punch" and smash_damage > 11.0, "charge=%.2f state=%s damage=%.1f" % [charge_seen, charging_state, smash_damage])

	# Side punch: a direction held with the punch key.
	await reset_scene(620.0, 400.0)
	await set_gap(100.0)
	base = _hits(p2)
	press(&"P1_right")
	await s.frames(2)
	await tap(&"P1_punch", 3)
	await s.frames(3)
	release(&"P1_right")
	await s.frames(22)
	s.check("KB side punch: D+F throws the side punch and hits", p1.last_attack_direction == &"side" and _hits(p2) - base > 8.0, "dir=%s damage=%.1f" % [p1.last_attack_direction, _hits(p2) - base])

	# Up punch.
	await reset_scene(620.0, 400.0)
	await set_gap(40.0)
	base = _hits(p2)
	press(&"P1_up")
	await s.frames(2)
	await tap(&"P1_punch", 3)
	await s.frames(3)
	release(&"P1_up")
	await s.frames(22)
	s.check("KB up punch: E+F throws the up punch and hits a close target", p1.last_attack_direction == &"up" and _hits(p2) - base > 6.0, "dir=%s damage=%.1f" % [p1.last_attack_direction, _hits(p2) - base])

	# Down punch.
	await reset_scene(620.0, 400.0)
	await set_gap(80.0)
	base = _hits(p2)
	press(&"P1_down")
	await s.frames(2)
	await tap(&"P1_punch", 3)
	await s.frames(3)
	release(&"P1_down")
	await s.frames(22)
	s.check("KB down punch: C+F throws the low sweep and hits", p1.last_attack_direction == &"down" and _hits(p2) - base > 5.0, "dir=%s damage=%.1f" % [p1.last_attack_direction, _hits(p2) - base])

func _recovery_and_fall() -> void:
	await reset_scene(700.0, 330.0)
	await s.frames(20)
	# Up-recovery: up + punch in the air.
	await tap(&"P1_jump", 3)
	await s.frames(8)
	press(&"P1_up")
	await s.frames(2)
	await tap(&"P1_punch", 3)
	var recovery_state := _state(p1)
	var recovery_vy := p1.velocity.y
	var spent := not p1.recovery_available
	release(&"P1_up")
	var seen_helpless := await wait_until(func(): return _state(p1) == "Helpless", 90)
	await wait_until(func(): return p1.is_on_floor(), 300)
	s.check("KB up recovery: E+F in the air bursts upward once and leaves P1 helpless", recovery_state == "Recovery" and recovery_vy < -600.0 and spent and seen_helpless, "state=%s vy=%.0f spent=%s helpless=%s" % [recovery_state, recovery_vy, spent, seen_helpless])
	await s.frames(25)

	# Fast fall: hold C while falling.
	await tap(&"P1_jump", 3)
	await wait_until(func(): return p1.velocity.y > 100.0, 90)
	var slow_vy := p1.velocity.y
	press(&"P1_down")
	await s.frames(4)
	var fast_vy := p1.velocity.y
	var fast_flag := p1.fast_falling
	var fast_state := _state(p1)
	release(&"P1_down")
	await wait_until(func(): return p1.is_on_floor(), 300)
	s.check("KB fast fall: holding C while falling snaps the fall speed up", fast_flag and fast_vy >= 700.0 and fast_vy > slow_vy, "state=%s vy %.0f -> %.0f" % [fast_state, slow_vy, fast_vy])
	await s.frames(25)

func _block() -> void:
	await reset_scene(700.0, 380.0)
	await s.frames(20)
	var base := p1.damage_percent
	press(&"P1_protect")
	await s.frames(6)
	var blocking := _state(p1)
	await s.screenshot("kb_07_block")
	var meter_before := p1.shield.value
	Combat.apply_hit(p2, p1, 8.0, Vector2(220.0, -120.0))
	await s.frames(4)
	var blocked_damage := p1.damage_percent - base
	var meter_drain := meter_before - p1.shield.value
	var chip := 8.0 * p1.profile.shield_chip_fraction
	var expected_drain := 8.0 * p1.profile.shield_damage_scale
	release(&"P1_protect")
	await s.frames(40)
	await wait_until(func(): return p1.is_on_floor() and _state(p1) == "Idle" and not p1.is_invulnerable, 240)
	var open_base := p1.damage_percent
	Combat.apply_hit(p2, p1, 8.0, Vector2(220.0, -120.0))
	await s.frames(4)
	var open_damage := p1.damage_percent - open_base
	# The hold itself drains a little between the press and the hit, so the drain is
	# the hit's shield damage plus at most a few ticks of hold.
	s.check("KB block: holding S enters Protect, takes the chip fraction and drains the meter", blocking == "Protect" and is_equal_approx(blocked_damage, chip) and meter_drain >= expected_drain and meter_drain < expected_drain + 3.0 and is_equal_approx(open_damage, 8.0), "state=%s blocked=%.2f chip=%.2f drain=%.2f open=%.1f" % [blocking, blocked_damage, chip, meter_drain, open_damage])
	await s.frames(40)

func _food() -> void:
	await reset_scene(700.0, 330.0)
	# The spawner drops one every 3-5 s: wait for one to land on the table.
	var landed := await wait_until(func(): return not _landed_food().is_empty(), 900)
	s.check("KB food: a food item drops and lands on the table", landed)
	if not landed:
		return
	var food: FoodPickup = _landed_food()[0]
	await walk_to(food.position.x, 8.0)
	await s.screenshot("kb_08_food_ground")
	await tap(&"P1_shoot", 3)
	await s.frames(6)
	var held := p1.held_food
	s.check("KB pick up: G next to a food item picks it up", held != "" and p1.held_food_sprite.visible, "held=%s" % held)
	await s.screenshot("kb_09_food_held")
	# Face the dummy and throw.
	await wait_until(func(): return _state(p1) == "Idle", 60)
	p2.position.x = p1.position.x + 220.0
	p2.velocity = Vector2.ZERO
	await s.frames(6)
	if p1.facing != 1:
		await tap(&"P1_right", 2)
		await s.frames(10)
	var base := _hits(p2)
	await tap(&"P1_shoot", 3)
	await s.frames(4)
	var thrown: bool = p1.held_food == "" and not game.get_state_snapshot()["projectiles"].is_empty()
	await s.screenshot("kb_10_food_thrown")
	await s.sim(1.2)
	s.check("KB throw: G while holding food throws it and it hits the CPU", thrown and _hits(p2) > base, "thrown=%s damage=%.1f" % [thrown, _hits(p2) - base])

func _landed_food() -> Array:
	var found: Array = []
	for child in game.get_children():
		if child is FoodPickup and not child.picked_up and child.is_on_floor():
			found.append(child)
	return found

## Combat depth through the real keys: the shield bubble and its meter, the shield
## break (dizzy, BREAK! on the card, keys ignored, the meter back at 50%), the air
## dodge, and the throw that beats a punch pressed in the same frame.
func _shield_and_dizzy() -> void:
	await reset_scene(700.0, 330.0)
	await s.frames(20)
	var bubble: ShieldBubble = p1.get_node("ShieldBubble")
	var hud: FighterHud = p1.get_node("PlayerUI")
	var meter_start := p1.shield.value
	press(&"P1_protect")
	await s.sim(1.0)
	var shielding := _state(p1) == "Protect"
	var drained := meter_start - p1.shield.value
	var bar_shown := hud.shown_shield_ratio()
	await s.screenshot("kb_15_shield_bubble")
	s.check("KB shield: holding S raises the bubble, the meter drains about 20 per second and the HUD bar follows", shielding and bubble.visible and drained > 12.0 and drained < 30.0 and absf(bar_shown - p1.shield.ratio()) < 0.05, "state=%s drained=%.1f bar=%.2f meter=%.2f" % [_state(p1), drained, bar_shown, p1.shield.ratio()])
	release(&"P1_protect")
	await s.frames(3)
	var at_release := p1.shield.value
	await s.sim(1.5)
	s.check("KB shield: letting go hides the bubble and the meter regenerates", not bubble.visible and p1.shield.value > at_release, "meter %.1f -> %.1f" % [at_release, p1.shield.value])

	# Hold it until it breaks (about 5 s from full).
	p1.shield.refill()
	press(&"P1_protect")
	var broke := await wait_until(func(): return _state(p1) == "Dizzy", 420)
	await s.frames(8)
	await s.screenshot("kb_16_dizzy")
	var stars: DizzyStars = p1.get_node("DizzyStars")
	s.check("KB shield break: holding S breaks the shield, the fighter is dizzy with stars and BREAK! on its card", broke and p1.is_dizzy() and stars.visible and hud.break_label.visible, "state=%s" % _state(p1))
	release(&"P1_protect")
	var x_dizzy := p1.position.x
	press(&"P1_right")
	await tap(&"P1_punch", 2)
	await tap(&"P1_jump", 2)
	await s.sim(0.5)
	release(&"P1_right")
	s.check("KB shield break: while dizzy the movement, punch and jump keys do nothing", _state(p1) == "Dizzy" and absf(p1.position.x - x_dizzy) < 2.0, "state=%s dx=%.1f" % [_state(p1), p1.position.x - x_dizzy])
	var woke := await wait_until(func(): return _state(p1) != "Dizzy", 300)
	s.check("KB shield break: the dizzy wears off and the meter is back at half", woke and absf(p1.shield.ratio() - 0.5) < 0.1, "ratio=%.2f" % p1.shield.ratio())
	await s.frames(30)

func _air_dodge_keys() -> void:
	await reset_scene(700.0, 330.0)
	await s.frames(20)
	await tap(&"P1_jump", 3)
	await s.frames(8)
	var meter := p1.shield.value
	await tap(&"P1_protect", 3)
	await s.frames(2)
	var dodging := _state(p1) == "AirDodge" and p1.is_intangible()
	var bubble: ShieldBubble = p1.get_node("ShieldBubble")
	s.check("KB air dodge: S in the air is an intangible dodge with no bubble and no meter cost", dodging and not bubble.visible and p1.shield.value >= meter - 0.01, "state=%s meter %.1f -> %.1f" % [_state(p1), meter, p1.shield.value])
	await wait_until(func(): return p1.is_on_floor(), 300)
	await s.frames(20)

func _throw_priority_keys() -> void:
	await reset_scene(700.0, 330.0)
	# Only the food this check drops: the spawner is stopped and anything it dropped removed.
	game.food_spawner.stop()
	for child in game.get_children():
		if child is FoodPickup:
			child.queue_free()
	await s.frames(2)
	var pickup: FoodPickup = load("res://game/food/food_pickup.tscn").instantiate()
	pickup.food_name = "turkey"
	game.add_child(pickup)
	pickup.position = Vector2(p1.position.x + 60.0, _stage()["top"] - 30.0)
	await s.sim(0.8)
	await tap(&"P1_shoot", 3)
	await s.frames(6)
	s.check("KB food: G picks up a food item that is 60 px away (the wider reach)", p1.held_food == "turkey", "held=%s" % p1.held_food)
	await wait_until(func(): return _state(p1) == "Idle", 60)
	await s.frames(25)
	# Punch and throw pressed in the same frame: the throw wins while holding food.
	var punched := false
	press(&"P1_punch")
	press(&"P1_shoot")
	for i in 4:
		await s.frames(1)
		punched = punched or _state(p1) == "Punch"
	release(&"P1_punch")
	release(&"P1_shoot")
	await s.frames(3)
	var thrown: bool = p1.held_food == "" and not game.get_state_snapshot()["projectiles"].is_empty()
	s.check("KB throw priority: F and G together throw the food and do not punch", thrown and not punched, "held=%s punched=%s state=%s" % [p1.held_food, punched, _state(p1)])
	await s.sim(1.0)

func _pause() -> void:
	await reset_scene(700.0, 380.0)
	var left_before: float = game.timer.time_left
	await s.sim(1.0)
	var running: bool = game.timer.time_left < left_before - 0.5
	await tap(&"pause", 3)
	await s.frames(4)
	var menu: Control = game.get_node("UI/Pause")
	var opened: bool = menu.visible and paused
	var frozen_at: float = game.timer.time_left
	var x_frozen := p1.position.x
	press(&"P1_right")
	await s.sim(1.0)
	release(&"P1_right")
	var stayed: bool = is_equal_approx(game.timer.time_left, frozen_at) and absf(p1.position.x - x_frozen) < 1.0
	await s.screenshot("kb_11_pause")
	# The Back arrow of the pause menu must not sit on top of a fighter panel.
	var back_rect: Rect2 = menu.get_node("BackButton").get_global_rect()
	var covers_hud := false
	for fighter in [p1, p2]:
		covers_hud = covers_hud or back_rect.intersects((fighter.get_node("PlayerUI") as FighterHud).panel.get_global_rect())
	s.check("KB pause: the Back arrow does not cover a fighter panel", not covers_hud, "back=%s" % back_rect)
	await tap(&"pause", 3)
	await s.frames(4)
	var resumed: bool = not menu.visible and not paused
	await s.sim(1.0)
	var ticking: bool = game.timer.time_left < frozen_at - 0.5
	s.check("KB pause: Esc opens the pause menu and freezes the timer and P1", running and opened and stayed, "running=%s opened=%s frozen=%s" % [running, opened, stayed])
	s.check("KB pause: Esc again resumes the match and the timer", resumed and ticking, "resumed=%s ticking=%s" % [resumed, ticking])

## Smash reads the direction when the punch starts: letting go of it right after
## the press (before the swing, before a charged release) still throws it.
func _press_time_aim() -> void:
	await reset_scene(620.0, 400.0)
	await set_gap(100.0)
	press(&"P1_right")
	await s.frames(2)
	press(&"P1_punch")
	await s.frames(1)
	release(&"P1_right")
	await s.frames(5)
	release(&"P1_punch")
	await s.frames(5)
	s.check("KB press-time aim: releasing D before the punch key still throws the side punch", p1.last_attack_direction == &"side", "dir=%s" % p1.last_attack_direction)
	await reset_scene(620.0, 400.0)
	await set_gap(100.0)
	press(&"P1_up")
	await s.frames(2)
	press(&"P1_punch")
	await s.frames(1)
	release(&"P1_up")
	await s.sim(0.5)
	release(&"P1_punch")
	await s.frames(5)
	s.check("KB press-time aim: a charged up smash keeps the direction held at the start", p1.last_attack_direction == &"up", "dir=%s" % p1.last_attack_direction)

func _ledge() -> void:
	await reset_scene(700.0, 200.0)
	var stage := _stage()
	var stocks_before := p1.stocks
	press(&"P1_left")
	await wait_until(func(): return p1.position.x < stage["left"] - 12.0, 300)
	release(&"P1_left")
	var grabbed := await wait_until(func(): return _state(p1) == "LedgeHang", 90)
	var side := p1.ledge_side
	await s.screenshot("kb_12_ledge_hang")
	s.check("KB ledge grab: walking off the table end grabs the leg", grabbed and side == -1 and p1.stocks == stocks_before, "grabbed=%s side=%d state=%s pos=(%.0f, %.0f)" % [grabbed, side, _state(p1), p1.position.x, p1.position.y])
	if not grabbed:
		await wait_until(func(): return p1.is_on_floor(), 600)
		return
	await s.sim(0.4)
	press(&"P1_up")
	await s.frames(4)
	release(&"P1_up")
	await s.sim(1.0)
	var onto_table: bool = p1.is_on_floor() and p1.position.x > stage["left"] and p1.position.x < stage["right"] and _state(p1) != "LedgeHang" and p1.stocks == stocks_before
	s.check("KB ledge climb: E on the leg climbs back onto the table", onto_table, "state=%s pos=(%.0f, %.0f)" % [_state(p1), p1.position.x, p1.position.y])

	await _ledge_held_keys()

## Smash: holding away from the table does not stop the grab (the fighter turns to
## face the stage), only holding down does.
func _ledge_held_keys() -> void:
	await reset_scene(700.0, 200.0)
	var stage := _stage()
	# Walk off the end, let go, then push away (A) just before the leg and keep holding it.
	press(&"P1_left")
	await wait_until(func(): return p1.position.x < stage["left"] - 12.0, 300)
	release(&"P1_left")
	await wait_until(func(): return p1.position.y > stage["top"] - 60.0, 120)
	press(&"P1_left")
	var grabbed := await wait_until(func(): return _state(p1) == "LedgeHang", 400)
	s.check("KB ledge grab: holding away (A) all the way down still grabs the leg", grabbed and p1.ledge_side == -1 and p1.facing == 1, "state=%s side=%d facing=%d" % [_state(p1), p1.ledge_side, p1.facing])
	await s.sim(0.4)
	s.check("KB ledge grab: a direction held through the grab does not drop the fighter", _state(p1) == "LedgeHang", "state=%s" % _state(p1))
	release(&"P1_left")
	await reset_scene(700.0, 200.0)
	press(&"P1_left")
	await wait_until(func(): return p1.position.x < stage["left"] - 12.0, 300)
	release(&"P1_left")
	press(&"P1_down")
	await s.sim(0.5)
	s.check("KB ledge grab: holding down (C) skips the grab", _state(p1) != "LedgeHang" and p1.ledge_side == 0, "state=%s" % _state(p1))
	release(&"P1_down")
	await wait_until(func(): return p1.is_on_floor() or p1.stocks < Fighter.MAX_STOCKS, 600)

# ------------------------------------------------- CPU Hard and the strategy

func _cpu_fights_back_and_strategy() -> void:
	await reset_scene(560.0, 300.0)
	game.timer.start(STRATEGY_CLOCK)
	p1.set_damage_percent(0.0)
	p2.set_damage_percent(0.0)
	mlog = Smoke.MatchLog.new(game)
	p2.controls_locked = false
	var elapsed := 0.0
	var food_throws := 0
	while game.phase != Game.Phase.OVER and elapsed < 240.0:
		await _human_step()
		elapsed += 1.0 / 60.0 * 4.0
	var over: bool = game.phase == Game.Phase.OVER
	s.check("KB match: P1's keyboard strategy plays the match to its end", over, "phase=%d after %.0f s" % [game.phase, elapsed])
	s.check("KB match: the CPU Hard fights back (P1 took damage)", mlog.damage_taken[0] > 0.0, "p1 took %.0f%% in %d hits, p2 took %.0f%% in %d hits" % [mlog.damage_taken[0], mlog.hits_taken[0], mlog.damage_taken[1], mlog.hits_taken[1]])
	s.check("KB match: P1's punches land on the CPU too", mlog.damage_taken[1] > 0.0)
	print("INFO match: p1 stocks=%d p2 stocks=%d losses=%s self-inflicted=%s" % [p1.stocks, p2.stocks, mlog.losses, mlog.self_inflicted])
	for note in mlog.notes:
		print("INFO match: %s" % note)
	release_all()

## One decision of the scripted "human": a few frames of keys, then returns.
func _human_step() -> void:
	var stage := _stage()
	var me := p1.position
	var foe := p2.position
	var state := _state(p1)
	if p1.stocks <= 0 or p2.stocks <= 0:
		release_all()
		await s.frames(4)
		return
	var off_table: bool = me.x < stage["left"] - 4.0 or me.x > stage["right"] + 4.0 or me.y > stage["top"] + 20.0
	if state == "LedgeHang":
		release_all()
		await tap(&"P1_up", 6)
		await s.frames(6)
		return
	if off_table and not p1.is_on_floor():
		await _recover(stage)
		return
	if state in ["Hurt", "Helpless", "Recovery"]:
		release_all()
		await s.frames(4)
		return
	var toward: StringName = &"P1_right" if foe.x > me.x else &"P1_left"
	var away: StringName = &"P1_left" if foe.x > me.x else &"P1_right"
	var gap := absf(foe.x - me.x)
	# Pick up food when it is lying right here, throw it when holding one.
	if p1.is_holding_food() and gap < 420.0 and p1.facing == int(signf(foe.x - me.x)):
		release_all()
		await tap(&"P1_shoot", 3)
		await s.frames(8)
		return
	if gap > 105.0:
		release(away)
		press(toward)
		# Keep clear of the edge: never run off the table chasing the CPU.
		if (toward == &"P1_left" and me.x < stage["left"] + 25.0) or (toward == &"P1_right" and me.x > stage["right"] - 25.0):
			release(toward)
		await s.frames(4)
		return
	release(&"P1_left")
	release(&"P1_right")
	# Block when the CPU winds up a punch right in front of us.
	if _state(p2) == "Punch" and gap < 150.0 and p1.is_on_floor():
		press(&"P1_protect")
		await s.sim(0.35)
		release(&"P1_protect")
		return
	if p1.facing != int(signf(foe.x - me.x)):
		await tap(toward, 2)
		return
	if GameRng.randf() < 0.3:
		# A smash: a short charge, then release.
		press(&"P1_punch")
		await s.sim(0.5)
		release(&"P1_punch")
		await s.frames(10)
	else:
		await tap(&"P1_punch", 3)
		await s.frames(12)

## Back to the table from off the edge: steer in, double jump, then the up-recovery.
func _recover(stage: Dictionary) -> void:
	var center: float = (float(stage["left"]) + float(stage["right"])) / 2.0
	var toward: StringName = &"P1_right" if p1.position.x < center else &"P1_left"
	var away: StringName = &"P1_left" if toward == &"P1_right" else &"P1_right"
	release(away)
	release(&"P1_down")
	press(toward)
	var state := _state(p1)
	if state == "Hurt" or state == "Helpless":
		await s.frames(3)
		return
	if p1.jumps_left > 0 and p1.velocity.y > 100.0 and p1.position.y > stage["top"] - 40.0:
		await tap(&"P1_jump", 3)
		return
	if p1.recovery_available and p1.velocity.y > 100.0 and p1.position.y > stage["top"] + 40.0 and p1.jumps_left == 0:
		press(&"P1_up")
		await s.frames(2)
		await tap(&"P1_punch", 3)
		release(&"P1_up")
		return
	await s.frames(3)

# ------------------------------------------------- results, rematch, characters

func _results_rematch_characters() -> void:
	var shown := await wait_until(func(): return game.game_over.visible, 900)
	s.check("KB results: GAME! leads to the results screen with a winner", shown and game.winner != null, "visible=%s winner=%s" % [shown, game.winner])
	await s.real_wait(0.8)
	await s.screenshot("kb_13_results")
	var characters_button: Button = game.game_over.get_node("%CharactersButton")
	s.check("KB results: the main button has the focus and the Back arrow is there", characters_button.has_focus() and game.game_over.get_node_or_null("BackButton") != null)
	var first_game := game
	# No results button rematches any more; SceneManager.rematch() is still the API.
	paused = false  # the old Rematch button unpaused before restarting
	scene_manager.rematch()
	await s.frames(10)
	s.check("KB rematch: a restart starts a fresh match with the same controllers", scene_manager.current_scene is Game and scene_manager.current_scene != first_game and scene_manager.current_scene.phase == Game.Phase.COUNTDOWN and not paused)
	_bind(scene_manager.current_scene)
	s.check("KB rematch: P1 is still the human and P2 the CPU", p1.controller is HumanController and p2.controller is ScriptedController)
	await wait_until(func(): return game.phase == Game.Phase.PLAYING, 400)
	await s.sim(1.5)
	await s.screenshot("kb_14_rematch")
	# Finish it quickly: P2 on its last stock, then out of the blast zone.
	p2.set_stocks(1)
	p2.position = Vector2(p2.blast_zone.position.x - 40.0, 300.0)
	shown = await wait_until(func(): return game.game_over.visible, 900)
	s.check("KB rematch: the second match also reaches the results", shown and game.winner == p1)
	await s.real_wait(0.6)
	characters_button = game.game_over.get_node("%CharactersButton")
	await click(characters_button)
	await s.frames(10)
	s.check("KB characters: clicking Characters returns to the character select", scene_manager.current_scene_path == SELECT_SCENE and not paused, scene_manager.current_scene_path)
	await s.real_wait(0.6)

# ---------------------------------------------------------------- local 2P

func _local_two_player() -> void:
	var select: Control = scene_manager.current_scene
	await _pick_characters(select, 0)
	await click(select.play_button)
	await s.frames(10)
	_bind(scene_manager.current_scene)
	s.check("KB 2P: both fighters are human controlled", p1.controller is HumanController and p2.controller is HumanController)
	await wait_until(func(): return game.phase == Game.Phase.PLAYING, 400)
	await s.sim(0.4)
	await s.screenshot("kb_15_two_players")

	# P2 keys act on P2 only.
	var p1_x := p1.position.x
	var p2_x := p2.position.x
	await hold_for(&"P2_right", 0.3)
	s.check("KB 2P: the P2 right key moves P2 and not P1", p2.position.x - p2_x > 60.0 and absf(p1.position.x - p1_x) < 1.0, "p2 dx=%.0f p1 dx=%.1f" % [p2.position.x - p2_x, p1.position.x - p1_x])
	await s.frames(20)
	p1_x = p1.position.x
	p2_x = p2.position.x
	await hold_for(&"P1_left", 0.3)
	s.check("KB 2P: the P1 left key moves P1 and not P2", p1_x - p1.position.x > 50.0 and absf(p2.position.x - p2_x) < 1.0, "p1 dx=%.0f p2 dx=%.1f" % [p1.position.x - p1_x, p2.position.x - p2_x])
	await s.frames(20)

	var p1_y := p1.position.y
	press(&"P2_jump")
	var p2_rose := await _min_y_over(p2, 30)
	release(&"P2_jump")
	s.check("KB 2P: the P2 jump key jumps P2 only", p2_rose > 100.0 and absf(p1.position.y - p1_y) < 1.0 and _state(p1) != "Jump", "p2 rose %.0f, p1 state=%s" % [p2_rose, _state(p1)])
	await wait_until(func(): return p2.is_on_floor(), 200)
	var p2_y := p2.position.y
	press(&"P1_jump")
	var p1_rose := await _min_y_over(p1, 30)
	release(&"P1_jump")
	s.check("KB 2P: the P1 jump key jumps P1 only", p1_rose > 100.0 and absf(p2.position.y - p2_y) < 1.0 and _state(p2) != "Jump", "p1 rose %.0f, p2 state=%s" % [p1_rose, _state(p2)])
	await wait_until(func(): return p1.is_on_floor(), 200)
	await s.frames(20)

	# Bring them face to face with both keyboards, then trade punches.
	var closing := true
	press(&"P1_right")
	press(&"P2_left")
	for i in 240:
		await s.frames(1)
		if absf(p2.position.x - p1.position.x) < 95.0:
			break
	release_all()
	await s.frames(18)
	s.check("KB 2P: both keyboards walked the fighters together", absf(p2.position.x - p1.position.x) < 130.0, "gap=%.0f" % absf(p2.position.x - p1.position.x))
	var p1_base := p1.damage_percent
	var p2_base := p2.damage_percent
	await tap(&"P2_punch", 3)
	await s.frames(2)
	s.check("KB 2P: the P2 punch key makes P2 punch and not P1", _state(p2) == "Punch" and _state(p1) != "Punch", "p2=%s p1=%s" % [_state(p2), _state(p1)])
	await s.frames(40)
	var p2_hit := p1.damage_percent - p1_base
	await wait_until(func(): return _state(p1) == "Idle" and not p1.is_invulnerable, 240)
	await s.frames(10)
	await tap(&"P1_punch", 3)
	await s.frames(2)
	s.check("KB 2P: the P1 punch key makes P1 punch and not P2", _state(p1) == "Punch" and _state(p2) != "Punch", "p1=%s p2=%s" % [_state(p1), _state(p2)])
	await s.frames(40)
	var p1_hit := p2.damage_percent - p2_base
	s.check("KB 2P: each punch damages the other fighter", p2_hit > 0.0 and p1_hit > 0.0, "P2 punch -> P1 %.0f%%, P1 punch -> P2 %.0f%%" % [p2_hit, p1_hit])
	await wait_until(func(): return _state(p2) == "Idle" and not p2.is_invulnerable, 240)
	await s.frames(10)
	await tap(&"P2_protect", 4)
	var p2_blocks: bool = _state(p2) == "Protect" and _state(p1) != "Protect"
	await s.frames(40)
	s.check("KB 2P: the P2 block key blocks P2 only", p2_blocks)
	await s.screenshot("kb_16_two_players_fight")

func _min_y_over(fighter: Fighter, frames: int) -> float:
	var start := fighter.position.y
	var top := start
	for i in frames:
		await s.frames(1)
		top = minf(top, fighter.position.y)
	return start - top
