extends SceneTree
## The combat-depth acceptance harness: plays full, non-training matches of
## game.tscn and reports the numbers the acceptance gates read (sudden-death length,
## food use, blocking, KO results). Not part of run_all.sh (long-running, env-driven):
## `training/bvs_training/harness.py` launches it and applies the gates.
##
##   BVS_HARNESS_MODEL=<model.onnx> BVS_HARNESS_MATCHUPS=mvm,m_vs_cpu_easy,cpu_hard_vs_cpu_hard \
##   BVS_HARNESS_MATCHES=20 BVS_HARNESS_SEED=1 [BVS_HARNESS_FORCE_SD=1] BVS_HARNESS_OUT=<out.json> \
##   godot --headless --path . --fixed-fps 60 --script res://tests/smoke/combat_harness.gd
##
## Matchups (comma list):
##   mvm                          the model against itself
##   m_vs_cpu_<easy|normal|hard>  the model against the scripted CPU (sides alternate)
##   cpu_<lvl>_vs_cpu_<lvl>       two scripted CPUs (no model needed)
## BVS_HARNESS_MODEL is required only for the matchups that use the model; the model
## plays the schema its sidecar declares (any registered one). BVS_HARNESS_FORCE_SD=1
## puts every match into sudden death right away (the sudden-death length gate).
## BVS_HARNESS_SEED seeds the shared generator and the CPUs of every match, so the
## same seed and build give the same numbers (the documented tolerance for engine
## differences is 5% on the rate metrics).
##
## Output JSON (also printed as `BVS_HARNESS {json}`):
##   {"seed", "force_sd", "model", "schema_version", "matches_per_matchup",
##    "matchups": {"<name>": {"matches", "ko_results", "ko_wins", "ko_win_rate", "draws",
##       "mean_match_seconds", "mean_sd_seconds", "max_sd_seconds", "sd_matches",
##       "pickups_per_fighter_minute", "throws_per_fighter_minute", "blocked_share",
##       "damage_by_source", "shield_breaks"}}}
## `ko_results` counts the matches that ended by elimination; `ko_wins` the KO wins of
## the model (m_vs_cpu_*) or of the first CPU (cpu_* matchups; sides alternate), so
## `ko_win_rate` is the share of matches the model (or first CPU) won by KO.
## Exits non-zero on a setup error or an inference failure.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const LEVELS := {"easy": CpuDifficulty.Level.EASY, "normal": CpuDifficulty.Level.NORMAL, "hard": CpuDifficulty.Level.HARD}
## A match that has not resolved after this much game time counts as a draw.
const MATCH_LIMIT_SECONDS := 400.0
## Ticks of game time the engine runs per second under --fixed-fps 60.
const DEFAULT_MATCHES := 20

var _model: OnnxPolicyModel
var _model_schema: Object

func _initialize() -> void:
	_run()

func _fail(message: String) -> void:
	printerr("combat_harness: %s" % message)
	quit(1)

func _run() -> void:
	var matchups := _split(OS.get_environment("BVS_HARNESS_MATCHUPS"))
	var matches := int(OS.get_environment("BVS_HARNESS_MATCHES")) if OS.get_environment("BVS_HARNESS_MATCHES") != "" else DEFAULT_MATCHES
	var harness_seed := int(OS.get_environment("BVS_HARNESS_SEED")) if OS.get_environment("BVS_HARNESS_SEED") != "" else 1
	var force_sd := OS.get_environment("BVS_HARNESS_FORCE_SD") in ["1", "true", "yes"]
	var out_path := OS.get_environment("BVS_HARNESS_OUT")
	var model_path := OS.get_environment("BVS_HARNESS_MODEL")
	if matchups.is_empty():
		_fail("BVS_HARNESS_MATCHUPS must list matchups (mvm, m_vs_cpu_<lvl>, cpu_<lvl>_vs_cpu_<lvl>)")
		return
	if matches < 1:
		_fail("BVS_HARNESS_MATCHES must be at least 1")
		return
	var needs_model := false
	var parsed: Dictionary = {}
	for name in matchups:
		var spec := _parse_matchup(name)
		if spec.is_empty():
			_fail("unknown matchup '%s' (use mvm, m_vs_cpu_<easy|normal|hard>, cpu_<lvl>_vs_cpu_<lvl>)" % name)
			return
		parsed[name] = spec
		needs_model = needs_model or bool(spec["model"])
	if needs_model:
		if model_path == "" or not FileAccess.file_exists(model_path):
			_fail("BVS_HARNESS_MODEL must name an existing model.onnx (got '%s')" % model_path)
			return
		if not _load_model(model_path):
			return

	var s := Smoke.new(self, MATCH_LIMIT_SECONDS * float(matches * matchups.size() + 2))
	var report := {
		"seed": harness_seed,
		"force_sd": force_sd,
		"model": model_path if needs_model else "",
		"schema_version": int(_model_schema.VERSION) if _model_schema != null else 0,
		"matches_per_matchup": matches,
		"matchups": {},
	}
	for name in matchups:
		var result := await _play_matchup(s, name, parsed[name], matches, harness_seed, force_sd)
		if result.has("error"):
			_fail(String(result["error"]))
			return
		report["matchups"][name] = result
	var json := JSON.stringify(report)
	print("BVS_HARNESS %s" % json)
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file == null:
			_fail("cannot write %s" % out_path)
			return
		file.store_string(JSON.stringify(report, "  "))
	s.finish()

