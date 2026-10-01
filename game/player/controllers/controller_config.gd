class_name ControllerConfig
extends Resource

## Describes which controller a fighter should use and builds it. Character
## select produces one per player; SceneManager applies it after the match
## scene is instantiated (and keeps it for rematches).

enum Kind { HUMAN, CPU, POLICY }

@export var kind: Kind = Kind.HUMAN
## CPU difficulty (0 easy, 1 normal, 2 hard). Becomes CpuDifficulty.Level once
## the scripted CPU lands.
@export var difficulty: int = 1
## Optional CpuDifficulty override (typed as Resource until that class exists).
@export var difficulty_resource: Resource
## Only used for Kind.POLICY. Empty keeps whatever the AI controller already has.
@export var onnx_model_path: String = ""

func build(fighter: Fighter) -> FighterController:
	match kind:
		Kind.POLICY:
			# The ONNX mode is only ever set by an explicit selection.
			var ai := fighter.ai_controller_2d
			ai.control_mode = AIController2D.ControlModes.ONNX_INFERENCE
			if onnx_model_path != "":
				ai.onnx_model_path = onnx_model_path
			return PolicyController.new()
		Kind.CPU:
			# TODO(S3): return a ScriptedController. Human placeholder until then.
			return HumanController.new()
		_:
			return HumanController.new()
