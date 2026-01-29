extends State
class_name Motion

@export var state_machine: PlayerStateMachine
@export var available_actions: Array[String] = []

signal velocity_updated(vel: Vector2)
signal animation_state_changed(state: String)

const SPEED = 300.0
const JUMP_VELOCITY = -600.0
const ACCELERATION: float = 1000

var gravity: float = 500

func _ready() -> void:
	velocity_updated.connect(owner.set_velocity_from_motion)

func _enter() -> void:
	print(name)
	animation_state_changed.emit(name.to_lower())

func _update(_delta: float) -> void:
	# Procesar acciones de IA automáticamente
	if owner.ai_controller_2d and owner.ai_controller_2d.control_mode != AIController2D.ControlModes.HUMAN:
		process_ai_transitions()

func process_ai_transitions() -> void:
	var ai = owner.ai_controller_2d as PlayerAIController

	# Si ya estamos en una acción importante, no permitir nuevas transiciones automáticas
	if state_machine.current_state.name in ["Jump", "Punch", "Shoot", "Fall", "Protect"]:
		return

	# Recorrer las acciones disponibles y ejecutarlas si la IA lo indica
	for action in available_actions:
		var action_value = 0.0
		
		match action.to_lower():
			"jump":
				action_value = ai.jump_action
			"punch":
				action_value = ai.attack_action
			"shoot":
				action_value = ai.shoot_action
			"protect":
				action_value = ai.protect_action
		
		if action_value > 0.5:
			# Verificar condiciones específicas para algunas acciones
			if action == "Jump" and not is_on_floor():
				continue  # No saltar si ya estás en el aire
			
			finished.emit(action.capitalize())
			return

	# Movimiento básico
	if ai.move_left_action > 0.5 or ai.move_right_action > 0.5:
		if name != "Run":
			finished.emit("Run")
	elif name == "Run":
		finished.emit("Idle")

func set_direction() -> void:
	if owner.ai_controller_2d and owner.ai_controller_2d.control_mode != AIController2D.ControlModes.HUMAN:
		set_ai_direction()
	else:
		set_manual_direction()

func set_ai_direction() -> void:
	var ai = owner.ai_controller_2d
	var ai_direction = Vector2.ZERO
	
	if ai.move_left_action > 0.5:
		ai_direction.x -= 1.0
	if ai.move_right_action > 0.5:
		ai_direction.x += 1.0
	
	state_machine.direction = ai_direction.normalized()

func set_manual_direction() -> void:
	match owner.control_scheme:
		0:
			state_machine.input_dir = Input.get_vector("P1_left", "P1_right", "ui_up", "ui_down")
		1:
			state_machine.input_dir = Input.get_vector("P2_left", "P2_right", "ui_up", "ui_down")
	state_machine.direction = (owner.global_transform.x * Vector2(state_machine.input_dir.x, state_machine.input_dir.y)).normalized()

func _state_input(event: InputEvent) -> void:
	if owner.ai_controller_2d and owner.ai_controller_2d.control_mode != AIController2D.ControlModes.HUMAN:
		return
	
	var prefix = "P1_" if owner.control_scheme == 0 else "P2_"
	
	for action in available_actions:
		var action_name = prefix + action.to_lower()
		if event.is_action_pressed(action_name):
			finished.emit(action.capitalize())

func calculate_velocity(_speed: float, _direction: Vector2, delta: float) -> void:
	state_machine.velocity.x = move_toward(state_machine.velocity.x, _direction.x * _speed, ACCELERATION * delta)
	velocity_updated.emit(state_machine.velocity)

func calculate_gravity(delta: float) -> void:
	if not owner.is_on_floor():
		state_machine.velocity.y += gravity * delta

func is_on_floor() -> bool: 
	return owner.is_on_floor()
