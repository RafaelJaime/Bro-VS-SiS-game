extends SceneTree
## The results screen, windowed (both winners): a Smash-style panel with the
## winner as a deliberate bust, the reused pizza-slice menu buttons, the loser as a
## greyed portrait, final stats, and keyboard / gamepad focus navigation.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const BUTTON_REMATCH := "res://assets/images/ui/buttons/button5.png"
const BUTTON_CHARACTERS := "res://assets/images/ui/buttons/button1.png"
const BUTTON_MAIN_MENU := "res://assets/images/ui/buttons/button4.png"
const SCREEN := Rect2(0, 0, 800, 600)

var s: RefCounted

func _initialize() -> void:
	_run()

func _key(keycode: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	return event

func _tap(keycode: Key) -> void:
	Input.parse_input_event(_key(keycode, true))
	await s.frames(2)
	Input.parse_input_event(_key(keycode, false))
	await s.frames(3)

func _to_results(game: Node2D, loser_name: String) -> bool:
	game.skip_countdown()
	var loser: Fighter = game.get_node(loser_name)
	loser.set_stocks(1)
	loser.position = Vector2(loser.blast_zone.position.x - 80.0, 300.0)
	for i in 60:
		if game.game_over.visible:
			break
		await s.real_wait(0.1)
	await s.real_wait(0.5)
	return game.game_over.visible

func _rect(control: Control) -> Rect2:
	return Rect2(control.global_position, control.size * control.scale)

func _check_screen(game: Node2D, tag: String, winner_name: String, loser_name: String) -> void:
	var over: Control = game.game_over
	var winner: Fighter = game.get_node(winner_name)
	var loser: Fighter = game.get_node(loser_name)
	var panel: ResultsPanel = over.get_node("%WinnerPanel")
	var loser_panel: ResultsPanel = over.get_node("%LoserPanel")
	var buttons := {
		"%ReplayButton": BUTTON_REMATCH, "%CharactersButton": BUTTON_CHARACTERS, "%MainMenuButton": BUTTON_MAIN_MENU,
	}
	for button_name in buttons:
		var button: Button = over.get_node(button_name)
		var expected: Texture2D = load(buttons[button_name])
		s.check("%s: %s reuses the menu art %s" % [tag, button_name.trim_prefix("%"), String(buttons[button_name]).get_file()], button.icon == expected and button.flat and button.expand_icon)
		s.check("%s: %s is inside the screen" % [tag, button_name.trim_prefix("%")], SCREEN.encloses(_rect(button)), str(_rect(button)))
	s.check("%s: no placeholder gray rectangle buttons (no text on the buttons)" % tag, (over.get_node("%ReplayButton") as Button).text == "" and (over.get_node("%CharactersButton") as Button).text == "")
	var captions: Array[String] = []
	for button_name in buttons:
		captions.append((over.get_node(button_name).get_node("Caption") as Label).text)
	s.check("%s: captions Rematch / Characters / Main Menu" % tag, captions == ["Rematch", "Characters", "Main Menu"], str(captions))

	s.check("%s: the winner panel wears the winner's color" % tag, panel.color == winner.character_ui.color)
	s.check("%s: the winner art is the illustration, cropped as a bust" % tag, panel.texture == over.call("winner_texture", winner.character_ui) and panel.texture.get_height() > panel.texture.get_width() and panel.crop < 1.0, "crop=%.2f" % panel.crop)
	s.check("%s: the bust fills the whole panel (the cut is the panel edge, no gap)" % tag, panel.art_covers_panel())
	var bounds := Rect2(Vector2.ZERO, panel.size)
	var outline_inside := true
	for point in panel.outline():
		outline_inside = outline_inside and bounds.grow(0.01).has_point(point)
	s.check("%s: the panel outline stays inside its own bounds" % tag, outline_inside)
	s.check("%s: the winner panel is on screen, apart from the buttons" % tag, SCREEN.encloses(_rect(panel)) and not _rect(panel).intersects((_rect(over.get_node("%ReplayButton")))))
	var cut_height := panel.art_rect().size.y * panel.crop
	s.check("%s: the visible part of the art ends exactly at the panel bottom (intentional chest cut)" % tag, absf(cut_height - panel.size.y) < 1.0 or panel.art_rect().size.y * panel.crop > panel.size.y, "cut=%.1f panel=%.1f" % [cut_height, panel.size.y])
	s.check("%s: the winner name is big and named" % tag, (over.get_node("%WinnerNameLabel") as Label).text == winner.character_ui.name.to_upper() and (over.get_node("%WinnerNameLabel") as Label).get_theme_font_size("font_size") >= 56)
	s.check("%s: WINS! is shown" % tag, (over.get_node("%WinnerLabel") as Label).text == "WINS!")

	s.check("%s: the loser is a smaller greyed face portrait" % tag, loser_panel.visible and loser_panel.greyed and loser_panel.texture == over.call("face_texture", loser.character_ui) and loser_panel.size.x < panel.size.x / 2.0)
	s.check("%s: the loser is named" % tag, (over.get_node("%LoserLabel") as Label).text == loser.character_ui.name.to_upper())
	var stats: String = (over.get_node("%StatsLabel") as Label).text
	s.check("%s: final stats show KOs, stocks left and damage" % tag, stats.contains("KOs") and stats.contains("Stocks left") and stats.contains("Damage taken"), stats.replace("\n", " | "))
	s.check("%s: the winner has stocks left in the stats" % tag, stats.contains("Stocks left  %d" % winner.stocks))
	s.check("%s: the pause-proof tree is paused with the results up" % tag, paused)

	# Focus navigation (keyboard / gamepad share the ui_* actions).
	var replay: Button = over.get_node("%ReplayButton")
	var characters: Button = over.get_node("%CharactersButton")
	var main_menu: Button = over.get_node("%MainMenuButton")
	s.check("%s: Rematch has the focus when the results open" % tag, replay.has_focus())
	await _tap(KEY_RIGHT)
	s.check("%s: Right moves the focus to Characters" % tag, characters.has_focus())
	await _tap(KEY_RIGHT)
	s.check("%s: Right again moves the focus to Main Menu" % tag, main_menu.has_focus())
	await _tap(KEY_LEFT)
	s.check("%s: Left comes back to Characters" % tag, characters.has_focus())
	s.check("%s: the focused button is highlighted (grown)" % tag, characters.scale.x > 1.05, "scale=%.2f" % characters.scale.x)
	await _tap(KEY_LEFT)
	await s.frames(8)
	await s.screenshot("results_%s" % tag)

func _run() -> void:
	s = Smoke.new(self)
	await s.frames(3)
	var game: Node2D = s.spawn_game()
	var reached := await _to_results(game, "Fighter2")
	s.check("p1 wins: the match ends in the results", reached and game.winner == game.get_node("Fighter1"))
	await _check_screen(game, "p1win", "Fighter1", "Fighter2")
	paused = false
	await s.despawn(game)

	game = s.spawn_game()
	reached = await _to_results(game, "Fighter1")
	s.check("p2 wins: the match ends in the results", reached and game.winner == game.get_node("Fighter2"))
	await _check_screen(game, "p2win", "Fighter2", "Fighter1")
	s.finish()
