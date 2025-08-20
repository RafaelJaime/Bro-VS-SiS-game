extends Motion

func _update(delta: float) -> void:
	set_direction()
	calculate_gravity(delta)
	calculate_velocity(SPEED, state_machine.direction, delta)
	
	if is_on_floor():
		finished.emit("Idle")
