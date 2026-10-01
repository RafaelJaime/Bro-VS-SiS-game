extends Motion

func _update(delta: float) -> void:
	super._update(delta)
	set_direction()
	calculate_velocity(profile.run_speed, state_machine.direction, delta)

	if handle_actions():
		return

	if !is_on_floor():
		finished.emit("Fall")
	elif state_machine.direction == Vector2.ZERO:
		finished.emit("Idle")
