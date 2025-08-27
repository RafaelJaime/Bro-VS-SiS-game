extends Motion
class_name Jump

func _enter() -> void:
	super._enter()
	jump()

func _update(delta: float) -> void:
	super._update(delta)
	set_direction()
	calculate_gravity(delta)
	calculate_velocity(SPEED, state_machine.direction, delta)
	
	if state_machine.velocity.y >= 0:
		finished.emit("Fall")

func jump() -> void:
	state_machine.velocity.y = JUMP_VELOCITY
