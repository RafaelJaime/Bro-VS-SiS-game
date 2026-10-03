extends RefCounted
class_name CombatClock

## Gameplay timers (shield regen delay, dizzy, air dodge, sudden-death grace and
## escalation, the training safety cap) count physics ticks, never `Timer` nodes
## or `delta`. Hit-stop scales `Engine.time_scale` (so `delta`) but not the number
## of `_physics_process` calls, and training speed-up raises the tick rate together
## with the time scale, so one tick is always 1/60 of a game second.

const TICKS_PER_SECOND := 60

## Whole ticks for a duration in game seconds (never negative).
static func ticks(seconds: float) -> int:
	return maxi(0, roundi(seconds * TICKS_PER_SECOND))

## Game seconds for a tick count.
static func seconds(tick_count: int) -> float:
	return float(tick_count) / float(TICKS_PER_SECOND)
