extends Motion
class_name Dash

const DASH_SPEED = 600.0
const DASH_DURATION = 0.3

var dash_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO

func _enter() -> void:
	# Aplicar la dirección del dash ANTES de super._enter()
	if dash_direction != Vector2.ZERO:
		state_machine.velocity.x = dash_direction.x * DASH_SPEED
	else:
		state_machine.velocity.x = state_machine.direction.x * DASH_SPEED if state_machine.direction.x != 0 else DASH_SPEED
	
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
	if dash_timer >= DASH_DURATION:
		if is_on_floor():
			# Si hay dirección de movimiento, ir a Run, sino a Idle
			if state_machine.direction != Vector2.ZERO:
				finished.emit("Run")
			else:
				finished.emit("Idle")
		else:
			finished.emit("Fall")
