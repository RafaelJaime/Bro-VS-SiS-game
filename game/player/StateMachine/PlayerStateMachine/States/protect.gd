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
	
	timer.connect("timeout", _on_block_finished)
	timer.start(block_duration)

	# Aplicar una pequeña fricción si estás en el suelo
	if owner.is_on_floor():
		state_machine.velocity.x = move_toward(state_machine.velocity.x, 0, 200 * get_physics_process_delta_time())
		owner.set_velocity(state_machine.velocity)

func _update(delta: float) -> void:
	super._update(delta)
	# Aplicar gravedad
	state_machine.velocity.y += gravity * delta
	owner.set_velocity(state_machine.velocity)

	# Mantener al jugador en el suelo
	if owner.is_on_floor():
		state_machine.velocity.y = 0

func _exit() -> void:
	if timer.is_connected("timeout", _on_block_finished):
		timer.disconnect("timeout", _on_block_finished)

func _on_block_finished() -> void:
	block_finished.emit()
	finished.emit("Idle")

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
