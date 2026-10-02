class_name BvsSchemaV2
extends RefCounted

## bvs-schema-2: the observation vector, the action layout and the decode rules
## shared by training (PlayerAIController through Sync) and play (PolicyController).
## FROZEN: published models depend on every index and constant in this file. A
## change belongs in a new bvs_schema_v3.gd plus a BvsSchema registry entry, never
## here. tests/fixtures/schema/v2_layout.json and v2_obs_golden.json guard it.
##
## The observation is built only from Game.get_state_snapshot(), which is
## Game-local, so offset rows (train.tscn) look the same as the real match. The
## order is "me first, opponent second" from the observing fighter's point of view.
## Every value is a float32, clipped to [-5, 5] (or to a narrower documented
## range) and finite.
##
## Normalization (frozen, not read from FighterProfile): stage center cx and half
## width HW come from the snapshot's stage edges; x_n = (x - cx) / HW and
## y_n = (y - stage.top) / HW (positive below the tabletop); velocities are
## vx / 600 (dash speed) and vy / 1300 (fast-fall speed).
##
## Layout (102 floats):
##   [0, 35)    me:       pos x/y, vel x/y, facing, on_floor, damage/100 [0,5], stocks/3,
##                        holding food, held weight one-hot (light, medium, heavy),
##                        punch cooldown [0,1], shoot cooldown/2 [0,1], jumps_left/2,
##                        air dash, recovery available, invulnerable, ledge side,
##                        fast falling, charge, state one-hot (14: STATES + other)
##   [35, 70)   opponent: the same 35 features
##   70, 71     opponent position relative to me (dx, dy over HW)
##   72         opponent in front: sign(dx) * my facing (0 when dx == 0)
##   73         me off stage (airborne and past an edge or below the top)
##   74, 75     ledge occupied (left, right)
##   [76, 88)   2 nearest foods on the stage: present, dx, dy, weight one-hot (3)
##   [88, 100)  2 nearest projectiles: present, dx, dy, vx, vy, mine
##   100        timer left / 99, clipped to [0, 1]
##   101        sudden death
## An absent food or projectile is all zeros (present = 0).
##
## Action: MultiDiscrete [3,3,2,5,2,2,2,2] (21 logits), decoded by
## BvsActionDecoderV2, held for ACTION_REPEAT physics frames.

const VERSION := 2
const OBS_DIM := 102
const ACTION_REPEAT := 4
const LOGITS := 21
const FORMAT := "bvs-model/1"

const BRANCHES: Array[Dictionary] = [
	{"name": "a0_move", "size": 3},
	{"name": "a1_vertical", "size": 3},
	{"name": "a2_jump", "size": 2},
	{"name": "a3_attack", "size": 5},
	{"name": "a4_special", "size": 2},
	{"name": "a5_throw", "size": 2},
	{"name": "a6_block", "size": 2},
	{"name": "a7_dash", "size": 2},
]

## Normalization and layout constants.
const CLIP := 5.0
const VEL_X_SCALE := 600.0
const VEL_Y_SCALE := 1300.0
const DAMAGE_SCALE := 100.0
const STOCK_SCALE := 3.0
const SHOOT_COOLDOWN_SCALE := 2.0
const JUMP_SCALE := 2.0
const TIMER_SCALE := 99.0
## Distance from a fighter's origin to its feet (the same value ScriptedController reads).
const FEET_OFFSET := 94.0
const OFF_STAGE_SLACK := 2.0
const FIGHTER_BLOCK := 35
const OPPONENT_OFFSET := 35
const SHARED_OFFSET := 70
const FOOD_OFFSET := 76
const FOOD_SLOTS := 2
const FOOD_STRIDE := 6
const PROJECTILE_OFFSET := 88
const PROJECTILE_SLOTS := 2
const PROJECTILE_STRIDE := 6
const TIMER_OFFSET := 100
const SUDDEN_DEATH_OFFSET := 101

## FSM state names in one-hot order; any other state lands in the 14th slot.
const STATES: PackedStringArray = ["Idle", "Run", "Jump", "Fall", "Punch", "Hurt", "Protect", "Shoot", "Dash", "Helpless", "LedgeHang", "Recovery", "Defeated"]

## Snapshot keys this schema reads. validate_snapshot reports the first one missing.
const GAME_KEYS: PackedStringArray = ["timer_left", "sudden_death", "stage", "ledges", "foods", "projectiles", "fighters"]
const STAGE_KEYS: PackedStringArray = ["left", "right", "top"]
const FIGHTER_KEYS: PackedStringArray = [
	"position", "velocity", "facing", "on_floor", "damage_percent", "stocks", "held_food", "state",
	"cooldowns", "jumps_left", "air_dash_available", "recovery_available", "is_invulnerable",
	"ledge_side", "fast_falling", "charge_level",
]
const COOLDOWN_KEYS: PackedStringArray = ["punch", "shoot"]

