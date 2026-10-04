extends SceneTree
## bvs-schema-4: the 149-float observation (the schema 3 vector plus 13 kit, chain,
## hitstun and combo floats), its decoder, the registry with versions 2, 3 and 4 and
## the golden fixtures. Run headless.
##
## Synthetic snapshots use a stage spanning x 30..830 at top 480 (center 430, half
## width 400): a fighter standing on the floor sits at y 386.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const LAYOUT_FIXTURE := "res://tests/fixtures/schema/v4_layout.json"
const OBS_FIXTURE := "res://tests/fixtures/schema/v4_obs_golden.json"

# The appended block (part of the v4 contract).
const SELF_KIT := 136
const OPP_KIT := 140
const CHAIN_STEP := 144
const LINK_OPEN := 145
const OPP_HITSTUN := 146
const COMBO_DEALT := 147
const COMBO_TAKEN := 148

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	_check_layout(s)
	_check_v3_prefix(s)
	_check_kit_block(s)
	_check_missing_keys(s)
	_check_registry(s)
	_check_decoder_parity(s)
	_check_fixtures(s)
	await _check_real_game(s)
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
		"kit_id": -1,
		"chain_step": 0,
		"link_open": false,
		"hitstun_left": 0.0,
		"combo_hits": 0,
		"combo_damage": 0.0,
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
		out.append(obs[from + i])
	return out

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
		for key in ["facing", "stocks", "jumps_left", "ledge_side", "kit_id", "chain_step", "combo_hits"]:
			fighter[key] = int(fighter[key])
	for food: Dictionary in snapshot["foods"]:
		food["position"] = _vec(food["position"])
	for shot: Dictionary in snapshot["projectiles"]:
		shot["position"] = _vec(shot["position"])
		shot["velocity"] = _vec(shot["velocity"])
		shot["shooter"] = int(shot["shooter"])
	for bomb: Dictionary in snapshot["bombs"]:
		bomb["position"] = _vec(bomb["position"])
		bomb["velocity"] = _vec(bomb["velocity"])
	for ledge: Dictionary in snapshot["ledges"]:
		ledge["side"] = int(ledge["side"])
	snapshot["sudden_death_phase"] = int(snapshot["sudden_death_phase"])
	return snapshot

# -------------------------------------------------------------------- layout

func _check_layout(s: RefCounted) -> void:
	s.check("schema 4 declares version 4, 149 inputs, repeat 4 and 21 logits", BvsSchemaV4.VERSION == 4 and BvsSchemaV4.OBS_DIM == 149 and BvsSchemaV4.ACTION_REPEAT == 4 and BvsSchemaV4.LOGITS == 21)
	s.check("FIELD_NAMES has 149 distinct names", BvsSchemaV4.FIELD_NAMES.size() == 149 and _distinct(BvsSchemaV4.FIELD_NAMES))
	var prefix := true
	for i in BvsSchemaV3.FIELD_NAMES.size():
		prefix = prefix and BvsSchemaV3.FIELD_NAMES[i] == BvsSchemaV4.FIELD_NAMES[i]
	s.check("the first 136 names equal the schema 3 names", prefix)
	s.check("the appended names sit at the documented indices", BvsSchemaV4.FIELD_NAMES[SELF_KIT] == "self_kit_0" and BvsSchemaV4.FIELD_NAMES[OPP_KIT] == "opp_kit_0" and BvsSchemaV4.FIELD_NAMES[COMBO_TAKEN] == "self_combo_taken")
	s.check("the branches equal the schema 3 branches (the decoder is unchanged)", BvsSchemaV4.BRANCHES == BvsSchemaV3.BRANCHES)
	var empty := BvsSchemaV4.build_obs(_snapshot(_fighter(), _fighter()), 0)
	s.check("an observation is 149 long", empty.size() == 149)

