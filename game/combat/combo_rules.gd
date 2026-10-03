class_name ComboRules
extends Resource

## Every number of the combo safeguards, in one tunable resource shared by both
## fighters (asymmetric anti-infinite rules would invite balance exploits). The
## defaults live in `combo_rules.tres`; nothing here is hard-coded in the states.
## Together they bound every combo: the hit count (hard cap), the hitstun a single
## hit can add (decay and the time cap) and how far a victim is pushed (growth).

## The Nth hit of a combo launches the victim and makes it invulnerable at once.
@export var hard_cap_hits: int = 6
## From this combo hit on, each hit's hitstun is multiplied by `hitstun_decay` once
## more (hit 4 once, hit 5 twice, ...). Hits before it are not decayed.
@export var decay_from_hit: int = 4
@export_range(0.0, 1.0) var hitstun_decay: float = 0.8
## Knockback is multiplied by this once per combo hit after the first (cumulative).
@export var knockback_growth: float = 1.1
## A combo may keep a victim in hitstun for at most this many seconds after its first
## hit (90 ticks): later hits are clamped to what is left, then launch.
@export var time_cap: float = 1.5
## Once this few ticks of the time cap are left, the hit launches instead of stunning.
@export var min_combo_stun_ticks: int = 4
## The knockback of a capped hit when it is stronger than the hit's own (x is the
## strength away from the attacker, y is up when negative).
@export var cap_launch_knockback: Vector2 = Vector2(260.0, -360.0)

## The time cap in physics ticks.
func time_cap_ticks() -> int:
	return CombatClock.ticks(time_cap)
