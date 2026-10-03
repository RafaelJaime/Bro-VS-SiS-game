class_name MatchMetrics
extends RefCounted

## Combat-depth metrics of ONE match (or training episode), aggregated from the same
## signals the reward terms use (Fighter.hit_received, food_picked_up, food_thrown,
## shield_broken), never from observations. `tests/smoke/policy_eval.gd` and
## `tests/smoke/combat_harness.gd` feed it and report the aggregate.
##
## Time is game time in physics ticks (CombatClock, 60 per game second), so the rates
## do not depend on the training speed-up or on hit-stop.
##
##   var metrics := MatchMetrics.new()
##   metrics.setup(game)          # connects to both fighters, counts ticks by itself
##   ... play ...
##   metrics.stop()               # freezes the numbers and disconnects
##   metrics.to_dict()            # one match; MatchMetrics.aggregate(list) over many

const SOURCE_NAMES: PackedStringArray = ["punch", "ledge", "food", "bomb"]

var game: Game
## Per fighter (index 0 = Fighter1): foods picked up, thrown, and shields of that
## fighter that broke.
var pickups: Array[int] = [0, 0]
var throws: Array[int] = [0, 0]
var shield_breaks: Array[int] = [0, 0]
## Resolved hits by outcome (bombs excluded: they cannot be blocked).
var full_hits := 0
var blocked_hits := 0
var broke_hits := 0
var ignored_hits := 0
## Damage applied per source: a FULL hit counts its damage, a shielded hit its chip.
var damage_by_source := {"punch": 0.0, "ledge": 0.0, "food": 0.0, "bomb": 0.0}
## Physics ticks of the whole match and of its sudden death (intro and grace included).
var ticks := 0
var sd_ticks := 0

var _fighters: Array[Fighter] = []
var _running := false

## Connects to both fighters of `match_game` and starts counting ticks.
func setup(match_game: Game) -> void:
	game = match_game
	_fighters = [game.fighter_1, game.fighter_2]
	for index in 2:
		var fighter := _fighters[index]
		fighter.hit_received.connect(_on_hit_received.bind(index))
		fighter.food_picked_up.connect(_on_food_picked_up.bind(index))
		fighter.food_thrown.connect(_on_food_thrown.bind(index))
		fighter.shield_broken.connect(_on_shield_broken.bind(index))
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.physics_frame.connect(_on_physics_frame)
	_running = true

## Freezes the numbers and disconnects (the fighters may be freed afterwards).
func stop() -> void:
	if not _running:
		return
	_running = false
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.physics_frame.is_connected(_on_physics_frame):
		tree.physics_frame.disconnect(_on_physics_frame)
	for index in 2:
		var fighter := _fighters[index]
		if not is_instance_valid(fighter):
			continue
		fighter.hit_received.disconnect(_on_hit_received.bind(index))
		fighter.food_picked_up.disconnect(_on_food_picked_up.bind(index))
		fighter.food_thrown.disconnect(_on_food_thrown.bind(index))
		fighter.shield_broken.disconnect(_on_shield_broken.bind(index))

func _on_physics_frame() -> void:
	if not _running or not is_instance_valid(game):
		return
	ticks += 1
	if game.phase == Game.Phase.SUDDEN_DEATH:
		sd_ticks += 1

func _on_food_picked_up(_food_name: String, index: int) -> void:
	pickups[index] += 1

func _on_food_thrown(_food_name: String, index: int) -> void:
	throws[index] += 1

func _on_shield_broken(_cause: Hit, index: int) -> void:
	shield_breaks[index] += 1

func _on_hit_received(hit: Hit, outcome: int, index: int) -> void:
	var source_name: String = SOURCE_NAMES[hit.source]
	var counted := hit.source != Hit.Source.BOMB
	match outcome:
		Combat.Outcome.IGNORED:
			ignored_hits += 1
		Combat.Outcome.FULL:
			damage_by_source[source_name] += hit.damage
			if counted:
				full_hits += 1
		_:
			var chip := hit.damage * _chip_fraction(index)
			damage_by_source[source_name] += chip
			if counted:
				if outcome == Combat.Outcome.BROKE:
					broke_hits += 1
				else:
					blocked_hits += 1

func _chip_fraction(index: int) -> float:
	var fighter := _fighters[index]
	return fighter.profile.shield_chip_fraction if fighter != null and fighter.profile != null else 0.0

## Game seconds counted so far.
func seconds() -> float:
	return CombatClock.seconds(ticks)

func sd_seconds() -> float:
	return CombatClock.seconds(sd_ticks)

## (BLOCKED + BROKE) / (FULL + BLOCKED + BROKE), bombs excluded; 0 with no hit.
func blocked_share() -> float:
	return share_of(full_hits, blocked_hits, broke_hits)

static func share_of(full: int, blocked: int, broke: int) -> float:
	var total := full + blocked + broke
	return float(blocked + broke) / float(total) if total > 0 else 0.0

## The raw counters of this match (the input of `aggregate`).
func to_dict() -> Dictionary:
	return {
		"seconds": seconds(),
		"sd_seconds": sd_seconds(),
		"pickups": pickups.duplicate(),
		"throws": throws.duplicate(),
		"shield_breaks": shield_breaks.duplicate(),
		"full_hits": full_hits,
		"blocked_hits": blocked_hits,
		"broke_hits": broke_hits,
		"ignored_hits": ignored_hits,
		"damage_by_source": damage_by_source.duplicate(),
	}

## Sums the `to_dict()` records of many matches into the report fields:
## pickups and throws per fighter-minute (all fighters over all match time),
## blocked share, damage by source, shield breaks, and the sudden-death lengths
## (only matches that reached sudden death count; 0 when none did).
static func aggregate(records: Array) -> Dictionary:
	var seconds_total := 0.0
	var pickups_total := 0
	var throws_total := 0
	var breaks_total := 0
	var full := 0
	var blocked := 0
	var broke := 0
	var damage := {"punch": 0.0, "ledge": 0.0, "food": 0.0, "bomb": 0.0}
	var sd_lengths: Array[float] = []
	for record: Dictionary in records:
		seconds_total += float(record["seconds"])
		for count: int in record["pickups"]:
			pickups_total += count
		for count: int in record["throws"]:
			throws_total += count
		for count: int in record["shield_breaks"]:
			breaks_total += count
		full += int(record["full_hits"])
		blocked += int(record["blocked_hits"])
		broke += int(record["broke_hits"])
		for key: String in damage:
			damage[key] += float(record["damage_by_source"][key])
		if float(record["sd_seconds"]) > 0.0:
			sd_lengths.append(float(record["sd_seconds"]))
	var fighter_minutes := seconds_total * 2.0 / 60.0
	var sd_sum := 0.0
	var sd_max := 0.0
	for length in sd_lengths:
		sd_sum += length
		sd_max = maxf(sd_max, length)
	return {
		"pickups_per_fighter_minute": float(pickups_total) / fighter_minutes if fighter_minutes > 0.0 else 0.0,
		"throws_per_fighter_minute": float(throws_total) / fighter_minutes if fighter_minutes > 0.0 else 0.0,
		"blocked_share": share_of(full, blocked, broke),
		"damage_by_source": damage,
		"shield_breaks": breaks_total,
		"sd_matches": sd_lengths.size(),
		"mean_sd_seconds": sd_sum / float(sd_lengths.size()) if not sd_lengths.is_empty() else 0.0,
		"max_sd_seconds": sd_max,
	}
