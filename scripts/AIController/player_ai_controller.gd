extends AIController2D
class_name PlayerAIController

var move_left_action: float = 0.0
var move_right_action: float = 0.0
var jump_action: float = 0.0
var attack_action: float = 0.0
var shoot_action: float = 0.0
var protect_action: float = 0.0

func _ready() -> void:
	var player_id: int = 0 if owner.control_scheme == 0 else 1
	
	if ModelManager.model_exists(player_id):
		print("Voy a hacer load del player ", player_id)
		print("Modelo existe: ", FileAccess.file_exists(ModelManager.get_model_path(player_id)))
		onnx_model_path = ModelManager.get_model_path(player_id)
		control_mode = AIController2D.ControlModes.ONNX_INFERENCE
		print("Modelo ONNX cargado para jugador: ", player_id)
	else:
		print("No hay modelo para jugador: ", player_id)
		control_mode = AIController2D.ControlModes.HUMAN

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
