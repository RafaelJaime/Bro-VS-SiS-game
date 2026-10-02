extends SceneTree
## Evaluates a bvs-schema-2 ONNX policy against the scripted CPU in full,
## non-training matches of game.tscn. The model runs through the shipped GDScript
## interpreter, so the numbers describe exactly what players get. Not part of
## run_all.sh (long-running): `training/bvs_training/evaluate.py` launches it.
##
##   BVS_EVAL_MODEL=<model.onnx> BVS_EVAL_LEVEL=easy BVS_EVAL_MATCHES=20 \
##   BVS_EVAL_OUT=<report.json> [BVS_EVAL_OBS_DUMP=<obs.json>] [BVS_EVAL_SIDECAR=<bvs.json>] \
##   godot --headless --path . --fixed-fps 60 --script res://tests/smoke/policy_eval.gd
##
## The model fighter alternates sides every match. Prints one `BVS_EVAL {json}`
## line, writes the report to BVS_EVAL_OUT and exits non-zero on a setup error.
## BVS_EVAL_OBS_DUMP receives a sample of real observations (`{"observations": [...]}`)
## for the golden parity fixtures.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const LEVELS := {"easy": CpuDifficulty.Level.EASY, "normal": CpuDifficulty.Level.NORMAL, "hard": CpuDifficulty.Level.HARD}
## A match that has not resolved after this much game time counts as a draw.
const MATCH_LIMIT_SECONDS := 150.0
## Frames closer than this (px, between the fighters) count as "approached".
const APPROACH_DISTANCE := 150.0
## One real observation is recorded every this many decisions.
const OBS_SAMPLE_EVERY := 25
const OBS_SAMPLE_CAP := 256
const MIN_MATCHES := 20

## Runs the model with the same loop as the in-game adapter: one inference per
## decision window (every ACTION_REPEAT frames), argmax per branch, then the
## stateful decoder every frame. Counts what the report needs.
class EvalPolicyController extends FighterController:
	var model: OnnxPolicyModel
	var my_index: int
	var decoder := BvsActionDecoderV2.new()
	var ticks := 0
	var frames := 0
	var idle_frames := 0
	var attack_presses := 0
	var decisions := 0
	var error := ""
	var observations: Array = []

	func _init(policy_model: OnnxPolicyModel, index: int) -> void:
		model = policy_model
		my_index = index

	func sample(_delta: float) -> FighterIntent:
		if fighter == null or error != "":
			return FighterIntent.new()
		if ticks % BvsSchemaV2.ACTION_REPEAT == 0:
			var game := fighter.get_parent()
			var obs := BvsSchemaV2.build_obs(game.get_state_snapshot(), my_index)
			var result := model.infer_checked(obs)
			if result.error != "":
				error = String(result.error)
				push_error("policy_eval: inference failed: %s" % error)
				return FighterIntent.new()
			decoder.begin_window(BvsSchemaV2.argmax_branches(result.logits))
			if decisions % OBS_SAMPLE_EVERY == 0 and observations.size() < OBS_SAMPLE_CAP:
				observations.append(Array(obs))
			decisions += 1
		ticks += 1
		var intent := decoder.frame(fighter)
		frames += 1
		if intent.attack_pressed or intent.special_pressed:
			attack_presses += 1
		if _is_neutral(intent):
			idle_frames += 1
		return intent

	static func _is_neutral(intent: FighterIntent) -> bool:
		return (
			is_zero_approx(intent.move_x) and not intent.jump_held and not intent.attack_pressed
			and not intent.throw_pressed and not intent.block_held and not intent.dash_pressed
			and not intent.special_pressed and intent.aim == FighterIntent.Aim.NEUTRAL
		)

	func kind_name() -> String:
		return "policy"

func _initialize() -> void:
	_run()

func _fail(message: String) -> void:
	printerr("policy_eval: %s" % message)
	quit(1)

func _run() -> void:
	var model_path := OS.get_environment("BVS_EVAL_MODEL")
	var level_name := OS.get_environment("BVS_EVAL_LEVEL")
	if level_name == "":
		level_name = "easy"
	var matches := int(OS.get_environment("BVS_EVAL_MATCHES")) if OS.get_environment("BVS_EVAL_MATCHES") != "" else MIN_MATCHES
	var out_path := OS.get_environment("BVS_EVAL_OUT")
	var dump_path := OS.get_environment("BVS_EVAL_OBS_DUMP")
	if model_path == "" or not FileAccess.file_exists(model_path):
		_fail("BVS_EVAL_MODEL must name an existing model.onnx (got '%s')" % model_path)
		return
	if not LEVELS.has(level_name):
		_fail("BVS_EVAL_LEVEL must be one of %s (got '%s')" % [str(LEVELS.keys()), level_name])
		return
	if matches < 1:
		_fail("BVS_EVAL_MATCHES must be at least 1 (evaluate.py enforces %d for reports)" % MIN_MATCHES)
		return
	var model := _load_model(model_path)
	if model == null:
		return

	var s := Smoke.new(self, MATCH_LIMIT_SECONDS * (matches + 2))
	var totals := {
		"wins": 0, "losses": 0, "draws": 0, "stocks_taken": 0, "stocks_lost": 0, "self_kos": 0,
		"damage_dealt": 0.0, "attack_presses": 0, "approach_frames": 0, "frames": 0,
		"idle_frames": 0, "recoveries": 0, "match_seconds": 0.0,
	}
	var observations: Array = []
	var per_match: Array = []
	for i in matches:
		var record := await _play_match(s, model, LEVELS[level_name], i)
		if record.has("error"):
			_fail(String(record["error"]))
			return
		per_match.append(record["summary"])
		for key in totals.keys():
			totals[key] += record["totals"][key]
		observations.append_array(record["observations"])
	var played := float(matches)
	var report := {
		"model": model_path,
		"level": level_name,
		"matches": matches,
		"wins": totals["wins"],
		"losses": totals["losses"],
		"draws": totals["draws"],
		"win_rate": float(totals["wins"]) / played,
		"stocks_taken_mean": float(totals["stocks_taken"]) / played,
		"stocks_lost_mean": float(totals["stocks_lost"]) / played,
		"self_kos": totals["self_kos"],
		"self_ko_share": float(totals["self_kos"]) / maxf(float(totals["stocks_lost"]), 1.0),
		"damage_dealt_mean": totals["damage_dealt"] / played,
		"attack_presses": totals["attack_presses"],
		"approach_ratio": float(totals["approach_frames"]) / maxf(float(totals["frames"]), 1.0),
		"recoveries": totals["recoveries"],
		"idle_ratio": float(totals["idle_frames"]) / maxf(float(totals["frames"]), 1.0),
		"mean_match_seconds": totals["match_seconds"] / played,
		"per_match": per_match,
	}
	var json := JSON.stringify(report)
	print("BVS_EVAL %s" % json)
	if out_path != "":
		_write(out_path, JSON.stringify(report, "  "))
	if dump_path != "":
		_write(dump_path, JSON.stringify({"observations": observations}))
	s.finish()

