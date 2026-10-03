extends SceneTree
## The shield bubble look: tinted with each fighter's player colour (the CharacterUI
## colour the HUD panel uses; P1 blue, P2 red), a weak shield fades and pulses
## instead of changing colour, and the bubble shrinks away during the drop lag.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const HUE_TOLERANCE := 0.02

func _initialize() -> void:
	_run()

func _character(character_name: String, color: Color) -> CharacterUI:
	var character := CharacterUI.new()
	character.name = character_name
	character.color = color
	return character

func _run() -> void:
	var s := Smoke.new(self)
	var game: Node2D = s.spawn_game(360.0, 560.0)
	var controllers: Array = s.attach_controllers(game)
	var f1: Fighter = game.get_node("Fighter1")
	var f2: Fighter = game.get_node("Fighter2")
	# The select screen's two players: Rafael (blue) and Matilde (red).
	f1.character_ui = _character("Rafael", Color(0, 0, 1))
	f2.character_ui = _character("Matilde", Color(1, 0, 0))
	await s.frames(90)

	var bubble1 := f1.get_node("ShieldBubble") as ShieldBubble
	var bubble2 := f2.get_node("ShieldBubble") as ShieldBubble
	s.check("the bubble is hidden when nobody shields", not bubble1.visible and not bubble2.visible)
	for c in controllers:
		c.block_held_level = true
		c.press_block()
	await s.frames(20)
	s.check("both bubbles show while shielding", bubble1.visible and bubble2.visible)
	var hue1 := bubble1.modulate.h
	var hue2 := bubble2.modulate.h
	s.check("P1's bubble has the blue player colour hue", absf(hue1 - f1.character_ui.color.h) <= HUE_TOLERANCE and bubble1.modulate.s > 0.5, "hue=%.3f sat=%.2f" % [hue1, bubble1.modulate.s])
	s.check("P2's bubble has the red player colour hue", minf(absf(hue2 - f2.character_ui.color.h), 1.0 - absf(hue2 - f2.character_ui.color.h)) <= HUE_TOLERANCE and bubble2.modulate.s > 0.5, "hue=%.3f sat=%.2f" % [hue2, bubble2.modulate.s])
	s.check("the two bubbles are visibly different colours", bubble1.modulate.b > bubble1.modulate.r and bubble2.modulate.r > bubble2.modulate.b, "p1=%s p2=%s" % [bubble1.modulate, bubble2.modulate])
	s.check("the bubble colour source is the HUD's CharacterUI colour", ShieldBubble.player_color(f1) == f1.character_ui.color and ShieldBubble.player_color(f2) == f2.character_ui.color)
	await s.screenshot("shield_both_colors")

	# Weak shield: the player's hue stays, the bubble fades and pulses.
	var full_alpha := bubble1.modulate.a
	f1.shield.set_ratio(0.3)
	var alphas: Array[float] = []
	var hue_kept := true
	await s.frames(2)
	for i in 20:
		await s.frames(1)
		alphas.append(bubble1.modulate.a)
		hue_kept = hue_kept and absf(bubble1.modulate.h - f1.character_ui.color.h) <= HUE_TOLERANCE
	var high: float = alphas.max()
	# The pulse runs on wall-clock time (4 Hz), so how much of a period 20 frames cover
	# depends on the machine: the live frames prove "dimmer", and the pulse is read from
	# the bubble's own colour function over one full second of phase.
	var pulse: Array[float] = []
	for step in 100:
		pulse.append(bubble1.bubble_color(ShieldBubble.player_color(f1), 0.3, -1.0, step * 0.01).a)
	var low: float = pulse.min()
	var peak: float = pulse.max()
	s.check("a weak shield keeps the player hue (no switch to red)", hue_kept)
	s.check("a weak shield is dimmer than a full one and pulses", high < full_alpha and peak - low > 0.03, "live alpha max %.2f vs %.2f full; pulse %.2f..%.2f" % [high, full_alpha, low, peak])
	await s.screenshot("shield_weak_pulse")

	# Drop lag: the bubble shrinks and fades away over the lag.
	f1.shield.refill()
	await s.frames(2)
	var shield_scale := bubble1.scale.x
	controllers[0].block_held_level = false
	var guard := 0
	while f1.shield_drop_progress() < 0.0 and guard < 30:
		await s.frames(1)
		guard += 1
	await s.frames(5)
	var progress := f1.shield_drop_progress()
	s.check("the bubble stays visible during the drop lag and shrinks", bubble1.visible and progress > 0.0 and bubble1.scale.x < shield_scale * 0.8, "progress=%.2f scale %.3f -> %.3f" % [progress, shield_scale, bubble1.scale.x])
	await s.screenshot("shield_drop_shrink")
	var shrinking: Array[float] = [bubble1.scale.x]
	await s.frames(3)
	shrinking.append(bubble1.scale.x)
	s.check("the bubble keeps shrinking until the lag ends", shrinking[1] < shrinking[0], "%.3f -> %.3f" % [shrinking[0], shrinking[1]])
	await s.frames(12)
	s.check("the bubble is gone when the lag ends", not bubble1.visible and f1.shield_drop_progress() < 0.0)
	controllers[1].block_held_level = false
	await s.despawn(game)
	s.finish()