func _distinct(names: PackedStringArray) -> bool:
	var seen := {}
	for field_name in names:
		if seen.has(field_name):
			return false
		seen[field_name] = true
	return true

## v4[0:136] is exactly the schema 3 vector for the same snapshot, for every recorded
## fixture snapshot (both views) plus a spread of synthetic ones.
func _check_v3_prefix(s: RefCounted) -> void:
	var snapshots: Array = []
	var golden: Variant = _read_json(OBS_FIXTURE)
	if golden is Dictionary:
		for entry: Dictionary in golden["cases"]:
			snapshots.append([_snapshot_from_json(entry["snapshot"]), int(entry["my_index"])])
	snapshots.append([_snapshot(_fighter({"kit_id": 0, "damage_percent": 63.0, "state": &"Punch"}), _fighter({"kit_id": 1, "position": Vector2(600.0, 200.0), "on_floor": false, "state": &"Hurt", "hitstun_left": 0.3, "combo_hits": 3, "combo_damage": 9.0}), {"foods": [{"name": "pizza", "position": Vector2(480.0, 400.0)}]}), 1])
	var identical := 0
	for pair: Array in snapshots:
		var v3 := BvsSchemaV3.build_obs(pair[0], pair[1])
		var v4 := BvsSchemaV4.build_obs(pair[0], pair[1])
		var same := v4.size() == 149 and v3.size() == 136
		for i in 136:
			same = same and v3[i] == v4[i]
		identical += 1 if same else 0
	s.check("v4[0:136] equals the schema 3 vector on %d snapshots" % snapshots.size(), snapshots.size() >= 10 and identical == snapshots.size(), "identical=%d/%d" % [identical, snapshots.size()])

# ----------------------------------------------------------------- kit block

