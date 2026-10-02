extends Motion
class_name Dash

var dash_timer: float = 0.0
var _in_air: bool = false

# Dash works from Idle, Run and the air. In the air it needs the air dash, which
# is spent here and restored on landing (Fighter._tick_movement).
func can_enter() -> bool:
	return profile.can_dash and (is_on_floor() or owner.air_dash_available)

func _enter() -> void:
	_in_air = not is_on_floor()
	owner.fast_falling = false
	if _in_air:
		owner.air_dash_available = false
		state_machine.velocity.y = 0.0

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

	# Air dashes suspend gravity (profile.air_dash_gravity_scale).
	calculate_gravity(delta, profile.air_dash_gravity_scale if _in_air else 1.0)
	velocity_updated.emit(state_machine.velocity)

	var duration := profile.air_dash_duration if _in_air else profile.dash_duration
	if dash_timer >= duration:
		if is_on_floor():
			# Si hay dirección de movimiento, ir a Run, sino a Idle
			if state_machine.direction != Vector2.ZERO:
				finished.emit("Run")
			else:
				finished.emit("Idle")
		else:
			finished.emit("Fall")
