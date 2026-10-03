extends SceneTree
## The results screen, windowed (both winners): a Smash-style panel with the
## winner as a deliberate bust, the reused pizza-slice menu buttons, the loser as a
## greyed portrait, final stats, and keyboard / gamepad focus navigation.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const BUTTON_CHARACTERS := "res://assets/images/ui/buttons/button5.png"
const BACK_SCENE := "res://ui/global/back_button/back_button.tscn"
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

# The art reaches the panel's bottom border: its bottom edge is at or below the
# panel's, it was lowered by the drop, and the bottom rows of the rendered panel
# are not the panel background (no strip of background between art and border).
func _check_art_meets_border(tag: String, panel: ResultsPanel) -> void:
	var rect := panel.art_rect()
	s.check("%s: the art's bottom edge is at or below the panel's inner bottom" % tag, rect.end.y >= panel.size.y, "art end=%.1f panel=%.1f" % [rect.end.y, panel.size.y])
	s.check("%s: the art was lowered a few pixels" % tag, rect.position.y >= ResultsPanel.ART_DROP - 0.01, "art top=%.1f" % rect.position.y)
	var shot := root.get_viewport().get_texture().get_image()
	var base := panel._base_color()
	var probe := Vector2i(int(panel.global_position.x + panel.size.x * 0.5), int(panel.global_position.y + panel.size.y - 6.0))
	var pixel := shot.get_pixelv(probe)
	var backgrounds: Array[Color] = [base, base.lightened(0.22), base.lightened(0.45)]
	var on_background := false
	for background in backgrounds:
		if absf(pixel.r - background.r) + absf(pixel.g - background.g) + absf(pixel.b - background.b) < 0.03:
			on_background = true
	s.check("%s: the pixels just above the border are the art, not the panel background" % tag, not on_background, "pixel=%s" % [pixel])

func _check_screen(game: Node2D, tag: String, winner_name: String, loser_name: String) -> void:
	var over: Control = game.game_over
	var winner: Fighter = game.get_node(winner_name)
	var loser: Fighter = game.get_node(loser_name)
	var panel: ResultsPanel = over.get_node("%WinnerPanel")
	var loser_panel: ResultsPanel = over.get_node("%LoserPanel")
	var button: Button = over.get_node("%CharactersButton")
	s.check("%s: the main button keeps the leftmost button's art" % tag, button.icon == load(BUTTON_CHARACTERS) and button.flat and button.expand_icon and button.text == "")
	s.check("%s: the main button is inside the screen" % tag, SCREEN.encloses(_rect(button)), str(_rect(button)))
	s.check("%s: it is captioned Characters" % tag, (button.get_node("Caption") as Label).text == "Characters")
	s.check("%s: it is the only button of the row (no Rematch, no Main Menu)" % tag, over.get_node("Buttons").get_child_count() == 1 and over.get_node_or_null("%ReplayButton") == null and over.get_node_or_null("%MainMenuButton") == null)
	var back: Button = over.get_node("BackButton")
	s.check("%s: the standard Back arrow is there (same scene as the other screens)" % tag, back.scene_file_path == BACK_SCENE and back.visible)
	s.check("%s: the Back arrow is at the bottom left, inside the screen, clear of the main button" % tag, SCREEN.encloses(_rect(back)) and _rect(back).position.x < 20.0 and _rect(back).end.y >= 560.0 and not _rect(back).intersects(_rect(button)), str(_rect(back)))

	s.check("%s: the winner panel wears the winner's color" % tag, panel.color == winner.character_ui.color)
	s.check("%s: the winner art is the illustration, cropped as a bust" % tag, panel.texture == over.call("winner_texture", winner.character_ui) and panel.texture.get_height() > panel.texture.get_width() and panel.crop < 1.0, "crop=%.2f" % panel.crop)
	s.check("%s: the bust fills the whole panel (the cut is the panel edge, no gap)" % tag, panel.art_covers_panel())
	var bounds := Rect2(Vector2.ZERO, panel.size)
	var outline_inside := true
	for point in panel.outline():
		outline_inside = outline_inside and bounds.grow(0.01).has_point(point)
	s.check("%s: the panel outline stays inside its own bounds" % tag, outline_inside)
	s.check("%s: the winner panel is on screen, apart from the buttons" % tag, SCREEN.encloses(_rect(panel)) and not _rect(panel).intersects(_rect(button)))
	var cut_height := panel.art_rect().size.y * panel.crop
	s.check("%s: the visible part of the art ends exactly at the panel bottom (intentional chest cut)" % tag, absf(cut_height - panel.size.y) < 1.0 or panel.art_rect().size.y * panel.crop > panel.size.y, "cut=%.1f panel=%.1f" % [cut_height, panel.size.y])
	_check_art_meets_border(tag + " winner", panel)
	_check_art_meets_border(tag + " loser", loser_panel)
	s.check("%s: the winner name is big and named" % tag, (over.get_node("%WinnerNameLabel") as Label).text == winner.character_ui.name.to_upper() and (over.get_node("%WinnerNameLabel") as Label).get_theme_font_size("font_size") >= 56)
	s.check("%s: WINS! is shown" % tag, (over.get_node("%WinnerLabel") as Label).text == "WINS!")

	s.check("%s: the loser is a smaller greyed face portrait" % tag, loser_panel.visible and loser_panel.greyed and loser_panel.texture == over.call("face_texture", loser.character_ui) and loser_panel.size.x < panel.size.x / 2.0)
	s.check("%s: the loser is named" % tag, (over.get_node("%LoserLabel") as Label).text == loser.character_ui.name.to_upper())
	var stats: String = (over.get_node("%StatsLabel") as Label).text
	s.check("%s: final stats show KOs, stocks left and damage" % tag, stats.contains("KOs") and stats.contains("Stocks left") and stats.contains("Damage taken"), stats.replace("\n", " | "))
	s.check("%s: the winner has stocks left in the stats" % tag, stats.contains("Stocks left  %d" % winner.stocks))
	s.check("%s: the pause-proof tree is paused with the results up" % tag, paused)

	# Focus (keyboard / gamepad share the ui_* actions): the only focusable control
	# is the main button; arrows keep it, accept opens the character select.
	s.check("%s: Characters has the focus when the results open" % tag, button.has_focus())
	await _tap(KEY_RIGHT)
	await _tap(KEY_LEFT)
	await _tap(KEY_DOWN)
	await _tap(KEY_UP)
	s.check("%s: the arrow keys never move the focus off the main button" % tag, button.has_focus())
	s.check("%s: the focused button is highlighted (grown)" % tag, button.scale.x > 1.05, "scale=%.2f" % button.scale.x)
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
	# The Back arrow and Characters navigation are clicked for real in navigation.gd.
	s.finish()
