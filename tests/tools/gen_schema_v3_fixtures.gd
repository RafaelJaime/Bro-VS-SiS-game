extends SceneTree
## One-off generator of the bvs-schema-3 fixtures. Run only after a DELIBERATE v3
## layout or normalization change (the smoke test and the Python side fail on any
## drift until these are regenerated):
##
##   godot --headless --path . --fixed-fps 60 --script res://tests/tools/gen_schema_v3_fixtures.gd
##
## Writes tests/fixtures/schema/v3_layout.json (the field names in order) and
## tests/fixtures/schema/v3_obs_golden.json (recorded synthetic snapshots with the
## vectors BvsSchemaV3 builds from them). The v2 fixtures are never touched.
##
## Synthetic snapshots use a stage spanning x 30..830 at top 480 (center 430, half
## width 400): a fighter standing on the floor sits at y 386 (feet 94 below).

const LAYOUT_PATH := "res://tests/fixtures/schema/v3_layout.json"
const OBS_PATH := "res://tests/fixtures/schema/v3_obs_golden.json"

func _initialize() -> void:
	_write(LAYOUT_PATH, JSON.stringify(Array(BvsSchemaV3.FIELD_NAMES), "  "))
	var cases: Array = []
	for entry: Dictionary in _cases():
		var snapshot: Dictionary = entry["snapshot"]
		var my_index: int = entry["my_index"]
		var obs := BvsSchemaV3.build_obs(snapshot, my_index)
		var expected: Array = []
		for value in obs:
			expected.append(float(value))
		cases.append({
			"name": entry["name"],
			"my_index": my_index,
			"snapshot": _to_json(snapshot),
			"expected": expected,
		})
	var golden := {
		"comment": "Golden observation fixture for bvs-schema-3 (tolerance 1e-6). Regenerate only with a deliberate schema change (tests/tools/gen_schema_v3_fixtures.gd).",
		"tolerance": 1e-06,
		"cases": cases,
	}
	_write(OBS_PATH, JSON.stringify(golden, "  ", true))
	print("wrote %s (%d names) and %s (%d cases)" % [LAYOUT_PATH, BvsSchemaV3.FIELD_NAMES.size(), OBS_PATH, cases.size()])
	quit(0)

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("cannot write %s" % path)
		quit(1)
		return
	file.store_string(text + "\n")

## Vectors become [x, y] arrays and names become strings, so the file is plain JSON.
func _to_json(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y]
	if value is StringName:
		return String(value)
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[String(key) if key is StringName else key] = _to_json(value[key])
		return out
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(_to_json(item))
		return items
	return value

func _fighter(over: Dictionary = {}) -> Dictionary:
	var fighter := {
		"position": Vector2(430.0, 386.0),
		"velocity": Vector2.ZERO,
		"facing": 1,
		"on_floor": true,
		"damage_percent": 0.0,
		"stocks": 3,
		"held_food": "",
		"state": &"Idle",
		"cooldowns": {"punch": 0.0, "shoot": 0.0},
		"jumps_left": 2,
		"air_dash_available": true,
		"charge_level": 0.0,
		"recovery_available": true,
		"last_attack_direction": &"neutral",
		"fast_falling": false,
		"ledge_side": 0,
		"ledge_grabs": 0,
		"is_invulnerable": false,
		"controller": "policy",
		"shield": 100.0,
		"shield_max": 100.0,
		"dizzy": false,
		"dizzy_left": 0.0,
		"air_dodge_available": true,
		"intangible": false,
	}
	fighter.merge(over, true)
	return fighter

func _snapshot(fighter_1: Dictionary, fighter_2: Dictionary, over: Dictionary = {}) -> Dictionary:
	var snapshot := {
		"phase": "playing",
		"timer_left": 50.0,
		"timer_running": true,
		"sudden_death": false,
		"sudden_death_phase": 0,
		"sudden_death_elapsed": 0.0,
		"stage": {"left": 30.0, "right": 830.0, "top": 480.0},
		"platforms": [],
		"blast_zone": {"left": -230.0, "right": 1090.0, "top": -400.0, "bottom": 810.0},
		"ledges": [
			{"side": -1, "x": 30.0, "top": 480.0, "bottom": 738.0, "occupied": false},
			{"side": 1, "x": 830.0, "top": 480.0, "bottom": 738.0, "occupied": false},
		],
		"foods": [],
		"projectiles": [],
		"bombs": [],
		"fighters": [fighter_1, fighter_2],
	}
	snapshot.merge(over, true)
	return snapshot

func _bomb(x: float, y: float, speed: float = 420.0) -> Dictionary:
	return {"position": Vector2(x, y), "velocity": Vector2(0.0, speed), "radius": 90.0}

