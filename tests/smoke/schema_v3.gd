extends SceneTree
## bvs-schema-3: the observation layout (synthetic snapshots plus real Games, shield,
## dizzy and bomb features), the schema registry and sidecar validation, and the
## action decoder with the exclusive throw. Run headless.
##
## Synthetic snapshots use a stage spanning x 30..830 at top 480, so the stage
## center is 430 and its half width 400: a fighter standing on the floor sits at
## y 386 (feet 94 below), which gives round normalized values.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const MODEL_PATH := "res://tests/fixtures/onnx/random_policy_v3.onnx"
const SIDECAR_PATH := "res://tests/fixtures/onnx/random_policy_v3.bvs.json"

# Layout offsets this test pins (they are part of the v3 contract).
const OPP := 43
const REL := 86
const IN_FRONT := 88
const OFF_STAGE := 89
const LEDGE_LEFT := 90
const LEDGE_RIGHT := 91
const FOOD0 := 92
const FOOD1 := 100
const PROJ0 := 108
const PROJ1 := 114
const BOMB0 := 120
const BOMB1 := 126
const TIMER := 132
const SUDDEN := 133
const SD_PHASE := 134
const SD_ELAPSED := 135
# Inside a fighter block.
const HELD_HOT := 12
const HELD_HARD := 13
const CANNOT_BE_HIT := 19
const SHIELD := 23
const DIZZY := 24
const DIZZY_LEFT := 25
const AIR_DODGE := 26
const STATE_BASE := 27

## Registered as schema 4 in the extensibility check, then removed again (versions 2
## and 3 are built in).
class StubSchemaV4 extends RefCounted:
	const OBS_DIM := 7

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	_check_observation(s)
	_check_bombs_and_sudden_death(s)
	_check_registry(s)
	await _check_real_game(s)
	await _check_training_equals_inference(s)
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

func _zeros(count: int) -> Array:
	var out: Array = []
	out.resize(count)
	out.fill(0.0)
	return out

func _distinct(names: PackedStringArray) -> bool:
	var seen := {}
	for field_name in names:
		if seen.has(field_name) or field_name == "":
			return false
		seen[field_name] = true
	return true

# --------------------------------------------------------------- observation

