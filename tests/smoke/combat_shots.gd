extends SceneTree
## Combat-depth screenshots for visual review (windowed only): the shield bubble at
## a high and a low meter, the dizzy cue and the HUD shield bar. The checks are only
## that the cue is on screen; the pictures are what a person looks at.

const Smoke := preload("res://tests/smoke/smoke_util.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	await _shield_and_dizzy(s)
	s.finish()

func _shield_and_dizzy(s: RefCounted) -> void:
	var game: Node2D = s.spawn_game(330.0, 560.0)
	var controllers: Array = s.attach_controllers(game)
	await s.frames(90)
	var fighter: Fighter = game.get_node("Fighter1")
	var ctrl = controllers[0]
	var bubble: ShieldBubble = fighter.get_node("ShieldBubble")
	var stars: DizzyStars = fighter.get_node("DizzyStars")
	ctrl.block_held_level = true
	ctrl.press_block()
	await s.frames(6)
	await s.screenshot("cd_shield_bubble_high")
	s.check("the high bubble is on screen", bubble.visible)
	fighter.shield.set_ratio(0.18)
	await s.frames(3)
	await s.screenshot("cd_shield_bubble_low")
	s.check("the low bubble is on screen and smaller", bubble.visible and bubble.scale.x < bubble.scale_full * 0.6, "scale=%.3f" % bubble.scale.x)
	ctrl.block_held_level = false
	await s.frames(4)
	fighter.break_shield(null)
	await s.frames(14)
	await s.screenshot("cd_dizzy")
	s.check("the dizzy stars are on screen", stars.visible)
	await s.despawn(game)
