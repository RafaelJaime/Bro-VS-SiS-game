class_name GameRng
extends RefCounted

## The one source of randomness for gameplay: food drops, the food picked, CPU
## decisions that were not given an explicit seed, SFX pitch, the charge shake.
## Real play keeps it randomized; smoke tests call `seed_all` with a fixed seed so
## a run is reproducible.

static var _rng := _make_randomized()

static func _make_randomized() -> RandomNumberGenerator:
	var made := RandomNumberGenerator.new()
	made.randomize()
	return made

## Makes every following random draw reproducible.
static func seed_all(value: int) -> void:
	_rng.seed = value

static func randf() -> float:
	return _rng.randf()

static func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)

static func randi_below(count: int) -> int:
	return _rng.randi() % count

## A seed for an object that owns its own generator (a CPU controller).
static func next_seed() -> int:
	return _rng.randi() & 0x7fffffff
