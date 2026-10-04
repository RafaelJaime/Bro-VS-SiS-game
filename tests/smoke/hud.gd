extends SceneTree
## S2 HUD (Smash style): bottom panels, big damage % that changes colour and
## pops on a hit, stock icons, no gradient bands or damage bars, small timer.

const Smoke := preload("res://tests/smoke/smoke_util.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	var game: Node2D = s.spawn_game(330.0, 700.0)
	s.attach_controllers(game)
	await s.frames(60)
	var f1: Fighter = game.get_node("Fighter1")
	var f2: Fighter = game.get_node("Fighter2")
	var hud1: FighterHud = f1.get_node("PlayerUI")
	var hud2: FighterHud = f2.get_node("PlayerUI")
	var screen := Vector2(root.get_visible_rect().size)

	s.check("HUD lives on a CanvasLayer (immune to camera zoom)", hud1 is CanvasLayer and hud2 is CanvasLayer)
	s.check("no damage progress bars remain", hud1.find_children("*", "ProgressBar", true, false).is_empty() and hud2.find_children("*", "ProgressBar", true, false).is_empty())
	s.check("no gradient bands remain", hud1.find_children("*", "TextureRect", true, false).all(func(n): return not (n.texture is GradientTexture1D)) and hud2.find_children("*", "TextureRect", true, false).all(func(n): return not (n.texture is GradientTexture1D)))

	var rect1: Rect2 = hud1.panel.get_global_rect()
	var rect2: Rect2 = hud2.panel.get_global_rect()
	s.check("P1 panel is bottom-left and P2 bottom-right", rect1.get_center().x < screen.x * 0.5 and rect2.get_center().x > screen.x * 0.5 and rect1.get_center().y > screen.y * 0.7 and rect2.get_center().y > screen.y * 0.7, "p1=%s p2=%s screen=%s" % [rect1, rect2, screen])
	s.check("panels stay inside the screen", Rect2(Vector2.ZERO, screen).encloses(rect1) and Rect2(Vector2.ZERO, screen).encloses(rect2))
	s.check("portrait and name are shown", hud1.portrait.texture != null and hud2.portrait.texture != null and hud1.name_label.text == "Rafael" and hud2.name_label.text == "Matilde", "p1=%s p2=%s" % [hud1.name_label.text, hud2.name_label.text])
	s.check("the damage number is big", hud1.percent_label.get_theme_font_size("font_size") >= 48)
	s.check("starts at 0% in white", hud1.percent_label.text == "0%" and hud1.percent_label.get_theme_color("font_color").is_equal_approx(Color.WHITE))
	s.check("stocks start at three mini faces", hud1.visible_stock_count() == 3 and hud2.visible_stock_count() == 3, "p1=%d p2=%d" % [hud1.visible_stock_count(), hud2.visible_stock_count()])

	var timer_label: Label = game.get_node("UI/TimerLabel")
	s.check("the timer is small and top-center", timer_label.get_theme_font_size("font_size") <= 48 and timer_label.get_global_rect().get_center().y < screen.y * 0.2 and absf(timer_label.get_global_rect().get_center().x - screen.x * 0.5) < 80.0, "rect=%s size=%d" % [timer_label.get_global_rect(), timer_label.get_theme_font_size("font_size")])

	var white := FighterHud.damage_color(0.0)
	var yellow := FighterHud.damage_color(60.0)
	var red := FighterHud.damage_color(120.0)
	var dark := FighterHud.damage_color(250.0)
	s.check("damage colour ramps white -> yellow -> red -> dark red", white.is_equal_approx(Color.WHITE) and yellow.r > 0.9 and yellow.g > 0.8 and yellow.b < 0.4 and red.r > 0.9 and red.g < 0.3 and dark.r < 0.6 and dark.r > 0.2 and dark.g < 0.1, "yellow=%s red=%s dark=%s" % [yellow, red, dark])

	Combat.apply_hit(f2, f1, 8.0, Vector2(220.0, -120.0))
	await s.frames(2)
	s.check("the % text updates after a hit", hud1.percent_label.text == "8%", "text=%s" % hud1.percent_label.text)
	s.check("the number pops on damage", hud1.percent_label.scale.x > 1.05, "scale=%.2f" % hud1.percent_label.scale.x)
	await s.frames(45)
	s.check("the pop settles back", absf(hud1.percent_label.scale.x - 1.0) < 0.02, "scale=%.2f" % hud1.percent_label.scale.x)

	f1.add_damage(112.0)
	await s.frames(2)
	var shown: Color = hud1.percent_label.get_theme_color("font_color")
	s.check("120% is shown in red", hud1.percent_label.text == "120%" and shown.r > 0.9 and shown.g < 0.3, "text=%s color=%s" % [hud1.percent_label.text, shown])
	s.check("the other fighter's panel is untouched", hud2.percent_label.text == "0%")

	f1.damage_percent = 0.0
	f1.damage_changed.emit(f1.damage_percent)
	f1.add_damage(8.0)
	f1.add_damage(8.0)
	await s.frames(30)
	await s.screenshot("s2_hud_after_damage")

	f2.add_damage(87.0)
	await s.frames(2)
	f1._lose_stock()
	await s.frames(2)
	s.check("losing a stock removes one mini face", hud1.visible_stock_count() == 2 and f1.stocks == 2, "icons=%d stocks=%d" % [hud1.visible_stock_count(), f1.stocks])
	f1._lose_stock()
	await s.frames(2)
	s.check("stocks keep decrementing", hud1.visible_stock_count() == 1 and hud2.visible_stock_count() == 3, "p1=%d p2=%d" % [hud1.visible_stock_count(), hud2.visible_stock_count()])
	await s.screenshot("s2_hud_after_stock_loss")

	# 300%: the darkest red must stay readable (thick outline and a shadow).
	f2.set_damage_percent(300.0)
	await s.frames(40)
	var high: Label = hud2.percent_label
	var high_color: Color = high.get_theme_color("font_color")
	s.check("300% is dark red with a thick dark outline and a shadow", high.text == "300%" and high_color.r > 0.4 and high_color.r < 0.6 and high_color.g < 0.1 and high.get_theme_constant("outline_size") >= 10 and high.get_theme_color("font_outline_color").get_luminance() < 0.1 and high.get_theme_color("font_shadow_color").a > 0.5 and high.get_theme_constant("shadow_offset_y") > 0, "color=%s outline=%d" % [high_color, high.get_theme_constant("outline_size")])
	await s.screenshot("s5b_hud_300")
	await _shield_hud(s, game, f1, f2, hud1, hud2)
	await s.despawn(game)
	await _combo_hud(s)
	s.finish()

# The shield bar under the percent follows the meter, sits idle at full, and the
# "BREAK!" cue shows while the fighter is dizzy.
func _shield_hud(s: RefCounted, game: Node2D, f1: Fighter, f2: Fighter, hud1: FighterHud, hud2: FighterHud) -> void:
	f1.stocks = Fighter.MAX_STOCKS
	f1.shield.refill()
	f2.shield.refill()
	await s.frames(3)
	s.check("the HUD card has a shield bar and a hidden BREAK label", hud1.shield_bar != null and hud1.shield_fill != null and hud1.break_label != null and not hud1.break_label.visible and hud2.shield_bar != null)
	s.check("the shield bar is a plain panel, not a ProgressBar", hud1.shield_bar.get_class() == "Panel" and hud1.shield_bar.size.y == 6.0, "size=%s" % hud1.shield_bar.size)
	s.check("a full meter shows a full bar, idle (dim)", is_equal_approx(hud1.shown_shield_ratio(), 1.0) and hud1.shield_bar.modulate.a < 0.6, "ratio=%.2f alpha=%.2f" % [hud1.shown_shield_ratio(), hud1.shield_bar.modulate.a])
	f1.shield.set_ratio(0.5)
	await s.frames(2)
	s.check("the bar fill tracks the meter (about 0.5)", absf(hud1.shown_shield_ratio() - 0.5) < 0.02 and hud1.shield_bar.modulate.a > 0.9, "ratio=%.3f" % hud1.shown_shield_ratio())
	s.check("the other fighter's bar is untouched", is_equal_approx(hud2.shown_shield_ratio(), 1.0))
	var rect: Rect2 = hud1.panel.get_global_rect()
	var bar_rect: Rect2 = hud1.shield_bar.get_global_rect()
	s.check("the bar sits inside its panel", rect.encloses(bar_rect), "panel=%s bar=%s" % [rect, bar_rect])
	f1.shield.set_ratio(0.2)
	await s.frames(2)
	var weak: Color = (hud1.shield_fill.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
	s.check("a weak shield turns the bar red", weak.r > 0.8 and weak.b < 0.4, "color=%s" % weak)
	await s.screenshot("cd_hud_shield_bar")

	f1.break_shield(null)
	await s.frames(3)
	s.check("BREAK! shows while dizzy", hud1.break_label.visible and hud1.break_label.text == "BREAK!" and not hud2.break_label.visible)
	await s.screenshot("cd_hud_break_label")
	var guard := 0
	while f1.is_dizzy() and guard < 400:
		await s.frames(1)
		guard += 1
	await s.frames(2)
	s.check("BREAK! hides when the dizzy ends", not hud1.break_label.visible)

# The combo counter on the attacker's card: hidden for one hit, "N HIT COMBO  D%" from
# two, gone about a second after the combo ends, and absent in training. The hits are
# real ones resolved through Combat, so the victim's tracker drives the signals.
func _combo_hud(s: RefCounted) -> void:
	var game: Node2D = s.spawn_game(400.0, 470.0)
	s.attach_controllers(game)
	await s.frames(60)
	var victim: Fighter = game.get_node("Fighter1")
	var attacker: Fighter = game.get_node("Fighter2")
	var attacker_hud: FighterHud = attacker.get_node("PlayerUI")
	var victim_hud: FighterHud = victim.get_node("PlayerUI")
	var label: Label = attacker_hud.combo_label
	s.check("the attacker's card has a combo label above it, hidden at first", label != null and not label.visible and label.position.y < 0.0 and label.get_theme_font_size("font_size") == 22 and label.get_theme_color("font_color") == Color.WHITE and label.get_theme_color("font_outline_color") == Color.BLACK, "label=%s" % [label])
	var jab := AttackProfile.frames(AttackProfile.make(4.0, Vector2(100.0, -50.0), Vector2(75.0, -10.0), Vector2(110.0, 40.0), &"neutral"), 2, 2, 2, 0, 0, 24, 0.0, 0.5)
	Combat.resolve(Hit.punch(attacker, jab.damage, jab.knockback, -1.0, Hit.Source.PUNCH, jab), victim)
	Combat.cancel_hit_stop()
	await s.frames(2)
	s.check("a single hit shows no combo counter", not label.visible)
	await s.frames(3)
	Combat.resolve(Hit.punch(attacker, jab.damage, jab.knockback, -1.0, Hit.Source.PUNCH, jab), victim)
	Combat.cancel_hit_stop()
	await s.frames(2)
	s.check("two hits show \"2 HIT COMBO\" with the combo damage", label.visible and label.text == "2 HIT COMBO  8%" and is_equal_approx(label.modulate.a, 1.0), "text=%s visible=%s" % [label.text, label.visible])
	s.check("the counter pops on a new hit", label.scale.x > 1.05, "scale=%.2f" % label.scale.x)
	s.check("the other fighter's card shows nothing", not victim_hud.combo_label.visible)
	await s.frames(3)
	Combat.resolve(Hit.punch(attacker, jab.damage, jab.knockback, -1.0, Hit.Source.PUNCH, jab), victim)
	Combat.cancel_hit_stop()
	await s.frames(2)
	s.check("the counter follows the combo (3 hits, 12%)", label.text == "3 HIT COMBO  12%", "text=%s" % label.text)
	# A combo of someone else (or a bomb) never shows on this card.
	victim.combo_updated.emit(5, 30.0, victim)
	s.check("a combo dealt by the other fighter is ignored", label.text == "3 HIT COMBO  12%")
	await s.screenshot("kc_combo_counter")
	# Wait for the combo to end, then time the fade in frames (60 per second).
	var guard := 0
	while victim.combo.is_active() and guard < 200:
		await s.frames(1)
		guard += 1
	await s.frames(2)
	s.check("the counter is still up right after the combo ends (it holds 0.35 s)", label.visible and label.modulate.a > 0.9, "alpha=%.2f" % label.modulate.a)
	await s.frames(36)
	await s.screenshot("kc_combo_counter_fading")
	s.check("the counter is fading about half a second later", label.visible and label.modulate.a < 0.9 and label.modulate.a > 0.0, "alpha=%.2f visible=%s" % [label.modulate.a, label.visible])
	await s.frames(36)
	s.check("the counter is gone about 1.1 s after the combo ended", not label.visible, "alpha=%.2f" % label.modulate.a)
	await s.despawn(game)

	# A bomb clears a combo without ending it: the counter must still go away.
	game = s.spawn_game(400.0, 470.0)
	s.attach_controllers(game)
	await s.frames(60)
	victim = game.get_node("Fighter1")
	attacker = game.get_node("Fighter2")
	label = (attacker.get_node("PlayerUI") as FighterHud).combo_label
	for i in 2:
		Combat.resolve(Hit.punch(attacker, jab.damage, jab.knockback, -1.0, Hit.Source.PUNCH, jab), victim)
		Combat.cancel_hit_stop()
		await s.frames(3)
	s.check("the counter shows the second hit", label.visible and label.text == "2 HIT COMBO  8%")
	Combat.resolve(Hit.bomb(victim.global_position + Vector2(40.0, 0.0), 5.0, Vector2(100.0, -100.0)), victim)
	Combat.cancel_hit_stop()
	await s.frames(90)
	s.check("a bomb clears the combo and the counter fades away anyway", not label.visible)
	await s.despawn(game)

	# Training rows have no HUD, so no counter and no signal hookup.
	var training_game: Node2D = load(Smoke.GAME_SCENE).instantiate()
	training_game.training = true
	root.add_child(training_game)
	await s.frames(3)
	var training_hud: FighterHud = training_game.get_node("Fighter1/PlayerUI")
	s.check("in training the combo counter does not exist", training_hud.combo_label == null and not training_hud.visible)
	await s.despawn(training_game)
