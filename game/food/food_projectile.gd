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

var shooter: Fighter
var speed: float = 0.0
var velocity: Vector2 = Vector2.ZERO
var gravity_scale: float = 0.0
var damage: float = 0.0
var knockback_base: Vector2 = Vector2.ZERO

func _ready() -> void:
	body_entered.connect(_on_body_entered)
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

func set_shooter(fighter: Fighter) -> void:
	shooter = fighter

func _on_body_entered(body: Node) -> void:
	if body == shooter or body == self:
		return
	if body is Fighter:
		Combat.apply_hit(shooter, body, damage, knockback_base)
		queue_free()
	elif body is StaticBody2D:
		queue_free()
