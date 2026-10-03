extends SceneTree
## bvs-schema-2: the observation layout (synthetic snapshots plus a real Game), the
## frozen layout fixture, the observation golden fixture, the schema registry and
## sidecar validation, and the action decoder. Run headless.
##
## Synthetic snapshots use a stage spanning x 30..830 at top 480, so the stage
## center is 430 and its half width 400: a fighter standing on the floor sits at
## y 386 (feet 94 below), which gives round normalized values.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const LAYOUT_FIXTURE := "res://tests/fixtures/schema/v2_layout.json"
const OBS_FIXTURE := "res://tests/fixtures/schema/v2_obs_golden.json"

# Layout offsets this test pins (they are part of the frozen v2 contract).
const OPP := 35
const REL := 70
const IN_FRONT := 72
const OFF_STAGE := 73
const LEDGE_LEFT := 74
const LEDGE_RIGHT := 75
const FOOD0 := 76
const FOOD1 := 82
const PROJ0 := 88
const PROJ1 := 94
const TIMER := 100
const SUDDEN := 101

## Registered as schema 4 in the extensibility check, then removed again (versions 2
## and 3 are built in).
class StubSchemaV4 extends RefCounted:
	const OBS_DIM := 7

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	_check_observation(s)
	_check_fixtures(s)
	_check_registry(s)
	await _check_real_game(s)
	await _check_decoder(s)
	s.finish()

# ------------------------------------------------------------------ builders

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
	}
	fighter.merge(over, true)
	return fighter

func _snapshot(fighter_1: Dictionary, fighter_2: Dictionary, over: Dictionary = {}) -> Dictionary:
	var snapshot := {
		"phase": "playing",
		"timer_left": 50.0,
		"timer_running": true,
		"sudden_death": false,
		"stage": {"left": 30.0, "right": 830.0, "top": 480.0},
		"platforms": [],
		"blast_zone": {"left": -230.0, "right": 1090.0, "top": -400.0, "bottom": 810.0},
		"ledges": [
			{"side": -1, "x": 30.0, "top": 480.0, "bottom": 738.0, "occupied": false},
			{"side": 1, "x": 830.0, "top": 480.0, "bottom": 738.0, "occupied": false},
		],
		"foods": [],
		"projectiles": [],
		"fighters": [fighter_1, fighter_2],
	}
	snapshot.merge(over, true)
	return snapshot

func _near(a: float, b: float, eps: float = 1e-6) -> bool:
	return absf(a - b) <= eps

func _all_finite_and_bounded(obs: PackedFloat32Array) -> bool:
	for value in obs:
		if is_nan(value) or is_inf(value) or value < -5.0 or value > 5.0:
			return false
	return true

func _slice(obs: PackedFloat32Array, from: int, count: int) -> Array:
	var out: Array = []
	for i in count:
		out.append(snappedf(obs[from + i], 1e-6))
	return out

# --------------------------------------------------------------- observation