## Names of the 102 observation fields, in order (frozen by v2_layout.json).
const FIELD_NAMES: PackedStringArray = [
	"self_pos_x", "self_pos_y", "self_vel_x", "self_vel_y", "self_facing", "self_on_floor", "self_damage",
	"self_stocks", "self_holding_food", "self_food_light", "self_food_medium", "self_food_heavy", "self_cd_punch", "self_cd_shoot",
	"self_jumps_left", "self_air_dash", "self_recovery", "self_invulnerable", "self_ledge_side", "self_fast_falling", "self_charge",
	"self_st_idle", "self_st_run", "self_st_jump", "self_st_fall", "self_st_punch", "self_st_hurt", "self_st_protect",
	"self_st_shoot", "self_st_dash", "self_st_helpless", "self_st_ledge_hang", "self_st_recovery", "self_st_defeated", "self_st_other",
	"opp_pos_x", "opp_pos_y", "opp_vel_x", "opp_vel_y", "opp_facing", "opp_on_floor", "opp_damage",
	"opp_stocks", "opp_holding_food", "opp_food_light", "opp_food_medium", "opp_food_heavy", "opp_cd_punch", "opp_cd_shoot",
	"opp_jumps_left", "opp_air_dash", "opp_recovery", "opp_invulnerable", "opp_ledge_side", "opp_fast_falling", "opp_charge",
	"opp_st_idle", "opp_st_run", "opp_st_jump", "opp_st_fall", "opp_st_punch", "opp_st_hurt", "opp_st_protect",
	"opp_st_shoot", "opp_st_dash", "opp_st_helpless", "opp_st_ledge_hang", "opp_st_recovery", "opp_st_defeated", "opp_st_other",
	"rel_x", "rel_y", "opp_in_front", "self_off_stage", "ledge_left_occupied", "ledge_right_occupied",
	"food0_present", "food0_dx", "food0_dy", "food0_light", "food0_medium", "food0_heavy",
	"food1_present", "food1_dx", "food1_dy", "food1_light", "food1_medium", "food1_heavy",
	"proj0_present", "proj0_dx", "proj0_dy", "proj0_vx", "proj0_vy", "proj0_mine",
	"proj1_present", "proj1_dx", "proj1_dy", "proj1_vx", "proj1_vy", "proj1_mine",
	"timer_left", "sudden_death",
]

# ------------------------------------------------------------------ snapshot

## "" when the snapshot has everything schema 2 reads, otherwise the name of the
## first missing key (for example "stage.left" or "fighters[1].jumps_left").
static func validate_snapshot(snapshot: Dictionary, my_index: int) -> String:
	for key in GAME_KEYS:
		if not snapshot.has(key):
			return "snapshot is missing the key '%s'" % key
	var stage: Variant = snapshot["stage"]
	if not (stage is Dictionary):
		return "snapshot key 'stage' is not a dictionary"
	for key in STAGE_KEYS:
		if not stage.has(key):
			return "snapshot is missing the key 'stage.%s'" % key
	if float(stage["right"]) <= float(stage["left"]):
		return "snapshot key 'stage.right' must be greater than 'stage.left'"
	var fighters: Variant = snapshot["fighters"]
	if not (fighters is Array) or fighters.size() < 2:
		return "snapshot key 'fighters' must hold two fighters"
	if my_index < 0 or my_index > 1:
		return "my_index must be 0 or 1, got %d" % my_index
	for index in 2:
		var fighter: Variant = fighters[index]
		if not (fighter is Dictionary):
			return "snapshot key 'fighters[%d]' is not a dictionary" % index
		for key in FIGHTER_KEYS:
			if not fighter.has(key):
				return "snapshot is missing the key 'fighters[%d].%s'" % [index, key]
		for key in COOLDOWN_KEYS:
			if not (fighter["cooldowns"] is Dictionary) or not fighter["cooldowns"].has(key):
				return "snapshot is missing the key 'fighters[%d].cooldowns.%s'" % [index, key]
	for ledge: Variant in snapshot["ledges"]:
		if not (ledge is Dictionary) or not ledge.has("side") or not ledge.has("occupied"):
			return "snapshot key 'ledges' entries need 'side' and 'occupied'"
	for food: Variant in snapshot["foods"]:
		if not (food is Dictionary) or not food.has("name") or not food.has("position"):
			return "snapshot key 'foods' entries need 'name' and 'position'"
	for shot: Variant in snapshot["projectiles"]:
		if not (shot is Dictionary) or not shot.has("position") or not shot.has("velocity") or not shot.has("shooter"):
			return "snapshot key 'projectiles' entries need 'position', 'velocity' and 'shooter'"
	return ""

