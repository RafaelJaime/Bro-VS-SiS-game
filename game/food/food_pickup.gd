extends CharacterBody2D
class_name FoodPickup

## A food item dropped by FoodSpawner. Falls under gravity and lands on the
## floor/platforms (same default collision layer as everything else in this
## project, so it just works with the existing StaticBody2D stage). Not
## auto-picked-up on touch: the Fighter only picks it up when the player
## presses the pickup/throw action while overlapping (see Fighter.pickup_area
## and the Shoot state).

@export var food_name: String = ""

@onready var sprite: Sprite2D = $Sprite2D

const GRAVITY: float = 500.0

var picked_up: bool = false

func _ready() -> void:
	if food_name != "":
		sprite.texture = FoodCatalog.get_texture(food_name)

func _physics_process(delta: float) -> void:
	if picked_up:
		return
	velocity.y += GRAVITY * delta
	move_and_slide()

## Called by Fighter.pick_up_food() right before it frees this node.
func mark_picked_up() -> void:
	picked_up = true