func _check_observation(s: RefCounted) -> void:
	var obs := BvsSchemaV2.build_obs(_snapshot(_fighter(), _fighter({"position": Vector2(630.0, 386.0)})), 0)
	s.check("obs length is 102", obs.size() == 102 and BvsSchemaV2.OBS_DIM == 102, "len=%d" % obs.size())
	s.check("FIELD_NAMES lists 102 distinct names", BvsSchemaV2.FIELD_NAMES.size() == 102 and _distinct(BvsSchemaV2.FIELD_NAMES))
	s.check("declared constants are version 2, repeat 4, 21 logits", BvsSchemaV2.VERSION == 2 and BvsSchemaV2.ACTION_REPEAT == 4 and BvsSchemaV2.LOGITS == 21)

	# The fighter block: self at [0,35), opponent at [35,70).
	var me := _fighter({
		"position": Vector2(630.0, 386.0), "velocity": Vector2(300.0, -650.0), "facing": -1,
		"damage_percent": 50.0, "stocks": 2, "held_food": "pizza", "state": &"Punch",
		"cooldowns": {"punch": 0.5, "shoot": 1.0}, "jumps_left": 1, "air_dash_available": false,
		"recovery_available": false, "is_invulnerable": true, "ledge_side": -1, "fast_falling": true,
		"charge_level": 0.25,
	})
	var foe := _fighter({"position": Vector2(230.0, 480.0), "held_food": "turkey", "state": &"Hurt", "on_floor": false})
	var block := BvsSchemaV2.build_obs(_snapshot(me, foe), 0)
	s.check("self position is stage-relative", _near(block[0], 0.5) and _near(block[1], -0.235), "x=%.4f y=%.4f" % [block[0], block[1]])
	s.check("self velocity is scaled by dash speed and fast-fall speed", _near(block[2], 0.5) and _near(block[3], -0.5))
	s.check("self facing, floor, damage, stocks", block[4] == -1.0 and block[5] == 1.0 and _near(block[6], 0.5) and _near(block[7], 2.0 / 3.0))
	s.check("self held food: flag and MEDIUM one-hot", block[8] == 1.0 and _slice(block, 9, 3) == [0.0, 1.0, 0.0])
	s.check("self cooldowns and air actions", _near(block[12], 0.5) and _near(block[13], 0.5) and _near(block[14], 0.5) and block[15] == 0.0 and block[16] == 0.0)
	s.check("self invulnerable, ledge side, fast fall, charge", block[17] == 1.0 and block[18] == -1.0 and block[19] == 1.0 and _near(block[20], 0.25))
	s.check("self state one-hot: Punch is slot 4 of 14", _slice(block, 21, 14) == [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	s.check("opponent block starts at 35 with its own values", _near(block[OPP], -0.5) and _near(block[OPP + 1], 0.0) and block[OPP + 5] == 0.0 and block[OPP + 8] == 1.0 and _slice(block, OPP + 9, 3) == [0.0, 0.0, 1.0])
	s.check("opponent state one-hot: Hurt is slot 5", block[OPP + 21 + 5] == 1.0)
	var odd := BvsSchemaV2.build_obs(_snapshot(_fighter({"state": &"Wobble"}), _fighter()), 0)
	s.check("an unknown FSM state lands in the catch-all slot", odd[21 + 13] == 1.0 and odd[21 + 4] == 0.0)

	# Shared block.
	s.check("opponent relative position", _near(block[REL], -1.0) and _near(block[REL + 1], 0.235), "dx=%.4f dy=%.4f" % [block[REL], block[REL + 1]])
	var front := BvsSchemaV2.build_obs(_snapshot(_fighter({"facing": 1}), _fighter({"position": Vector2(630.0, 386.0)})), 0)
	var behind := BvsSchemaV2.build_obs(_snapshot(_fighter({"facing": -1}), _fighter({"position": Vector2(630.0, 386.0)})), 0)
	var same_x := BvsSchemaV2.build_obs(_snapshot(_fighter(), _fighter()), 0)
	s.check("opponent in front is +1 facing it, -1 behind, 0 when aligned", front[IN_FRONT] == 1.0 and behind[IN_FRONT] == -1.0 and same_x[IN_FRONT] == 0.0)
	var off_x := BvsSchemaV2.build_obs(_snapshot(_fighter({"position": Vector2(-100.0, 386.0), "on_floor": false}), _fighter()), 0)
	var off_y := BvsSchemaV2.build_obs(_snapshot(_fighter({"position": Vector2(430.0, 400.0), "on_floor": false}), _fighter()), 0)
	var in_air := BvsSchemaV2.build_obs(_snapshot(_fighter({"position": Vector2(430.0, 300.0), "on_floor": false}), _fighter()), 0)
	var grounded := BvsSchemaV2.build_obs(_snapshot(_fighter({"position": Vector2(-100.0, 386.0)}), _fighter()), 0)
	s.check("off stage: airborne past an edge or below the top only", off_x[OFF_STAGE] == 1.0 and off_y[OFF_STAGE] == 1.0 and in_air[OFF_STAGE] == 0.0 and grounded[OFF_STAGE] == 0.0)
	var occupied := BvsSchemaV2.build_obs(_snapshot(_fighter(), _fighter(), {"ledges": [
		{"side": -1, "x": 30.0, "top": 480.0, "bottom": 738.0, "occupied": false},
		{"side": 1, "x": 830.0, "top": 480.0, "bottom": 738.0, "occupied": true},
	]}), 0)
	s.check("ledge occupancy is left then right", occupied[LEDGE_LEFT] == 0.0 and occupied[LEDGE_RIGHT] == 1.0)
	var timed := BvsSchemaV2.build_obs(_snapshot(_fighter(), _fighter(), {"timer_left": 49.5, "sudden_death": true}), 0)
	var long_timer := BvsSchemaV2.build_obs(_snapshot(_fighter(), _fighter(), {"timer_left": 400.0}), 0)
	s.check("timer is left/99 clipped to 1, sudden death flag", _near(timed[TIMER], 0.5) and long_timer[TIMER] == 1.0 and timed[SUDDEN] == 1.0 and obs[SUDDEN] == 0.0)

	# Clipping and finiteness.
	var extreme := _fighter({
		"position": Vector2(1.0e6, -1.0e6), "velocity": Vector2(1.0e9, -1.0e9), "damage_percent": 999.0,
		"cooldowns": {"punch": 99.0, "shoot": 99.0}, "stocks": 99, "jumps_left": 99, "charge_level": 9.0,
	})
	var clipped := BvsSchemaV2.build_obs(_snapshot(extreme, _fighter({"position": Vector2(NAN, INF)}), {"timer_left": INF}), 0)
	s.check("999% damage, huge position and velocity stay finite and inside [-5, 5]", _all_finite_and_bounded(clipped))
	s.check("clipping lands on the documented bounds", clipped[0] == 5.0 and clipped[1] == -5.0 and clipped[2] == 5.0 and clipped[3] == -5.0 and clipped[6] == 5.0 and clipped[7] == 1.0 and clipped[12] == 1.0)
	s.check("a NaN position becomes a finite value", not is_nan(clipped[OPP]) and not is_nan(clipped[REL]))

	# Perspective: player 2 sees itself first.
	var f1 := _fighter({"position": Vector2(630.0, 386.0), "damage_percent": 20.0, "facing": -1})
	var f2 := _fighter({"position": Vector2(230.0, 386.0), "damage_percent": 70.0})
	var for_p1 := BvsSchemaV2.build_obs(_snapshot(f1, f2), 0)
	var for_p2 := BvsSchemaV2.build_obs(_snapshot(f1, f2), 1)
	var mirrored := true
	for i in 35:
		mirrored = mirrored and for_p2[i] == for_p1[OPP + i] and for_p2[OPP + i] == for_p1[i]
	s.check("player 2 sees itself in the first block and player 1 in the second", mirrored)
	s.check("relative position flips sign for the other player", _near(for_p2[REL], -for_p1[REL]) and _near(for_p2[REL + 1], -for_p1[REL + 1]))

	# Foods: the two nearest on the stage, nearest first; the rest are sentinels.
	var foods := [
		{"name": "pizza", "position": Vector2(630.0, 400.0)},
		{"name": "popcorn", "position": Vector2(130.0, 400.0)},
		{"name": "turkey", "position": Vector2(480.0, 400.0)},
		{"name": "steak", "position": Vector2(900.0, 400.0)},
	]
	var fed := BvsSchemaV2.build_obs(_snapshot(_fighter(), _fighter({"position": Vector2(430.0, 100.0)}), {"foods": foods}), 0)
	s.check("food slot 0 is the nearest: present, dx, dy, HEAVY one-hot", fed[FOOD0] == 1.0 and _near(fed[FOOD0 + 1], 0.125) and _near(fed[FOOD0 + 2], 0.035) and _slice(fed, FOOD0 + 3, 3) == [0.0, 0.0, 1.0], str(_slice(fed, FOOD0, 6)))
	s.check("food slot 1 is the second nearest (MEDIUM); an off-stage food is ignored", fed[FOOD1] == 1.0 and _near(fed[FOOD1 + 1], 0.5) and _slice(fed, FOOD1 + 3, 3) == [0.0, 1.0, 0.0])
	var one_food := BvsSchemaV2.build_obs(_snapshot(_fighter(), _fighter(), {"foods": [foods[0]]}), 0)
	s.check("a missing second food is the all-zero sentinel", _slice(one_food, FOOD1, 6) == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0] and one_food[FOOD0] == 1.0)
	s.check("no food on stage: both slots are sentinels and the length is unchanged", _slice(obs, FOOD0, 12) == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0] and obs.size() == 102)

	# Projectiles: nearest first, with the shooter flag from my point of view.
	var shots := [
		{"position": Vector2(730.0, 386.0), "velocity": Vector2(-600.0, 0.0), "shooter": 2},
		{"position": Vector2(480.0, 336.0), "velocity": Vector2(300.0, -130.0), "shooter": 1},
	]
	var shot_snapshot := _snapshot(_fighter(), _fighter({"position": Vector2(730.0, 386.0)}), {"projectiles": shots})
	var shot_p1 := BvsSchemaV2.build_obs(shot_snapshot, 0)
	var shot_p2 := BvsSchemaV2.build_obs(shot_snapshot, 1)
	s.check("projectile slot 0 is the nearest with scaled velocity", shot_p1[PROJ0] == 1.0 and _near(shot_p1[PROJ0 + 1], 0.125) and _near(shot_p1[PROJ0 + 2], -0.125) and _near(shot_p1[PROJ0 + 3], 0.5) and _near(shot_p1[PROJ0 + 4], -0.1), str(_slice(shot_p1, PROJ0, 6)))
	s.check("the mine flag is 1 for my own shot (P1 sees shooter 1 as mine)", shot_p1[PROJ0 + 5] == 1.0 and shot_p1[PROJ1 + 5] == 0.0)
	s.check("player 2 sees its own shot (right on top of it) as mine and player 1's as not", shot_p2[PROJ0 + 5] == 1.0 and _near(shot_p2[PROJ0 + 1], 0.0) and shot_p2[PROJ1 + 5] == 0.0)
	s.check("no projectile: both slots are sentinels", _slice(obs, PROJ0, 12) == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])

	# Read-only: the same snapshot builds the same vector and is not touched.
	var snapshot := _snapshot(f1, f2, {"foods": foods, "projectiles": shots})
	var before := snapshot.hash()
	var first := BvsSchemaV2.build_obs(snapshot, 0)
	var second := BvsSchemaV2.build_obs(snapshot, 0)
	s.check("building twice gives equal vectors and leaves the snapshot untouched", first == second and snapshot.hash() == before)

	# Missing keys are reported by name, never replaced with zeros.
	var missing_timer := _snapshot(f1, f2)
	missing_timer.erase("timer_left")
	s.check("a missing Game key is reported by name", BvsSchemaV2.validate_snapshot(missing_timer, 0).contains("timer_left"), BvsSchemaV2.validate_snapshot(missing_timer, 0))
	var missing_edge := _snapshot(f1, f2)
	missing_edge["stage"] = {"right": 830.0, "top": 480.0}
	s.check("a missing stage edge is reported by name", BvsSchemaV2.validate_snapshot(missing_edge, 0).contains("stage.left"))
	var broken_fighter := _fighter()
	broken_fighter.erase("jumps_left")
	s.check("a missing fighter key names the fighter and the key", BvsSchemaV2.validate_snapshot(_snapshot(f1, broken_fighter), 0).contains("jumps_left"), BvsSchemaV2.validate_snapshot(_snapshot(f1, broken_fighter), 0))
	s.check("a complete snapshot validates clean", BvsSchemaV2.validate_snapshot(_snapshot(f1, f2), 0) == "" and BvsSchemaV2.validate_snapshot(_snapshot(f1, f2), 1) == "")
	var fallback := BvsSchemaV2.build_obs(missing_timer, 0)
	s.check("build_obs on a broken snapshot reports and returns a neutral vector of the right length", fallback.size() == 102 and fallback.count(0.0) == 102)

	# Action space and logits.
	var space := BvsSchemaV2.action_space()
	var names: Array = space.keys()
	var sizes: Array = []
	for key in names:
		sizes.append(space[key]["size"])
	s.check("action space: eight discrete branches a0_move..a7_dash sized 3,3,2,5,2,2,2,2", names == ["a0_move", "a1_vertical", "a2_jump", "a3_attack", "a4_special", "a5_throw", "a6_block", "a7_dash"] and sizes == [3, 3, 2, 5, 2, 2, 2, 2] and space["a3_attack"]["action_type"] == "discrete")
	var logits := PackedFloat32Array()
	logits.resize(21)
	logits.fill(0.0)
	logits[2] = 3.0 # a0_move: right
	logits[4] = 1.0 # a1_vertical: up
	logits[7] = 2.0 # a2_jump: hold
	logits[12] = 9.0 # a3_attack: offset 8, index 4 (side)
	s.check("argmax per branch over 21 logits, ties go to the lowest index", BvsSchemaV2.argmax_branches(logits) == PackedInt32Array([2, 1, 1, 4, 0, 0, 0, 0]), str(BvsSchemaV2.argmax_branches(logits)))
	s.check("action_from_dict reads ints, floats and one-element arrays in branch order", BvsSchemaV2.action_from_dict({"a0_move": 2, "a1_vertical": 1.0, "a2_jump": [1], "a3_attack": 4, "a4_special": 0, "a5_throw": 1, "a6_block": 0, "a7_dash": 1}) == PackedInt32Array([2, 1, 1, 4, 0, 1, 0, 1]))
	var template := BvsSchemaV2.sidecar_template()
	s.check("sidecar template carries the schema contract", template["schema_version"] == 2 and template["obs_dim"] == 102 and template["action_repeat"] == 4 and template["action_branches"].size() == 8 and template["format"] == "bvs-model/1")

