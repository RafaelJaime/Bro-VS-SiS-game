extends RefCounted
class_name FoodCatalog

## Static data for every throwable food item. Textures are loaded at RUNTIME
## via load() (never preload()/ext_resource in a .tscn): the sliced food
## sprites under assets/images/game/food/ have no .import files yet, so
## referencing them at scene-parse time would fail before the user opens the
## project in the editor once. See odd/tasks/kitchen-food-fight.md (T0).

enum WeightClass { LIGHT, MEDIUM, HEAVY }

const FOOD_DIR := "res://assets/images/game/food/"

# Design doc weight classes (damage %, throw speed, knockback, arc gravity scale).
const WEIGHT_STATS := {
	WeightClass.LIGHT: {
		"damage": 6.0,
		"speed": 500.0,
		"knockback": Vector2(160, -80),
		"gravity_scale": 0.0, # fast, flat trajectory
	},
	WeightClass.MEDIUM: {
		"damage": 10.0,
		"speed": 380.0,
		"knockback": Vector2(230, -120),
		"gravity_scale": 0.3,
	},
	WeightClass.HEAVY: {
		"damage": 16.0,
		"speed": 260.0,
		"knockback": Vector2(320, -160),
		"gravity_scale": 0.6, # slow arc
	},
}

const FOOD_ITEMS := {
	"popcorn": WeightClass.LIGHT,
	"nuggets": WeightClass.LIGHT,
	"coffee": WeightClass.LIGHT,
	"nachos": WeightClass.LIGHT,
	"sandwich": WeightClass.LIGHT,
	"bread": WeightClass.LIGHT,
	"pancake": WeightClass.LIGHT,
	"pizza": WeightClass.MEDIUM,
	"noodles": WeightClass.MEDIUM,
	"hotdogs": WeightClass.MEDIUM,
	"sausage_plate": WeightClass.MEDIUM,
	"sausage_stick": WeightClass.MEDIUM,
	"salad": WeightClass.MEDIUM,
	"soup": WeightClass.MEDIUM,
	"cheese": WeightClass.MEDIUM,
	"steak": WeightClass.MEDIUM,
	"turkey": WeightClass.HEAVY,
	"ham": WeightClass.HEAVY,
	"grill": WeightClass.HEAVY,
	"stew": WeightClass.HEAVY,
}

static func get_weight_class(food_name: String) -> int:
	return FOOD_ITEMS.get(food_name, WeightClass.MEDIUM)

static func get_stats(food_name: String) -> Dictionary:
	return WEIGHT_STATS[get_weight_class(food_name)]

static func get_texture(food_name: String) -> Texture2D:
	return load(FOOD_DIR + food_name + ".png")

static func get_random_food_name() -> String:
	var names = FOOD_ITEMS.keys()
	return names[randi() % names.size()]

static func get_damage(food_name: String) -> float:
	return get_stats(food_name)["damage"]

static func get_throw_speed(food_name: String) -> float:
	return get_stats(food_name)["speed"]

static func get_knockback(food_name: String) -> Vector2:
	return get_stats(food_name)["knockback"]

static func get_gravity_scale(food_name: String) -> float:
	return get_stats(food_name)["gravity_scale"]
