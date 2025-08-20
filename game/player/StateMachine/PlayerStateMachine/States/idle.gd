extends Motion

func _state_input(event: InputEvent) -> void:
	match owner.control_scheme:
		0:
			if event.is_action_pressed("P1_jump"):
				finished.emit("Jump")
			if event.is_action_pressed("P1_punch"):
				finished.emit("Punch")
			if event.is_action_pressed("P1_protect"):
				finished.emit("Protect")
			if event.is_action_pressed("P1_fire"):
				finished.emit("Shoot")
		1:
			if event.is_action_pressed("P2_jump"):
				finished.emit("Jump")
			if event.is_action_pressed("P2_punch"):
				finished.emit("Punch")
			if event.is_action_pressed("P2_protect"):
				finished.emit("Protect")
			if event.is_action_pressed("P2_fire"):
				finished.emit("Shoot")
	

func _update(delta: float) -> void:
	set_direction()
	calculate_velocity(SPEED, state_machine.direction, delta)
	
	if state_machine.direction != Vector2.ZERO:
		finished.emit("Run")
	
	if !is_on_floor():
		finished.emit("Fall")