func _distinct(names: PackedStringArray) -> bool:
	var seen := {}
	for field_name in names:
		if seen.has(field_name) or field_name == "":
			return false
		seen[field_name] = true
	return true

# ------------------------------------------------------------------ fixtures

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _vec(value: Variant) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

## Fixture snapshots are JSON: vectors are [x, y] arrays and names are strings.
func _snapshot_from_json(raw: Dictionary) -> Dictionary:
	var snapshot: Dictionary = raw.duplicate(true)
	for fighter: Dictionary in snapshot["fighters"]:
		fighter["position"] = _vec(fighter["position"])
		fighter["velocity"] = _vec(fighter["velocity"])
		fighter["facing"] = int(fighter["facing"])
		fighter["stocks"] = int(fighter["stocks"])
		fighter["jumps_left"] = int(fighter["jumps_left"])
		fighter["ledge_side"] = int(fighter["ledge_side"])
	for food: Dictionary in snapshot["foods"]:
		food["position"] = _vec(food["position"])
	for shot: Dictionary in snapshot["projectiles"]:
		shot["position"] = _vec(shot["position"])
		shot["velocity"] = _vec(shot["velocity"])
		shot["shooter"] = int(shot["shooter"])
	for ledge: Dictionary in snapshot["ledges"]:
		ledge["side"] = int(ledge["side"])
	return snapshot

