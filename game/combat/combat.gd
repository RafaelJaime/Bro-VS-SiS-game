extends RefCounted
class_name Combat

## Heavy-food damage threshold (see FoodCatalog.WEIGHT_STATS) above which the
## explosion SFX plays instead of the punch SFX.
const HEAVY_DAMAGE_THRESHOLD := 16.0

## Centralizes "attacker hits target" resolution so every damage source
## (punch, thrown food, ...) shares identical block/no-block handling.
## This is also the fix for the previously unused
## Protect.receive_blocked_damage() codepath: before this, a hit landing on
## a blocking target just kicked the target back to Idle with zero damage
## and zero knockback (full immunity). Now a blocking target always goes
## through receive_blocked_damage(), which applies the reduced % and
## reduced knockback from the design doc. Also triggers hit-stop and the
## punch/explosion SFX (T5).
static func apply_hit(attacker: Fighter, target: Fighter, damage: float, knockback_base: Vector2) -> void:
	if target == null or target.state_machine == null:
		return
	if target.is_invulnerable:
		return

	var target_sm = target.state_machine
	var blocked = target_sm.current_state and target_sm.current_state.name == "Protect"

	if blocked:
		target_sm.current_state.receive_blocked_damage(damage, knockback_base)
	else:
		var hurt_state = target_sm.state_map.get("Hurt")
		if hurt_state:
			hurt_state.pending_damage = damage
			hurt_state.pending_knockback = knockback_base
		target_sm._change_state("Hurt")

	# Skip juice (global time_scale hit-stop + SFX) under AI training: dozens
	# of train.tscn's Game rows run in parallel, and time_scale is a single
	# global Engine property, so one row's hit would stutter every other row.
	if Sfx.is_training(target):
		return

	if blocked:
		_trigger_hit_stop(0.04, 0.3)
	else:
		_trigger_hit_stop(0.08, 0.05)

	if blocked:
		Sfx.play_event(&"block", target)
	elif damage >= HEAVY_DAMAGE_THRESHOLD:
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
