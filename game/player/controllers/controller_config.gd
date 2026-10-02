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
## Only used for Kind.POLICY: the loaded model handle (parsed graph, sidecar, repo and
## revision). Held in memory, not a resource property, so a rematch keeps it with no
## new download. Null means the selection has no usable model: `error_message`
## says why and the match must not start with it.
var model: OnnxPolicyModel
var error_message: String = ""

## Convenience constructors, used by character select and the tests.
static func human() -> ControllerConfig:
	return ControllerConfig.new()

static func cpu(level: int = CpuDifficulty.Level.NORMAL) -> ControllerConfig:
	var config := ControllerConfig.new()
	config.kind = Kind.CPU
	config.difficulty = level
	return config

## A policy fighter driven by `policy`. A null model is an explicit error state
## (`error_message`), never a scripted CPU.
static func policy_model(policy: OnnxPolicyModel, failure: String = "") -> ControllerConfig:
	var config := ControllerConfig.new()
	config.kind = Kind.POLICY
	config.model = policy
	if policy == null:
		config.error_message = failure if failure != "" else "No model is loaded for this player"
	return config

## False for a Policy selection that has no usable model: it must not start a match.
func is_playable() -> bool:
	return kind != Kind.POLICY or model != null

func build(fighter: Fighter) -> FighterController:
	match kind:
		Kind.POLICY:
			# No CPU fallback and no AIController2D mode write: a Policy selection
			# either carries a model, or yields a policy fighter that reports its
			# error once and stays neutral.
			if model == null:
				push_error("ControllerConfig: no model for the policy fighter (%s)" % error_message)
			return PolicyController.new(model)
		Kind.CPU:
			return _build_cpu()
		_:
			return HumanController.new()

func _build_cpu() -> ScriptedController:
	var resolved: CpuDifficulty = difficulty_resource
	if resolved == null:
		resolved = CpuDifficulty.preset(CpuDifficulty.level_from_int(difficulty))
	return ScriptedController.new(resolved)
