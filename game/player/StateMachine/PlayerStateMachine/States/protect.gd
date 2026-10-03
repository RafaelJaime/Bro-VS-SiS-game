extends Motion
class_name Protect

## The ground shield. It lasts as long as the block key is held and the fighter's
## ShieldMeter lasts: the meter (owned by the Fighter, ticked every frame) drains
## while this state is active and `absorb` drains it further for every blocked hit.
## A hit that empties the meter breaks the shield (Fighter.break_shield -> Dizzy).
## Tuning is in the FighterProfile "Shield" group.

func can_enter() -> bool:
	return owner.is_on_floor() and not owner.shield.is_empty() and not owner.is_dizzy()

func _update(delta: float) -> void:
	super._update(delta)
	calculate_gravity(delta)
	# A shielding fighter plants itself.
	calculate_velocity(0.0, Vector2.ZERO, delta)

	# Ground only: walking off the table drops the shield.
	if not is_on_floor():
		finished.emit("Fall")
		return
	if not owner.intent.block_held:
		exit_to_neutral()

## Called by Combat.resolve when a blockable hit lands on this shielding fighter.
## Drains the meter by the hit's shield damage, applies the chip damage and the
## reduced pushback, and never starts hitstun. Returns true when the meter ran out:
## the shield breaks and the fighter goes dizzy (no pushback then).
func absorb(hit: Hit) -> bool:
	var fighter: Fighter = owner
	var shield_damage := hit.shield_damage if hit.shield_damage >= 0.0 else hit.damage * profile.shield_damage_scale
	fighter.add_damage(hit.damage * profile.shield_chip_fraction)
	if fighter.shield.absorb(shield_damage):
		fighter.break_shield(hit)
		return true

	# A grounded shield slides back: only the horizontal push applies, so a blocked
	# hit never lifts the fighter off the floor (the shield is ground-only).
	var push := Vector2(hit.knockback.x * profile.shield_knockback_fraction, 0.0)
	push.x = absf(push.x) if hit.source_position.x < fighter.global_position.x else -absf(push.x)
	# Smash-style: knockback grows with the victim's accumulated damage %.
	push *= fighter.get_knockback_scale()
	state_machine.velocity = push
	fighter.set_velocity(push)
	return false
