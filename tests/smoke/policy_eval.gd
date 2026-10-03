extends SceneTree
## Evaluates a bvs-schema ONNX policy (the schema its sidecar declares: 2 or 3) against
## the scripted CPU in full, non-training matches of game.tscn. The model runs through the shipped GDScript
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
## for the golden parity fixtures. The report also carries the combat-depth metrics
## (MatchMetrics.aggregate): pickups and throws per fighter-minute, blocked share,
## damage by source, shield breaks and the sudden-death lengths.

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

## The shipped PolicyController (same loop as in a match: one inference per decision
## window, argmax per branch, the stateful decoder every frame), plus the counters the
## report needs. It only observes: the intents are the controller's own.
class EvalPolicyController extends PolicyController:
	var frames := 0
	var idle_frames := 0
	var attack_presses := 0
	var special_presses := 0
	var observations: Array = []
	## Per branch, how many decisions chose each index (the action distribution).
	var histogram: Array = []
	var _sampled_decisions := 0

	func sample(delta: float) -> FighterIntent:
		var intent := super.sample(delta)
		if error != "":
			return intent
		if decisions != _sampled_decisions:
			_sampled_decisions = decisions
			_count_action()
			if (decisions - 1) % OBS_SAMPLE_EVERY == 0 and observations.size() < OBS_SAMPLE_CAP:
				observations.append(Array(last_obs))
		frames += 1
		if intent.attack_pressed or intent.special_pressed:
			attack_presses += 1
		if intent.special_pressed:
			special_presses += 1
		if _is_neutral(intent):
			idle_frames += 1
		return intent

	func _count_action() -> void:
		if histogram.is_empty():
			for branch in _schema.BRANCHES:
				var counts: Array = []
				counts.resize(int(branch["size"]))
				counts.fill(0)
				histogram.append(counts)
		for branch in mini(last_action.size(), histogram.size()):
			histogram[branch][last_action[branch]] += 1

	static func _is_neutral(intent: FighterIntent) -> bool:
		return (
			is_zero_approx(intent.move_x) and not intent.jump_held and not intent.attack_pressed
			and not intent.throw_pressed and not intent.block_held and not intent.dash_pressed
			and not intent.special_pressed and intent.aim == FighterIntent.Aim.NEUTRAL
		)

