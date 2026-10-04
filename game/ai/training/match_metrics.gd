class_name MatchMetrics
extends RefCounted

## Combat-depth and character-kits metrics of ONE match (or training episode),
## aggregated from the same signals the reward terms use (Fighter.hit_received,
## food_picked_up, food_thrown, shield_broken, combo_ended), never from observations. `tests/smoke/policy_eval.gd` and
## `tests/smoke/combat_harness.gd` feed it and report the aggregate.
##
## Time is game time in physics ticks (CombatClock, 60 per game second), so the rates
## do not depend on the training speed-up or on hit-stop.
##
##   var metrics := MatchMetrics.new()
##   metrics.setup(game)          # connects to both fighters, counts ticks by itself
##   ... play ...
##   metrics.stop()               # freezes the numbers, flushes an open combo, disconnects
##   metrics.to_dict()            # one match; MatchMetrics.aggregate(list) over many

const SOURCE_NAMES: PackedStringArray = ["punch", "ledge", "food", "bomb"]
## A victim stays in Hurt at most this many ticks (ComboRules.time_cap_ticks).
const HURT_CAP_TICKS := 90
## Combo lengths up to this have their own histogram bucket, longer ones land in "7+".
const HISTOGRAM_BUCKETS := 6
## A shield raise held fewer ticks than this is a tap (0.25 s): the "shield tapped between
## other actions" pattern. The mandatory minimum hold alone is 4 ticks.
const SHIELD_TAP_TICKS := 15

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
## Shield raises per fighter (the Fighter.shield_raises delta since `setup`).
var shield_raises: Array[int] = [0, 0]
## Finished shield holds per fighter (consecutive ticks in Protect) and how many of them
## were shorter than SHIELD_TAP_TICKS. A hold still open when the match ends is not counted.
var shield_holds: Array[int] = [0, 0]
var shield_taps: Array[int] = [0, 0]
## Every combo that ended (single hits count as length 1): {hits, damage,
## attacker_kit, victim_index}. An open combo is flushed by `stop()`.
var combos: Array[Dictionary] = []
## Longest run of consecutive ticks each fighter spent in Hurt, and how many runs
## (of both) exceeded the 90 tick cap.
var max_hurt_ticks: Array[int] = [0, 0]
var hurt_over_cap := 0
## Kit name of each fighter (`FighterProfile.kit_name`; "default" for the baseline).
var kits: Array[String] = ["default", "default"]
## Damage of FULL hits by the kit of the attacker (bombs excluded: no attacker).
var damage_by_kit := {}
## Physics ticks of the whole match and of its sudden death (intro and grace included).
var ticks := 0
var sd_ticks := 0

var _fighters: Array[Fighter] = []
var _running := false
var _hurt_run: Array[int] = [0, 0]
var _shield_run: Array[int] = [0, 0]
var _raises_start: Array[int] = [0, 0]

## Connects to both fighters of `match_game` and starts counting ticks. The fighters
## are found by node name, so it also works on a Game that is not ready yet (its
## `fighter_1` / `fighter_2` are @onready).
func setup(match_game: Game) -> void:
	game = match_game
	_fighters = [game.get_node("Fighter1") as Fighter, game.get_node("Fighter2") as Fighter]
	for index in 2:
		var fighter := _fighters[index]
		fighter.hit_received.connect(_on_hit_received.bind(index))
		fighter.food_picked_up.connect(_on_food_picked_up.bind(index))
		fighter.food_thrown.connect(_on_food_thrown.bind(index))
		fighter.shield_broken.connect(_on_shield_broken.bind(index))
		fighter.combo_ended.connect(_on_combo_ended.bind(index))
		_raises_start[index] = fighter.shield_raises
		kits[index] = _kit_of(fighter)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.physics_frame.connect(_on_physics_frame)
	_running = true

## Freezes the numbers, flushes any combo still open and disconnects (the fighters
## may be freed afterwards).
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
		# A combo still running when the match ends is counted as it stands (the
		# tracker is left alone: the fighters may be reused).
		if fighter.combo != null and fighter.combo.is_active():
			_record_combo(fighter.combo.hits, fighter.combo.damage, fighter.combo.attacker, index)
		shield_raises[index] = fighter.shield_raises - _raises_start[index]
		kits[index] = _kit_of(fighter)
		fighter.combo_ended.disconnect(_on_combo_ended.bind(index))
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
	for index in 2:
		var fighter := _fighters[index]
		if not is_instance_valid(fighter):
			continue
		if fighter.state_machine != null and fighter.state_machine.current_state != null and fighter.state_machine.current_state.name == "Hurt":
			_hurt_run[index] += 1
			max_hurt_ticks[index] = maxi(max_hurt_ticks[index], _hurt_run[index])
			if _hurt_run[index] == HURT_CAP_TICKS + 1:
				hurt_over_cap += 1
		else:
			_hurt_run[index] = 0
		_track_shield(index, fighter)

## Counts the consecutive ticks of a Protect hold and records the hold when it ends.
func _track_shield(index: int, fighter: Fighter) -> void:
	var shielding: bool = fighter.state_machine != null and fighter.state_machine.current_state != null and fighter.state_machine.current_state.name == "Protect"
	if shielding:
		_shield_run[index] += 1
	elif _shield_run[index] > 0:
		shield_holds[index] += 1
		if _shield_run[index] < SHIELD_TAP_TICKS:
			shield_taps[index] += 1
		_shield_run[index] = 0

