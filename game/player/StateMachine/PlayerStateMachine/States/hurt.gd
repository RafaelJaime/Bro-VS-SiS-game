extends Motion

signal update_health
signal player_defeated(player_instance: Fighter)

@export var knockback_force: Vector2 = Vector2(200, -100)
@export var hurt_duration: float = 0.5

var timer: Timer
var shake: FastNoiseLite

func _enter() -> void:
	shake = FastNoiseLite.new()
	var final_knockback = knockback_force
	
	if owner is Fighter:
		owner.health -= 10
	update_health.emit()
	
	if owner.enemy is Fighter:
		if owner.enemy.global_position.x < owner.global_position.x:
			final_knockback.x = abs(knockback_force.x)
		else:
			final_knockback.x = -abs(knockback_force.x)
	
	state_machine.velocity = final_knockback
	owner.set_velocity(state_machine.velocity)
	
	# Emitir señal para animación
	super._enter()
	# Camera shake
	var camera_tween = get_tree().create_tween()
	camera_tween.tween_method(shake_camera, 5.0, 1.0, 0.3)
	# Blink
	var blink_tween = get_tree().create_tween()
	blink_tween.tween_method(set_shader_blink, 1.0, 0.5, 0.3)
	blink_tween.tween_callback(reset_shader_blink)
	
	
	# Crear temporizador para salir del estado
	if not timer:
		timer = Timer.new()
		timer.one_shot = true
		add_child(timer)
	
	timer.connect("timeout", _on_hurt_finished)
	timer.start(hurt_duration)

func _update(delta: float) -> void:
	state_machine.velocity.y += gravity * delta
	owner.set_velocity(state_machine.velocity)

func _exit() -> void:
	if timer.is_connected("timeout", _on_hurt_finished):
		timer.disconnect("timeout", _on_hurt_finished)

func _on_hurt_finished() -> void:
	if owner.health > 0:
		if owner.is_on_floor():
			finished.emit("Idle")
		else:
			finished.emit("Fall")
	else:
		finished.emit("Defeated")
		player_defeated.emit(owner)

func set_shader_blink(new_value: float) -> void:
	var sprite = state_machine.animated_sprite_2d
	
	sprite.material.set_shader_parameter("blink_color", owner.enemy.color)
	var health_percentage = float(owner.health) / float(owner.max_health)
	var adjusted_intensity = new_value * (1.0 - health_percentage)
	
	sprite.material.set_shader_parameter("blink_intensity", adjusted_intensity)

func reset_shader_blink() -> void:
	var sprite = state_machine.animated_sprite_2d
	sprite.material.set_shader_parameter("blink_intensity", 0.0)

func shake_camera(intensity: float) -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	
	var cameraOffset = shake.get_noise_1d(Time.get_ticks_msec()) * intensity
	camera.offset.x = cameraOffset
	camera.offset.y = cameraOffset
