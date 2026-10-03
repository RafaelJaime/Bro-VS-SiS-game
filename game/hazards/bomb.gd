extends Area2D
class_name Bomb

## A sudden-death bomb. It falls at a constant speed from above the stage, shows a
## shadow on the tabletop that grows as it comes down (the telegraph), and explodes
## on the first fighter hurtbox or the tabletop it touches. The explosion is a
## deterministic distance check, once per fighter: every fighter whose hurtbox is
## within `explosion_radius` takes an unblockable bomb Hit through Combat.resolve
## (so respawn invulnerability and air dodges still protect, and a shield does not).
## A bomb that misses the table falls past the bottom blast zone and is freed
## silently. It is a plain Area2D with no physics callbacks: contact is tested here
## every physics frame, so timing never depends on when the engine reports overlaps.
##
## Everything is Game-local through its parent (SuddenDeathHazards at the Game
## origin) and holds no global state. With `visuals` off (training) it creates no
## particles and plays no sound. The effects reuse the existing fire textures.

const BODY_RADIUS := 22.0
const GLOW_PATH := "res://assets/textures/2D Fire  - Tutorial/T_VFX_Glow_1.PNG"
const FLAME_PATH := "res://assets/textures/2D Fire  - Tutorial/T_Gradient_circle22.jpg"
const SHADOW_MIN_RADIUS := 12.0

# Set by SuddenDeathHazards before the bomb enters the tree.
var fall_speed: float = 420.0
var explosion_radius: float = 90.0
var damage: float = 12.0
var knockback: Vector2 = Vector2(120.0, -560.0)
## Table top and the horizontal extent of the table, in this bomb's own space.
var stage_top: float = 480.0
var stage_left: float = 30.0
var stage_right: float = 830.0
## Global x of the table centre: a bomb right above a fighter pushes it away from it.
var stage_center_x: float = 430.0
var blast_bottom: float = 810.0
var spawn_y: float = 0.0
var fighters: Array = []
var visuals: bool = true

var _done: bool = false
var _glow: Sprite2D

func _ready() -> void:
	if not visuals:
		return
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var glow_texture: Texture2D = load(GLOW_PATH)

	# A hot streak above the bomb.
	var flame := Sprite2D.new()
	flame.texture = load(FLAME_PATH)
	flame.material = additive
	flame.modulate = Color(1.0, 0.5, 0.15, 0.85)
	flame.scale = Vector2(0.22, 0.4)
	flame.position = Vector2(0.0, -BODY_RADIUS - 22.0)
	add_child(flame)

	# The fuse glow, pulsing.
	_glow = Sprite2D.new()
	_glow.texture = glow_texture
	_glow.material = additive
	_glow.modulate = Color(1.0, 0.55, 0.15, 0.9)
	_glow.scale = Vector2.ONE * 0.12
	_glow.position = Vector2(9.0, -BODY_RADIUS - 10.0)
	add_child(_glow)

	var sparks := CPUParticles2D.new()
	sparks.texture = glow_texture
	sparks.material = additive
	sparks.local_coords = false
	sparks.position = _glow.position
	sparks.amount = 10
	sparks.lifetime = 0.4
	sparks.direction = Vector2.UP
	sparks.spread = 40.0
	sparks.gravity = Vector2.ZERO
	sparks.initial_velocity_min = 30.0
	sparks.initial_velocity_max = 90.0
	sparks.scale_amount_min = 0.03
	sparks.scale_amount_max = 0.06
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.85, 0.4, 0.9), Color(1.0, 0.3, 0.0, 0.0)])
	sparks.color_ramp = ramp
	add_child(sparks)

func _physics_process(delta: float) -> void:
	if _done:
		return
	position.y += fall_speed * delta
	if _touching_fighter() or _touching_table():
		explode()
		return
	if position.y > blast_bottom:
		_done = true
		queue_free()
		return
	if visuals:
		_glow.scale = Vector2.ONE * (0.12 + 0.03 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 6.0))
		queue_redraw()

## Current velocity (read by the Game snapshot).
func velocity() -> Vector2:
	return Vector2(0.0, fall_speed)

func _touching_table() -> bool:
	return position.x >= stage_left and position.x <= stage_right and position.y + BODY_RADIUS >= stage_top

func _touching_fighter() -> bool:
	for fighter: Fighter in fighters:
		if fighter.stocks > 0 and _distance_to_hurtbox(fighter) <= BODY_RADIUS:
			return true
	return false

