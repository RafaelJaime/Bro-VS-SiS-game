extends SceneTree
## Keyboard and mouse path to the bundled model, windowed: in the character select a
## player opens P2's controller dropdown with a real click, moves to "AI: BVS default"
## with the arrow keys, confirms with Enter and presses Play with a real click. The
## match must start with the bundled model on P2 (a PolicyController, no Sync node, no
## network request) and P2 must act: non-neutral intents and movement.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const SELECT_SCENE := "res://ui/character_select/character_select.tscn"
const OPTION_BVS_DEFAULT := 4

var s: RefCounted

func _initialize() -> void:
	_run()

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
		Input.parse_input_event(button)
		await s.frames(3)

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

func _run() -> void:
	s = Smoke.new(self)
	var scene_manager: Node = root.get_node("SceneManager")
	var model_manager: Node = root.get_node("ModelManager")
	var requests: Array[String] = []
	model_manager.hub_transport = func(url: String, done: Callable) -> void:
		requests.append(url)
		done.call(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())
	var holder := Node.new()
	root.add_child(holder)
	scene_manager.scene_container = holder
	var select: Control = load(SELECT_SCENE).instantiate()
	holder.add_child(select)
	await s.real_wait(0.6)

	var items: Array = select.characters_container.get_children().filter(func(node): return node is CharacterSelectItem)
	s.check("the character select lists at least two fighters", items.size() >= 2, str(items.size()))
	await click(items[0])
	await s.real_wait(0.8)
	await click(items[1])
	await s.real_wait(0.8)
	s.check("two characters are picked and Play is shown", select.player1_selected != null and select.player2_selected != null and select.play_button.visible)

	var option: OptionButton = select.ai_controller.controller_option_p2
	await pick_option(option, OPTION_BVS_DEFAULT)
	s.check("P2's dropdown shows 'AI: BVS default' after the arrow keys and Enter", option.selected == OPTION_BVS_DEFAULT and option.get_item_text(option.selected) == "AI: BVS default", "selected=%d" % option.selected)
	var config: ControllerConfig = select.ai_controller.get_controller_config(true)
	s.check("the selection is a ready Policy config holding the bundled model", config.kind == ControllerConfig.Kind.POLICY and config.model != null and config.model.repo_id == "bundled" and config.is_playable())
	s.check("the panel says the bundled model is ready and Play is enabled", select.ai_controller.status_label_p2.visible and select.ai_controller.status_label_p2.text.contains("bundled") and not select.play_button.disabled, select.ai_controller.status_label_p2.text)
	await s.screenshot("policy_select_ready")

	await click(select.play_button)
	await s.frames(10)
	var game := scene_manager.current_scene as Game
	s.check("Play starts the match scene", game != null, str(scene_manager.current_scene))
	if game == null:
		s.finish()
		return
	var p1: Fighter = game.get_node("Fighter1")
	var p2: Fighter = game.get_node("Fighter2")
	s.check("P1 is the human and P2 runs the bundled model through a PolicyController", p1.controller is HumanController and p2.controller is PolicyController and (p2.controller as PolicyController).model == config.model, "%s / %s" % [p1.controller.kind_name(), p2.controller.kind_name()])
	s.check("the match has no Sync node and made no network request", root.find_child("Sync", true, false) == null and requests.is_empty(), str(requests))
	game.skip_countdown()
	var policy := p2.controller as PolicyController
	var start_x := p2.position.x
	var active := 0
	var moved := 0.0
	for frame in 180:
		await s.frames(1)
		var intent := p2.intent
		if not is_zero_approx(intent.move_x) or intent.attack_pressed or intent.jump_pressed or intent.dash_pressed or intent.block_held or intent.throw_pressed or intent.special_pressed:
			active += 1
		moved = maxf(moved, absf(p2.position.x - start_x))
	s.check("the policy fighter takes decisions (one per 4 frames)", policy.decisions >= 40 and policy.error == "", "decisions=%d error=%s" % [policy.decisions, policy.error])
	s.check("the policy fighter's actions are non-zero (it acts, it does not idle)", active > 20, "active_frames=%d of 180" % active)
	s.check("the policy fighter moves", moved > 20.0, "max dx=%.0f" % moved)
	await s.screenshot("policy_select_match")
	model_manager.hub_transport = Callable()
	game.queue_free()
	await s.frames(2)
	s.finish()
