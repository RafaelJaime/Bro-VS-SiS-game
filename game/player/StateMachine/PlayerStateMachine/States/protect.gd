extends Motion
class_name Protect

signal update_health

@export var block_duration: float = 1
@export var block_damage_reduction: float = 0.5  # 50% de reducción de daño
@export var block_knockback_reduction: float = 0.3  # Reduce el empuje recibido

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

# Función para recibir daño mientras bloquea
func receive_blocked_damage(damage: int, knockback: Vector2) -> void:
	var reduced_damage = int(damage * (1.0 - block_damage_reduction))
	var reduced_knockback = knockback * (1.0 - block_knockback_reduction)

	if owner is Fighter:
		owner.health -= reduced_damage
		update_health.emit()

	# Aplicar knockback reducido
	state_machine.velocity = reduced_knockback
	owner.set_velocity(state_machine.velocity)
