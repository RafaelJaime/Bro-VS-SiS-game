extends Area2D
class_name FoodProjectile

## Thrown food. Same attacker/target resolution as a punch (Combat.apply_hit),
## so it correctly respects blocking and respawn invulnerability. Direction-
## based movement + Area2D hit detection follows the same pattern the old
## game/projectile/projectile.gd used for free-shoot (now removed).

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
	body_shape_entered.connect(_on_body_shape_entered)
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

func _on_body_shape_entered(_body_rid: RID, body: Node, body_shape_index: int, _local_shape_index: int) -> void:
	# Fires once per shape, so a multi-shape body must not be hit twice.
	if is_queued_for_deletion() or body == shooter or body == self:
		return
	if body is Fighter:
		Combat.apply_hit(shooter, body, damage, knockback_base)
		queue_free()
	elif body is StaticBody2D and not _is_one_way_shape(body, body_shape_index):
		queue_free()

# Area2D overlaps ignore one_way_collision, so thrown food would otherwise be
# destroyed when flying under or through the floating platforms.
func _is_one_way_shape(body: CollisionObject2D, body_shape_index: int) -> bool:
	var shape_owner = body.shape_owner_get_owner(body.shape_find_owner(body_shape_index))
	return shape_owner is CollisionShape2D and shape_owner.one_way_collision
