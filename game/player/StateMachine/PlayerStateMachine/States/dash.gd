extends Motion
class_name Dash

const DASH_SPEED = 600.0
const DASH_DURATION = 0.3

var dash_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO

func _enter() -> void:
	super._enter()
	animation_state_changed.emit("dash")
	
	# Aplicar la dirección del dash
	if dash_direction != Vector2.ZERO:
		state_machine.velocity.x = dash_direction.x * DASH_SPEED
	else:
		state_machine.velocity.x = state_machine.direction.x * DASH_SPEED if state_machine.direction.x != 0 else DASH_SPEED
	
	velocity_updated.emit(state_machine.velocity)
	dash_timer = 0.0

func _update(delta: float) -> void:
	dash_timer += delta
	
	# Aplicar gravedad durante el dash
	calculate_gravity(delta)
	velocity_updated.emit(state_machine.velocity)
	
	# Finalizar el dash después de la duración
	if dash_timer >= DASH_DURATION:
		if is_on_floor():
			finished.emit("Idle")
		else:
			finished.emit("Fall")
