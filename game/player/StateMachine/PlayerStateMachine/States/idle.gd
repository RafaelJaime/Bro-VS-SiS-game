extends Motion
class_name Idle

const DOUBLE_TAP_WINDOW = 0.3

var last_input_direction: Vector2 = Vector2.ZERO
var last_input_time: float = 0.0

func _update(delta: float) -> void:
	super._update(delta)
	set_direction()
	calculate_velocity(profile.run_speed, state_machine.direction, delta)
	
	if state_machine.direction != Vector2.ZERO:
		finished.emit("Run")
	
	if !is_on_floor():
		finished.emit("Fall")

func _state_input(event: InputEvent) -> void:
	if owner.ai_controller_2d and owner.ai_controller_2d.control_mode != AIController2D.ControlModes.HUMAN:
		return
	
	var prefix = "P1_" if owner.control_scheme == 0 else "P2_"
	var left_action = prefix + "left"
	var right_action = prefix + "right"
	
	# Detectar doble tap en izquierda
	if event.is_action_pressed(left_action):
		if last_input_direction.x == -1.0 and (Time.get_ticks_msec() / 1000.0 - last_input_time) < DOUBLE_TAP_WINDOW:
			# Doble tap detectado, iniciar dash
			var dash_state = state_machine.state_map.get("Dash")
			if dash_state:
				dash_state.dash_direction = Vector2.LEFT
			finished.emit("Dash")
			last_input_time = 0.0
			return
		else:
			last_input_direction = Vector2.LEFT
			last_input_time = Time.get_ticks_msec() / 1000.0
	
	# Detectar doble tap en derecha
	elif event.is_action_pressed(right_action):
		if last_input_direction.x == 1.0 and (Time.get_ticks_msec() / 1000.0 - last_input_time) < DOUBLE_TAP_WINDOW:
			# Doble tap detectado, iniciar dash
			var dash_state = state_machine.state_map.get("Dash")
			if dash_state:
				dash_state.dash_direction = Vector2.RIGHT
			finished.emit("Dash")
			last_input_time = 0.0
			return
		else:
			last_input_direction = Vector2.RIGHT
			last_input_time = Time.get_ticks_msec() / 1000.0
	
	# Llamar a la función parent para detectar punch, shoot, protect, etc.
	super._state_input(event)
