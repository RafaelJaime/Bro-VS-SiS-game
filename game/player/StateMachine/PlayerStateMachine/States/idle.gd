extends Motion
class_name Idle

func _update(delta: float) -> void:
	super._update(delta)
	set_direction()
	calculate_velocity(SPEED, state_machine.direction, delta)
	
	if state_machine.direction != Vector2.ZERO:
		finished.emit("Run")
	
	if !is_on_floor():
		finished.emit("Fall")
