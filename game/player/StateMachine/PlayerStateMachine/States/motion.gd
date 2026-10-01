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
			# The jump buffer (Fighter) remembers a press for a few frames.
			return owner.jump_buffer_timer > 0.0
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
	var accel := profile.ground_acceleration if is_on_floor() else profile.air_acceleration
	state_machine.velocity.x = move_toward(state_machine.velocity.x, _direction.x * _speed, accel * delta)
	velocity_updated.emit(state_machine.velocity)

## Adds gravity (scaled by `scale`), faster while falling and capped at the
## profile's max fall speed. On the floor it only drops a stale downward speed,
## so walking off a ledge starts a fall from zero, not from the last landing.
func calculate_gravity(delta: float, scale: float = 1.0) -> void:
	var velocity_y: float = state_machine.velocity.y
	if owner.is_on_floor():
		if velocity_y > 0.0:
			state_machine.velocity.y = 0.0
		return
	var pull := gravity * scale
	if velocity_y > 0.0:
		pull *= profile.fall_gravity_multiplier
	if velocity_y < profile.max_fall_speed:
		state_machine.velocity.y = minf(velocity_y + pull * delta, profile.max_fall_speed)

func is_on_floor() -> bool: 
	return owner.is_on_floor()
