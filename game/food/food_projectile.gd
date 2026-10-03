extends Area2D
class_name FoodProjectile

## Thrown food. It builds a FOOD Hit (weight class and tag values from the
## FoodCatalog) and resolves it through Combat.resolve, so it follows the same
## shield, dizzy and invulnerability rules as a punch. Direction-based movement +
## Area2D hit detection follows the same pattern the old
## game/projectile/projectile.gd used for free-shoot (now removed). It hits
## fighters through their hurtbox and is destroyed by the counter.
##
## Item identity: a `hot` food flies with a fire trail and bursts into a fire puff
## on impact, a `hard` food spins. Training rows get none of the VFX.

@export var food_name: String = ""
@export var direction: int = 1

@onready var sprite: Sprite2D = $Sprite2D

const GRAVITY: float = 500.0
# Missed throws have no walls to hit anymore, so free them after this long.
const MAX_LIFETIME: float = 3.0
const GLOW_PATH := "res://assets/textures/2D Fire  - Tutorial/T_VFX_Glow_1.PNG"
const SPIN_SPEED: float = TAU * 2.0
const FIRE_COLOR := Color(1.0, 0.45, 0.1)

var shooter: Fighter
var speed: float = 0.0
var velocity: Vector2 = Vector2.ZERO
var gravity_scale: float = 0.0
var lifetime: float = 0.0

var _hard: bool = false
var _hot: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	if food_name != "":
		sprite.texture = FoodCatalog.get_texture(food_name)
		var stats = FoodCatalog.get_stats(food_name)
		speed = stats["speed"]
		gravity_scale = stats["gravity_scale"]
		_hard = FoodCatalog.has_tag(food_name, "hard")
		_hot = FoodCatalog.has_tag(food_name, "hot")
	sprite.flip_h = direction < 0
	velocity = Vector2(speed * direction, -100.0 * gravity_scale)
	if _hot and not Sfx.is_training(self):
		add_child(_make_fire(false))
	# Avoid colliding with the thrower immediately on spawn.
	set_physics_process(false)
	await get_tree().create_timer(0.08).timeout
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	velocity.y += GRAVITY * gravity_scale * delta
	position += velocity * delta
	if _hard:
		sprite.rotation += SPIN_SPEED * delta * direction
	lifetime += delta
	if lifetime >= MAX_LIFETIME:
		queue_free()

func set_shooter(fighter: Fighter) -> void:
	shooter = fighter

# Fighters are hit through their hurtbox Area2D (the movement body is not on the
# projectile's mask). The hurtbox's parent is the Fighter.
func _on_area_entered(area: Area2D) -> void:
	var target := area.get_parent() as Fighter
	if is_queued_for_deletion() or target == null or target == shooter:
		return
	Combat.resolve(Hit.food(shooter, food_name, global_position), target)
	if _hot and not Sfx.is_training(self):
		_spawn_impact_puff()
	queue_free()

# The only solid thing a throw can hit is the counter.
func _on_body_entered(body: Node2D) -> void:
	if is_queued_for_deletion() or body == shooter:
		return
	if body is StaticBody2D:
		queue_free()

# A fire made of the glow texture (additive, CPU particles so it also runs in the
# web build). `burst` is the one-shot impact puff, otherwise the continuous trail.
func _make_fire(burst: bool) -> CPUParticles2D:
	var fire := CPUParticles2D.new()
	fire.texture = load(GLOW_PATH)
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fire.material = material
	fire.local_coords = false
	fire.direction = Vector2.UP if burst else Vector2(-direction, 0.0)
	fire.spread = 180.0 if burst else 25.0
	fire.gravity = Vector2(0.0, -60.0)
	fire.initial_velocity_min = 80.0 if burst else 20.0
	fire.initial_velocity_max = 220.0 if burst else 70.0
	fire.scale_amount_min = 0.07 if burst else 0.05
	fire.scale_amount_max = 0.14 if burst else 0.09
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.95, 0.6, 0.9), FIRE_COLOR, Color(0.8, 0.1, 0.0, 0.0)])
	fire.color_ramp = ramp
	fire.lifetime = 0.45 if burst else 0.35
	fire.amount = 24 if burst else 16
	fire.one_shot = burst
	fire.explosiveness = 0.95 if burst else 0.0
	fire.emitting = true
	return fire

# The puff outlives the projectile: it is a child of the Game and frees itself.
func _spawn_impact_puff() -> void:
	var game := get_parent()
	if game == null:
		return
	var puff := _make_fire(true)
	game.add_child(puff)
	puff.global_position = global_position
	game.get_tree().create_timer(puff.lifetime + 0.1).timeout.connect(puff.queue_free)
