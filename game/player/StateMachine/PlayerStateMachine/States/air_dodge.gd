extends Motion
class_name AirDodge

## The block key in the air: a brief intangible dodge that costs no shield meter.
## One per airtime (`Fighter.air_dodge_available`, refilled by landing, a ledge
## grab or a hit) and a cooldown counted from the dodge start. The fighter is
## intangible for `air_dodge_invuln`, then helpless for `air_dodge_endlag`, then
## falls (or idles on landing). Everything is counted in physics ticks.

const DODGE_TINT := Color(1.0, 1.0, 1.0, 0.45)

var invuln_ticks_left: int = 0
var endlag_ticks_left: int = 0

func can_enter() -> bool:
	return not is_on_floor() and owner.air_dodge_available and owner.air_dodge_cooldown_left <= 0

func _enter() -> void:
	# The fall frame stands in for the dodge (no new art).
	animation_state_changed.emit("fall")
	owner.air_dodge_available = false
	owner.air_dodge_cooldown_left = CombatClock.ticks(profile.air_dodge_cooldown)
	invuln_ticks_left = CombatClock.ticks(profile.air_dodge_invuln)
	endlag_ticks_left = CombatClock.ticks(profile.air_dodge_endlag)
	owner.fast_falling = false
	state_machine.velocity.x *= profile.air_dodge_drift
	velocity_updated.emit(state_machine.velocity)
	owner.status_tint = DODGE_TINT
	owner.animated_sprite_2d.modulate = DODGE_TINT

## True during the invulnerable window (read through Fighter.is_intangible).
func is_intangible() -> bool:
	return invuln_ticks_left > 0

func _update(delta: float) -> void:
	super._update(delta)
	calculate_gravity(delta, profile.air_dodge_gravity_scale)
	velocity_updated.emit(state_machine.velocity)
	if invuln_ticks_left > 0:
		invuln_ticks_left -= 1
		return
	endlag_ticks_left -= 1
	if endlag_ticks_left <= 0:
		exit_to_neutral()

func _exit() -> void:
	invuln_ticks_left = 0
	endlag_ticks_left = 0
	owner.status_tint = Color.WHITE
	owner.animated_sprite_2d.modulate = Color.WHITE
