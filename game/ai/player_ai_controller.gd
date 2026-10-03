extends AIController2D
class_name PlayerAIController

## The godot_rl_agents side of a fighter in TRAINING mode. It owns no layout of its
## own: the observation, the action space and the action decode all come from the
## bvs-schema module registered for `schema_version` (BvsSchema registry), the same
## code the in-game policy uses, so training and play cannot drift.
##
## Sync calls set_action() once per decision (every ACTION_REPEAT physics frames,
## before the fighters process); the action is stored here and PolicyController
## decodes it frame by frame. Rewards come from a RewardTracker (damage, stock and
## match signals), not from the states.

## The schema this agent observes and acts with. TrainArena sets it from
## BVS_TRAIN_CONFIG.schema_version before the row enters the tree; the default is the
## playable version.
var schema_version: int = BvsSchema.CURRENT_VERSION

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

## The registered schema module of `schema_version`; never a silent default.
func _schema() -> Object:
	var schema := BvsSchema.get_schema(schema_version)
	if schema == null:
		push_error("PlayerAIController: schema version %d is not registered" % schema_version)
	return schema

func get_obs() -> Dictionary:
	var schema := _schema()
	var game := _player.get_parent() as Game if _player != null else null
	if game == null or schema == null:
		if game == null:
			push_error("PlayerAIController: the fighter is not inside a Game, no observation")
		var empty := PackedFloat32Array()
		empty.resize(int(schema.OBS_DIM) if schema != null else 0)
		return {"obs": Array(empty)}
	var my_index := 1 if game.fighter_2 == _player else 0
	return {"obs": Array(schema.build_obs(game.get_state_snapshot(), my_index))}

func get_reward() -> float:
	if reward_tracker != null:
		reward_tracker.on_decision()
	return reward

func get_action_space() -> Dictionary:
	var schema := _schema()
	return schema.action_space() if schema != null else {}

func set_action(action) -> void:
	var schema := _schema()
	if schema == null:
		return
	latest_action = schema.action_from_dict(action)
	action_seq += 1
