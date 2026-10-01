extends State
class_name Motion

@export var state_machine: PlayerStateMachine
@export var available_actions: Array[String] = []

signal velocity_updated(vel: Vector2)
signal animation_state_changed(state: String)

# Tuning is read from the owner's FighterProfile; no state hardcodes it.
var profile: FighterProfile:
	get:
		return owner.profile

var gravity: float:
	get:
		return owner.profile.gravity

func _ready() -> void:
	velocity_updated.connect(owner.set_velocity_from_motion)

func _enter() -> void:
	animation_state_changed.emit(name.to_lower())

func _update(_delta: float) -> void:
	return

# Fixed priority; the per-state `available_actions` and `can_enter()` gate it.
# Relative order jump > punch > protect > shoot matches the old AI order.
const ACTION_PRIORITY: Array[String] = ["recovery", "dash", "jump", "punch", "protect", "shoot"]

## Reads owner.intent and emits at most one transition. Returns true when it did.
func handle_actions() -> bool:
	var intent: FighterIntent = owner.intent
	for action in ACTION_PRIORITY:
		if not available_actions.has(action) or not _is_requested(action, intent):
			continue
		var target_name := action.capitalize()
		var target: State = state_machine.state_map.get(target_name)
		if target == null or not target.can_enter():
			continue
		finished.emit(target_name)
		return true
	return false

func _is_requested(action: String, intent: FighterIntent) -> bool:
	match action:
		"recovery":
			return intent.special_pressed
		"dash":
			return intent.dash_pressed
		"jump":
			return intent.jump_pressed
		"punch":
			return intent.attack_pressed
		"protect":
			return intent.block_pressed
		"shoot":
			return intent.throw_pressed
	return false

func move_axis() -> float:
	return owner.intent.move_x

func set_direction() -> void:
	state_machine.direction = Vector2(move_axis(), 0.0).normalized()

func exit_to_neutral() -> void:
	finished.emit("Idle" if is_on_floor() else "Fall")

func calculate_velocity(_speed: float, _direction: Vector2, delta: float) -> void:
	state_machine.velocity.x = move_toward(state_machine.velocity.x, _direction.x * _speed, profile.acceleration * delta)
	velocity_updated.emit(state_machine.velocity)

func calculate_gravity(delta: float) -> void:
	if not owner.is_on_floor():
		state_machine.velocity.y += gravity * delta

func is_on_floor() -> bool: 
	return owner.is_on_floor()