func _kit_of(fighter: Fighter) -> String:
	return String(fighter.profile.kit_name) if fighter != null and fighter.profile != null else "default"

func _on_combo_ended(hits: int, damage: float, attacker: Fighter, index: int) -> void:
	_record_combo(hits, damage, attacker, index)

func _record_combo(hits: int, damage: float, attacker: Fighter, victim_index: int) -> void:
	combos.append({"hits": hits, "damage": damage, "attacker_kit": _kit_of(attacker) if is_instance_valid(attacker) else "default", "victim_index": victim_index})

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
			if hit.attacker != null and is_instance_valid(hit.attacker):
				var kit_name := _kit_of(hit.attacker)
				damage_by_kit[kit_name] = float(damage_by_kit.get(kit_name, 0.0)) + hit.damage
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
		"shield_raises": _current_raises(),
		"shield_holds": shield_holds.duplicate(),
		"shield_taps": shield_taps.duplicate(),
		"combos": combos.duplicate(true),
		"max_hurt_ticks": max_hurt_ticks.duplicate(),
		"hurt_over_cap": hurt_over_cap,
		"kits": kits.duplicate(),
		"damage_by_kit": damage_by_kit.duplicate(),
	}

## Raises per fighter: live while running, frozen by `stop()`.
func _current_raises() -> Array[int]:
	var raises: Array[int] = [shield_raises[0], shield_raises[1]]
	if _running:
		for index in 2:
			if is_instance_valid(_fighters[index]):
				raises[index] = _fighters[index].shield_raises - _raises_start[index]
	return raises

## Sums the `to_dict()` records of many matches into the report fields:
## pickups and throws per fighter-minute (all fighters over all match time),
## blocked share, damage by source, shield breaks, and the sudden-death lengths
## (only matches that reached sudden death count; 0 when none did), plus the
## character-kits fields: shield raises per fighter-minute, the shield tap share (finished
## shield holds shorter than 15 ticks over all finished holds), the combo histogram
## ("1".."6", "7+"), the longest combo, the number of 2+ hit combos, the longest
## continuous Hurt in seconds, the Hurt runs over the 90 tick cap, damage by kit and
## the mean multi-hit combo damage by attacker kit (with its sum and count, so
## matchups can be pooled).
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
	var raises_total := 0
	var holds_total := 0
	var taps_total := 0
	var histogram := {}
	for bucket in HISTOGRAM_BUCKETS:
		histogram[str(bucket + 1)] = 0
	histogram["%d+" % (HISTOGRAM_BUCKETS + 1)] = 0
	var max_combo := 0
	var multi_hit := 0
	var max_hurt := 0
	var over_cap := 0
	var damage_kit := {}
	var combo_sum := {}
	var combo_count := {}
	for record: Dictionary in records:
		seconds_total += float(record["seconds"])
		for count: int in record.get("shield_raises", []):
			raises_total += count
		for count: int in record.get("shield_holds", []):
			holds_total += count
		for count: int in record.get("shield_taps", []):
			taps_total += count
		for combo: Dictionary in record.get("combos", []):
			var hits := int(combo["hits"])
			histogram[str(hits) if hits <= HISTOGRAM_BUCKETS else "%d+" % (HISTOGRAM_BUCKETS + 1)] += 1
			max_combo = maxi(max_combo, hits)
			if hits >= 2:
				multi_hit += 1
				var kit := String(combo["attacker_kit"])
				combo_sum[kit] = float(combo_sum.get(kit, 0.0)) + float(combo["damage"])
				combo_count[kit] = int(combo_count.get(kit, 0)) + 1
		for ticks_in_hurt: int in record.get("max_hurt_ticks", []):
			max_hurt = maxi(max_hurt, ticks_in_hurt)
		over_cap += int(record.get("hurt_over_cap", 0))
		var kit_damage: Dictionary = record.get("damage_by_kit", {})
		for kit: String in kit_damage:
			damage_kit[kit] = float(damage_kit.get(kit, 0.0)) + float(kit_damage[kit])
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
		"shield_raises": raises_total,
		"shield_raises_per_fighter_minute": float(raises_total) / fighter_minutes if fighter_minutes > 0.0 else 0.0,
		"shield_holds": holds_total,
		"shield_taps": taps_total,
		"shield_tap_share": float(taps_total) / float(holds_total) if holds_total > 0 else 0.0,
		"combo_histogram": histogram,
		"max_combo": max_combo,
		"multi_hit_combos": multi_hit,
		"max_hurt_seconds": CombatClock.seconds(max_hurt),
		"hurt_over_cap": over_cap,
		"damage_by_kit": damage_kit,
		"combo_damage_sum_by_kit": combo_sum,
		"combo_count_by_kit": combo_count,
		"combo_damage_by_kit": _mean_by_key(combo_sum, combo_count),
	}

## sum[key] / count[key] for every key with a count.
static func _mean_by_key(sums: Dictionary, counts: Dictionary) -> Dictionary:
	var means := {}
	for key: String in counts:
		means[key] = float(sums[key]) / float(counts[key])
	return means
