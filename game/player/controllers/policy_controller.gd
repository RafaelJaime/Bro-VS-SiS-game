class_name PolicyController
extends FighterController

## Fighter controller of an RL policy. In training it decodes the branch indices
## PlayerAIController received from Sync, through the bvs-schema-2 decoder
## (BvsActionDecoderV2): held flags last the whole decision window, presses fire on
## its first frame. It has no layout, threshold or constant of its own.
##
## The model inference path (play without Sync) arrives with the in-game ONNX
## interpreter; until then a policy fighter with no training source gets a neutral
## intent and one error.

var _decoder := BvsActionDecoderV2.new()
var _seen_seq := 0
var _reported_missing_source := false

func sample(_delta: float) -> FighterIntent:
	if fighter == null:
		return FighterIntent.new()
	var ai := fighter.ai_controller_2d as PlayerAIController
	if ai == null or ai.control_mode != AIController2D.ControlModes.TRAINING:
		if not _reported_missing_source:
			_reported_missing_source = true
			push_error("PolicyController: no action source (not a TRAINING agent and no model), the fighter stays neutral")
		return FighterIntent.new()
	if ai.action_seq != _seen_seq:
		_seen_seq = ai.action_seq
		_decoder.begin_window(ai.latest_action)
	return _decoder.frame(fighter)

func kind_name() -> String:
	return "policy"
