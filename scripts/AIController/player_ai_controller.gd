extends AIController2D
class_name PlayerAIController

var move_left_action: float = 0.0
var move_right_action: float = 0.0
var jump_action: float = 0.0
var attack_action: float = 0.0
var shoot_action: float = 0.0
var protect_action: float = 0.0

func _ready() -> void:
	# Do not override control_mode here: the scene (player.tscn = HUMAN,
	# train.tscn = TRAINING) and SceneManager/ControllerConfig decide it. The
	# old auto-ONNX logic made a stale user://Agent{N}.onnx hijack human input.
	super._ready()

func get_obs() -> Dictionary:
	var obs = []
	
	# Player position and velocity
	obs.append(_player.global_position.x / 1000.0)
	obs.append(_player.global_position.y / 1000.0)
	obs.append(_player.velocity.x / 300.0)
	obs.append(_player.velocity.y / 800.0)
	
	# Ground detection
	obs.append(1.0 if _player.is_on_floor() else 0.0)
	
	# Find the opponent (other CharacterBody2D that is not this player)
	var opponent = _player.enemy
	
	if opponent:
		# Opponent position and velocity
		obs.append(opponent.global_position.x / 1000.0)
		obs.append(opponent.global_position.y / 1000.0)
		obs.append(opponent.velocity.x / 300.0)
		obs.append(opponent.velocity.y / 800.0)
		
		# Relative position to opponent
		var relative_pos = opponent.global_position - _player.global_position
		obs.append(relative_pos.x / 1000.0)
		obs.append(relative_pos.y / 1000.0)
		
		# Distance to opponent
		obs.append(_player.global_position.distance_to(opponent.global_position) / 1000.0)
		
		# Opponent ground detection
		obs.append(1.0 if opponent.is_on_floor() else 0.0)
	else:
		# Fill with zeros if no opponent found
		for i in range(8):
			obs.append(0.0)
	
	return {"obs": obs}

func get_reward() -> float:
	return reward

func get_action_space() -> Dictionary:
	return {
		"move_left_action": {
			"size": 1,
			"action_type": "continuous"
		},
		"move_right_action": {
			"size": 1,
			"action_type": "continuous"
		},
		"jump_action": {
			"size": 1,
			"action_type": "continuous"
		},
		"attack_action": {
			"size": 1,
			"action_type": "continuous"
		},
		"shoot_action": {
			"size": 1,
			"action_type": "continuous"
		},
		"protect_action": {
			"size": 1,
			"action_type": "continuous"
		}
	}

func set_action(action) -> void:
	move_left_action = clamp(action["move_left_action"][0], 0.0, 1.0)
	move_right_action = clamp(action["move_right_action"][0], 0.0, 1.0)
	jump_action = clamp(action["jump_action"][0], 0.0, 1.0)
	attack_action = clamp(action["attack_action"][0], 0.0, 1.0)
	shoot_action = clamp(action["shoot_action"][0], 0.0, 1.0)
	protect_action = clamp(action["protect_action"][0], 0.0, 1.0)
