extends Motion

func _state_input(event: InputEvent) -> void:
	match owner.control_scheme:
		0:
			if event.is_action_pressed("P1_jump"):
				finished.emit("Jump")
			if event.is_action_pressed("P1_punch"):
				finished.emit("Punch")
		1:
			if event.is_action_pressed("P2_jump"):
				finished.emit("Jump")
			if event.is_action_pressed("P2_punch"):
				finished.emit("Punch")

func _update(delta: float) -> void:
	set_direction()
	calculate_velocity(SPEED, state_machine.direction, delta)
	
	if state_machine.direction == Vector2.ZERO:
		finished.emit("Idle")
	
	if !is_on_floor():
		finished.emit("Fall")
