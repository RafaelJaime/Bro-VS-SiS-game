class_name HumanController
extends FighterController

## Maps the P1_*/P2_* keyboard actions to a FighterIntent. Also owns the
## double-tap dash detection that used to live in the Idle state. The up and
## down actions give the aim (directional punches, the recovery chord).

const DOUBLE_TAP_WINDOW := 0.30

var _last_tap_dir: int = 0
## Game time of the last tap, in seconds of physics ticks. The window follows the
## simulation clock, not the wall clock, so it does not depend on how fast the
## frames are produced (a recording or a test running faster than real time
## would otherwise turn every second step into a dash).
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
	var up := prefix + "up"
	var down := prefix + "down"

	intent.move_x = Input.get_axis(left, right)
	intent.jump_pressed = Input.is_action_just_pressed(jump)
	intent.jump_held = Input.is_action_pressed(jump)
	intent.attack_pressed = Input.is_action_just_pressed(punch)
	intent.throw_pressed = Input.is_action_just_pressed(shoot)
	intent.block_pressed = Input.is_action_just_pressed(protect)
	intent.block_held = Input.is_action_pressed(protect)
	intent.dash_pressed = _detect_double_tap(left, right)
	intent.attack_held = Input.is_action_pressed(punch)
	intent.attack_released = Input.is_action_just_released(punch)
	intent.aim = _aim(Input.is_action_pressed(up), Input.is_action_pressed(down), intent.move_x)
	# The recovery chord: up + punch. The state machine decides what it means (a
	# recovery burst in the air when available, otherwise an ordinary punch).
	intent.special_pressed = intent.attack_pressed and intent.aim == FighterIntent.Aim.UP
	return intent

## Up wins over side, down over side; up and down together cancel out.
static func _aim(up_held: bool, down_held: bool, move_x: float) -> FighterIntent.Aim:
	if up_held and not down_held:
		return FighterIntent.Aim.UP
	if down_held and not up_held:
		return FighterIntent.Aim.DOWN
	if not is_zero_approx(move_x):
		return FighterIntent.Aim.SIDE
	return FighterIntent.Aim.NEUTRAL

func kind_name() -> String:
	return "human"

static func _game_time() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)

func _detect_double_tap(left: String, right: String) -> bool:
	var tap := 0
	if Input.is_action_just_pressed(left):
		tap = -1
	elif Input.is_action_just_pressed(right):
		tap = 1
	if tap == 0:
		return false

	var now := _game_time()
	if tap == _last_tap_dir and now - _last_tap_time < DOUBLE_TAP_WINDOW:
		_last_tap_dir = 0
		_last_tap_time = 0.0
		return true

	_last_tap_dir = tap
	_last_tap_time = now
	return false
