extends Motion
class_name Protect

@export var block_duration: float = 1
@export var block_damage_reduction: float = 0.5  # Block halves the % gained from a hit.
@export var block_knockback_reduction: float = 0.3  # Fraction of knockback RETAINED while blocking (30% knockback).

var timer: Timer

signal block_finished

func _enter() -> void:
	super._enter()

	# Inicializar temporizador
	if not timer:
		timer = Timer.new()
		timer.one_shot = true
		add_child(timer)

	if not timer.timeout.is_connected(_on_block_finished):
		timer.timeout.connect(_on_block_finished)
	timer.start(block_duration)

func _update(delta: float) -> void:
	super._update(delta)
	calculate_gravity(delta)
	# A blocking fighter plants itself (friction on the ground, air drag in the air).
	calculate_velocity(0.0, Vector2.ZERO, delta)

	# Hold-to-block, ground and air: the block lasts while the key is held, up to
	# block_duration.
	if not owner.intent.block_held:
		exit_to_neutral()

func _exit() -> void:
	timer.stop()
	if timer.timeout.is_connected(_on_block_finished):
		timer.timeout.disconnect(_on_block_finished)

func _on_block_finished() -> void:
	block_finished.emit()
	exit_to_neutral()

# Called by Combat.apply_hit when the target is currently blocking. This is
# the fix for the previously unused/dead receive_blocked_damage() codepath:
# before, any hit landing on a blocking player was fully absorbed (full
# immunity, 0 damage, 0 knockback). Now it halves the % gained and reduces
# knockback to block_knockback_reduction of the attack's base knockback.
func receive_blocked_damage(damage: float, knockback_base: Vector2) -> void:
	var reduced_damage = damage * (1.0 - block_damage_reduction)
	var final_knockback = knockback_base * block_knockback_reduction

	if owner is Fighter:
		owner.add_damage(reduced_damage)

	if owner.enemy is Fighter:
		if owner.enemy.global_position.x < owner.global_position.x:
			final_knockback.x = abs(final_knockback.x)
		else:
			final_knockback.x = -abs(final_knockback.x)

	# Smash-style: knockback grows with the victim's accumulated damage %,
	# applied on top of the block reduction.
	final_knockback *= owner.get_knockback_scale()

	state_machine.velocity = final_knockback
	owner.set_velocity(state_machine.velocity)