func _check_fixtures(s: RefCounted) -> void:
	var layout: Variant = _read_json(LAYOUT_FIXTURE)
	var frozen: bool = layout is Array and layout.size() == BvsSchemaV2.FIELD_NAMES.size()
	if frozen:
		for i in layout.size():
			frozen = frozen and String(layout[i]) == BvsSchemaV2.FIELD_NAMES[i]
	s.check("the layout fixture equals FIELD_NAMES name by name (the v2 freeze)", frozen)

	var golden: Variant = _read_json(OBS_FIXTURE)
	s.check("the observation golden fixture holds recorded cases", golden is Dictionary and golden.get("cases", []).size() >= 4)
	if not (golden is Dictionary):
		return
	var matched := 0
	var worst := 0.0
	for entry: Dictionary in golden["cases"]:
		var built := BvsSchemaV2.build_obs(_snapshot_from_json(entry["snapshot"]), int(entry["my_index"]))
		var expected: Array = entry["expected"]
		if built.size() != expected.size():
			continue
		var ok := true
		for i in expected.size():
			var diff := absf(built[i] - float(expected[i]))
			worst = maxf(worst, diff)
			ok = ok and diff <= 1e-6
		matched += 1 if ok else 0
	s.check("every golden case rebuilds within 1e-6", matched == golden["cases"].size(), "matched=%d/%d worst=%.2e" % [matched, golden["cases"].size(), worst])