func _check_kit_block(s: RefCounted) -> void:
	var rafael := BvsSchemaV4.build_obs(_snapshot(_fighter({"kit_id": 0}), _fighter({"kit_id": 1})), 0)
	s.check("kit one-hot: me Rafael (slot 0), opponent Matilde (slot 1)", _slice(rafael, SELF_KIT, 4) == [1.0, 0.0, 0.0, 0.0] and _slice(rafael, OPP_KIT, 4) == [0.0, 1.0, 0.0, 0.0], str(_slice(rafael, SELF_KIT, 8)))
	var swapped := BvsSchemaV4.build_obs(_snapshot(_fighter({"kit_id": 0}), _fighter({"kit_id": 1})), 1)
	s.check("the opponent view swaps the two one-hots", _slice(swapped, SELF_KIT, 4) == [0.0, 1.0, 0.0, 0.0] and _slice(swapped, OPP_KIT, 4) == [1.0, 0.0, 0.0, 0.0])
	for kit_id in [-1, 4, 99]:
		var obs := BvsSchemaV4.build_obs(_snapshot(_fighter({"kit_id": kit_id}), _fighter({"kit_id": kit_id})), 0)
		s.check("kit id %d encodes as all zeros" % kit_id, _slice(obs, SELF_KIT, 8) == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var reserved := BvsSchemaV4.build_obs(_snapshot(_fighter({"kit_id": 3}), _fighter({"kit_id": 2})), 0)
	s.check("the reserved kit ids 2 and 3 have their own slots", _slice(reserved, SELF_KIT, 4) == [0.0, 0.0, 0.0, 1.0] and _slice(reserved, OPP_KIT, 4) == [0.0, 0.0, 1.0, 0.0])

	var chain := BvsSchemaV4.build_obs(_snapshot(_fighter({"chain_step": 2, "link_open": true}), _fighter({"hitstun_left": 0.25, "combo_hits": 3, "state": &"Hurt"})), 0)
	s.check("chain step is step / 3", _near(chain[CHAIN_STEP], 2.0 / 3.0), str(chain[CHAIN_STEP]))
	s.check("the link flag is 1 while the link window is open", chain[LINK_OPEN] == 1.0)
	s.check("the opponent hitstun is seconds clipped to 1", _near(chain[OPP_HITSTUN], 0.25))
	s.check("the combo I am dealing is the opponent's hits / 6", _near(chain[COMBO_DEALT], 0.5) and chain[COMBO_TAKEN] == 0.0)
	var taken := BvsSchemaV4.build_obs(_snapshot(_fighter({"combo_hits": 3}), _fighter()), 0)
	s.check("the combo I am taking is my hits / 6", _near(taken[COMBO_TAKEN], 0.5) and taken[COMBO_DEALT] == 0.0)
	var idle := BvsSchemaV4.build_obs(_snapshot(_fighter(), _fighter()), 0)
	s.check("outside a chain, hitstun or combo the block is zero", _slice(idle, CHAIN_STEP, 5) == [0.0, 0.0, 0.0, 0.0, 0.0])

	var extreme := BvsSchemaV4.build_obs(_snapshot(_fighter({"chain_step": 99, "link_open": true, "combo_hits": 99, "kit_id": 99}), _fighter({"hitstun_left": 99.0, "combo_hits": 99, "kit_id": -5})), 0)
	s.check("extreme chain, hitstun and combo values clip to 1 and stay finite", extreme[CHAIN_STEP] == 1.0 and extreme[OPP_HITSTUN] == 1.0 and extreme[COMBO_DEALT] == 1.0 and extreme[COMBO_TAKEN] == 1.0 and _all_finite_and_bounded(extreme))
	var negative := BvsSchemaV4.build_obs(_snapshot(_fighter({"chain_step": -3, "combo_hits": -2}), _fighter({"hitstun_left": -1.0, "combo_hits": -4})), 0)
	s.check("negative chain, hitstun and combo values clip to 0", _slice(negative, CHAIN_STEP, 5) == [0.0, 0.0, 0.0, 0.0, 0.0])

func _check_missing_keys(s: RefCounted) -> void:
	for key in ["kit_id", "chain_step", "link_open", "hitstun_left", "combo_hits"]:
		var fighter := _fighter()
		fighter.erase(key)
		var snapshot := _snapshot(_fighter(), fighter)
		var problem := BvsSchemaV4.validate_snapshot(snapshot, 0)
		s.check("a snapshot missing '%s' is reported by name" % key, problem.contains(key) and problem.contains("fighters[1]"), problem)
	s.check("a complete snapshot validates", BvsSchemaV4.validate_snapshot(_snapshot(_fighter(), _fighter()), 0) == "")
	var v3_style := _fighter()
	v3_style.erase("kit_id")
	var obs := BvsSchemaV4.build_obs(_snapshot(v3_style, _fighter()), 0)
	s.check("a schema 3 style snapshot gives an all-zero vector of the right length (an error is reported)", obs == _zeros(149))

func _zeros(count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(count)
	return out

# ------------------------------------------------------------------ registry

func _check_registry(s: RefCounted) -> void:
	s.check("the registry holds 2, 3 and 4 with their own modules", BvsSchema.get_schema(2) == BvsSchemaV2 and BvsSchema.get_schema(3) == BvsSchemaV3 and BvsSchema.get_schema(4) == BvsSchemaV4)
	s.check("each registered version has its own obs_dim", BvsSchema.get_schema(2).OBS_DIM == 102 and BvsSchema.get_schema(3).OBS_DIM == 136 and BvsSchema.get_schema(4).OBS_DIM == 149)
	s.check("an unregistered version is unsupported, not a default layout", BvsSchema.get_schema(99) == null and BvsSchema.new_decoder(99) == null and BvsSchema.get_schema(1) == null)
	s.check("decoders come from the registry by version", BvsSchema.new_decoder(2) is BvsActionDecoderV2 and BvsSchema.new_decoder(3) is BvsActionDecoderV3 and BvsSchema.new_decoder(4) is BvsActionDecoderV4)
	s.check("two requests give two independent v4 decoders", BvsSchema.new_decoder(4) != BvsSchema.new_decoder(4) and BvsSchemaV4.new_decoder() is BvsActionDecoderV4)
	s.check("2, 3 and 4 are built in, 5 and 99 are not", BvsSchema.is_builtin(2) and BvsSchema.is_builtin(3) and BvsSchema.is_builtin(4) and not BvsSchema.is_builtin(5) and not BvsSchema.is_builtin(99))
	s.check("the playable version flipped to 4 once the schema 4 model was bundled", BvsSchema.CURRENT_VERSION == 4 and BvsSchema.current() == BvsSchemaV4)

	var template := BvsSchemaV4.sidecar_template()
	s.check("the v4 sidecar template validates against schema 4", BvsSchema.validate_sidecar_for(template, 4) == "", BvsSchema.validate_sidecar_for(template, 4))
	s.check("the v4 template is not valid for schema 3 and names the mismatch", BvsSchema.validate_sidecar_for(template, 3).contains("schema"), BvsSchema.validate_sidecar_for(template, 3))
	s.check("the v4 sidecar template is now current and playable", BvsSchema.validate_sidecar(template) == "", BvsSchema.validate_sidecar(template))
	var older_template := BvsSchemaV3.sidecar_template()
	s.check("a schema 3 sidecar is registered but not playable and says which schema the game uses", BvsSchema.validate_sidecar(older_template).contains("this game uses schema 4"), BvsSchema.validate_sidecar(older_template))
	var lying := template.duplicate(true)
	lying["obs_dim"] = 136
	s.check("a schema-4 sidecar with 136 inputs says what the model expects and what the game provides", BvsSchema.validate_sidecar_for(lying, 4).contains("expects 136 inputs") and BvsSchema.validate_sidecar_for(lying, 4).contains("provides 149"), BvsSchema.validate_sidecar_for(lying, 4))
	var resized := template.duplicate(true)
	resized["action_branches"][3]["size"] = 4
	s.check("a wrong branch size is rejected for schema 4", BvsSchema.validate_sidecar_for(resized, 4).contains("a3_attack"))
	var repeated := template.duplicate(true)
	repeated["action_repeat"] = 2
	s.check("a wrong action_repeat is rejected for schema 4", BvsSchema.validate_sidecar_for(repeated, 4).contains("action_repeat"))
	var v3_template := BvsSchemaV3.sidecar_template()
	s.check("the v3 template stays valid for schema 3 and is rejected for schema 4", BvsSchema.validate_sidecar_for(v3_template, 3) == "" and BvsSchema.validate_sidecar_for(v3_template, 4) != "")
	s.check("validating against an unregistered version is an error", BvsSchema.validate_sidecar_for(template, 99).to_lower().contains("unsupported"))

	BvsSchema.unregister_test_stub(4)
	s.check("unregistering a built-in version is refused", BvsSchema.get_schema(4) == BvsSchemaV4)

# ------------------------------------------------------------------- decoder

## The v4 decoder decodes exactly like v3: same intents for random branch vectors,
## random fighter state included.
func _check_decoder_parity(s: RefCounted) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var v3 := BvsActionDecoderV3.new()
	var v4 := BvsActionDecoderV4.new()
	var same := true
	var windows := 0
	for i in 400:
		var indices := PackedInt32Array()
		for branch in BvsSchemaV4.BRANCHES:
			indices.append(rng.randi_range(0, int(branch["size"]) - 1))
		same = same and v3.begin_window(indices) == v4.begin_window(indices)
		for tick in 4:
			var a := v3.frame(null)
			var b := v4.frame(null)
			same = same and _intent_equal(a, b)
		windows += 1
	s.check("v4 decodes %d random windows exactly like v3" % windows, same)
	var short := PackedInt32Array([1, 0, 0])
	s.check("a short action vector is rejected like in v3 (error text names the decoder)", v4.begin_window(short).contains("8 branches"))
	var out_of_range := PackedInt32Array([1, 0, 0, 5, 0, 0, 0, 0])
	s.check("an out-of-range branch index is rejected", v4.begin_window(out_of_range).contains("a3_attack"))
	var argmax_logits := PackedFloat32Array()
	argmax_logits.resize(21)
	argmax_logits[12] = 9.0
	s.check("argmax per branch matches schema 3", BvsSchemaV4.argmax_branches(argmax_logits) == BvsSchemaV3.argmax_branches(argmax_logits))
	s.check("action_from_dict matches schema 3", BvsSchemaV4.action_from_dict({"a0_move": 2, "a3_attack": 4, "a7_dash": 1}) == BvsSchemaV3.action_from_dict({"a0_move": 2, "a3_attack": 4, "a7_dash": 1}))

func _intent_equal(a: FighterIntent, b: FighterIntent) -> bool:
	return a.move_x == b.move_x and a.aim == b.aim and a.jump_pressed == b.jump_pressed and a.jump_held == b.jump_held \
		and a.attack_pressed == b.attack_pressed and a.attack_held == b.attack_held and a.attack_released == b.attack_released \
		and a.special_pressed == b.special_pressed and a.throw_pressed == b.throw_pressed and a.block_pressed == b.block_pressed \
		and a.block_held == b.block_held and a.dash_pressed == b.dash_pressed

# ------------------------------------------------------------------ fixtures

func _check_fixtures(s: RefCounted) -> void:
	var layout: Variant = _read_json(LAYOUT_FIXTURE)
	var frozen: bool = layout is Array and layout.size() == BvsSchemaV4.FIELD_NAMES.size()
	if frozen:
		for i in layout.size():
			frozen = frozen and String(layout[i]) == BvsSchemaV4.FIELD_NAMES[i]
	s.check("the layout fixture equals FIELD_NAMES name by name (the v4 freeze)", frozen)

	var golden: Variant = _read_json(OBS_FIXTURE)
	s.check("the golden fixture holds the recorded cases (kits, chain, hitstun, combo, bombs)", golden is Dictionary and golden.get("cases", []).size() >= 12)
	if not (golden is Dictionary):
		return
	var matched := 0
	var worst := 0.0
	var kits_seen := {}
	var chain_open := 0
	var combos := 0
	var bombs := 0
	for entry: Dictionary in golden["cases"]:
		var snapshot := _snapshot_from_json(entry["snapshot"])
		var built := BvsSchemaV4.build_obs(snapshot, int(entry["my_index"]))
		var expected: Array = entry["expected"]
		bombs += 1 if not snapshot["bombs"].is_empty() else 0
		for fighter: Dictionary in snapshot["fighters"]:
			kits_seen[int(fighter["kit_id"])] = true
			chain_open += 1 if bool(fighter["link_open"]) else 0
			combos += 1 if int(fighter["combo_hits"]) > 0 else 0
		if built.size() != expected.size():
			continue
		var ok := true
		for i in expected.size():
			var diff := absf(built[i] - float(expected[i]))
			worst = maxf(worst, diff)
			ok = ok and diff <= 1e-6
		matched += 1 if ok else 0
	s.check("every golden case rebuilds within 1e-6", matched == golden["cases"].size(), "matched=%d/%d worst=%s" % [matched, golden["cases"].size(), str(worst)])
	s.check("the golden cases cover both kits, the generic kit, an open link, combos and bombs", kits_seen.has(0) and kits_seen.has(1) and kits_seen.has(-1) and chain_open >= 1 and combos >= 1 and bombs >= 3, "kits=%s link=%d combos=%d bombs=%d" % [str(kits_seen.keys()), chain_open, combos, bombs])
	var players := {}
	for entry: Dictionary in golden["cases"]:
		players[int(entry["my_index"])] = true
	s.check("the golden cases include the player 2 view", players.has(0) and players.has(1))

# ----------------------------------------------------------------- real game

func _check_real_game(s: RefCounted) -> void:
	var game: Node2D = s.spawn_game(NAN, NAN, false, true)
	await s.frames(30)
	var snapshot: Dictionary = game.get_state_snapshot()
	s.check("a real Game snapshot carries every key schema 4 reads", BvsSchemaV4.validate_snapshot(snapshot, 0) == "" and BvsSchemaV4.validate_snapshot(snapshot, 1) == "", BvsSchemaV4.validate_snapshot(snapshot, 0))
	var obs := BvsSchemaV4.build_obs(snapshot, 0)
	s.check("a real observation is 149 long, finite and bounded", obs.size() == 149 and _all_finite_and_bounded(obs))
	s.check("the real kits are Rafael (0) for player 1 and Matilde (1) for player 2", _slice(obs, SELF_KIT, 8) == [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0], str(_slice(obs, SELF_KIT, 8)))
	var other := BvsSchemaV4.build_obs(snapshot, 1)
	s.check("player 2 sees the kits swapped", _slice(other, SELF_KIT, 8) == [0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0])
	var v3 := BvsSchemaV3.build_obs(snapshot, 0)
	var same_prefix := true
	for i in 136:
		same_prefix = same_prefix and v3[i] == obs[i]
	s.check("the real v4 vector starts with the real v3 vector", same_prefix)
	var attacker: Fighter = game.get_node("Fighter1")
	var victim: Fighter = game.get_node("Fighter2")
	var fighter_snapshot := attacker.get_state_snapshot()
	s.check("the fighter snapshot has the six new keys at rest", fighter_snapshot["kit_id"] == 0 and fighter_snapshot["chain_step"] == 0 and fighter_snapshot["link_open"] == false and fighter_snapshot["hitstun_left"] == 0.0 and fighter_snapshot["combo_hits"] == 0 and fighter_snapshot["combo_damage"] == 0.0, str(fighter_snapshot["kit_id"]))
	var generic_game: Node2D = s.spawn_game()
	await s.frames(5)
	s.check("a smoke Game with the baseline profile reports kit id -1 (all-zero one-hots)", generic_game.get_state_snapshot()["fighters"][0]["kit_id"] == -1)
	await s.despawn(generic_game)

	# A live hit: the victim reports its hitstun and the combo, the attacker the dealt combo.
	victim.global_position = attacker.global_position + Vector2(90.0, 0.0)
	victim.facing = -1
	await s.frames(20)
	var hit := Hit.punch(attacker, 8.0, Vector2(120.0, -60.0))
	Combat.resolve(hit, victim)
	await s.frames(2)
	var hurt_snapshot := victim.get_state_snapshot()
	s.check("the victim snapshot reports hitstun left and one combo hit", String(hurt_snapshot["state"]) == "Hurt" and float(hurt_snapshot["hitstun_left"]) > 0.0 and int(hurt_snapshot["combo_hits"]) == 1 and float(hurt_snapshot["combo_damage"]) > 0.0, str(hurt_snapshot))
	var dealt := BvsSchemaV4.build_obs(game.get_state_snapshot(), 0)
	var taken := BvsSchemaV4.build_obs(game.get_state_snapshot(), 1)
	s.check("the attacker sees the combo dealt and the opponent hitstun, the victim the combo taken", dealt[OPP_HITSTUN] > 0.0 and _near(dealt[COMBO_DEALT], 1.0 / 6.0) and dealt[COMBO_TAKEN] == 0.0 and _near(taken[COMBO_TAKEN], 1.0 / 6.0) and taken[COMBO_DEALT] == 0.0, "hitstun=%.3f dealt=%.3f taken=%.3f" % [dealt[OPP_HITSTUN], dealt[COMBO_DEALT], taken[COMBO_TAKEN]])
	await s.despawn(game)
