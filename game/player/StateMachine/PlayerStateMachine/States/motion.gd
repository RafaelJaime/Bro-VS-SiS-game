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
# Relative order jump > punch > protect > shoot matches the old AI order. The
# block key is "protect" on the ground and "air_dodge" in the air (a state lists
# only the one it allows).
const ACTION_PRIORITY: Array[String] = ["recovery", "dash", "jump", "punch", "protect", "air_dodge", "shoot"]
# While holding food a throw outranks punch and block (only recovery, dash and
# jump still win), so a punch pressed in the same frame never masks it.
const ACTION_PRIORITY_HOLDING: Array[String] = ["recovery", "dash", "jump", "shoot", "punch", "protect", "air_dodge"]

## Reads owner.intent and emits at most one transition. Returns true when it did.
func handle_actions() -> bool:
	var intent: FighterIntent = owner.intent
	var priority := ACTION_PRIORITY_HOLDING if owner.is_holding_food() else ACTION_PRIORITY
	for action in priority:
		if not available_actions.has(action) or not _is_requested(action, intent):
			continue
		var target_name := action.to_pascal_case()
		var target: State = state_machine.state_map.get(target_name)
		if target == null or not target.can_enter():
			continue
		# One press, one action: any other transition spends the remembered punch.
		if action != "punch":
			owner.clear_attack_buffer()
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
			# The attack buffer (Fighter) remembers a press for a few ticks.
			return owner.attack_buffer_ticks > 0
		"protect", "air_dodge":
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
	var cap := profile.fast_fall_speed if owner.fast_falling else profile.max_fall_speed
	if velocity_y < cap:
		state_machine.velocity.y = minf(velocity_y + pull * delta, cap)

func is_on_floor() -> bool: 
	return owner.is_on_floor()
