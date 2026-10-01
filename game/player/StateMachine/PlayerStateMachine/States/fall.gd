extends Motion
class_name Fall

func _update(delta: float) -> void:
	super._update(delta)
	set_direction()
	calculate_gravity(delta)
	calculate_velocity(profile.run_speed, state_machine.direction, delta)
	
	if is_on_floor():
		finished.emit("Idle")
