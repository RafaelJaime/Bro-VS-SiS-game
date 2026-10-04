extends RefCounted
class_name ShieldMeter

## A fighter's shield meter. It is owned by the Fighter and ticked once per
## physics frame (`Fighter._physics_process`), so it regenerates in every state,
## not only while a state is active. Everything is counted in physics ticks
## (CombatClock), so hit-stop never changes a duration.
##
## Holding drains it at `max / break_ticks` per tick. Releasing starts a delay of
## `regen_delay_ticks`, after which it refills at `max / regen_ticks` per tick.
## While the fighter is dizzy it neither drains nor regenerates.

## Below this the meter counts as empty (float drift of the per-tick drain).
const EMPTY_EPSILON := 0.0001

var value: float = 100.0
var max_value: float = 100.0
## Continuous hold length in ticks (0 when released); the reward penalty and the
## HUD read it.
var held_ticks: int = 0

var _drain_per_tick: float = 0.0
var _regen_per_tick: float = 0.0
var _regen_delay_ticks: int = 0
var _delay_left: int = 0

func setup(profile: FighterProfile) -> void:
	max_value = profile.shield_max
	_drain_per_tick = max_value / float(maxi(1, CombatClock.ticks(profile.shield_break_time)))
	_regen_per_tick = max_value / float(maxi(1, CombatClock.ticks(profile.shield_regen_time)))
	_regen_delay_ticks = CombatClock.ticks(profile.shield_regen_delay)
	refill()

## Advances one tick. Returns true when the hold drain emptied the meter on this
## tick (the Fighter then breaks the shield).
func tick(holding: bool, suspended: bool) -> bool:
	if suspended:
		held_ticks = 0
		return false
	if holding:
		held_ticks += 1
		_delay_left = _regen_delay_ticks
		if value <= EMPTY_EPSILON:
			return false
		value = _clamped(value - _drain_per_tick)
		return value <= EMPTY_EPSILON
	held_ticks = 0
	if _delay_left > 0:
		_delay_left -= 1
		return false
	value = _clamped(value + _regen_per_tick)
	return false

## Takes `amount` off the meter (a blocked hit) and restarts the regeneration
## delay. Returns true when it emptied the meter.
func absorb(amount: float) -> bool:
	value = _clamped(value - maxf(0.0, amount))
	_delay_left = _regen_delay_ticks
	return value <= EMPTY_EPSILON

## Spends `cost` for raising the shield and restarts the regeneration delay. It
## never empties the meter by itself (a raise cannot break the shield).
func pay_raise(cost: float) -> void:
	value = maxf(value - maxf(0.0, cost), minf(value, 1.0))
	_delay_left = _regen_delay_ticks

func refill() -> void:
	value = max_value
	held_ticks = 0
	_delay_left = 0

## Sets the meter to a fraction of the maximum (the dizzy recovery) and restarts
## the regeneration delay.
func set_ratio(ratio: float) -> void:
	value = _clamped(max_value * ratio)
	_delay_left = _regen_delay_ticks

func ratio() -> float:
	return value / max_value if max_value > 0.0 else 0.0

func is_empty() -> bool:
	return value <= EMPTY_EPSILON

func _clamped(amount: float) -> float:
	var clamped := clampf(amount, 0.0, max_value)
	return 0.0 if clamped <= EMPTY_EPSILON else clamped
