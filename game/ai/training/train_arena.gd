class_name TrainArena
extends Node2D

## The training environment: builds the Game rows at run time, so the curriculum is
## data (BVS_TRAIN_CONFIG) and not a hand-edited scene.
##
## BVS_TRAIN_CONFIG is the path of a JSON file (environment variable, inherited
## from the trainer):
##   {"rows": [{"opponent": "cpu_easy", "seed": 11}, {"opponent": "self"}],
##    "reward": {"win": 3.0}, "episode_log": true, "columns": 8}
## Without it the arena builds DEFAULT_ROWS rows: 6 cpu_easy and 2 self.
##
## Row opponent kinds:
##   self                     both fighters are training agents (shared policy)
##   cpu_easy|normal|hard     one training agent against a scripted CPU of that level
##                            (a HUMAN-mode AI controller, so Sync treats it as a
##                            heuristic, plus a seeded ScriptedController)
##   snapshot                 a frozen model as the opponent: a PolicyController runs
##                            the ONNX file `model` of the row spec (path) through the
##                            GDScript interpreter, like in a normal match. The path may
##                            also be given inline as `snapshot:<path>`. A missing,
##                            unreadable or schema-incompatible file is an error naming
##                            the row; the model is loaded once per path.
## An unknown kind is reported in `errors`, naming the row, and the row is not
## built: the scripted CPU Easy is never used as a silent default.
##
## Rows sit on one line (or a grid when `columns` is smaller than the row count)
## with a constant PITCH larger than a blast zone (1320 x 1210), so no body, area or
## projectile of one row can reach another. The agent's side alternates by row.

const PITCH := Vector2(2000.0, 1600.0)
const DEFAULT_ROWS := 8
const DEFAULT_SELF_ROWS := 2
const BASE_SEED := 1000
## Loaded at run time, not preloaded: this script compiles before the autoloads
## exist (smoke scripts), and the Game scene's scripts need them.
const GAME_SCENE_PATH := "res://game/game.tscn"
const CPU_LEVELS := {
	"cpu_easy": CpuDifficulty.Level.EASY,
	"cpu_normal": CpuDifficulty.Level.NORMAL,
	"cpu_hard": CpuDifficulty.Level.HARD,
}

## Set before the node enters the tree to use a config without a file (tests).
var config: Dictionary = {}
## The Game of every row that was built.
var games: Array[Game] = []
## One entry per built row: index, opponent kind, agent_side (1, 2 or 0 for self).
var rows: Array[Dictionary] = []
## One message per row that was rejected.
var errors: PackedStringArray = PackedStringArray()
## Loaded snapshot models by path (a snapshot is shared by every row that names it).
var _snapshot_models := {}

func _ready() -> void:
	if config.is_empty():
		config = _load_config()
	var reward_config := RewardConfig.from_dict(config.get("reward", {}))
	var row_specs: Array = config.get("rows", [])
	var columns := int(config.get("columns", row_specs.size()))
	columns = maxi(columns, 1)
	for index in row_specs.size():
		var spec: Dictionary = row_specs[index]
		var opponent := String(spec.get("opponent", ""))
		var problem := _check_opponent(opponent, spec)
		if problem != "":
			var message := "TrainArena: row %d: %s" % [index, problem]
			errors.append(message)
			push_error(message)
			continue
		var offset := Vector2(index % columns, floori(index / float(columns))) * PITCH
		_build_row(index, spec, opponent, offset, reward_config)
	_frame_camera(row_specs.size(), columns)
	var label := get_node_or_null("CanvasLayer/Label") as Label
	if label != null:
		label.text = "Training: %d rows" % games.size()

func _load_config() -> Dictionary:
	var path := OS.get_environment("BVS_TRAIN_CONFIG")
	if path != "":
		if not FileAccess.file_exists(path):
			push_error("TrainArena: BVS_TRAIN_CONFIG points to a missing file: %s" % path)
		else:
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				return parsed
			push_error("TrainArena: BVS_TRAIN_CONFIG is not a JSON object: %s" % path)
	return _default_config()

func _default_config() -> Dictionary:
	var row_specs: Array = []
	for index in DEFAULT_ROWS:
		var is_self := index >= DEFAULT_ROWS - DEFAULT_SELF_ROWS
		row_specs.append({"opponent": "self" if is_self else "cpu_easy", "seed": BASE_SEED + index})
	return {"rows": row_specs}