func _split(text: String) -> PackedStringArray:
	var names := PackedStringArray()
	for part in text.split(","):
		var trimmed := part.strip_edges()
		if trimmed != "":
			names.append(trimmed)
	return names

## {"model": bool, "sides": [kind, kind]} for a matchup name, {} when it is unknown.
## A kind is "model" or a CPU level name.
func _parse_matchup(name: String) -> Dictionary:
	if name == "mvm":
		return {"model": true, "kinds": ["model", "model"]}
	if name.begins_with("m_vs_cpu_"):
		var level := name.trim_prefix("m_vs_cpu_")
		return {"model": true, "kinds": ["model", level]} if LEVELS.has(level) else {}
	if name.begins_with("cpu_") and name.contains("_vs_cpu_"):
		var halves := name.trim_prefix("cpu_").split("_vs_cpu_")
		if halves.size() == 2 and LEVELS.has(halves[0]) and LEVELS.has(halves[1]):
			return {"model": false, "kinds": [String(halves[0]), String(halves[1])]}
	return {}

func _load_model(model_path: String) -> bool:
	var sidecar: Dictionary = {}
	var sidecar_path := model_path.get_base_dir().path_join("bvs.json")
	if not FileAccess.file_exists(sidecar_path):
		sidecar_path = model_path.get_basename() + ".bvs.json"
	if FileAccess.file_exists(sidecar_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sidecar_path))
		if parsed is Dictionary:
			sidecar = parsed
	var result := OnnxPolicyModel.load_bytes(FileAccess.get_file_as_bytes(model_path), sidecar)
	if result.model == null:
		_fail("model rejected: %s" % result.error)
		return false
	_model = result.model
	var version := _model.schema_version()
	_model_schema = BvsSchema.get_schema(version)
	if _model_schema == null:
		_fail("model declares the unregistered schema %d" % version)
		return false
	if not sidecar.is_empty():
		var sidecar_problem := BvsSchema.validate_sidecar_for(sidecar, version)
		if sidecar_problem != "":
			_fail("sidecar rejected: %s" % sidecar_problem)
			return false
	var problem := _model.validate(_model_schema)
	if problem != "":
		_fail("model does not fit schema %d: %s" % [version, problem])
		return false
	return true

## Plays `matches` matches of one matchup and aggregates them.
func _play_matchup(s: RefCounted, name: String, spec: Dictionary, matches: int, harness_seed: int, force_sd: bool) -> Dictionary:
	var records: Array = []
	var ko_results := 0
	var ko_wins := 0
	var draws := 0
	var seconds_total := 0.0
	for index in matches:
		var record := await _play_match(s, spec["kinds"], index, harness_seed, force_sd)
		if record.has("error"):
			return {"error": "%s: match %d: %s" % [name, index, record["error"]]}
		records.append(record["metrics"])
		ko_results += 1 if record["by_ko"] else 0
		ko_wins += 1 if record["by_ko"] and record["first_won"] else 0
		draws += 1 if record["draw"] else 0
		seconds_total += float(record["metrics"]["seconds"])
	var result := {
		"matches": matches,
		"ko_results": ko_results,
		"ko_wins": ko_wins,
		"ko_win_rate": float(ko_wins) / float(matches),
		"draws": draws,
		"mean_match_seconds": seconds_total / float(matches),
	}
	result.merge(MatchMetrics.aggregate(records))
	return result

## One match. `kinds` are the two controllers; the first one takes side 0 on even
## matches and side 1 on odd ones, so both sides are played.
func _play_match(s: RefCounted, kinds: Array, index: int, harness_seed: int, force_sd: bool) -> Dictionary:
	GameRng.seed_all(harness_seed * 100003 + index)
	var game: Node2D = s.spawn_game()
	var fighters: Array[Fighter] = [game.get_node("Fighter1"), game.get_node("Fighter2")]
	var first := fighters[index % 2]
	var order: Array[Fighter] = [first, fighters[1 - index % 2]]
	var controllers: Array = []
	for side in 2:
		var kind: String = kinds[side]
		if kind == "model":
			var controller := PolicyController.new(_model)
			order[side].set_controller(controller)
			controllers.append(controller)
		else:
			s.set_cpu(order[side], LEVELS[kind], harness_seed * 1000 + index * 2 + side)
	var metrics := MatchMetrics.new()
	metrics.setup(game as Game)
	var done := {"over": false, "winner": null}
	game.match_over.connect(func(winner: Fighter) -> void:
		done["over"] = true
		done["winner"] = winner)
	if force_sd:
		await s.frames(2)
		(game as Game).force_sudden_death()
	var start := Engine.get_physics_frames()
	var failure := ""
	while not done["over"] and float(Engine.get_physics_frames() - start) / 60.0 < MATCH_LIMIT_SECONDS and failure == "":
		await s.frames(1)
		for controller: PolicyController in controllers:
			if controller.error != "":
				failure = controller.error
	metrics.stop()
	var by_ko: bool = fighters[0].stocks <= 0 or fighters[1].stocks <= 0
	var first_won: bool = done["winner"] == first
	var draw: bool = not done["over"] or done["winner"] == null
	paused = false
	Combat.cancel_hit_stop()
	await s.despawn(game)
	if failure != "":
		return {"error": "inference failed: %s" % failure}
	return {"metrics": metrics.to_dict(), "by_ko": by_ko and done["over"], "first_won": first_won, "draw": draw}