# Distance from the bomb centre to the fighter's hurtbox rectangle (0 inside).
func _distance_to_hurtbox(fighter: Fighter) -> float:
	var shape_node := fighter.hurtbox.get_node("CollisionShape2D") as CollisionShape2D
	var half := (shape_node.shape as RectangleShape2D).size / 2.0
	var center := shape_node.global_position
	var nearest := Vector2(clampf(global_position.x, center.x - half.x, center.x + half.x), clampf(global_position.y, center.y - half.y, center.y + half.y))
	return global_position.distance_to(nearest)

## Goes off: one bomb Hit per fighter inside the radius, then the bomb is gone.
func explode() -> void:
	if is_queued_for_deletion():
		return
	_done = true
	for fighter: Fighter in fighters:
		if fighter.stocks > 0 and _distance_to_hurtbox(fighter) <= explosion_radius:
			Combat.resolve(Hit.bomb(_hit_source(fighter), damage, knockback), fighter)
	if visuals:
		_burst()
		Sfx.play_event(&"bomb", self)
	queue_free()

# Where the hit comes from: the bomb itself, unless it is right above the fighter,
# then a point on the table-centre side so the launch goes away from the middle.
func _hit_source(fighter: Fighter) -> Vector2:
	var source := global_position
	if absf(fighter.global_position.x - source.x) < 4.0:
		var away := signf(fighter.global_position.x - stage_center_x)
		if is_zero_approx(away):
			away = 1.0
		source.x = fighter.global_position.x - away * 8.0
	return source

# The explosion: a flash and a burst of fire, children of the hazards node so they
# outlive the bomb, freed by a timer.
func _burst() -> void:
	var holder := get_parent()
	if holder == null:
		return
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var glow_texture: Texture2D = load(GLOW_PATH)

	var fire := CPUParticles2D.new()
	fire.texture = glow_texture
	fire.material = additive
	fire.z_index = 2
	fire.local_coords = false
	fire.one_shot = true
	fire.explosiveness = 0.95
	fire.amount = 36
	fire.lifetime = 0.6
	fire.direction = Vector2.UP
	fire.spread = 180.0
	fire.gravity = Vector2(0.0, -80.0)
	fire.initial_velocity_min = 120.0
	fire.initial_velocity_max = 340.0
	fire.scale_amount_min = 0.1
	fire.scale_amount_max = 0.24
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 1.0, 0.9, 1.0), Color(1.0, 0.85, 0.2, 0.9), Color(1.0, 0.4, 0.05, 0.6), Color(0.5, 0.05, 0.0, 0.0)])
	fire.color_ramp = ramp
	fire.emitting = true
	holder.add_child(fire)
	fire.global_position = global_position

	var flash := Sprite2D.new()
	flash.texture = glow_texture
	flash.material = additive
	flash.z_index = 2
	flash.modulate = Color(1.0, 0.85, 0.5, 0.95)
	flash.scale = Vector2.ONE * 0.2
	holder.add_child(flash)
	flash.global_position = global_position
	var final_scale := explosion_radius * 2.0 / glow_texture.get_width() * 1.3
	var tween := flash.create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector2.ONE * final_scale, 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(flash.queue_free)
	holder.get_tree().create_timer(fire.lifetime + 0.2).timeout.connect(fire.queue_free)

func _draw() -> void:
	if not visuals:
		return
	# The shadow on the tabletop: it grows and darkens as the bomb comes down.
	var progress := clampf(inverse_lerp(spawn_y, stage_top - BODY_RADIUS, position.y), 0.0, 1.0)
	var radius := lerpf(SHADOW_MIN_RADIUS, explosion_radius * 0.9, progress)
	draw_set_transform(Vector2(0.0, stage_top - position.y), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, radius, Color(0.0, 0.0, 0.0, lerpf(0.18, 0.55, progress)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The bomb: a dark ball with a highlight and a fuse.
	draw_circle(Vector2.ZERO, BODY_RADIUS, Color(0.07, 0.07, 0.09))
	draw_circle(Vector2(-7.0, -7.0), 6.0, Color(0.38, 0.38, 0.45))
	draw_line(Vector2(4.0, -BODY_RADIUS + 3.0), Vector2(9.0, -BODY_RADIUS - 10.0), Color(0.65, 0.45, 0.2), 3.0)
