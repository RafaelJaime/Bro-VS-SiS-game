extends State
class_name Motion

@export var state_machine: StateMachine

signal velocity_updated(vel: Vector2)
signal animation_state_changed(state: String)

const SPEED = 300.0
const JUMP_VELOCITY = -600.0
const ACCELERATION: float = 1000

var gravity: float = 1000

func _ready() -> void:
	velocity_updated.connect(owner.set_velocity_from_motion)

func _enter() -> void:
	animation_state_changed.emit(name.to_lower())

func set_direction() -> void:
	match owner.control_scheme:
		0:
			state_machine.input_dir = Input.get_vector("P1_left", "P1_right", "ui_up", "ui_down")
		1:
			state_machine.input_dir = Input.get_vector("P2_left", "P2_right", "ui_up", "ui_down")
	state_machine.direction = (owner.global_transform.x * Vector2(state_machine.input_dir.x, state_machine.input_dir.y)).normalized()

func calculate_velocity(_speed: float, _direction: Vector2, delta: float) -> void:
	state_machine.velocity.x = move_toward(state_machine.velocity.x, _direction.x*_speed, ACCELERATION*delta)
	
	velocity_updated.emit(state_machine.velocity)

func calculate_gravity(delta: float) -> void:
	if not owner.is_on_floor():
		state_machine.velocity.y += gravity * delta

func is_on_floor() -> bool: 
	return owner.is_on_floor()
