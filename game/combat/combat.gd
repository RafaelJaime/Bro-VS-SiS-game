extends RefCounted
class_name Combat

## Centralizes "attacker hits target" resolution so every damage source
## (punch, thrown food, ...) shares identical block/no-block handling.
## This is also the fix for the previously unused
## Protect.receive_blocked_damage() codepath: before this, a hit landing on
## a blocking target just kicked the target back to Idle with zero damage
## and zero knockback (full immunity). Now a blocking target always goes
## through receive_blocked_damage(), which applies the reduced % and
## reduced knockback from the design doc.
static func apply_hit(attacker: Fighter, target: Fighter, damage: float, knockback_base: Vector2) -> void:
	if target == null or target.state_machine == null:
		return
	if target.is_invulnerable:
		return

	var target_sm = target.state_machine
	if target_sm.current_state and target_sm.current_state.name == "Protect":
		target_sm.current_state.receive_blocked_damage(damage, knockback_base)
		return

	var hurt_state = target_sm.state_map.get("Hurt")
	if hurt_state:
		hurt_state.pending_damage = damage
		hurt_state.pending_knockback = knockback_base
	target_sm._change_state("Hurt")
