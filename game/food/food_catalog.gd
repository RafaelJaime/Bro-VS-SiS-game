extends RefCounted
class_name FoodCatalog

## Static data for every throwable food item. Textures are loaded at RUNTIME
## via load() (never preload()/ext_resource in a .tscn): the sliced food
## sprites under assets/images/game/food/ have no .import files yet, so
## referencing them at scene-parse time would fail before the user opens the
## project in the editor once. See odd/tasks/kitchen-food-fight.md (T0).

enum WeightClass { LIGHT, MEDIUM, HEAVY }

const FOOD_DIR := "res://assets/images/game/food/"

# Weight classes (damage %, throw speed, knockback, arc gravity scale, meter damage
# against a shield). Every class out-damages and out-launches a neutral punch
# (8 damage, 220 knockback), so picking food up is always worth it. Heavy food
# takes a full shield down in two hits (55 + 55 > 100) and a weakened one in one,
# and the strongest tag multiplier keeps a full shield alive through one heavy
# hit: 1.4 * 55 = 77 < 100 (food_balance.gd asserts it).
const WEIGHT_STATS := {
	WeightClass.LIGHT: {
		"damage": 9.0,
		"speed": 560.0,
		"knockback": Vector2(240, -110),
		"gravity_scale": 0.0, # fast, flat trajectory
		"shield_damage": 20.0,
	},
	WeightClass.MEDIUM: {
		"damage": 13.0,
		"speed": 420.0,
		"knockback": Vector2(290, -150),
		"gravity_scale": 0.3,
		"shield_damage": 35.0,
	},
	WeightClass.HEAVY: {
		"damage": 18.0,
		"speed": 300.0,
		"knockback": Vector2(360, -190),
		"gravity_scale": 0.6, # slow arc
		"shield_damage": 55.0,
	},
}

# Item identity: a food name maps to tags, and a tag only scales numbers the weight
# class already defines (no new art or behaviour). Exactly two effects:
#   hot   knockback x1.25, a fire trail while flying and a fire puff on impact
#   hard  shield damage x1.4, and the item spins in flight
const TAGS := {
	"coffee": ["hot"],
	"soup": ["hot"],
	"stew": ["hot"],
	"cheese": ["hard"],
	"steak": ["hard"],
	"grill": ["hard"],
}

const TAG_EFFECTS := {
	"hot": {"knockback_mul": 1.25},
	"hard": {"shield_mul": 1.4},
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
	return names[GameRng.randi_below(names.size())]

static func get_damage(food_name: String) -> float:
	return get_stats(food_name)["damage"]

static func get_throw_speed(food_name: String) -> float:
	return get_stats(food_name)["speed"]

static func get_knockback(food_name: String) -> Vector2:
	return get_stats(food_name)["knockback"]

static func get_gravity_scale(food_name: String) -> float:
	return get_stats(food_name)["gravity_scale"]

static func get_shield_damage_base(food_name: String) -> float:
	return get_stats(food_name)["shield_damage"]

## Tags of a food (empty for an untagged item).
static func get_tags(food_name: String) -> Array:
	return TAGS.get(food_name, [])

static func has_tag(food_name: String, tag: String) -> bool:
	return get_tags(food_name).has(tag)

## Knockback of the hit a thrown food makes: the weight class value times every
## tag's knockback multiplier (untagged food is exactly its class value).
static func get_hit_knockback(food_name: String) -> Vector2:
	var knockback := get_knockback(food_name)
	for tag in get_tags(food_name):
		knockback *= TAG_EFFECTS[tag].get("knockback_mul", 1.0)
	return knockback

## Meter damage a thrown food does to a shield: the class value times every tag's
## shield multiplier.
static func get_shield_damage(food_name: String) -> float:
	var shield_damage := get_shield_damage_base(food_name)
	for tag in get_tags(food_name):
		shield_damage *= TAG_EFFECTS[tag].get("shield_mul", 1.0)
	return shield_damage
