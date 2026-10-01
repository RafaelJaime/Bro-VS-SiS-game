extends Motion
class_name Dash

var dash_timer: float = 0.0

# S1 keeps the baseline rule: dashing is a ground move (S2 adds the air dash).
func can_enter() -> bool:
	return is_on_floor() and profile.can_dash

func _enter() -> void:
	# Dash direction: held direction (the double-tap key is still held), else
	# the way the fighter faces. The Fighter owns facing and the sprite flip.
	var dash_x: float = owner.intent.move_x
	if is_zero_approx(dash_x):
		dash_x = float(owner.facing)
	state_machine.velocity.x = signf(dash_x) * profile.dash_speed
	
	animation_state_changed.emit("dash")
	velocity_updated.emit(state_machine.velocity)
	dash_timer = 0.0

func _update(delta: float) -> void:
	dash_timer += delta
	set_direction()
	
	# Aplicar gravedad durante el dash
	calculate_gravity(delta)
	velocity_updated.emit(state_machine.velocity)
	
	# Finalizar el dash después de la duración
	if dash_timer >= profile.dash_duration:
		if is_on_floor():
			# Si hay dirección de movimiento, ir a Run, sino a Idle
			if state_machine.direction != Vector2.ZERO:
				finished.emit("Run")
			else:
				finished.emit("Idle")
		else:
			finished.emit("Fall")
