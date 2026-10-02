extends Motion
class_name Hurt

## Node-level override of the hitstun (train.tscn pins it to 0.5 s). Negative
## means "scale with the knockback", see _hitstun_for.
@export var hurt_duration: float = -1.0
@export var particles: GPUParticles2D

# Set by the attacker (via Combat.apply_hit) right before the state machine
# switches into this state.
var pending_damage: float = 8.0
var pending_knockback: Vector2 = Vector2(200, -100)

var timer: Timer
var shake: FastNoiseLite

func _ready() -> void:
	super._ready()
	# One timer, connected once. _exit stops it, so a stale timeout can never
	# end a later Hurt early.
	timer = Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(_on_hurt_finished)

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
	# Being hit refills the air jump and air dash.
	owner.restore_air_actions()
	# A hit also makes the next ledge grab a full one again.
	owner.ledge_grabs = 0

	# Emitir señal para animación
	super._enter()
	# Camera shake
	var camera_tween = get_tree().create_tween()
	camera_tween.tween_method(shake_camera, 5.0, 1.0, 0.3)
	camera_tween.tween_callback(reset_camera_shake)
	# Blink
	var blink_tween = get_tree().create_tween()
	blink_tween.tween_method(set_shader_blink, 1.0, 0.5, 0.3)
	blink_tween.tween_callback(reset_shader_blink)
	# Blood
	set_particles()
	particles.restart()
	particles.emitting = true

	timer.start(_hitstun_for(final_knockback))

func _update(delta: float) -> void:
	super._update(delta)
	# Light gravity while in hitstun keeps the launch arc long; x momentum is kept.
	state_machine.velocity.y += gravity * profile.hurt_gravity_scale * delta
	owner.set_velocity(state_machine.velocity)

func _exit() -> void:
	timer.stop()

# Harder hits stun longer: clamp(base + |knockback| * per_knockback, min, max).
func _hitstun_for(knockback: Vector2) -> float:
	if hurt_duration >= 0.0:
		return hurt_duration
	var stun := profile.hitstun_base + knockback.length() * profile.hitstun_per_knockback
	return clampf(stun, profile.hitstun_min, profile.hitstun_max)

func _on_hurt_finished() -> void:
	# No death by damage %: ring-out (stock loss) is handled by Fighter's
	# blast-zone detection, not here. Invulnerability is granted only when the
	# hitstun ends, never on a Hurt-to-Hurt re-entry, so combos inside hitstun
	# stay possible while a punch can never stun-lock.
	owner.grant_invulnerability(profile.post_hit_invulnerability)
	exit_to_neutral()

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

func reset_camera_shake() -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera:
		camera.offset = Vector2.ZERO

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
