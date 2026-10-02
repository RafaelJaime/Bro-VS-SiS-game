extends Motion
class_name Jump

# Jump is both the ground jump and the air (double) jump; the Fighter decides
# which one this is (coyote time, buffer, air jumps left).
var _cut_done: bool = false

func can_enter() -> bool:
	return owner.peek_jump() != Fighter.JumpKind.NONE

func _enter() -> void:
	super._enter()
	_cut_done = false
	owner.fast_falling = false
	var kind: Fighter.JumpKind = owner.consume_jump()
	if kind == Fighter.JumpKind.AIR:
		state_machine.velocity.y = profile.double_jump_velocity
		Sfx.play_event(&"double_jump", owner)
	else:
		state_machine.velocity.y = owner.jump_velocity_override if owner.jump_velocity_override != 0.0 else profile.jump_velocity
		owner.jump_velocity_override = 0.0
		Sfx.play_event(&"jump", owner)
	# Applied right away so the first airborne frame already rises.
	velocity_updated.emit(state_machine.velocity)

func _update(delta: float) -> void:
	super._update(delta)
	# Short hop: letting go of jump while rising cuts the ascent, once.
	if not _cut_done and not owner.intent.jump_held and state_machine.velocity.y < 0.0:
		state_machine.velocity.y *= profile.jump_cut_multiplier
		_cut_done = true

	set_direction()
	calculate_gravity(delta)
	calculate_velocity(profile.run_speed, state_machine.direction, delta)

	if handle_actions():
		return

	if state_machine.velocity.y >= 0:
		finished.emit("Fall")
