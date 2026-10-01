extends Node2D
class_name FoodSpawner

## Drops a random food item every spawn_min_interval..spawn_max_interval
## seconds, capped at max_alive items alive at once (design doc: 3-5s, max 4).

@export var food_pickup_scene: PackedScene
@export var spawn_min_interval: float = 3.0
@export var spawn_max_interval: float = 5.0
@export var max_alive: int = 4
@export var spawn_x_min: float = 180.0
@export var spawn_x_max: float = 620.0
@export var spawn_y: float = -50.0

var alive_food: Array = []
var spawn_timer: Timer

func _ready() -> void:
	spawn_timer = Timer.new()
	spawn_timer.one_shot = true
	add_child(spawn_timer)
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	_schedule_next_spawn()

func _schedule_next_spawn() -> void:
	spawn_timer.start(randf_range(spawn_min_interval, spawn_max_interval))

func _on_spawn_timer_timeout() -> void:
	_cleanup_freed()
	if alive_food.size() < max_alive:
		_spawn_food()
	_schedule_next_spawn()

func _cleanup_freed() -> void:
	var still_alive = []
	for food in alive_food:
		if is_instance_valid(food):
			still_alive.append(food)
	alive_food = still_alive

func _spawn_food() -> void:
	if not food_pickup_scene:
		push_warning("FoodSpawner has no food_pickup_scene assigned.")
		return

	var food = food_pickup_scene.instantiate()
	food.food_name = FoodCatalog.get_random_food_name()
	get_parent().add_child(food)
	food.global_position = Vector2(randf_range(spawn_x_min, spawn_x_max), spawn_y)
	alive_food.append(food)
