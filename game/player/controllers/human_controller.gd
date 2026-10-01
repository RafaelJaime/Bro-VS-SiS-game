class_name HumanController
extends FighterController

## Maps the P1_*/P2_* keyboard actions to a FighterIntent. Also owns the
## double-tap dash detection that used to live in the Idle state.

const DOUBLE_TAP_WINDOW := 0.30

var _last_tap_dir: int = 0
var _last_tap_time: float = 0.0

func sample(_delta: float) -> FighterIntent:
	var intent := FighterIntent.new()
	if fighter == null:
		return intent

	var prefix := "P1_" if fighter.control_scheme == Fighter.PlayerNumber.JUGADOR1 else "P2_"
	var left := prefix + "left"
	var right := prefix + "right"
	var jump := prefix + "jump"
	var punch := prefix + "punch"
	var protect := prefix + "protect"
	var shoot := prefix + "shoot"

	intent.move_x = Input.get_axis(left, right)
	intent.jump_pressed = Input.is_action_just_pressed(jump)
	intent.jump_held = Input.is_action_pressed(jump)
	intent.attack_pressed = Input.is_action_just_pressed(punch)
	intent.throw_pressed = Input.is_action_just_pressed(shoot)
	intent.block_pressed = Input.is_action_just_pressed(protect)
	intent.block_held = Input.is_action_pressed(protect)
	intent.dash_pressed = _detect_double_tap(left, right)
	# attack_held / attack_released / aim / special_pressed stay neutral until S5.
	return intent

func kind_name() -> String:
	return "human"

func _detect_double_tap(left: String, right: String) -> bool:
	var tap := 0
	if Input.is_action_just_pressed(left):
		tap = -1
	elif Input.is_action_just_pressed(right):
		tap = 1
	if tap == 0:
		return false

	var now := Time.get_ticks_msec() / 1000.0
	if tap == _last_tap_dir and now - _last_tap_time < DOUBLE_TAP_WINDOW:
		_last_tap_dir = 0
		_last_tap_time = 0.0
		return true

	_last_tap_dir = tap
	_last_tap_time = now
	return false
