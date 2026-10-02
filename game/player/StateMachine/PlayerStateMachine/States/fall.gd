extends Motion
class_name Fall

func _update(delta: float) -> void:
	super._update(delta)
	set_direction()
	_try_fast_fall()
	calculate_gravity(delta)
	calculate_velocity(profile.run_speed, state_machine.direction, delta)
	
	if handle_actions():
		return

	if is_on_floor():
		finished.emit("Idle")

# Down while falling snaps the fall speed up until landing (Smash fast fall).
func _try_fast_fall() -> void:
	if not profile.can_fast_fall or owner.fast_falling or is_on_floor():
		return
	if owner.intent.aim == FighterIntent.Aim.DOWN and state_machine.velocity.y >= 0.0:
		owner.fast_falling = true
		state_machine.velocity.y = maxf(state_machine.velocity.y, profile.fast_fall_start_speed)
