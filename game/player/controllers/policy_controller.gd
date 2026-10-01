class_name PolicyController
extends FighterController

## Adapter over PlayerAIController's continuous action floats (RL training and
## ONNX inference). It does not change the observation or action space.
## Every action is thresholded at > 0.5 with level semantics, plus one guard so
## a held jump cannot chain a ground jump into an instant double jump.

const THRESHOLD := 0.5

var _prev_jump := false

func sample(_delta: float) -> FighterIntent:
	var intent := FighterIntent.new()
	if fighter == null:
		return intent
	var ai := fighter.ai_controller_2d as PlayerAIController
	if ai == null:
		return intent

	var left := ai.move_left_action > THRESHOLD
	var right := ai.move_right_action > THRESHOLD
	var jump := ai.jump_action > THRESHOLD
	var attack := ai.attack_action > THRESHOLD
	var shoot := ai.shoot_action > THRESHOLD
	var protect := ai.protect_action > THRESHOLD

	intent.move_x = (1.0 if right else 0.0) - (1.0 if left else 0.0)
	intent.jump_held = jump
	intent.jump_pressed = jump and (not _prev_jump or fighter.is_on_floor())
	intent.attack_pressed = attack # attack_held stays false: instant tap, never a charge.
	intent.throw_pressed = shoot
	intent.block_pressed = protect
	intent.block_held = protect
	# dash_pressed, aim and special_pressed stay neutral for policies.

	_prev_jump = jump
	return intent

func kind_name() -> String:
	return "policy"
