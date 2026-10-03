extends Node2D
class_name FoodSpawner

## Drops a random food item every spawn_min_interval..spawn_max_interval
## seconds, capped at max_alive items alive at once (1.8-3 s and 5 since combat
## depth; it was 3-5 s and 4, which left the stage empty most of the time).

@export var food_pickup_scene: PackedScene
@export var spawn_min_interval: float = 1.8
@export var spawn_max_interval: float = 3.0
@export var max_alive: int = 5
## Spawn range in this spawner's local space (the Game origin), over the counter.
@export var spawn_x_min: float = 100.0
@export var spawn_x_max: float = 760.0
@export var spawn_y: float = 40.0

var alive_food: Array = []
var spawn_timer: Timer

func _ready() -> void:
	spawn_timer = Timer.new()
	spawn_timer.one_shot = true
	add_child(spawn_timer)
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)

## Starts dropping food. The Game calls it when the match begins (after the
## countdown), so nothing falls while the fighters are still locked.
func start() -> void:
	if spawn_timer.is_stopped():
		_schedule_next_spawn()

## Stops dropping food (the match is over). Food already on the counter stays.
func stop() -> void:
	spawn_timer.stop()

func _schedule_next_spawn() -> void:
	spawn_timer.start(GameRng.randf_range(spawn_min_interval, spawn_max_interval))

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
	# Local coordinates: the spawner sits at its Game's origin, so this stays
	# correct for offset Game rows (train.tscn).
	food.position = position + Vector2(GameRng.randf_range(spawn_x_min, spawn_x_max), spawn_y)
	alive_food.append(food)