## The observation of fighter `my_index` (0 or 1) in a Game snapshot. A snapshot
## missing a key reports an error naming it and returns an all-zero vector of the
## right length (no value is ever substituted silently).
static func build_obs(snapshot: Dictionary, my_index: int) -> PackedFloat32Array:
	var obs := PackedFloat32Array()
	obs.resize(OBS_DIM)
	var problem := validate_snapshot(snapshot, my_index)
	if problem != "":
		push_error("BvsSchemaV2: " + problem)
		return obs

	var stage: Dictionary = snapshot["stage"]
	var left := float(stage["left"])
	var right := float(stage["right"])
	var top := float(stage["top"])
	var center := (left + right) * 0.5
	var half_width := (right - left) * 0.5
	var fighters: Array = snapshot["fighters"]
	var me: Dictionary = fighters[my_index]
	var foe: Dictionary = fighters[1 - my_index]
	var my_pos: Vector2 = me["position"]
	var foe_pos: Vector2 = foe["position"]

	_write_fighter(obs, 0, me, center, top, half_width)
	_write_fighter(obs, OPPONENT_OFFSET, foe, center, top, half_width)

	var offset_x := foe_pos.x - my_pos.x
	obs[SHARED_OFFSET] = _clip(offset_x / half_width, -CLIP, CLIP)
	obs[SHARED_OFFSET + 1] = _clip((foe_pos.y - my_pos.y) / half_width, -CLIP, CLIP)
	obs[SHARED_OFFSET + 2] = 0.0 if (is_nan(offset_x) or offset_x == 0.0) else signf(offset_x) * (1.0 if int(me["facing"]) >= 0 else -1.0)
	var airborne := not bool(me["on_floor"])
	obs[SHARED_OFFSET + 3] = 1.0 if airborne and (my_pos.x < left or my_pos.x > right or my_pos.y + FEET_OFFSET > top + OFF_STAGE_SLACK) else 0.0
	for ledge: Dictionary in snapshot["ledges"]:
		if bool(ledge["occupied"]):
			obs[SHARED_OFFSET + 4 + (0 if int(ledge["side"]) < 0 else 1)] = 1.0

	_write_foods(obs, snapshot["foods"], my_pos, left, right, half_width)
	_write_projectiles(obs, snapshot["projectiles"], my_pos, my_index + 1, half_width)
	obs[TIMER_OFFSET] = _clip(float(snapshot["timer_left"]) / TIMER_SCALE, 0.0, 1.0)
	obs[SUDDEN_DEATH_OFFSET] = 1.0 if bool(snapshot["sudden_death"]) else 0.0
	return obs

static func _write_fighter(obs: PackedFloat32Array, base: int, fighter: Dictionary, center: float, top: float, half_width: float) -> void:
	var pos: Vector2 = fighter["position"]
	var vel: Vector2 = fighter["velocity"]
	obs[base] = _clip((pos.x - center) / half_width, -CLIP, CLIP)
	obs[base + 1] = _clip((pos.y - top) / half_width, -CLIP, CLIP)
	obs[base + 2] = _clip(vel.x / VEL_X_SCALE, -CLIP, CLIP)
	obs[base + 3] = _clip(vel.y / VEL_Y_SCALE, -CLIP, CLIP)
	obs[base + 4] = 1.0 if int(fighter["facing"]) >= 0 else -1.0
	obs[base + 5] = 1.0 if bool(fighter["on_floor"]) else 0.0
	obs[base + 6] = _clip(float(fighter["damage_percent"]) / DAMAGE_SCALE, 0.0, CLIP)
	obs[base + 7] = _clip(float(fighter["stocks"]) / STOCK_SCALE, 0.0, 1.0)
	var held := String(fighter["held_food"])
	if held != "":
		obs[base + 8] = 1.0
		obs[base + 9 + FoodCatalog.get_weight_class(held)] = 1.0
	var cooldowns: Dictionary = fighter["cooldowns"]
	obs[base + 12] = _clip(float(cooldowns["punch"]), 0.0, 1.0)
	obs[base + 13] = _clip(float(cooldowns["shoot"]) / SHOOT_COOLDOWN_SCALE, 0.0, 1.0)
	obs[base + 14] = _clip(float(fighter["jumps_left"]) / JUMP_SCALE, 0.0, 1.0)
	obs[base + 15] = 1.0 if bool(fighter["air_dash_available"]) else 0.0
	obs[base + 16] = 1.0 if bool(fighter["recovery_available"]) else 0.0
	obs[base + 17] = 1.0 if bool(fighter["is_invulnerable"]) else 0.0
	obs[base + 18] = _clip(float(fighter["ledge_side"]), -1.0, 1.0)
	obs[base + 19] = 1.0 if bool(fighter["fast_falling"]) else 0.0
	obs[base + 20] = _clip(float(fighter["charge_level"]), 0.0, 1.0)
	var state_slot := STATES.find(String(fighter["state"]))
	obs[base + 21 + (state_slot if state_slot >= 0 else STATES.size())] = 1.0

