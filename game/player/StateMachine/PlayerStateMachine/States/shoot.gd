extends Motion

@export var projectile_scene: PackedScene
@export var shoot_duration: float = 0.3
@export var shoot_cooldown: float = 2.0
@export var right_mark: Marker2D
@export var left_mark: Marker2D

var shoot_timer: Timer
var cooldown_timer: Timer
var is_shooting: bool = false

func _enter() -> void:
	setup_timers()
	
	if cooldown_timer.is_stopped() or cooldown_timer.time_left <= 0:
		super._enter()
		start_shoot()
	else:
		finished.emit("Idle")

func setup_timers() -> void:
	if not shoot_timer:
		shoot_timer = Timer.new()
		shoot_timer.one_shot = true
		add_child(shoot_timer)
	
	if not cooldown_timer:
		cooldown_timer = Timer.new()
		cooldown_timer.one_shot = true
		add_child(cooldown_timer)

func start_shoot() -> void:
	is_shooting = true
	
	if not shoot_timer.is_connected("timeout", _on_shoot_timer_timeout):
		shoot_timer.connect("timeout", _on_shoot_timer_timeout)
	
	shoot_timer.start(shoot_duration)
	cooldown_timer.start(shoot_cooldown)
	
	spawn_projectile()

func spawn_projectile() -> void:
	if not projectile_scene:
		push_warning("No projectile scene assigned to Shoot state.")
		return
	
	if not owner or not owner.enemy:
		push_warning("Owner or enemy not found.")
		return
	
	var projectile = projectile_scene.instantiate()
	
	# Determinar dirección basada en la posición del enemigo
	var direction = 1
	var spawn_marker = right_mark
	
	if owner.enemy.global_position.x < owner.global_position.x:
		direction = -1
		spawn_marker = left_mark
	
	# Posicionar el proyectil
	if spawn_marker:
		projectile.global_position = spawn_marker.global_position
	else:
		var spawn_position = owner.global_position
		spawn_position.x += 30 * direction
		projectile.global_position = spawn_position
	
	# Pasar dirección y referencia al fighter (no al state machine)
	if projectile.has_method("set_direction"):
		projectile.set_direction(direction)
	
	if projectile.has_method("set_shooter"):
		projectile.set_shooter(owner)  # owner debería ser el Fighter
	
	owner.get_parent().add_child(projectile)
	projectile.set_color(owner.character_ui.color)

func _on_shoot_timer_timeout() -> void:
	end_shoot()

func end_shoot() -> void:
	is_shooting = false
	finished.emit("Idle")
