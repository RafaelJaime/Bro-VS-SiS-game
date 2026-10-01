extends Motion
class_name Dash

var dash_timer: float = 0.0

# S1 keeps the baseline rule: dashing is a ground move (S2 adds the air dash).
func can_enter() -> bool:
	return is_on_floor() and profile.can_dash

func _enter() -> void:
	# Dash direction: held direction (the double-tap key is still held), else
	# toward the enemy. Applied BEFORE the animation flip below.
	var dash_x: float = owner.intent.move_x
	if is_zero_approx(dash_x):
		dash_x = float(owner.facing)
	state_machine.velocity.x = signf(dash_x) * profile.dash_speed
	
	# Invertir animación si el enemigo está en el lado contrario al dash
	if owner.enemy:
		var enemy_position_x = owner.enemy.global_position.x
		var player_position_x = owner.global_position.x
		var dash_is_right = state_machine.velocity.x > 0
		var enemy_is_right = enemy_position_x > player_position_x
		
		# Si el dash va hacia un lado pero el enemigo está en el otro, invertir
		if (dash_is_right and not enemy_is_right) or (not dash_is_right and enemy_is_right):
			owner.animated_sprite_2d.flip_h = true
		else:
			owner.animated_sprite_2d.flip_h = false
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