## The two foods closest to me that lie over the stage, nearest first.
static func _write_foods(obs: PackedFloat32Array, foods: Array, my_pos: Vector2, left: float, right: float, half_width: float) -> void:
	var candidates: Array = []
	for food: Dictionary in foods:
		var pos: Vector2 = food["position"]
		if pos.x < left or pos.x > right:
			continue
		candidates.append({"distance": my_pos.distance_squared_to(pos), "food": food})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	for slot in mini(FOOD_SLOTS, candidates.size()):
		var food: Dictionary = candidates[slot]["food"]
		var pos: Vector2 = food["position"]
		var base := FOOD_OFFSET + slot * FOOD_STRIDE
		obs[base] = 1.0
		obs[base + 1] = _clip((pos.x - my_pos.x) / half_width, -CLIP, CLIP)
		obs[base + 2] = _clip((pos.y - my_pos.y) / half_width, -CLIP, CLIP)
		obs[base + 3 + FoodCatalog.get_weight_class(String(food["name"]))] = 1.0

## The two projectiles closest to me, nearest first; `mine` compares the shooter
## number (1 or 2) with my own.
static func _write_projectiles(obs: PackedFloat32Array, shots: Array, my_pos: Vector2, my_number: int, half_width: float) -> void:
	var candidates: Array = []
	for shot: Dictionary in shots:
		var pos: Vector2 = shot["position"]
		candidates.append({"distance": my_pos.distance_squared_to(pos), "shot": shot})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	for slot in mini(PROJECTILE_SLOTS, candidates.size()):
		var shot: Dictionary = candidates[slot]["shot"]
		var pos: Vector2 = shot["position"]
		var vel: Vector2 = shot["velocity"]
		var base := PROJECTILE_OFFSET + slot * PROJECTILE_STRIDE
		obs[base] = 1.0
		obs[base + 1] = _clip((pos.x - my_pos.x) / half_width, -CLIP, CLIP)
		obs[base + 2] = _clip((pos.y - my_pos.y) / half_width, -CLIP, CLIP)
		obs[base + 3] = _clip(vel.x / VEL_X_SCALE, -CLIP, CLIP)
		obs[base + 4] = _clip(vel.y / VEL_Y_SCALE, -CLIP, CLIP)
		obs[base + 5] = 1.0 if int(shot["shooter"]) == my_number else 0.0

## Clamps into [low, high]; NaN becomes 0 and infinities land on the bounds.
static func _clip(value: float, low: float, high: float) -> float:
	if is_nan(value):
		return 0.0
	return clampf(value, low, high)

# -------------------------------------------------------------------- action

## The godot_rl_agents action space: eight discrete branches, in order.
static func action_space() -> Dictionary:
	var space := {}
	for branch in BRANCHES:
		space[branch["name"]] = {"size": branch["size"], "action_type": "discrete"}
	return space

## Branch indices from the dictionary Sync passes to set_action. A value may be an
## int, a float or a one-element array. A missing branch makes the vector short,
## which the decoder rejects.
static func action_from_dict(action: Dictionary) -> PackedInt32Array:
	var indices := PackedInt32Array()
	for branch in BRANCHES:
		var key: String = branch["name"]
		if not action.has(key):
			continue
		var value: Variant = action[key]
		if value is Array or value is PackedFloat32Array or value is PackedInt32Array:
			if value.is_empty():
				continue
			value = value[0]
		indices.append(roundi(float(value)))
	return indices

## Argmax of each branch over the concatenated logits. Ties go to the lowest index.
static func argmax_branches(logits: PackedFloat32Array) -> PackedInt32Array:
	var indices := PackedInt32Array()
	var offset := 0
	for branch in BRANCHES:
		var best := 0
		for i in range(1, int(branch["size"])):
			if logits[offset + i] > logits[offset + best]:
				best = i
		indices.append(best)
		offset += int(branch["size"])
	return indices

## The part of bvs.json that is fixed by the schema (the trainer fills the rest).
static func sidecar_template() -> Dictionary:
	var branches: Array = []
	for branch in BRANCHES:
		branches.append({"name": branch["name"], "size": branch["size"]})
	return {
		"format": FORMAT,
		"schema_version": VERSION,
		"obs_dim": OBS_DIM,
		"action_branches": branches,
		"action_repeat": ACTION_REPEAT,
		"onnx": {"file": "model.onnx", "input": "obs", "output": "logits", "opset": 17},
	}