func _check_observation(s: RefCounted) -> void:
	var obs := BvsSchemaV3.build_obs(_snapshot(_fighter(), _fighter({"position": Vector2(630.0, 386.0)})), 0)
	s.check("obs length is 136", obs.size() == 136 and BvsSchemaV3.OBS_DIM == 136, "len=%d" % obs.size())
	s.check("FIELD_NAMES lists 136 distinct names", BvsSchemaV3.FIELD_NAMES.size() == 136 and _distinct(BvsSchemaV3.FIELD_NAMES))
	s.check("declared constants are version 3, repeat 4, 21 logits", BvsSchemaV3.VERSION == 3 and BvsSchemaV3.ACTION_REPEAT == 4 and BvsSchemaV3.LOGITS == 21)
	s.check("the block offsets match the field names", BvsSchemaV3.FIELD_NAMES[OPP] == "opp_pos_x" and BvsSchemaV3.FIELD_NAMES[REL] == "rel_x" and BvsSchemaV3.FIELD_NAMES[FOOD0] == "food0_present" and BvsSchemaV3.FIELD_NAMES[PROJ0] == "proj0_present" and BvsSchemaV3.FIELD_NAMES[BOMB0] == "bomb0_present" and BvsSchemaV3.FIELD_NAMES[TIMER] == "timer_left" and BvsSchemaV3.FIELD_NAMES[SD_ELAPSED] == "sudden_death_elapsed")
	s.check("the fighter block holds the combat-depth fields", BvsSchemaV3.FIELD_NAMES[SHIELD] == "self_shield" and BvsSchemaV3.FIELD_NAMES[DIZZY] == "self_dizzy" and BvsSchemaV3.FIELD_NAMES[DIZZY_LEFT] == "self_dizzy_left" and BvsSchemaV3.FIELD_NAMES[AIR_DODGE] == "self_air_dodge" and BvsSchemaV3.FIELD_NAMES[HELD_HOT] == "self_food_hot" and BvsSchemaV3.FIELD_NAMES[HELD_HARD] == "self_food_hard" and BvsSchemaV3.FIELD_NAMES[CANNOT_BE_HIT] == "self_cannot_be_hit")

	# The fighter block: self at [0,43), opponent at [43,86).
	var me := _fighter({
		"position": Vector2(630.0, 386.0), "velocity": Vector2(300.0, -650.0), "facing": -1,
		"damage_percent": 50.0, "stocks": 2, "held_food": "pizza", "state": &"Punch",
		"cooldowns": {"punch": 0.5, "shoot": 1.0}, "jumps_left": 1, "air_dash_available": false,
		"recovery_available": false, "is_invulnerable": true, "ledge_side": -1, "fast_falling": true,
		"charge_level": 0.25,
	})
	var foe := _fighter({"position": Vector2(230.0, 480.0), "held_food": "turkey", "state": &"Hurt", "on_floor": false})
	var block := BvsSchemaV3.build_obs(_snapshot(me, foe), 0)
	var medium := FoodCatalog.get_weight_class("pizza")
	var heavy := FoodCatalog.get_weight_class("turkey")
	s.check("self position is stage-relative", _near(block[0], 0.5) and _near(block[1], -0.235), "x=%.4f y=%.4f" % [block[0], block[1]])
	s.check("self velocity is scaled by dash speed and fast-fall speed", _near(block[2], 0.5) and _near(block[3], -0.5))
	s.check("self facing, floor, damage, stocks", block[4] == -1.0 and block[5] == 1.0 and _near(block[6], 0.5) and _near(block[7], 2.0 / 3.0))
	s.check("self held food: flag and weight one-hot", block[8] == 1.0 and block[9 + medium] == 1.0 and _slice(block, 9, 3).count(1.0) == 1, str(_slice(block, 9, 3)))
	s.check("an untagged held food leaves the hot and hard flags at 0", block[HELD_HOT] == 0.0 and block[HELD_HARD] == 0.0)
	s.check("self cooldowns and air actions", _near(block[14], 0.5) and _near(block[15], 0.5) and _near(block[16], 0.5) and block[17] == 0.0 and block[18] == 0.0)
	s.check("self cannot-be-hit, ledge side, fast fall, charge", block[CANNOT_BE_HIT] == 1.0 and block[20] == -1.0 and block[21] == 1.0 and _near(block[22], 0.25))
	s.check("self state one-hot: Punch is slot 4 of 16", _slice(block, STATE_BASE, 16) == [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	s.check("opponent block starts at 43 with its own values", _near(block[OPP], -0.5) and _near(block[OPP + 1], 0.0) and block[OPP + 5] == 0.0 and block[OPP + 8] == 1.0 and block[OPP + 9 + heavy] == 1.0)
	s.check("opponent state one-hot: Hurt is slot 5", block[OPP + STATE_BASE + 5] == 1.0)
	var odd := BvsSchemaV3.build_obs(_snapshot(_fighter({"state": &"Wobble"}), _fighter()), 0)
	s.check("an unknown FSM state lands in the catch-all slot", odd[STATE_BASE + 15] == 1.0 and odd[STATE_BASE + 4] == 0.0)
	var dizzy_state := BvsSchemaV3.build_obs(_snapshot(_fighter({"state": &"Dizzy"}), _fighter({"state": &"AirDodge"})), 0)
	s.check("Dizzy is slot 13 and AirDodge slot 14 of the state one-hot", dizzy_state[STATE_BASE + 13] == 1.0 and dizzy_state[OPP + STATE_BASE + 14] == 1.0 and dizzy_state[STATE_BASE + 15] == 0.0)
	s.check("the 16 state slots always hold exactly one 1", _slice(dizzy_state, STATE_BASE, 16).count(1.0) == 1 and _slice(dizzy_state, OPP + STATE_BASE, 16).count(1.0) == 1)

	# Food identity: hot and hard flags of the held food.
	var tags := BvsSchemaV3.build_obs(_snapshot(_fighter({"held_food": "coffee"}), _fighter({"held_food": "cheese"})), 0)
	s.check("a hot food sets the hot flag only", tags[HELD_HOT] == 1.0 and tags[HELD_HARD] == 0.0)
	s.check("the opponent's hard food sets its hard flag only", tags[OPP + HELD_HOT] == 0.0 and tags[OPP + HELD_HARD] == 1.0)

	# Shield and dizzy features.
	var half := _fighter({"shield": 50.0})
	var stunned := _fighter({"dizzy": true, "dizzy_left": 1.0, "shield": 25.0, "state": &"Dizzy"})
	var shielded := BvsSchemaV3.build_obs(_snapshot(half, stunned), 0)
	s.check("self shield at half meter encodes 0.5", _near(shielded[SHIELD], 0.5), "shield=%.3f" % shielded[SHIELD])
	s.check("opponent dizzy is 1 with half the dizzy time left (about 0.5)", shielded[OPP + DIZZY] == 1.0 and _near(shielded[OPP + DIZZY_LEFT], 0.5), "dizzy=%.2f left=%.3f" % [shielded[OPP + DIZZY], shielded[OPP + DIZZY_LEFT]])
	s.check("the opponent's own shield and my dizzy slots are separate", _near(shielded[OPP + SHIELD], 0.25) and shielded[DIZZY] == 0.0 and shielded[DIZZY_LEFT] == 0.0)
	var full := BvsSchemaV3.build_obs(_snapshot(_fighter(), _fighter()), 0)
	s.check("a full shield is 1 and a fresh fighter has an air dodge", full[SHIELD] == 1.0 and full[AIR_DODGE] == 1.0 and full[DIZZY] == 0.0)
	var spent := BvsSchemaV3.build_obs(_snapshot(_fighter({"air_dodge_available": false}), _fighter()), 0)
	s.check("a spent air dodge is 0", spent[AIR_DODGE] == 0.0 and spent[OPP + AIR_DODGE] == 1.0)
	var dodging := BvsSchemaV3.build_obs(_snapshot(_fighter({"intangible": true}), _fighter()), 0)
	s.check("an intangible fighter counts as cannot-be-hit", dodging[CANNOT_BE_HIT] == 1.0 and dodging[OPP + CANNOT_BE_HIT] == 0.0)
	var no_max := BvsSchemaV3.build_obs(_snapshot(_fighter({"shield": 10.0, "shield_max": 0.0}), _fighter()), 0)
	s.check("a zero shield_max never divides by zero", no_max[SHIELD] == 0.0)

	# Shared block.
	s.check("opponent relative position", _near(block[REL], -1.0) and _near(block[REL + 1], 0.235), "dx=%.4f dy=%.4f" % [block[REL], block[REL + 1]])
	var front := BvsSchemaV3.build_obs(_snapshot(_fighter({"facing": 1}), _fighter({"position": Vector2(630.0, 386.0)})), 0)
	var behind := BvsSchemaV3.build_obs(_snapshot(_fighter({"facing": -1}), _fighter({"position": Vector2(630.0, 386.0)})), 0)
	var same_x := BvsSchemaV3.build_obs(_snapshot(_fighter(), _fighter()), 0)
	s.check("opponent in front is +1 facing it, -1 behind, 0 when aligned", front[IN_FRONT] == 1.0 and behind[IN_FRONT] == -1.0 and same_x[IN_FRONT] == 0.0)
	var off_x := BvsSchemaV3.build_obs(_snapshot(_fighter({"position": Vector2(-100.0, 386.0), "on_floor": false}), _fighter()), 0)
	var off_y := BvsSchemaV3.build_obs(_snapshot(_fighter({"position": Vector2(430.0, 400.0), "on_floor": false}), _fighter()), 0)
	var in_air := BvsSchemaV3.build_obs(_snapshot(_fighter({"position": Vector2(430.0, 300.0), "on_floor": false}), _fighter()), 0)
	var grounded := BvsSchemaV3.build_obs(_snapshot(_fighter({"position": Vector2(-100.0, 386.0)}), _fighter()), 0)
	s.check("off stage: airborne past an edge or below the top only", off_x[OFF_STAGE] == 1.0 and off_y[OFF_STAGE] == 1.0 and in_air[OFF_STAGE] == 0.0 and grounded[OFF_STAGE] == 0.0)
	var occupied := BvsSchemaV3.build_obs(_snapshot(_fighter(), _fighter(), {"ledges": [
		{"side": -1, "x": 30.0, "top": 480.0, "bottom": 738.0, "occupied": false},
		{"side": 1, "x": 830.0, "top": 480.0, "bottom": 738.0, "occupied": true},
	]}), 0)
	s.check("ledge occupancy is left then right", occupied[LEDGE_LEFT] == 0.0 and occupied[LEDGE_RIGHT] == 1.0)
	var timed := BvsSchemaV3.build_obs(_snapshot(_fighter(), _fighter(), {"timer_left": 49.5, "sudden_death": true}), 0)
	var long_timer := BvsSchemaV3.build_obs(_snapshot(_fighter(), _fighter(), {"timer_left": 400.0}), 0)
	s.check("timer is left/99 clipped to 1, sudden death flag", _near(timed[TIMER], 0.5) and long_timer[TIMER] == 1.0 and timed[SUDDEN] == 1.0 and obs[SUDDEN] == 0.0)

	# Clipping and finiteness.
	var extreme := _fighter({
		"position": Vector2(1.0e6, -1.0e6), "velocity": Vector2(1.0e9, -1.0e9), "damage_percent": 999.0,
		"cooldowns": {"punch": 99.0, "shoot": 99.0}, "stocks": 99, "jumps_left": 99, "charge_level": 9.0,
		"shield": 9999.0, "dizzy_left": 99.0,
	})
	var clipped := BvsSchemaV3.build_obs(_snapshot(extreme, _fighter({"position": Vector2(NAN, INF)}), {"timer_left": INF, "sudden_death_elapsed": INF}), 0)
	s.check("999% damage, huge position and velocity stay finite and inside [-5, 5]", _all_finite_and_bounded(clipped))
	s.check("clipping lands on the documented bounds", clipped[0] == 5.0 and clipped[1] == -5.0 and clipped[2] == 5.0 and clipped[3] == -5.0 and clipped[6] == 5.0 and clipped[7] == 1.0 and clipped[14] == 1.0 and clipped[SHIELD] == 1.0 and clipped[DIZZY_LEFT] == 1.0)
	s.check("a NaN position becomes a finite value", not is_nan(clipped[OPP]) and not is_nan(clipped[REL]))

	# Perspective: player 2 sees itself first.
	var f1 := _fighter({"position": Vector2(630.0, 386.0), "damage_percent": 20.0, "facing": -1, "shield": 40.0})
	var f2 := _fighter({"position": Vector2(230.0, 386.0), "damage_percent": 70.0, "dizzy": true, "dizzy_left": 0.5})
	var for_p1 := BvsSchemaV3.build_obs(_snapshot(f1, f2), 0)
	var for_p2 := BvsSchemaV3.build_obs(_snapshot(f1, f2), 1)
	var mirrored := true
	for i in 43:
		mirrored = mirrored and for_p2[i] == for_p1[OPP + i] and for_p2[OPP + i] == for_p1[i]
	s.check("player 2 sees itself in the first block and player 1 in the second", mirrored)
	s.check("relative position flips sign for the other player", _near(for_p2[REL], -for_p1[REL]) and _near(for_p2[REL + 1], -for_p1[REL + 1]))

	# Foods: the two nearest on the stage, nearest first, with the identity flags.
	var foods := [
		{"name": "pizza", "position": Vector2(630.0, 400.0)},
		{"name": "popcorn", "position": Vector2(130.0, 400.0)},
		{"name": "coffee", "position": Vector2(480.0, 400.0)},
		{"name": "steak", "position": Vector2(900.0, 400.0)},
	]
	var fed := BvsSchemaV3.build_obs(_snapshot(_fighter(), _fighter({"position": Vector2(430.0, 100.0)}), {"foods": foods}), 0)
	s.check("food slot 0 is the nearest (coffee): present, dx, dy, weight one-hot, hot", fed[FOOD0] == 1.0 and _near(fed[FOOD0 + 1], 0.125) and _near(fed[FOOD0 + 2], 0.035) and fed[FOOD0 + 3 + FoodCatalog.get_weight_class("coffee")] == 1.0 and fed[FOOD0 + 6] == 1.0 and fed[FOOD0 + 7] == 0.0, str(_slice(fed, FOOD0, 8)))
	s.check("food slot 1 is the second nearest (pizza); an off-stage food is ignored", fed[FOOD1] == 1.0 and _near(fed[FOOD1 + 1], 0.5) and fed[FOOD1 + 3 + FoodCatalog.get_weight_class("pizza")] == 1.0 and fed[FOOD1 + 6] == 0.0 and fed[FOOD1 + 7] == 0.0, str(_slice(fed, FOOD1, 8)))
	var hard_food := BvsSchemaV3.build_obs(_snapshot(_fighter(), _fighter(), {"foods": [{"name": "cheese", "position": Vector2(480.0, 400.0)}]}), 0)
	s.check("a hard food sets the hard flag", hard_food[FOOD0 + 6] == 0.0 and hard_food[FOOD0 + 7] == 1.0)
	s.check("a missing second food is the all-zero sentinel", _slice(hard_food, FOOD1, 8) == _zeros(8) and hard_food[FOOD0] == 1.0)
	s.check("no food on stage: both slots are sentinels and the length is unchanged", _slice(obs, FOOD0, 16) == _zeros(16) and obs.size() == 136)

	# Projectiles: nearest first, with the shooter flag from my point of view.
	var shots := [
		{"position": Vector2(730.0, 386.0), "velocity": Vector2(-600.0, 0.0), "shooter": 2},
		{"position": Vector2(480.0, 336.0), "velocity": Vector2(300.0, -130.0), "shooter": 1},
	]
	var shot_snapshot := _snapshot(_fighter(), _fighter({"position": Vector2(730.0, 386.0)}), {"projectiles": shots})
	var shot_p1 := BvsSchemaV3.build_obs(shot_snapshot, 0)
	var shot_p2 := BvsSchemaV3.build_obs(shot_snapshot, 1)
	s.check("projectile slot 0 is the nearest with scaled velocity", shot_p1[PROJ0] == 1.0 and _near(shot_p1[PROJ0 + 1], 0.125) and _near(shot_p1[PROJ0 + 2], -0.125) and _near(shot_p1[PROJ0 + 3], 0.5) and _near(shot_p1[PROJ0 + 4], -0.1), str(_slice(shot_p1, PROJ0, 6)))
	s.check("the mine flag is 1 for my own shot (P1 sees shooter 1 as mine)", shot_p1[PROJ0 + 5] == 1.0 and shot_p1[PROJ1 + 5] == 0.0)
	s.check("player 2 sees its own shot as mine and player 1's as not", shot_p2[PROJ0 + 5] == 1.0 and _near(shot_p2[PROJ0 + 1], 0.0) and shot_p2[PROJ1 + 5] == 0.0)
	s.check("no projectile: both slots are sentinels", _slice(obs, PROJ0, 12) == _zeros(12))

	# Read-only: the same snapshot builds the same vector and is not touched.
	var snapshot := _snapshot(f1, f2, {"foods": foods, "projectiles": shots, "bombs": [_bomb(500.0, 100.0)]})
	var before := snapshot.hash()
	var first := BvsSchemaV3.build_obs(snapshot, 0)
	var second := BvsSchemaV3.build_obs(snapshot, 0)
	s.check("building twice gives equal vectors and leaves the snapshot untouched", first == second and snapshot.hash() == before)

	# Missing keys are reported by name, never replaced with zeros.
	var missing_timer := _snapshot(f1, f2)
	missing_timer.erase("timer_left")
	s.check("a missing Game key is reported by name", BvsSchemaV3.validate_snapshot(missing_timer, 0).contains("timer_left"), BvsSchemaV3.validate_snapshot(missing_timer, 0))
	for key in ["bombs", "sudden_death_phase", "sudden_death_elapsed"]:
		var missing_game_key := _snapshot(f1, f2)
		missing_game_key.erase(key)
		s.check("a snapshot lacking '%s' is reported by name" % key, BvsSchemaV3.validate_snapshot(missing_game_key, 0).contains(key), BvsSchemaV3.validate_snapshot(missing_game_key, 0))
	var missing_edge := _snapshot(f1, f2)
	missing_edge["stage"] = {"right": 830.0, "top": 480.0}
	s.check("a missing stage edge is reported by name", BvsSchemaV3.validate_snapshot(missing_edge, 0).contains("stage.left"))
	for key in ["shield", "shield_max", "dizzy", "dizzy_left", "air_dodge_available", "intangible", "jumps_left"]:
		var broken_fighter := _fighter()
		broken_fighter.erase(key)
		var report := BvsSchemaV3.validate_snapshot(_snapshot(f1, broken_fighter), 0)
		s.check("a fighter lacking '%s' names the fighter and the key" % key, report.contains(key) and report.contains("fighters[1]"), report)
	s.check("a bomb entry without a velocity is reported", BvsSchemaV3.validate_snapshot(_snapshot(f1, f2, {"bombs": [{"position": Vector2.ZERO}]}), 0).contains("bombs"))
	s.check("a complete snapshot validates clean", BvsSchemaV3.validate_snapshot(_snapshot(f1, f2), 0) == "" and BvsSchemaV3.validate_snapshot(_snapshot(f1, f2), 1) == "")
	var fallback := BvsSchemaV3.build_obs(missing_timer, 0)
	s.check("build_obs on a broken snapshot reports and returns a neutral vector of the right length", fallback.size() == 136 and fallback.count(0.0) == 136)
	var no_shield := _fighter()
	no_shield.erase("shield")
	s.check("a v2-shaped snapshot (no shield key) is not accepted by schema 3", BvsSchemaV3.build_obs(_snapshot(no_shield, _fighter()), 0).count(0.0) == 136)

	# Action space and logits.
	var space := BvsSchemaV3.action_space()
	var names: Array = space.keys()
	var sizes: Array = []
	for key in names:
		sizes.append(space[key]["size"])
	s.check("action space: eight discrete branches a0_move..a7_dash sized 3,3,2,5,2,2,2,2", names == ["a0_move", "a1_vertical", "a2_jump", "a3_attack", "a4_special", "a5_throw", "a6_block", "a7_dash"] and sizes == [3, 3, 2, 5, 2, 2, 2, 2] and space["a3_attack"]["action_type"] == "discrete")
	s.check("the v3 action layout equals the v2 layout", BvsSchemaV3.action_space() == BvsSchemaV2.action_space() and BvsSchemaV3.BRANCHES == BvsSchemaV2.BRANCHES)
	var logits := PackedFloat32Array()
	logits.resize(21)
	logits.fill(0.0)
	logits[2] = 3.0 # a0_move: right
	logits[4] = 1.0 # a1_vertical: up
	logits[7] = 2.0 # a2_jump: hold
	logits[12] = 9.0 # a3_attack: offset 8, index 4 (side)
	s.check("argmax per branch over 21 logits, ties go to the lowest index", BvsSchemaV3.argmax_branches(logits) == PackedInt32Array([2, 1, 1, 4, 0, 0, 0, 0]), str(BvsSchemaV3.argmax_branches(logits)))
	s.check("action_from_dict reads ints, floats and one-element arrays in branch order", BvsSchemaV3.action_from_dict({"a0_move": 2, "a1_vertical": 1.0, "a2_jump": [1], "a3_attack": 4, "a4_special": 0, "a5_throw": 1, "a6_block": 0, "a7_dash": 1}) == PackedInt32Array([2, 1, 1, 4, 0, 1, 0, 1]))
	var template := BvsSchemaV3.sidecar_template()
	s.check("sidecar template carries the schema contract", template["schema_version"] == 3 and template["obs_dim"] == 136 and template["action_repeat"] == 4 and template["action_branches"].size() == 8 and template["format"] == "bvs-model/1")

# ------------------------------------------------ bombs and sudden-death slots

func _check_bombs_and_sudden_death(s: RefCounted) -> void:
	var me := _fighter({"position": Vector2(330.0, 386.0)})
	var foe := _fighter({"position": Vector2(530.0, 386.0), "facing": -1})
	var quiet := BvsSchemaV3.build_obs(_snapshot(me, foe), 0)
	s.check("no bombs and no sudden death: both bomb slots are the zero sentinel", _slice(quiet, BOMB0, 12) == _zeros(12))
	s.check("no sudden death: flag, phase and elapsed slots are 0", quiet[SUDDEN] == 0.0 and quiet[SD_PHASE] == 0.0 and quiet[SD_ELAPSED] == 0.0)

	var grace := BvsSchemaV3.build_obs(_snapshot(me, foe, {"sudden_death": true, "sudden_death_phase": 1, "sudden_death_elapsed": 15.0}), 0)
	var falling := BvsSchemaV3.build_obs(_snapshot(me, foe, {"sudden_death": true, "sudden_death_phase": 2, "sudden_death_elapsed": 60.0}), 0)
	s.check("sudden death phase is 0.5 during grace and 1 once bombs fall", grace[SUDDEN] == 1.0 and _near(grace[SD_PHASE], 0.5) and _near(falling[SD_PHASE], 1.0))
	s.check("sudden death elapsed is seconds / 60 clipped to 1", _near(grace[SD_ELAPSED], 0.25) and falling[SD_ELAPSED] == 1.0)
	s.check("grace has no bomb in the slots (length unchanged)", _slice(grace, BOMB0, 12) == _zeros(12) and grace.size() == 136)

	# One bomb: self-relative position, velocity and time to impact.
	var one := BvsSchemaV3.build_obs(_snapshot(me, foe, {"sudden_death": true, "sudden_death_phase": 2, "bombs": [_bomb(430.0, 180.0)]}), 0)
	s.check("one bomb fills slot 0 only", one[BOMB0] == 1.0 and one[BOMB1] == 0.0 and _slice(one, BOMB1, 6) == _zeros(6))
	s.check("bomb dx, dy are self-relative over the half width", _near(one[BOMB0 + 1], 0.25) and _near(one[BOMB0 + 2], -0.515), "dx=%.4f dy=%.4f" % [one[BOMB0 + 1], one[BOMB0 + 2]])
	s.check("bomb velocity is scaled like a projectile's", _near(one[BOMB0 + 3], 0.0) and _near(one[BOMB0 + 4], 420.0 / 1300.0))
	s.check("time to impact is seconds to the tabletop / 2 (300 px at 420 px/s)", _near(one[BOMB0 + 5], (300.0 / 420.0) / 2.0), "impact=%.4f" % one[BOMB0 + 5])
	var rising := BvsSchemaV3.build_obs(_snapshot(me, foe, {"bombs": [_bomb(430.0, 180.0, -420.0)]}), 0)
	var below := BvsSchemaV3.build_obs(_snapshot(me, foe, {"bombs": [_bomb(430.0, 700.0)]}), 0)
	var far := BvsSchemaV3.build_obs(_snapshot(me, foe, {"bombs": [_bomb(430.0, -2000.0)]}), 0)
	s.check("a bomb that is not descending or is below the tabletop encodes impact 1", rising[BOMB0 + 5] == 1.0 and below[BOMB0 + 5] == 1.0)
	s.check("a very high bomb clips its impact time to 1", far[BOMB0 + 5] == 1.0)
	var landing := BvsSchemaV3.build_obs(_snapshot(me, foe, {"bombs": [_bomb(430.0, 480.0)]}), 0)
	s.check("a bomb at the tabletop is below it (impact 1)", landing[BOMB0 + 5] == 1.0)

	# Three bombs at different distances: the two nearest, nearest first.
	var bombs := [_bomb(800.0, 50.0), _bomb(340.0, 200.0), _bomb(500.0, 380.0)]
	var many := BvsSchemaV3.build_obs(_snapshot(me, foe, {"bombs": bombs}), 0)
	# From (330, 386): (500, 380) is 170 away, (340, 200) is 186, (800, 50) is 578.
	s.check("slot 0 holds the nearest bomb and slot 1 the second nearest", many[BOMB0] == 1.0 and _near(many[BOMB0 + 1], (500.0 - 330.0) / 400.0) and many[BOMB1] == 1.0 and _near(many[BOMB1 + 1], (340.0 - 330.0) / 400.0), "%s | %s" % [str(_slice(many, BOMB0, 6)), str(_slice(many, BOMB1, 6))])
	var swapped := BvsSchemaV3.build_obs(_snapshot(me, foe, {"bombs": [bombs[2], bombs[0], bombs[1]]}), 0)
	s.check("the order of the bombs in the snapshot does not matter", swapped == many)
	var other_view := BvsSchemaV3.build_obs(_snapshot(me, foe, {"bombs": bombs}), 1)
	s.check("the other fighter sees the same bombs relative to itself", _near(other_view[BOMB0 + 1], (500.0 - 530.0) / 400.0) and other_view[BOMB0] == 1.0)

	# Many bombs: still two slots, still bounded, fixed length.
	var swarm: Array = []
	for i in 40:
		swarm.append(_bomb(430.0 + i * 25.0, -3.0e5 + i * 1.0e4, 1.0e9))
	swarm.append(_bomb(NAN, INF))
	var crowded := BvsSchemaV3.build_obs(_snapshot(me, foe, {"sudden_death": true, "sudden_death_phase": 2, "bombs": swarm}), 0)
	s.check("41 bombs keep the length and stay finite and bounded", crowded.size() == 136 and _all_finite_and_bounded(crowded))

# ------------------------------------------------------------------ registry

func _check_registry(s: RefCounted) -> void:
	s.check("the registry holds version 2 and version 3 with their own modules", BvsSchema.get_schema(2) == BvsSchemaV2 and BvsSchema.get_schema(3) == BvsSchemaV3)
	s.check("each registered version has its own obs_dim", BvsSchema.get_schema(2).OBS_DIM == 102 and BvsSchema.get_schema(3).OBS_DIM == 136)
	s.check("an unregistered version is unsupported, not a default layout", BvsSchema.get_schema(99) == null and BvsSchema.new_decoder(99) == null and BvsSchema.get_schema(1) == null)
	s.check("decoders come from the registry by version", BvsSchema.new_decoder(2) is BvsActionDecoderV2 and BvsSchema.new_decoder(3) is BvsActionDecoderV3)
	s.check("two requests give two independent decoders", BvsSchema.new_decoder(3) != BvsSchema.new_decoder(3))
	s.check("2 and 3 are built in", BvsSchema.is_builtin(2) and BvsSchema.is_builtin(3) and not BvsSchema.is_builtin(4) and not BvsSchema.is_builtin(99))
	s.check("current() is the registered module of CURRENT_VERSION", BvsSchema.current() == BvsSchema.get_schema(BvsSchema.CURRENT_VERSION))

	var template := BvsSchemaV3.sidecar_template()
	s.check("the v3 sidecar template validates against schema 3", BvsSchema.validate_sidecar_for(template, 3) == "", BvsSchema.validate_sidecar_for(template, 3))
	s.check("the v3 template is not valid for schema 2 and names the mismatch", BvsSchema.validate_sidecar_for(template, 2).contains("schema"), BvsSchema.validate_sidecar_for(template, 2))
	var v2_template := BvsSchemaV2.sidecar_template()
	s.check("the v2 template validates against schema 2 and not against schema 3", BvsSchema.validate_sidecar_for(v2_template, 2) == "" and BvsSchema.validate_sidecar_for(v2_template, 3) != "")
	var lying := template.duplicate(true)
	lying["obs_dim"] = 102
	s.check("a schema-3 sidecar with 102 inputs says what the model expects and what the game provides", BvsSchema.validate_sidecar_for(lying, 3).contains("expects 102 inputs") and BvsSchema.validate_sidecar_for(lying, 3).contains("provides 136"), BvsSchema.validate_sidecar_for(lying, 3))
	var resized := template.duplicate(true)
	resized["action_branches"][3]["size"] = 4
	s.check("a wrong branch size is rejected for schema 3", BvsSchema.validate_sidecar_for(resized, 3).contains("a3_attack"))
	var repeated := template.duplicate(true)
	repeated["action_repeat"] = 2
	s.check("a wrong action_repeat is rejected for schema 3", BvsSchema.validate_sidecar_for(repeated, 3).contains("action_repeat"))
	s.check("validating against an unregistered version is an error", BvsSchema.validate_sidecar_for(template, 99).to_lower().contains("unsupported"))
	var future := template.duplicate(true)
	future["schema_version"] = 99
	s.check("a sidecar for version 99 reports unsupported", BvsSchema.validate_sidecar(future).to_lower().contains("unsupported"), BvsSchema.validate_sidecar(future))
	var current_template: Dictionary = BvsSchema.current().sidecar_template()
	s.check("the current schema's template is a valid sidecar", BvsSchema.validate_sidecar(current_template) == "", BvsSchema.validate_sidecar(current_template))
	var other := BvsSchema.CURRENT_VERSION == 2
	var other_template: Dictionary = (BvsSchemaV3 if other else BvsSchemaV2).sidecar_template()
	s.check("a registered but not playable version says which schema the game uses", BvsSchema.validate_sidecar(other_template).contains("this game uses schema %d" % BvsSchema.CURRENT_VERSION), BvsSchema.validate_sidecar(other_template))

	# A test-only schema 4 leaves 2 and 3 untouched; built-in versions cannot be removed.
	var snapshot_2 := {"foods": [{"name": "pizza", "position": Vector2(480.0, 400.0)}]}
	var obs_before_2 := BvsSchemaV2.build_obs(_v2_snapshot(snapshot_2), 0)
	var obs_before_3 := BvsSchemaV3.build_obs(_snapshot(_fighter(), _fighter({"position": Vector2(630.0, 386.0)}), snapshot_2), 0)
	BvsSchema.register_test_stub(4, StubSchemaV4)
	var obs_with_2 := BvsSchemaV2.build_obs(_v2_snapshot(snapshot_2), 0)
	var obs_with_3 := BvsSchemaV3.build_obs(_snapshot(_fighter(), _fighter({"position": Vector2(630.0, 386.0)}), snapshot_2), 0)
	s.check("a stub registered as version 4 is found by the registry", BvsSchema.get_schema(4) == StubSchemaV4 and BvsSchema.new_decoder(4) == null)
	s.check("schema 2 and schema 3 results are identical with the stub registered", obs_with_2 == obs_before_2 and obs_with_3 == obs_before_3 and BvsSchema.get_schema(2) == BvsSchemaV2 and BvsSchema.get_schema(3) == BvsSchemaV3)
	BvsSchema.unregister_test_stub(4)
	s.check("the stub is gone again after the test", BvsSchema.get_schema(4) == null)
	BvsSchema.unregister_test_stub(2)
	BvsSchema.unregister_test_stub(3)
	s.check("unregistering a built-in version is refused", BvsSchema.get_schema(2) == BvsSchemaV2 and BvsSchema.get_schema(3) == BvsSchemaV3)
	BvsSchema.register_test_stub(3, StubSchemaV4)
	s.check("registering a stub over a built-in version is refused", BvsSchema.get_schema(3) == BvsSchemaV3)

## A snapshot that carries the keys of both schemas (schema 2 ignores the new ones),
## for the "a stub leaves versions 2 and 3 alone" check.
func _v2_snapshot(over: Dictionary) -> Dictionary:
	return _snapshot(_fighter(), _fighter({"position": Vector2(630.0, 386.0)}), over)

# ----------------------------------------------------------------- real game

func _check_real_game(s: RefCounted) -> void:
	var game: Node2D = s.spawn_game()
	await s.frames(30)
	var snapshot: Dictionary = game.get_state_snapshot()
	s.check("a real Game snapshot carries every key schema 3 reads", BvsSchemaV3.validate_snapshot(snapshot, 0) == "" and BvsSchemaV3.validate_snapshot(snapshot, 1) == "", BvsSchemaV3.validate_snapshot(snapshot, 0))
	var at_origin := BvsSchemaV3.build_obs(snapshot, 0)
	var origin_stage: Dictionary = snapshot["stage"].duplicate()
	game.global_position += Vector2(3000.0, 2000.0)
	var moved_snapshot: Dictionary = game.get_state_snapshot()
	var moved := BvsSchemaV3.build_obs(moved_snapshot, 0)
	s.check("the stage edges do not change with the global offset", moved_snapshot["stage"] == origin_stage)
	s.check("observations are identical at a different global offset", moved == at_origin)
	s.check("a real fighter observation is finite, bounded and 136 long", moved.size() == 136 and _all_finite_and_bounded(moved))
	s.check("a fresh fighter shows a full shield, an air dodge and no dizzy", moved[SHIELD] == 1.0 and moved[AIR_DODGE] == 1.0 and moved[DIZZY] == 0.0 and moved[OPP + SHIELD] == 1.0)
	var fighter: Fighter = game.get_node("Fighter1")
	fighter.shield.set_ratio(0.5)
	var half := BvsSchemaV3.build_obs(game.get_state_snapshot(), 0)
	s.check("the real shield meter feeds the shield slot (half meter is about 0.5)", _near(half[SHIELD], 0.5, 1e-3), "shield=%.3f" % half[SHIELD])
	var read_once := BvsSchemaV3.build_obs(game.get_state_snapshot(), 0)
	var read_twice := BvsSchemaV3.build_obs(game.get_state_snapshot(), 0)
	s.check("two reads with no frame in between agree", read_once == read_twice)
	await s.despawn(game)

	# Two Games at different global offsets, both in sudden death with one bomb at
	# the same Game-local spot: identical observations, with the bomb in slot 0.
	var views: Array[PackedFloat32Array] = []
	var games: Array[Game] = []
	for offset in [Vector2.ZERO, Vector2(5000.0, 900.0)]:
		var duel: Game = s.spawn_game(330.0, 700.0)
		duel.position = offset
		duel.food_spawner.stop()
		duel.sudden_death_intro = 0.0
		duel.hazards.grace_time = 600.0
		games.append(duel)
	await s.frames(60)
	for duel in games:
		duel.force_sudden_death()
	await s.frames(2)
	# Both bombs appear on the same frame, so neither has moved when it is read.
	for duel in games:
		duel.hazards.spawn_bomb(500.0, 100.0)
	var live_a := games[0].get_state_snapshot()
	var live_b := games[1].get_state_snapshot()
	views.append(BvsSchemaV3.build_obs(live_a, 0))
	views.append(BvsSchemaV3.build_obs(live_b, 0))
	s.check("a real bomb fills the first bomb slot", views[0][BOMB0] == 1.0 and views[0][BOMB1] == 0.0 and views[0][BOMB0 + 4] > 0.0, str(_slice(views[0], BOMB0, 6)))
	s.check("sudden death sets the flag and the grace phase (0.5)", views[0][SUDDEN] == 1.0 and _near(views[0][SD_PHASE], 0.5), "flag=%.1f phase=%.2f" % [views[0][SUDDEN], views[0][SD_PHASE]])
	s.check("two Games at different offsets give equal vectors (bomb included)", views[0] == views[1] and views[0].size() == 136 and _all_finite_and_bounded(views[0]))
	s.check("the opponent view of the same bomb is not the same vector (self-relative)", BvsSchemaV3.build_obs(live_a, 1) != views[0])
	for duel in games:
		await s.despawn(duel)

# ------------------------------------------------- training == inference

func _check_training_equals_inference(s: RefCounted) -> void:
	var sidecar_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SIDECAR_PATH))
	s.check("the v3 random fixture sidecar validates for schema 3", sidecar_data is Dictionary and BvsSchema.validate_sidecar_for(sidecar_data, 3) == "")
	var loaded := OnnxPolicyModel.load_bytes(FileAccess.get_file_as_bytes(MODEL_PATH), sidecar_data if sidecar_data is Dictionary else {})
	var model: OnnxPolicyModel = loaded.model
	s.check("the v3 random fixture loads and fits schema 3 (136 inputs, 21 logits)", model != null and model.validate(BvsSchemaV3) == "", str(loaded.error))
	if model == null:
		return
	s.check("the model reports its schema version from the sidecar", model.schema_version() == 3)
	s.check("a model with no sidecar version defaults to the current schema", OnnxPolicyModel.new().schema_version() == BvsSchema.CURRENT_VERSION)

	var game: Node2D = s.spawn_game()
	await s.frames(3)
	for side in 2:
		var fighter: Fighter = game.get_node("Fighter%d" % (side + 1))
		fighter.position += Vector2(37.0, -12.0 * side)
		fighter.damage_percent = 41.0
		fighter.shield.set_ratio(0.4)
		var controller := PolicyController.new(model)
		fighter.set_controller(controller)
		# The fighters are frozen for the comparison: no physics frame runs between
		# the two observations, only these direct calls.
		for call_index in side + 1:
			controller.sample(0.0)
		var ai := fighter.ai_controller_2d as PlayerAIController
		ai.schema_version = 3
		var training_obs: Array = ai.get_obs()["obs"]
		var same := controller.last_obs.size() == 136 and training_obs.size() == 136
		for i in controller.last_obs.size():
			same = same and is_equal_approx(controller.last_obs[i], float(training_obs[i]))
		s.check("fighter %d: the play observation equals the training observation (136 values)" % (side + 1), same, controller.error)
		s.check("fighter %d: the model decides through the v3 decoder (21-logit decision)" % (side + 1), controller.error == "" and controller.last_action.size() == 8 and controller._decoder is BvsActionDecoderV3)
		s.check("fighter %d: the training agent builds the v3 action space" % (side + 1), ai.get_action_space() == BvsSchemaV3.action_space())
	var unplayable := PolicyController.new(model)
	model.sidecar = {"schema_version": 99}
	(game.get_node("Fighter1") as Fighter).set_controller(unplayable)
	unplayable.sample(0.0)
	s.check("a model of an unregistered schema fails once with a message and stays neutral", unplayable.error.contains("not registered") and unplayable.sample(0.0).move_x == 0.0, unplayable.error)
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
func _window(decoder: BvsActionDecoderV3, fighter: Fighter, actions: PackedInt32Array) -> Array[FighterIntent]:
	var err := decoder.begin_window(actions)
	var frames: Array[FighterIntent] = []
	if err != "":
		frames.append(decoder.frame(fighter))
		return frames
	for i in BvsSchemaV3.ACTION_REPEAT:
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

	var decoder := BvsActionDecoderV3.new()
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
	s.check("vertical down is a held DOWN aim on every tick and up a held UP aim", down[0].aim == FighterIntent.Aim.DOWN and down[3].aim == FighterIntent.Aim.DOWN and up[0].aim == FighterIntent.Aim.UP and up[3].aim == FighterIntent.Aim.UP and none[0].aim == FighterIntent.Aim.NEUTRAL)

	# Attack: pressed once on the first tick, aim from the branch (no food in hand).
	var attack_aims := {}
	for value in [1, 2, 3, 4]:
		var window := _window(decoder, fighter, _acts(1, 0, 0, value))
		attack_aims[value] = window[0].aim
		s.check("attack %d presses once on the first tick only" % value, window[0].attack_pressed and _count(window, "attack_pressed") == 1)
	s.check("attack 1..4 maps to aim neutral, up, down, side", attack_aims == {1: FighterIntent.Aim.NEUTRAL, 2: FighterIntent.Aim.UP, 3: FighterIntent.Aim.DOWN, 4: FighterIntent.Aim.SIDE}, str(attack_aims))
	s.check("attack none never presses", _count(_window(decoder, fighter, _acts(1, 0, 0, 0)), "attack_pressed") == 0)

	# Special overrides attack and forces aim UP on its tick.
	var special := _window(decoder, fighter, _acts(1, 0, 0, 2, 1))
	s.check("special presses once with aim UP and overrides the attack branch", special[0].special_pressed and special[0].aim == FighterIntent.Aim.UP and _count(special, "special_pressed") == 1 and _count(special, "attack_pressed") == 0)

	# Throw and dash pulse once.
	var throw := _window(decoder, fighter, _acts(1, 0, 0, 0, 0, 1))
	var dash := _window(decoder, fighter, _acts(1, 0, 0, 0, 0, 0, 0, 1))
	s.check("throw presses on the first tick only", throw[0].throw_pressed and _count(throw, "throw_pressed") == 1)
	s.check("dash presses on the first tick only", dash[0].dash_pressed and _count(dash, "dash_pressed") == 1)

	# Exclusive throw: with food in hand a throw decision suppresses the same-window attack.
	var empty_both := _window(decoder, fighter, _acts(1, 0, 0, 1, 0, 1))
	s.check("no food held: throw and attack both press, exactly as in v2", empty_both[0].throw_pressed and empty_both[0].attack_pressed and _count(empty_both, "throw_pressed") == 1 and _count(empty_both, "attack_pressed") == 1)
	fighter.held_food = "pizza"
	var exclusive := _window(decoder, fighter, _acts(1, 0, 0, 1, 0, 1))
	s.check("holding food: throw presses and attack does not", exclusive[0].throw_pressed and not exclusive[0].attack_pressed and _count(exclusive, "attack_pressed") == 0)
	s.check("the throw pulse fires on exactly one of the four ticks", _count(exclusive, "throw_pressed") == 1 and exclusive.size() == 4)
	s.check("the suppressed attack leaves the aim neutral", exclusive[0].aim == FighterIntent.Aim.NEUTRAL)
	var kept := _window(decoder, fighter, _acts(1, 0, 0, 4, 0, 0))
	s.check("holding food with no throw decision keeps the attack", kept[0].attack_pressed and kept[0].aim == FighterIntent.Aim.SIDE and _count(kept, "throw_pressed") == 0)
	var vertical_throw := _window(decoder, fighter, _acts(1, 2, 0, 2, 0, 1))
	s.check("the held vertical aim still applies to an exclusive throw", vertical_throw[0].throw_pressed and not vertical_throw[0].attack_pressed and vertical_throw[0].aim == FighterIntent.Aim.DOWN)
	var special_throw := _window(decoder, fighter, _acts(1, 0, 0, 1, 1, 1))
	s.check("special is untouched by the exclusive throw", special_throw[0].special_pressed and special_throw[0].throw_pressed)
	fighter.held_food = ""
	var after := _window(decoder, fighter, _acts(1, 0, 0, 1, 0, 1))
	s.check("after the food is gone both press again", after[0].throw_pressed and after[0].attack_pressed)
	var no_fighter := BvsActionDecoderV3.new()
	no_fighter.begin_window(_acts(1, 0, 0, 1, 0, 1))
	var detached := no_fighter.frame(null)
	s.check("with no fighter to ask the throw decodes as in v2", detached.throw_pressed and detached.attack_pressed)

	# Block: held for the window, pressed only on a rising edge.
	var block_1 := _window(decoder, fighter, _acts(1, 0, 0, 0, 0, 0, 1))
	var block_2 := _window(decoder, fighter, _acts(1, 0, 0, 0, 0, 0, 1))
	var block_off := _window(decoder, fighter, _acts(1, 0, 0, 0, 0, 0, 0))
	var block_3 := _window(decoder, fighter, _acts(1, 0, 0, 0, 0, 0, 1))
	s.check("block is held for the whole window", _count(block_1, "block_held") == 4 and _count(block_off, "block_held") == 0)
	s.check("block presses on the rising edge only (the game turns it into an air dodge in the air)", _count(block_1, "block_pressed") == 1 and _count(block_2, "block_pressed") == 0 and _count(block_3, "block_pressed") == 1)

	# Jump guard, on the floor and in the air.
	var jump_floor_1 := _window(decoder, fighter, _acts(1, 0, 1))
	var jump_floor_2 := _window(decoder, fighter, _acts(1, 0, 1))
	s.check("jump hold keeps jump_held on all ticks; on the floor it presses every window", _count(jump_floor_1, "jump_held") == 4 and jump_floor_1[0].jump_pressed and jump_floor_2[0].jump_pressed and _count(jump_floor_2, "jump_pressed") == 1)
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
	var bad_throw := decoder.begin_window(_acts(1, 0, 0, 0, 0, 2))
	s.check("a throw index equal to the branch size is rejected", bad_throw != "" and _neutral(decoder.frame(fighter)), bad_throw)
	var recovered := _window(decoder, fighter, _acts(2))
	s.check("a valid window after a rejected one works again", recovered[0].move_x == 1.0)
	await s.despawn(game)