# ------------------------------------------------------------------ registry

func _check_registry(s: RefCounted) -> void:
	# Nothing in this function depends on which schema is the CURRENT one: the frozen
	# v2 contract is checked against schema 2 itself (BvsSchema.validate_sidecar_for).
	s.check("schema 2 declares version 2", BvsSchemaV2.VERSION == 2 and BvsSchema.get_schema(2).VERSION == 2)
	s.check("the registry maps 2 to BvsSchemaV2", BvsSchema.get_schema(2) == BvsSchemaV2)
	s.check("an unregistered version is unsupported, not a default layout", BvsSchema.get_schema(99) == null)

	var template := BvsSchemaV2.sidecar_template()
	s.check("the schema's own sidecar template validates against schema 2", BvsSchema.validate_sidecar_for(template, 2) == "", BvsSchema.validate_sidecar_for(template, 2))
	var future := template.duplicate(true)
	future["schema_version"] = 99
	s.check("a sidecar for version 99 reports unsupported", BvsSchema.validate_sidecar(future).to_lower().contains("unsupported"), BvsSchema.validate_sidecar(future))
	var old := template.duplicate(true)
	old["schema_version"] = 1
	s.check("a sidecar for version 1 reports an older schema", BvsSchema.validate_sidecar(old).to_lower().contains("older") or BvsSchema.validate_sidecar(old).to_lower().contains("unsupported"), BvsSchema.validate_sidecar(old))
	var narrow := template.duplicate(true)
	narrow["obs_dim"] = 13
	s.check("a wrong obs_dim says what the model expects and what the game provides", BvsSchema.validate_sidecar_for(narrow, 2).contains("expects 13 inputs") and BvsSchema.validate_sidecar_for(narrow, 2).contains("provides 102"), BvsSchema.validate_sidecar_for(narrow, 2))
	var reordered := template.duplicate(true)
	var swapped: Array = reordered["action_branches"]
	var first_branch: Dictionary = swapped[0]
	swapped[0] = swapped[1]
	swapped[1] = first_branch
	s.check("reordered action branches are rejected naming action_branches", BvsSchema.validate_sidecar_for(reordered, 2).contains("action_branches"), BvsSchema.validate_sidecar_for(reordered, 2))
	var resized := template.duplicate(true)
	resized["action_branches"][3]["size"] = 4
	s.check("a wrong branch size is rejected", BvsSchema.validate_sidecar_for(resized, 2).contains("a3_attack"), BvsSchema.validate_sidecar_for(resized, 2))
	var repeated := template.duplicate(true)
	repeated["action_repeat"] = 2
	s.check("a wrong action_repeat is rejected", BvsSchema.validate_sidecar_for(repeated, 2).contains("action_repeat"), BvsSchema.validate_sidecar_for(repeated, 2))
	var lacking := template.duplicate(true)
	lacking.erase("schema_version")
	s.check("a missing sidecar key is named", BvsSchema.validate_sidecar(lacking).contains("schema_version"), BvsSchema.validate_sidecar(lacking))

	# A test-only schema 4 must leave schema 2 untouched.
	var snapshot := _snapshot(_fighter(), _fighter({"position": Vector2(630.0, 386.0)}), {"foods": [{"name": "pizza", "position": Vector2(480.0, 400.0)}]})
	var before := BvsSchemaV2.build_obs(snapshot, 0)
	BvsSchema.register_test_stub(4, StubSchemaV4)
	var with_stub := BvsSchemaV2.build_obs(snapshot, 0)
	s.check("a stub registered as version 4 is found by the registry", BvsSchema.get_schema(4) == StubSchemaV4)
	s.check("schema 2 results are identical with the version 4 stub registered", with_stub == before and BvsSchema.validate_sidecar_for(template, 2) == "")
	BvsSchema.unregister_test_stub(4)
	s.check("the stub is gone again after the test", BvsSchema.get_schema(4) == null)