## The schema of the model under evaluation (set by _load_model).
var _model_schema: Object = BvsSchemaV3

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
		"ko_wins": 0, "timeout_wins": 0, "ko_losses": 0, "timeout_losses": 0,
		"off_stage_events": 0, "special_presses": 0, "distance_sum": 0.0,
	}
	var histogram: Array = []
	for branch in _model_schema.BRANCHES:
		var counts: Array = []
		counts.resize(int(branch["size"]))
		counts.fill(0)
		histogram.append(counts)
	var observations: Array = []
	var per_match: Array = []
	var match_metrics: Array = []
	for i in matches:
		var record := await _play_match(s, model, LEVELS[level_name], i)
		if record.has("error"):
			_fail(String(record["error"]))
			return
		per_match.append(record["summary"])
		match_metrics.append(record["metrics"])
		for key in totals.keys():
			totals[key] += record["totals"][key]
		observations.append_array(record["observations"])
		for branch in histogram.size():
			for index in histogram[branch].size():
				histogram[branch][index] += record["histogram"][branch][index]
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
		"ko_wins": totals["ko_wins"],
		"timeout_wins": totals["timeout_wins"],
		"ko_losses": totals["ko_losses"],
		"timeout_losses": totals["timeout_losses"],
		"off_stage_events": totals["off_stage_events"],
		"recovery_success_rate": float(totals["recoveries"]) / maxf(float(totals["off_stage_events"]), 1.0),
		"special_presses": totals["special_presses"],
		"mean_distance": totals["distance_sum"] / maxf(float(totals["frames"]), 1.0),
		"action_distribution": _distribution(histogram),
		"per_match": per_match,
		"schema_version": int(_model_schema.VERSION),
	}
	report.merge(MatchMetrics.aggregate(match_metrics))
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
	var result := OnnxPolicyModel.load_bytes(FileAccess.get_file_as_bytes(model_path), sidecar)
	if result.model == null:
		_fail("model rejected: %s" % result.error)
		return null
	# The model plays the schema its sidecar declares (any registered one), not only the
	# current one: a schema-3 model is evaluated before the playable version moves.
	var version := (result.model as OnnxPolicyModel).schema_version()
	_model_schema = BvsSchema.get_schema(version)
	if _model_schema == null:
		_fail("model declares the unregistered schema %d" % version)
		return null
	if not sidecar.is_empty():
		var sidecar_problem := BvsSchema.validate_sidecar_for(sidecar, version)
		if sidecar_problem != "":
			_fail("sidecar rejected: %s" % sidecar_problem)
			return null
	var problem := (result.model as OnnxPolicyModel).validate(_model_schema)
	if problem != "":
		_fail("model does not fit schema %d: %s" % [version, problem])
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
	var controller := EvalPolicyController.new(model)
	me.set_controller(controller)
	s.set_cpu(foe, level, 1000 + index)
	var mlog = Smoke.MatchLog.new(game, false)
	var metrics := MatchMetrics.new()
	metrics.setup(game as Game)
	var stage: Dictionary = game.get_state_snapshot()["stage"]
	var done := {"over": false, "winner": null}
	game.match_over.connect(func(winner: Fighter) -> void:
		done["over"] = true
		done["winner"] = winner)

	var approach_frames := 0
	var frames := 0
	var recoveries := 0
	var was_off := false
	var off_events := 0
	var distance_sum := 0.0
	var stocks_when_off := me.stocks
	while not done["over"] and mlog.now() < MATCH_LIMIT_SECONDS and controller.error == "":
		await s.frames(1)
		frames += 1
		var gap := me.position.distance_to(foe.position)
		distance_sum += gap
		if gap <= APPROACH_DISTANCE:
			approach_frames += 1
		var off := _is_off_stage(me, stage)
		if off and not was_off:
			off_events += 1
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
	# A win by elimination leaves the loser at zero stocks; otherwise the clock decided it.
	var by_ko: bool = fighters[0].stocks <= 0 or fighters[1].stocks <= 0
	metrics.stop()
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
		"ko_wins": 1 if outcome == "win" and by_ko else 0,
		"timeout_wins": 1 if outcome == "win" and not by_ko else 0,
		"ko_losses": 1 if outcome == "loss" and by_ko else 0,
		"timeout_losses": 1 if outcome == "loss" and not by_ko else 0,
		"off_stage_events": off_events,
		"special_presses": controller.special_presses,
		"distance_sum": distance_sum,
	}
	return {
		"summary": {"match": index, "side": agent_side + 1, "outcome": outcome, "seconds": seconds,
			"stocks_taken": totals["stocks_taken"], "stocks_lost": totals["stocks_lost"]},
		"totals": totals,
		"observations": observations,
		"histogram": controller.histogram,
		"metrics": metrics.to_dict(),
	}

## Per branch: the share of each index and the Shannon entropy in bits (0 = always the same choice).
func _distribution(histogram: Array) -> Array:
	var result: Array = []
	for branch in histogram.size():
		var counts: Array = histogram[branch]
		var total := 0.0
		for count: int in counts:
			total += count
		var shares: Array = []
		var entropy := 0.0
		for count: int in counts:
			var share := float(count) / maxf(total, 1.0)
			shares.append(share)
			if share > 0.0:
				entropy -= share * log(share) / log(2.0)
		result.append({"name": _model_schema.BRANCHES[branch]["name"], "shares": shares, "entropy_bits": entropy})
	return result

## Airborne and outside the table top (same test as ScriptedController._is_off_stage).
func _is_off_stage(fighter: Fighter, stage: Dictionary) -> bool:
	if fighter.is_on_floor():
		return false
	var x := fighter.position.x
	return x < stage["left"] or x > stage["right"] or fighter.position.y > float(stage["top"]) + 2.0
