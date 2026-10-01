extends Motion
class_name Hurt

@export var hurt_duration: float = 0.5
@export var particles: GPUParticles2D

# Set by the attacker (via Combat.apply_hit) right before the state machine
# switches into this state.
var pending_damage: float = 8.0
var pending_knockback: Vector2 = Vector2(200, -100)

var timer: Timer
var shake: FastNoiseLite

func _enter() -> void:
	shake = FastNoiseLite.new()
	var final_knockback = pending_knockback

	if owner is Fighter:
		owner.add_damage(pending_damage)
		owner.enemy.state_machine.ai_controller_2d.reward += 1
		state_machine.ai_controller_2d.reward -= 0.5

	if owner.enemy is Fighter:
		if owner.enemy.global_position.x < owner.global_position.x:
			final_knockback.x = abs(pending_knockback.x)
		else:
			final_knockback.x = -abs(pending_knockback.x)

	# Smash-style: knockback grows with the victim's accumulated damage %.
	final_knockback *= owner.get_knockback_scale()

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
	# Blood
	set_particles()
	particles.restart()
	particles.emitting = true

	# Crear temporizador para salir del estado
	if not timer:
		timer = Timer.new()
		timer.one_shot = true
		add_child(timer)

	timer.connect("timeout", _on_hurt_finished)
	timer.start(hurt_duration)

func _update(delta: float) -> void:
	super._update(delta)
	state_machine.velocity.y += gravity * delta
	owner.set_velocity(state_machine.velocity)

func _exit() -> void:
	if timer.is_connected("timeout", _on_hurt_finished):
		timer.disconnect("timeout", _on_hurt_finished)

func _on_hurt_finished() -> void:
	# No death by damage %: ring-out (stock loss) is handled by Fighter's
	# blast-zone detection, not here.
	if owner.is_on_floor():
		finished.emit("Idle")
	else:
		finished.emit("Fall")

func set_shader_blink(new_value: float) -> void:
	var sprite = state_machine.animated_sprite_2d

	sprite.material.set_shader_parameter("blink_color", owner.enemy.character_ui.color)
	# Visual severity ramps up with damage % (capped at 150% for the flash effect).
	var severity = clamp(owner.damage_percent / 150.0, 0.0, 1.0)
	var adjusted_intensity = new_value * severity

	sprite.material.set_shader_parameter("blink_intensity", adjusted_intensity)

func reset_shader_blink() -> void:
	var sprite = state_machine.animated_sprite_2d
	sprite.material.set_shader_parameter("blink_intensity", 0.0)

func shake_camera(intensity: float) -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()

	var cameraOffset = shake.get_noise_1d(Time.get_ticks_msec()) * intensity
	camera.offset.x = cameraOffset
	camera.offset.y = cameraOffset

func set_particles() -> void:
	var new_material: ParticleProcessMaterial = particles.process_material

	var direction_x = -0.5 if owner.enemy.position.x < owner.position.x else 0.5
	new_material.direction = Vector3(direction_x, -5.5, 0)

	var gradient = Gradient.new()

	gradient.offsets = [0.0, 1.0]
	match owner.control_scheme:
		0:
			gradient.colors = [
				owner.character_ui.color,
				Color(owner.character_ui.color, 0),    # Transparente
			]
		1:
			gradient.colors = [
				Color(owner.character_ui.color, 0),
				owner.character_ui.color
			]

	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 512

	new_material.color_ramp = gradient_texture

	particles.process_material = new_material