# ----------------------------------------------------------------- real game

func _check_real_game(s: RefCounted) -> void:
	var game: Node2D = s.spawn_game()
	await s.frames(30)
	var snapshot: Dictionary = game.get_state_snapshot()
	s.check("a real Game snapshot carries every key schema 2 reads", BvsSchemaV2.validate_snapshot(snapshot, 0) == "", BvsSchemaV2.validate_snapshot(snapshot, 0))
	var stage: Dictionary = snapshot["stage"]
	s.check("stage edges are present and Game-local", stage.has("left") and stage.has("right") and stage.has("top") and stage["left"] < stage["right"])
	var at_origin := BvsSchemaV2.build_obs(snapshot, 0)
	var origin_stage: Dictionary = stage.duplicate()
	game.global_position += Vector2(3000.0, 2000.0)
	var moved_snapshot: Dictionary = game.get_state_snapshot()
	var moved := BvsSchemaV2.build_obs(moved_snapshot, 0)
	s.check("the stage edges do not change with the global offset", moved_snapshot["stage"] == origin_stage)
	s.check("observations are identical at a different global offset", moved == at_origin)
	s.check("a real fighter observation is finite, bounded and 102 long", moved.size() == 102 and _all_finite_and_bounded(moved))
	await s.despawn(game)

