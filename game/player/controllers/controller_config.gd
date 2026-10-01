class_name ControllerConfig
extends Resource

## Describes which controller a fighter should use and builds it. Character
## select produces one per player; SceneManager applies it after the match
## scene is instantiated (and keeps it for rematches).

enum Kind { HUMAN, CPU, POLICY }

@export var kind: Kind = Kind.HUMAN
## CPU difficulty as a CpuDifficulty.Level value (0 easy, 1 normal, 2 hard).
@export var difficulty: int = CpuDifficulty.Level.NORMAL
## Optional CpuDifficulty override: when set it replaces the preset, so a designer
## can drop in a `.tres` with no script change.
@export var difficulty_resource: CpuDifficulty
## Only used for Kind.POLICY. Empty keeps whatever the AI controller already has.
@export var onnx_model_path: String = ""

## Convenience constructors, used by character select and the tests.
static func human() -> ControllerConfig:
	return ControllerConfig.new()

static func cpu(level: int = CpuDifficulty.Level.NORMAL) -> ControllerConfig:
	var config := ControllerConfig.new()
	config.kind = Kind.CPU
	config.difficulty = level
	return config

static func policy(model_path: String = "") -> ControllerConfig:
	var config := ControllerConfig.new()
	config.kind = Kind.POLICY
	config.onnx_model_path = model_path
	return config

func build(fighter: Fighter) -> FighterController:
	match kind:
		Kind.POLICY:
			# The ONNX mode is only ever set by an explicit selection. A model that
			# is not on disk (a download still running, a failed one) falls back to
			# the scripted CPU instead of leaving the fighter idle.
			if onnx_model_path != "" and not FileAccess.file_exists(onnx_model_path):
				push_warning("ControllerConfig: ONNX model missing at %s, using the scripted CPU" % onnx_model_path)
				return _build_cpu()
			var ai := fighter.ai_controller_2d
			ai.control_mode = AIController2D.ControlModes.ONNX_INFERENCE
			if onnx_model_path != "":
				ai.onnx_model_path = onnx_model_path
			return PolicyController.new()
		Kind.CPU:
			return _build_cpu()
		_:
			return HumanController.new()

func _build_cpu() -> ScriptedController:
	var resolved: CpuDifficulty = difficulty_resource
	if resolved == null:
		resolved = CpuDifficulty.preset(CpuDifficulty.level_from_int(difficulty))
	return ScriptedController.new(resolved)