func _load_model(model_path: String) -> OnnxPolicyModel:
	var sidecar_path := OS.get_environment("BVS_EVAL_SIDECAR")
	if sidecar_path == "":
		sidecar_path = model_path.get_base_dir().path_join("bvs.json")
		if not FileAccess.file_exists(sidecar_path):
			sidecar_path = model_path.get_basename() + ".bvs.json"
	var sidecar: Dictionary = {}
	if FileAccess.file_exists(sidecar_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sidecar_path))
		if parsed is Dictionary:
			sidecar = parsed
			var problem := BvsSchema.validate_sidecar(sidecar)
			if problem != "":
				_fail("sidecar %s rejected: %s" % [sidecar_path, problem])
				return null
	var result := OnnxPolicyModel.load_bytes(FileAccess.get_file_as_bytes(model_path), sidecar)
	if result.model == null:
		_fail("model rejected: %s" % result.error)
		return null
	var problem := (result.model as OnnxPolicyModel).validate(BvsSchemaV2)
	if problem != "":
		_fail("model does not fit schema 2: %s" % problem)
		return null
	return result.model

func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write %s" % path)
		return
	file.store_string(text)

## Plays one full match; the model fighter takes side 0 on even matches and side 1
## on odd ones. Returns {"summary", "totals", "observations"} or {"error"}.
func _play_match(s: RefCounted, model: OnnxPolicyModel, level: int, index: int) -> Dictionary:
	var game: Node2D = s.spawn_game()
	var agent_side := index % 2
	var fighters: Array[Fighter] = [game.get_node("Fighter1"), game.get_node("Fighter2")]
	var me := fighters[agent_side]
	var foe := fighters[1 - agent_side]
	var controller := EvalPolicyController.new(model, agent_side)
	me.set_controller(controller)
	s.set_cpu(foe, level, 1000 + index)
	var mlog = Smoke.MatchLog.new(game, false)
	var stage: Dictionary = game.get_state_snapshot()["stage"]
	var done := {"over": false, "winner": null}
	game.match_over.connect(func(winner: Fighter) -> void:
		done["over"] = true
		done["winner"] = winner)

	var approach_frames := 0
	var frames := 0
	var recoveries := 0
	var was_off := false
	var stocks_when_off := me.stocks
	while not done["over"] and mlog.now() < MATCH_LIMIT_SECONDS and controller.error == "":
		await s.frames(1)
		frames += 1
		if me.position.distance_to(foe.position) <= APPROACH_DISTANCE:
			approach_frames += 1
		var off := _is_off_stage(me, stage)
		if off and not was_off:
			stocks_when_off = me.stocks
		elif was_off and not off and me.stocks == stocks_when_off:
			recoveries += 1
		was_off = off
	var outcome := "draw"
	if done["winner"] == me:
		outcome = "win"
	elif done["winner"] == foe:
		outcome = "loss"
	var seconds: float = mlog.now()
	var observations := controller.observations
	var error := controller.error
	paused = false
	await s.despawn(game)
	if error != "":
		return {"error": "inference failed in match %d: %s" % [index, error]}
	var totals := {
		"wins": 1 if outcome == "win" else 0,
		"losses": 1 if outcome == "loss" else 0,
		"draws": 1 if outcome == "draw" else 0,
		"stocks_taken": mlog.losses[1 - agent_side],
		"stocks_lost": mlog.losses[agent_side],
		"self_kos": mlog.self_inflicted[agent_side],
		"damage_dealt": mlog.damage_taken[1 - agent_side],
		"attack_presses": controller.attack_presses,
		"approach_frames": approach_frames,
		"frames": frames,
		"idle_frames": controller.idle_frames,
		"recoveries": recoveries,
		"match_seconds": seconds,
	}
	return {
		"summary": {"match": index, "side": agent_side + 1, "outcome": outcome, "seconds": seconds,
			"stocks_taken": totals["stocks_taken"], "stocks_lost": totals["stocks_lost"]},
		"totals": totals,
		"observations": observations,
	}

## Airborne and outside the table top (same test as ScriptedController._is_off_stage).
func _is_off_stage(fighter: Fighter, stage: Dictionary) -> bool:
	if fighter.is_on_floor():
		return false
	var x := fighter.position.x
	return x < stage["left"] or x > stage["right"] or fighter.position.y > float(stage["top"]) + 2.0
