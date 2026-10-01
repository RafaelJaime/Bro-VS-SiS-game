extends Motion
class_name Helpless

## Smash "special fall": after the up-recovery the fighter can only drift until it
## lands. A table leg can still be grabbed and a hit ends it like any other state.

func _enter() -> void:
	animation_state_changed.emit("fall")

func _update(delta: float) -> void:
	super._update(delta)
	set_direction()
	calculate_gravity(delta)
	state_machine.velocity.x = move_toward(state_machine.velocity.x, state_machine.direction.x * profile.run_speed, profile.air_acceleration * profile.helpless_air_control * delta)
	velocity_updated.emit(state_machine.velocity)
	if is_on_floor():
		finished.emit("Idle")
