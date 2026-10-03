extends RefCounted
class_name Combat

## Heavy-food damage threshold (see FoodCatalog.WEIGHT_STATS) above which the
## explosion SFX plays instead of the punch SFX.
const HEAVY_DAMAGE_THRESHOLD := 16.0

## What a hit did to its target.
## IGNORED: invulnerable or intangible, nothing happened.
## FULL: full damage and knockback (the target is in Hurt).
## BLOCKED: the shield absorbed it (meter drain, chip damage, reduced pushback).
## BROKE: the shield absorbed it and ran out; the target is dizzy.
enum Outcome { IGNORED, FULL, BLOCKED, BROKE }

## The single resolver of every damage source (punch, ledge attack, thrown food,
## bomb), in a fixed order:
##   1. an invulnerable or intangible target takes nothing;
##   2. an unblockable hit applies in full whatever the target is doing;
##   3. a dizzy target takes it in full (it is not shielding);
##   4. a shielding target takes the shielded path (Protect.absorb);
##   5. otherwise the hit applies normally (Hurt).
## It emits `hit_received(hit, outcome)` on the target, which rewards, metrics and
## the CPU consume, and plays the juice (hit-stop, SFX) unless training.
static func resolve(hit: Hit, target: Fighter) -> Outcome:
	if target == null or target.state_machine == null:
		return Outcome.IGNORED
	if target.is_invulnerable or target.is_intangible():
		target.hit_received.emit(hit, Outcome.IGNORED)
		return Outcome.IGNORED

	var target_sm = target.state_machine
	var shielding: bool = target_sm.current_state != null and target_sm.current_state.name == "Protect"
	var outcome: Outcome
	if shielding and not hit.unblockable:
		outcome = Outcome.BROKE if target_sm.current_state.absorb(hit) else Outcome.BLOCKED
	else:
		_apply_full(hit, target)
		outcome = Outcome.FULL

	target.hit_received.emit(hit, outcome)
	_play_juice(hit, target, outcome)
	return outcome

## Thin wrapper kept for the call sites that build a plain punch.
static func apply_hit(attacker: Fighter, target: Fighter, damage: float, knockback_base: Vector2) -> void:
	resolve(Hit.punch(attacker, damage, knockback_base), target)

# Full damage and knockback: the target goes into Hurt, which reads the pending
# values (and the side the hit came from) when it starts.
static func _apply_full(hit: Hit, target: Fighter) -> void:
	var hurt_state = target.state_machine.state_map.get("Hurt")
	if hurt_state:
		hurt_state.pending_damage = hit.damage
		hurt_state.pending_knockback = hit.knockback
		hurt_state.pending_source_x = hit.source_position.x
		hurt_state.pending_attack = hit.attack
	target.state_machine._change_state("Hurt")

# Skip juice (global time_scale hit-stop + SFX) under AI training: dozens
# of train.tscn's Game rows run in parallel, and time_scale is a single
# global Engine property, so one row's hit would stutter every other row.
static func _play_juice(hit: Hit, target: Fighter, outcome: Outcome) -> void:
	if Sfx.is_training(target):
		return
	match outcome:
		Outcome.BROKE:
			# The break cue (SFX) is played by the Dizzy state.
			_trigger_hit_stop(0.14, 0.05)
		Outcome.BLOCKED:
			_trigger_hit_stop(0.04, 0.3)
			Sfx.play_event(&"block", target)
		_:
			_trigger_hit_stop(0.08 * hit.hitstop_scale, 0.05)
			# A bomb has its own explosion cue.
			if hit.source == Hit.Source.BOMB:
				return
			if hit.damage >= HEAVY_DAMAGE_THRESHOLD:
				Sfx.play_event(&"heavy_hit", target)
			else:
				Sfx.play_event(&"hit", target)

## Only the latest hit-stop may restore the clock. Every trigger takes a new
## token and its restore callback only acts while that token is still current,
## so overlapping hit-stops can neither end each other early nor leave a stale
## time scale behind.
static var _hit_stop_token: int = 0

## Briefly slows the whole game down to sell the impact of a hit ("hit-stop" /
## "hit-pause"), then restores normal speed. duration is real (unscaled) time.
static func _trigger_hit_stop(duration: float, scale: float) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	if not tree:
		return
	_hit_stop_token += 1
	var token := _hit_stop_token
	Engine.time_scale = scale
	# process_always=true, process_in_physics=false, ignore_time_scale=true:
	# this timer must keep counting real time while time_scale is near zero,
	# otherwise it would (almost) never fire.
	var timer = tree.create_timer(duration, true, false, true)
	timer.timeout.connect(func():
		if token == _hit_stop_token:
			Engine.time_scale = 1.0)

## Slows the whole game to `scale` for `duration` real seconds (the "GAME!"
## finish). Shares the hit-stop token, so it can never be cut short by an older
## hit-stop and nothing can leave the clock slowed afterwards.
static func slow_motion(duration: float, scale: float) -> void:
	_trigger_hit_stop(duration, scale)

## Ends any running hit-stop at once (a Game leaving the tree mid-stop).
static func cancel_hit_stop() -> void:
	_hit_stop_token += 1
	Engine.time_scale = 1.0
