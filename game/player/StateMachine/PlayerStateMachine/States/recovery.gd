extends Motion
class_name Recovery

## Up-recovery: one upward burst per airtime, no hitbox, nothing can interrupt it.
## When the rise ends the fighter is helpless (see Helpless) until it lands, grabs
## a table leg or is hit. The Fighter owns the "once per airtime" bookkeeping
## (`recovery_available`, refilled by landing, a hit or a ledge grab).

func can_enter() -> bool:
	return profile.can_recover and owner.recovery_available and not is_on_floor()

func _enter() -> void:
	# The jump frame stands in for the burst (no new art).
	animation_state_changed.emit("jump")
	owner.recovery_available = false
	owner.fast_falling = false
	state_machine.velocity.y = profile.recovery_velocity
	var x := move_axis()
	if not is_zero_approx(x):
		state_machine.velocity.x = x * profile.recovery_drift
	velocity_updated.emit(state_machine.velocity)
	Sfx.play_event(&"recovery", owner)

func _update(delta: float) -> void:
	super._update(delta)
	set_direction()
	calculate_gravity(delta)
	state_machine.velocity.x = move_toward(state_machine.velocity.x, state_machine.direction.x * profile.recovery_drift, profile.air_acceleration * profile.recovery_air_control * delta)
	velocity_updated.emit(state_machine.velocity)
	if state_machine.velocity.y >= 0.0:
		finished.emit("Helpless")