func _cases() -> Array:
	var cases: Array = []

	var spawn := _snapshot(_fighter({"position": Vector2(130.0, 386.0)}), _fighter({"position": Vector2(730.0, 386.0), "facing": -1}), {"timer_left": 99.0})
	cases.append({"name": "neutral spawn, player 1", "my_index": 0, "snapshot": spawn})

	# Shield at half, the opponent dizzy with half the dizzy time left, hot and hard food in hand.
	var guard := _fighter({"position": Vector2(330.0, 386.0), "shield": 50.0, "held_food": "coffee", "state": &"Protect"})
	var stunned := _fighter({"position": Vector2(530.0, 300.0), "facing": -1, "on_floor": false, "dizzy": true, "dizzy_left": 1.0, "state": &"Dizzy", "shield": 50.0, "held_food": "cheese"})
	var foods := [
		{"name": "pizza", "position": Vector2(480.0, 400.0)},
		{"name": "steak", "position": Vector2(130.0, 400.0)},
		{"name": "soup", "position": Vector2(700.0, 400.0)},
		{"name": "popcorn", "position": Vector2(900.0, 400.0)},
	]
	var shots := [
		{"position": Vector2(480.0, 336.0), "velocity": Vector2(300.0, -130.0), "shooter": 1},
		{"position": Vector2(730.0, 386.0), "velocity": Vector2(-600.0, 0.0), "shooter": 2},
	]
	var shield_snapshot := _snapshot(guard, stunned, {"foods": foods, "projectiles": shots})
	cases.append({"name": "shield half, opponent dizzy, tagged food, player 1", "my_index": 0, "snapshot": shield_snapshot})
	cases.append({"name": "shield half, opponent dizzy, tagged food, player 2", "my_index": 1, "snapshot": shield_snapshot})

	# An air dodge window: intangible counts as cannot-be-hit, and the allowance is spent.
	var dodger := _fighter({"position": Vector2(430.0, 250.0), "velocity": Vector2(200.0, 100.0), "on_floor": false, "intangible": true, "air_dodge_available": false, "state": &"AirDodge", "jumps_left": 1})
	cases.append({"name": "air dodge intangible, player 1", "my_index": 0, "snapshot": _snapshot(dodger, _fighter({"position": Vector2(630.0, 386.0)}))})

	# Sudden death: grace (no bombs), one bomb, three bombs.
	var duelist_1 := _fighter({"position": Vector2(330.0, 386.0), "damage_percent": 300.0, "stocks": 1})
	var duelist_2 := _fighter({"position": Vector2(530.0, 386.0), "damage_percent": 300.0, "stocks": 1, "facing": -1})
	cases.append({"name": "sudden death grace, no bombs, player 1", "my_index": 0, "snapshot": _snapshot(duelist_1, duelist_2, {"sudden_death": true, "sudden_death_phase": 1, "sudden_death_elapsed": 5.0, "timer_left": 0.0})})
	cases.append({"name": "sudden death, one bomb, player 1", "my_index": 0, "snapshot": _snapshot(duelist_1, duelist_2, {"sudden_death": true, "sudden_death_phase": 2, "sudden_death_elapsed": 24.0, "timer_left": 0.0, "bombs": [_bomb(350.0, 100.0)]})})
	var three_bombs := _snapshot(duelist_1, duelist_2, {
		"sudden_death": true, "sudden_death_phase": 2, "sudden_death_elapsed": 41.5, "timer_left": 0.0,
		"bombs": [_bomb(900.0, -200.0), _bomb(340.0, 200.0), _bomb(500.0, 450.0), {"position": Vector2(100.0, 600.0), "velocity": Vector2(0.0, 420.0), "radius": 90.0}],
	})
	cases.append({"name": "sudden death, four bombs (two nearest encoded), player 1", "my_index": 0, "snapshot": three_bombs})
	cases.append({"name": "sudden death, four bombs (two nearest encoded), player 2", "my_index": 1, "snapshot": three_bombs})

	# Extremes: everything clipped, NaN-free.
	var extreme := _fighter({
		"position": Vector2(1.0e6, -1.0e6), "velocity": Vector2(1.0e9, -1.0e9), "damage_percent": 999.0,
		"cooldowns": {"punch": 99.0, "shoot": 99.0}, "stocks": 99, "jumps_left": 99, "charge_level": 9.0,
		"shield": 9999.0, "dizzy_left": 99.0, "dizzy": true,
	})
	var extreme_bombs: Array = []
	for i in 6:
		extreme_bombs.append(_bomb(430.0 + i * 1.0e4, -1.0e5 + i * 1.0e4))
	cases.append({"name": "extremes and sudden death, player 1", "my_index": 0, "snapshot": _snapshot(extreme, _fighter({"position": Vector2(-1.0e6, 1.0e6)}), {"timer_left": 1000.0, "sudden_death": true, "sudden_death_phase": 2, "sudden_death_elapsed": 1000.0, "bombs": extreme_bombs})})
	cases.append({"name": "extremes and sudden death, player 2", "my_index": 1, "snapshot": _snapshot(extreme, _fighter({"position": Vector2(-1.0e6, 1.0e6)}), {"timer_left": 1000.0, "sudden_death": true, "sudden_death_phase": 2, "sudden_death_elapsed": 1000.0, "bombs": extreme_bombs})})
	return cases
