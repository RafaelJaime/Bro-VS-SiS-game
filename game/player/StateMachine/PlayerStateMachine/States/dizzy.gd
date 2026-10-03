extends Motion
class_name Dizzy

## The shield broke: a long, helpless daze (about 2 s of physics ticks). The state
## lists no actions, so the fighter ignores its intent; it only falls and slides to
## a stop. A hit on a dizzy fighter is a normal full hit (Combat.resolve treats it
## as not shielding) and leaves through Hurt. Either way `_exit` wakes the shield
## meter at `shield_break_recovery`. The stars and the wobble are the DizzyStars
## node's job (it reads `Fighter.is_dizzy()`).

const DIZZY_TINT := Color(1.0, 1.0, 0.7)

var ticks_left: int = 0

func _enter() -> void:
	# The existing hitstun frame stands in for the daze (no new art).
	animation_state_changed.emit("hurt")
	ticks_left = CombatClock.ticks(profile.dizzy_duration)
	state_machine.velocity = Vector2(0.0, profile.shield_break_pop_velocity)
	velocity_updated.emit(state_machine.velocity)
	owner.status_tint = DIZZY_TINT
	owner.animated_sprite_2d.modulate = DIZZY_TINT
	Sfx.play_event(&"shield_break", owner)

func _update(delta: float) -> void:
	super._update(delta)
	calculate_gravity(delta)
	calculate_velocity(0.0, Vector2.ZERO, delta)
	ticks_left -= 1
	if ticks_left <= 0:
		exit_to_neutral()

func _exit() -> void:
	ticks_left = 0
	owner.shield.set_ratio(profile.shield_break_recovery)
	owner.status_tint = Color.WHITE
	owner.animated_sprite_2d.modulate = Color.WHITE