## "" for a supported opponent kind, otherwise why the row cannot be built.
func _check_opponent(opponent: String, spec: Dictionary) -> String:
	if opponent == "self" or CPU_LEVELS.has(opponent):
		return ""
	if opponent == "snapshot" or opponent.begins_with("snapshot:"):
		return _prepare_snapshot(_snapshot_path(opponent, spec))
	return "unknown opponent kind '%s' (use self, cpu_easy, cpu_normal, cpu_hard, snapshot)" % opponent

## The model path of a snapshot row: `snapshot:<path>` or the spec's `model`.
static func _snapshot_path(opponent: String, spec: Dictionary) -> String:
	if opponent.begins_with("snapshot:"):
		return opponent.trim_prefix("snapshot:")
	return String(spec.get("model", ""))

## Loads (once) the frozen model at `path`; "" when it is usable, else why not.
func _prepare_snapshot(path: String) -> String:
	if path == "":
		return "the 'snapshot' opponent needs a model path (spec key 'model')"
	if _snapshot_models.has(path):
		return ""
	if not FileAccess.file_exists(path):
		return "the snapshot model '%s' does not exist" % path
	var sidecar_data: Dictionary = {}
	var sidecar_path := path.get_basename() + ".bvs.json"
	if FileAccess.file_exists(sidecar_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sidecar_path))
		if parsed is Dictionary:
			sidecar_data = parsed
	var loaded := OnnxPolicyModel.load_bytes(FileAccess.get_file_as_bytes(path), sidecar_data)
	if loaded.model == null:
		return "the snapshot model '%s' was rejected: %s" % [path, loaded.error]
	var mismatch := (loaded.model as OnnxPolicyModel).validate(BvsSchemaV2)
	if mismatch != "":
		return "the snapshot model '%s' does not fit schema 2: %s" % [path, mismatch]
	_snapshot_models[path] = loaded.model
	return ""

func _build_row(index: int, spec: Dictionary, opponent: String, offset: Vector2, reward_config: RewardConfig) -> void:
	var game := (load(GAME_SCENE_PATH) as PackedScene).instantiate() as Game
	game.training = true
	game.position = offset
	game.name = "Row%d" % index
	# Which fighter is the agent: alternating sides so it learns both spawns.
	var agent_side := 1 if index % 2 == 0 else 2
	var fighters: Array[Fighter] = [game.get_node("Fighter1") as Fighter, game.get_node("Fighter2") as Fighter]
	for side in 2:
		var fighter := fighters[side]
		var is_agent := opponent == "self" or side + 1 == agent_side
		var ai := fighter.get_node("AIController2D") as PlayerAIController
		ai.reward_config = reward_config
		if is_agent:
			ai.control_mode = AIController2D.ControlModes.TRAINING
		else:
			ai.control_mode = AIController2D.ControlModes.HUMAN
	add_child(game)
	if opponent != "self":
		var foe := fighters[2 - agent_side]
		if CPU_LEVELS.has(opponent):
			var level: int = CPU_LEVELS[opponent]
			var bot_seed := int(spec.get("seed", BASE_SEED + index))
			foe.set_controller(ScriptedController.new(CpuDifficulty.preset(level as CpuDifficulty.Level), bot_seed))
		else:
			# A frozen model, run by the same PolicyController as in a normal match.
			foe.set_controller(PolicyController.new(_snapshot_models[_snapshot_path(opponent, spec)]))
	games.append(game)
	rows.append({"index": index, "opponent": opponent, "agent_side": 0 if opponent == "self" else agent_side, "game": game})

## Frames the whole arena (for watching a run; headless ignores it).
func _frame_camera(row_count: int, columns: int) -> void:
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera == null or row_count == 0:
		return
	var used_columns := mini(columns, row_count)
	var used_rows := int(ceil(float(row_count) / float(columns)))
	var size := Vector2(used_columns, used_rows) * PITCH
	camera.position = size * 0.5
	var viewport := get_viewport_rect().size
	var fit := minf(viewport.x / size.x, viewport.y / size.y)
	camera.zoom = Vector2.ONE * fit
