extends AIController2D
class_name PlayerAIController

## The godot_rl_agents side of a fighter in TRAINING mode. It owns no layout of its
## own: the observation, the action space and the action decode all come from the
## bvs-schema-2 module (BvsSchemaV2 / BvsActionDecoderV2), the same code the
## in-game policy uses, so training and play cannot drift.
##
## Sync calls set_action() once per decision (every ACTION_REPEAT physics frames,
## before the fighters process); the action is stored here and PolicyController
## decodes it frame by frame. Rewards come from a RewardTracker (damage, stock and
## match signals), not from the states.

## Branch indices of the latest decision (empty before the first one).
var latest_action := PackedInt32Array()
## Incremented on every set_action, so a controller can tell a new decision.
var action_seq := 0
## Weights for the tracker; the training arena sets it before the row enters the
## tree (null keeps the defaults).
var reward_config: RewardConfig
## Created in TRAINING mode only.
var reward_tracker: RewardTracker

func _ready() -> void:
	# Do not override control_mode here: the scene (player.tscn = HUMAN) and the
	# training arena / SceneManager / ControllerConfig decide it. The old auto-ONNX
	# logic made a stale user://Agent{N}.onnx hijack human input.
	super._ready()
	if control_mode == ControlModes.TRAINING and _player is Fighter:
		reward_tracker = RewardTracker.new()
		reward_tracker.setup(self, _player as Fighter, reward_config)

func get_obs() -> Dictionary:
	var game := _player.get_parent() as Game if _player != null else null
	if game == null:
		push_error("PlayerAIController: the fighter is not inside a Game, no observation")
		var empty := PackedFloat32Array()
		empty.resize(BvsSchemaV2.OBS_DIM)
		return {"obs": Array(empty)}
	var my_index := 1 if game.fighter_2 == _player else 0
	return {"obs": Array(BvsSchemaV2.build_obs(game.get_state_snapshot(), my_index))}

func get_reward() -> float:
	if reward_tracker != null:
		reward_tracker.on_decision()
	return reward

func get_action_space() -> Dictionary:
	return BvsSchemaV2.action_space()

func set_action(action) -> void:
	latest_action = BvsSchemaV2.action_from_dict(action)
	action_seq += 1
