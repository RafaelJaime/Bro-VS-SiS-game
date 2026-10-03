class_name PolicyController
extends FighterController

## Fighter controller of an RL policy, always through the bvs-schema-2 module: the
## observation comes from BvsSchemaV2.build_obs and the actions are decoded by
## BvsActionDecoderV2 (held flags last the whole decision window, presses fire on
## its first frame; `attack_held` stays false). It has no layout, threshold or
## constant of its own.
##
## Two sources of decisions:
##   - With a model (`PolicyController.new(model)`) it runs the interpreter itself:
##     every ACTION_REPEAT sampled frames it builds the observation from the Game
##     snapshot, infers, takes the argmax per branch and opens a decoder window.
##     No Sync node is needed (desktop and web). Fighters are staggered: the
##     fighter index delays the decision frames, so two policy fighters never infer
##     on the same frame.
##   - Without a model, in TRAINING, it decodes the branch indices PlayerAIController
##     received from Sync (`latest_action` / `action_seq`).
## With neither it returns a neutral intent and reports one error. A model that
## fails at run time does the same: one error, neutral intents from then on.

var model: OnnxPolicyModel
## Frames the first decision is delayed by (the fighter index: 0 or 1).
var phase_offset := 0
## Number of inferences run so far.
var decisions := 0
## The observation and the branch indices of the latest decision (read-only for tests/eval).
var last_obs := PackedFloat32Array()
var last_action := PackedInt32Array()
## The run-time inference error, or "" while the model works.
var error := ""

var _decoder := BvsActionDecoderV2.new()
var _ticks := 0
var _my_index := -1
var _seen_seq := 0
var _reported_missing_source := false

func _init(policy_model: OnnxPolicyModel = null) -> void:
	model = policy_model

func sample(_delta: float) -> FighterIntent:
	if fighter == null:
		return FighterIntent.new()
	if model != null:
		return _sample_model()
	return _sample_training()

func _sample_model() -> FighterIntent:
	if error != "":
		return FighterIntent.new()
	var game := fighter.get_parent() as Game
	if game == null:
		return _fail("the fighter is not inside a Game")
	if _my_index < 0:
		_my_index = 1 if game.fighter_2 == fighter else 0
		phase_offset = _my_index
	# Decision frames are ticks phase_offset, phase_offset + 4, ... : the same
	# cadence for every fighter, shifted by the fighter index.
	if posmod(_ticks - phase_offset, BvsSchemaV2.ACTION_REPEAT) == 0:
		var obs := BvsSchemaV2.build_obs(game.get_state_snapshot(), _my_index)
		var result := model.infer_checked(obs)
		if result.error != "":
			return _fail("inference failed: %s" % result.error)
		last_obs = obs
		last_action = BvsSchemaV2.argmax_branches(result.logits)
		_decoder.begin_window(last_action)
		decisions += 1
	_ticks += 1
	return _decoder.frame(fighter)

func _sample_training() -> FighterIntent:
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

## Latches the first run-time error: reported once, neutral intents afterwards.
func _fail(message: String) -> FighterIntent:
	error = message
	push_error("PolicyController: %s, the fighter stays neutral" % message)
	return FighterIntent.new()

func kind_name() -> String:
	return "policy"
