class_name ComboTracker
extends RefCounted

## The combo a fighter is taking (a victim-side tracker, like the ShieldMeter it sits
## beside). A combo is every hit that lands while the victim is still in `Hurt`; it
## ends the tick after the victim leaves `Hurt`. `register` is called by Combat for
## each FULL hit, before the victim changes state, and returns the Scale record that
## `Hurt` applies (knockback growth, hitstun decay, the time-cap clamp and the hard
## cap launch). Everything counts physics ticks, never `Timer` nodes or delta.
## Observers (HUD, metrics, rewards) read the victim's `combo_updated` and
## `combo_ended` signals and never mutate this.

## What Hurt must apply to the hit that was just registered.
class Scale extends RefCounted:
	## Hit number inside the combo (0 for a hit that is not part of one: a bomb).
	var hits: int = 0
	var kb_mult: float = 1.0
	var stun_mult: float = 1.0
	## Ticks of the time cap left: the hitstun is never longer than this.
	var stun_cap_ticks: int = 1 << 30
	## The hit launches the victim and grants invulnerability at once.
	var capped: bool = false

var rules: ComboRules
## Hits so far, the damage they did and who dealt them (0 / 0.0 / null when idle).
var hits: int = 0
var damage: float = 0.0
## Ticks since the first hit.
var elapsed_ticks: int = 0
var attacker: Fighter

var _owner: Fighter

func setup(owner_fighter: Fighter, combo_rules: ComboRules = null) -> void:
	_owner = owner_fighter
	rules = combo_rules if combo_rules != null else load("res://game/combat/combo_rules.tres") as ComboRules
	reset()

func is_active() -> bool:
	return hits > 0

## Counts a FULL hit and returns its scaling. `in_hitstun` is whether the victim was
## in Hurt before this hit. A hit with no attacker (a bomb) is a hazard, not a
## combo: it silently clears the tracker and is not counted. Blocked hits never get
## here (Combat only registers FULL hits).
func register(hit: Hit, in_hitstun: bool) -> Scale:
	var scale := Scale.new()
	if hit.attacker == null:
		reset()
		return scale
	if in_hitstun and is_active():
		hits += 1
		damage += hit.damage
	else:
		# A new combo. The previous one (if its end was still pending) closes first.
		end()
		hits = 1
		damage = hit.damage
		elapsed_ticks = 0
	attacker = hit.attacker
	scale.hits = hits
	scale.kb_mult = pow(rules.knockback_growth, hits - 1)
	scale.stun_mult = pow(rules.hitstun_decay, maxi(0, hits - (rules.decay_from_hit - 1)))
	scale.stun_cap_ticks = rules.time_cap_ticks() - elapsed_ticks
	scale.capped = hits >= rules.hard_cap_hits or scale.stun_cap_ticks <= rules.min_combo_stun_ticks
	if _owner != null:
		_owner.combo_updated.emit(hits, damage, attacker)
	return scale

## Once per physics tick. The combo ends on the first tick the victim is no longer in
## Hurt; a Hurt-to-Hurt re-entry happens inside one tick, so it never ends it.
func tick(state_name: String) -> void:
	if hits <= 0:
		return
	elapsed_ticks += 1
	if state_name != "Hurt":
		end()

## Closes the combo: emits `combo_ended` when it had hits, then clears it.
func end() -> void:
	if hits > 0 and _owner != null:
		_owner.combo_ended.emit(hits, damage, attacker)
	reset()

## Clears the combo without telling anyone.
func reset() -> void:
	hits = 0
	damage = 0.0
	elapsed_ticks = 0
	attacker = null
