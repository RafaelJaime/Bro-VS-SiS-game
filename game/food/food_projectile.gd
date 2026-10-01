extends Area2D
class_name FoodProjectile

## Thrown food. Same attacker/target resolution as a punch (Combat.apply_hit),
## so it correctly respects blocking and respawn invulnerability. Direction-
## based movement + Area2D hit detection follows the same pattern the old
## game/projectile/projectile.gd used for free-shoot (now removed). It hits
## fighters through their hurtbox and is destroyed by the counter.

@export var food_name: String = ""
@export var direction: int = 1

@onready var sprite: Sprite2D = $Sprite2D

const GRAVITY: float = 500.0
# Missed throws have no walls to hit anymore, so free them after this long.
const MAX_LIFETIME: float = 3.0

var shooter: Fighter
var speed: float = 0.0
var velocity: Vector2 = Vector2.ZERO
var gravity_scale: float = 0.0
var damage: float = 0.0
var knockback_base: Vector2 = Vector2.ZERO
var lifetime: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	if food_name != "":
		sprite.texture = FoodCatalog.get_texture(food_name)
		var stats = FoodCatalog.get_stats(food_name)
		speed = stats["speed"]
		gravity_scale = stats["gravity_scale"]
		damage = stats["damage"]
		knockback_base = stats["knockback"]
	sprite.flip_h = direction < 0
	velocity = Vector2(speed * direction, -100.0 * gravity_scale)
	# Avoid colliding with the thrower immediately on spawn.
	set_physics_process(false)
	await get_tree().create_timer(0.08).timeout
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	velocity.y += GRAVITY * gravity_scale * delta
	position += velocity * delta
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
	Combat.apply_hit(shooter, target, damage, knockback_base)
	queue_free()

# The only solid thing a throw can hit is the counter.
func _on_body_entered(body: Node2D) -> void:
	if is_queued_for_deletion() or body == shooter:
		return
	if body is StaticBody2D:
		queue_free()