# ------------------------------------------------------------------- decoder

func _acts(move: int = 1, vertical: int = 0, jump: int = 0, attack: int = 0, special: int = 0, throw: int = 0, block: int = 0, dash: int = 0) -> PackedInt32Array:
	return PackedInt32Array([move, vertical, jump, attack, special, throw, block, dash])

func _neutral(intent: FighterIntent) -> bool:
	return intent.move_x == 0.0 and not intent.jump_pressed and not intent.jump_held and not intent.attack_pressed \
		and not intent.attack_held and not intent.attack_released and not intent.throw_pressed \
		and not intent.block_pressed and not intent.block_held and not intent.dash_pressed \
		and intent.aim == FighterIntent.Aim.NEUTRAL and not intent.special_pressed

## The four frames of one window; frame 0 is the decision frame.
func _window(decoder: BvsActionDecoderV2, fighter: Fighter, actions: PackedInt32Array) -> Array[FighterIntent]:
	var err := decoder.begin_window(actions)
	var frames: Array[FighterIntent] = []
	if err != "":
		frames.append(decoder.frame(fighter))
		return frames
	for i in BvsSchemaV2.ACTION_REPEAT:
		frames.append(decoder.frame(fighter))
	return frames

func _count(frames: Array[FighterIntent], field: String) -> int:
	var total := 0
	for intent in frames:
		total += 1 if intent.get(field) else 0
	return total

