extends RefCounted
class_name Hit

## One damage event, built by every source (punch, ledge attack, thrown food, bomb)
## and resolved by `Combat.resolve` in a single, fixed order. Rewards, metrics and
## the CPU read the outcome from `Fighter.hit_received`, never from observations.

enum Source { PUNCH, LEDGE, FOOD, BOMB }

## Null for hazards (bombs).
var attacker: Fighter
var damage: float = 0.0
## Base knockback, before the damage-% scaling. `x` is the strength; its sign comes
## from which side `source_position` is on.
var knockback: Vector2 = Vector2.ZERO
## Meter damage against a shield. Below 0 means "derive it from `damage`".
var shield_damage: float = -1.0
## Ignores the shield entirely (bombs).
var unblockable: bool = false
var source: Source = Source.PUNCH
## Global position the hit comes from; the knockback pushes away from its x.
var source_position: Vector2 = Vector2.ZERO
var food_name: String = ""

static func punch(from: Fighter, hit_damage: float, hit_knockback: Vector2, hit_shield_damage: float = -1.0, hit_source: Source = Source.PUNCH) -> Hit:
	var hit := Hit.new()
	hit.attacker = from
	hit.damage = hit_damage
	hit.knockback = hit_knockback
	hit.shield_damage = hit_shield_damage
	hit.source = hit_source
	if from != null:
		hit.source_position = from.global_position
	return hit

## A thrown food that reached a fighter at `at` (global): the weight class and tag
## values come from the FoodCatalog.
static func food(from: Fighter, item: String, at: Vector2) -> Hit:
	var hit := Hit.new()
	hit.attacker = from
	hit.damage = FoodCatalog.get_damage(item)
	hit.knockback = FoodCatalog.get_hit_knockback(item)
	hit.shield_damage = FoodCatalog.get_shield_damage(item)
	hit.source = Source.FOOD
	hit.source_position = at
	hit.food_name = item
	return hit

## A bomb: no attacker, never blocked.
static func bomb(at: Vector2, hit_damage: float, hit_knockback: Vector2) -> Hit:
	var hit := Hit.new()
	hit.damage = hit_damage
	hit.knockback = hit_knockback
	hit.unblockable = true
	hit.source = Source.BOMB
	hit.source_position = at
	return hit
