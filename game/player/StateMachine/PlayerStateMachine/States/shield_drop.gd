extends Motion
class_name ShieldDrop

## Shield drop lag (Smash): the fighter let go of the shield and cannot act until
## `shield_drop_lag` ticks have passed. The state lists no actions, so attack, run,
## dash, throw and a new shield are all ignored (those inputs are edges and are not
## buffered); only a jump pressed in the last few frames fires once it ends. It is
## not Protect, so a hit that lands now is a normal full hit. The bubble shrinks
## away over the lag (see ShieldBubble).

var ticks_left: int = 0
var _total_ticks: int = 1

func _enter() -> void:
	super._enter()
	_total_ticks = maxi(1, CombatClock.ticks(profile.shield_drop_lag))
	ticks_left = _total_ticks

func _update(delta: float) -> void:
	super._update(delta)
	calculate_gravity(delta)
	# Still planted, like the shield it just dropped.
	calculate_velocity(0.0, Vector2.ZERO, delta)
	ticks_left -= 1
	if ticks_left <= 0:
		exit_to_neutral()

## 0 at the start of the lag, 1 when it is over.
func progress() -> float:
	return 1.0 - float(ticks_left) / float(_total_ticks)