func _check_decoder(s: RefCounted) -> void:
	var game: Node2D = s.spawn_game()
	await s.frames(30)
	var fighter: Fighter = game.get_node("Fighter1")
	s.check("the fighter stands on the floor for the grounded decoder checks", fighter.is_on_floor())

	var decoder := BvsActionDecoderV2.new()
	s.check("a decoder with no window yet gives a neutral intent and no error", _neutral(decoder.frame(fighter)))

	# Move mapping, held for the whole window.
	var moves: Array[float] = []
	for move in [0, 1, 2]:
		moves.append(_window(decoder, fighter, _acts(move))[0].move_x)
	s.check("move 0, 1, 2 decode to -1, 0, +1", moves == [-1.0, 0.0, 1.0], str(moves))
	var right_window := _window(decoder, fighter, _acts(2))
	var held_right := true
	for intent in right_window:
		held_right = held_right and intent.move_x == 1.0
	s.check("a move decision holds for all four ticks (action repeat)", held_right and right_window.size() == 4)

	# Vertical: a held aim for the window.
	var down := _window(decoder, fighter, _acts(1, 2))
	var up := _window(decoder, fighter, _acts(1, 1))
	var none := _window(decoder, fighter, _acts(1, 0))
	var vertical_held := true
	for intent in down:
		vertical_held = vertical_held and intent.aim == FighterIntent.Aim.DOWN
	s.check("vertical down is a held DOWN aim on every tick", vertical_held)
	s.check("vertical up is a held UP aim and none is neutral", up[0].aim == FighterIntent.Aim.UP and up[3].aim == FighterIntent.Aim.UP and none[0].aim == FighterIntent.Aim.NEUTRAL)

	# Attack: pressed once on the first tick, aim from the branch.
	var attack_aims := {}
	for value in [1, 2, 3, 4]:
		var window := _window(decoder, fighter, _acts(1, 0, 0, value))
		attack_aims[value] = window[0].aim
		s.check("attack %d presses once on the first tick only" % value, window[0].attack_pressed and _count(window, "attack_pressed") == 1)
	s.check("attack 1..4 maps to aim neutral, up, down, side", attack_aims == {1: FighterIntent.Aim.NEUTRAL, 2: FighterIntent.Aim.UP, 3: FighterIntent.Aim.DOWN, 4: FighterIntent.Aim.SIDE}, str(attack_aims))
	var no_attack := _window(decoder, fighter, _acts(1, 0, 0, 0))
	s.check("attack none never presses", _count(no_attack, "attack_pressed") == 0)

	# Special overrides attack and forces aim UP on its tick.
	var special := _window(decoder, fighter, _acts(1, 0, 0, 2, 1))
	s.check("special presses once with aim UP and overrides the attack branch", special[0].special_pressed and special[0].aim == FighterIntent.Aim.UP and _count(special, "special_pressed") == 1 and _count(special, "attack_pressed") == 0)
	var special_down := _window(decoder, fighter, _acts(1, 2, 0, 0, 1))
	s.check("special beats a held down aim on its tick", special_down[0].aim == FighterIntent.Aim.UP)

	# Throw and dash pulse once.
	var throw := _window(decoder, fighter, _acts(1, 0, 0, 0, 0, 1))
	var dash := _window(decoder, fighter, _acts(1, 0, 0, 0, 0, 0, 0, 1))
	s.check("throw presses on the first tick only", throw[0].throw_pressed and _count(throw, "throw_pressed") == 1)
	s.check("dash presses on the first tick only", dash[0].dash_pressed and _count(dash, "dash_pressed") == 1)

	# Block: held for the window, pressed only on a rising edge.
	var block_1 := _window(decoder, fighter, _acts(1, 0, 0, 0, 0, 0, 1))
	var block_2 := _window(decoder, fighter, _acts(1, 0, 0, 0, 0, 0, 1))
	var block_off := _window(decoder, fighter, _acts(1, 0, 0, 0, 0, 0, 0))
	var block_3 := _window(decoder, fighter, _acts(1, 0, 0, 0, 0, 0, 1))
	s.check("block is held for the whole window", _count(block_1, "block_held") == 4 and _count(block_off, "block_held") == 0)
	s.check("block presses on the rising edge only", _count(block_1, "block_pressed") == 1 and _count(block_2, "block_pressed") == 0 and _count(block_3, "block_pressed") == 1)

	# Jump guard, on the floor and in the air.
	var jump_floor_1 := _window(decoder, fighter, _acts(1, 0, 1))
	var jump_floor_2 := _window(decoder, fighter, _acts(1, 0, 1))
	s.check("jump hold keeps jump_held on all ticks", _count(jump_floor_1, "jump_held") == 4)
	s.check("on the floor a held jump presses on the first tick every window", jump_floor_1[0].jump_pressed and jump_floor_2[0].jump_pressed and _count(jump_floor_2, "jump_pressed") == 1)
	_window(decoder, fighter, _acts(1, 0, 0))
	fighter.position.y -= 300.0
	await s.frames(3)
	s.check("the fighter is airborne for the air jump checks", not fighter.is_on_floor())
	var jump_air_1 := _window(decoder, fighter, _acts(1, 0, 1))
	var jump_air_2 := _window(decoder, fighter, _acts(1, 0, 1))
	_window(decoder, fighter, _acts(1, 0, 0))
	var jump_air_3 := _window(decoder, fighter, _acts(1, 0, 1))
	s.check("in the air a jump presses after a release, not on a continued hold", jump_air_1[0].jump_pressed and not jump_air_2[0].jump_pressed and jump_air_3[0].jump_pressed)

	# No charge, ever.
	var charged := false
	for window_actions in [_acts(2, 2, 1, 4, 1, 1, 1, 1), _acts(0, 1, 1, 3, 0, 1, 1, 0), _acts(1, 0, 0, 0, 0, 0, 0, 0)]:
		for intent in _window(decoder, fighter, window_actions):
			charged = charged or intent.attack_held or intent.attack_released
	s.check("attack_held and attack_released stay false", not charged)

	# Invalid vectors: an error and a neutral intent that does not act.
	var short := decoder.begin_window(PackedInt32Array([1, 0, 0, 0, 0, 0, 0]))
	var short_intent := decoder.frame(fighter)
	s.check("seven branches are rejected with an error and a neutral intent", short != "" and _neutral(short_intent), short)
	var out_of_range := decoder.begin_window(_acts(3))
	s.check("a move index equal to the branch size is rejected", out_of_range != "" and _neutral(decoder.frame(fighter)), out_of_range)
	var negative := decoder.begin_window(_acts(1, 0, 0, -1))
	s.check("a negative index is rejected", negative != "" and _neutral(decoder.frame(fighter)), negative)
	var recovered := _window(decoder, fighter, _acts(2))
	s.check("a valid window after a rejected one works again", recovered[0].move_x == 1.0)
	await s.despawn(game)
