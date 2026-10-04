extends Motion

## The punch, in two phases. A grounded fighter that enters with the punch key held
## CHARGES until the key is released (a smash); everything else, an air punch, a
## tap or a controller that never holds the key (the CPU, the RL policy), goes
## straight to the SWING. The swing picks one of five variants from the aim held
## when the punch started, scales it by the charge, and keeps the one hitbox of the
## S-A punch: live only between `punch_active_start` and `punch_active_end`.

@export var punch_area: Area2D
# Node-level overrides (train.tscn sets punch_duration/cooldown). An unset value
# (negative, or ZERO for the knockback) falls back to the owner's
# FighterProfile, which is the single source of the default numbers. They define
# the neutral punch; the other variants come from the profile.
@export var punch_duration: float = -1.0
@export var punch_cooldown: float = -1.0
@export var punch_damage: float = -1.0
@export var punch_knockback: Vector2 = Vector2.ZERO

enum Phase { CHARGING, SWING }

var is_punching: bool = false
var phase: Phase = Phase.SWING

# One swing = one hit per target, however long the hitbox overlaps.
var _hit_targets: Array[Fighter] = []
## Physics ticks since the swing fired (1 on the first `_update` after it). Timing
## counts ticks, never `Timer` nodes or delta, so hit-stop cannot stretch a swing.
var _tick: int = 0
## Startup / active / endlag / cooldown / link-window ticks of the current swing step
## (see `AttackProfile.resolved_frames`).
var _frames: Dictionary = {"startup": 0, "active": 0, "endlag": 0, "cooldown": 0, "link_window": 0}
## The jab chain being thrown (empty for every other attack), the index of the step
## in it, and whether a neutral press is waiting for the link window to open.
var _chain: Array[AttackProfile] = []
var _step: int = 0
var _chain_queued: bool = false
## Floor or air at the start of the swing: a chain only continues in the same medium.
var _on_floor_at_fire: bool = true
var _swing_facing: int = 1
var _hold_time: float = 0.0
var _charge: float = 0.0
var _attack: AttackProfile
## The aim held when the punch started (Smash: the direction is read at the press,
## so letting go of it before the swing or the release changes nothing).
var _start_aim: FighterIntent.Aim = FighterIntent.Aim.NEUTRAL

func _ready() -> void:
	super._ready()
	# The scene's hitbox shape is shared by every fighter instance; each swing
	# resizes it, so give this fighter its own copy.
	if punch_area:
		var shape_node: CollisionShape2D = punch_area.get_node("CollisionShape2D")
		shape_node.shape = shape_node.shape.duplicate()

# Cooldown gate used by Motion.handle_actions() (no re-entrant reject emit). The
# lockout is `Fighter.attack_cooldown_ticks`, which keeps running after Punch exits.
func can_enter() -> bool:
	if not (owner.is_on_floor() or profile.can_air_punch):
		return false
	return owner.attack_cooldown_ticks <= 0

## Seconds until a punch can start: the larger of the cooldown and the swing that
## is still running (the `cooldowns.punch` value of the snapshot).
func cooldown_left() -> float:
	var ticks_left: int = owner.attack_cooldown_ticks
	if is_punching:
		ticks_left = maxi(ticks_left, _swing_ticks() - _tick)
	return CombatClock.seconds(maxi(0, ticks_left))

func _enter() -> void:
	super._enter()

	# Facing is locked for the whole punch (the Fighter does not turn during
	# Punch), so the hitbox is placed once and mirrored by it. The owner is not
	# moved: reach comes from the hitbox, never from teleporting the fighter.
	_swing_facing = owner.facing
	_hit_targets.clear()
	_tick = 0
	_hold_time = 0.0
	_charge = 0.0
	# The press may have been made a few ticks ago (the attack buffer); its aim is
	# the one held at the press.
	_start_aim = owner.consume_attack_buffer()
	_set_hitbox_active(false)

	# Charging only starts on the ground, from a held key (spec: no air charge).
	if owner.is_on_floor() and profile.can_charge and owner.intent.attack_held:
		phase = Phase.CHARGING
	else:
		_fire()

func _update(delta: float) -> void:
	super._update(delta)
	# Grounded punches stop where the fighter stands. An air punch keeps the jump:
	# gravity carries on and the horizontal speed and air control are the ones of
	# Jump and Fall (it used to brake the fighter to a stop in mid-air).
	calculate_gravity(delta)
	if is_on_floor():
		calculate_velocity(0.0, Vector2.ZERO, delta)
	else:
		set_direction()
		calculate_velocity(profile.run_speed, state_machine.direction, delta)

	if phase == Phase.CHARGING:
		_update_charge(delta)
		return

	_tick += 1
	var startup: int = _frames["startup"]
	var active := _tick > startup and _tick <= startup + int(_frames["active"])
	_set_hitbox_active(active)
	# monitoring is switched deferred, so the area only reports overlaps from the
	# frame after it turned on.
	if active and punch_area.monitoring:
		_hit_overlapping_hurtboxes()
	if not _chain.is_empty() and _update_chain():
		return
	if _tick >= _swing_ticks():
		end_punch()

# Jab chain: a neutral press during a step that is not the last one is queued (it
# may come before the link window opens); once the window is open, the queued press
# starts the next step. Returns true when it did. Presses with another aim stay in
# the buffer for a new attack after the swing; one press is one step.
func _update_chain() -> bool:
	if _is_last_step():
		return false
	var link_close := _link_close()
	if not _chain_queued and owner.attack_buffer_ticks > 0 \
			and owner.buffered_attack_aim == FighterIntent.Aim.NEUTRAL and _tick <= link_close:
		_chain_queued = true
		owner.consume_attack_buffer()
	if not _chain_queued or _tick < _link_open():
		return false
	if _tick > link_close or owner.is_on_floor() != _on_floor_at_fire:
		_chain_queued = false
		return false
	_step += 1
	_start_step()
	return true

func _is_last_step() -> bool:
	return _step >= _chain.size() - 1

func _link_open() -> int:
	return int(_frames["startup"]) + int(_frames["active"]) + 1

func _link_close() -> int:
	return int(_frames["startup"]) + int(_frames["active"]) + int(_frames["link_window"])

## 1-based step of the jab chain being thrown, 0 when the swing is not a chain step.
func chain_step() -> int:
	if not is_punching or _chain.is_empty():
		return 0
	return _step + 1

## Steps of the chain being thrown (0 outside a chain).
func chain_length() -> int:
	return _chain.size() if is_punching else 0

## True while a neutral press would advance the chain this tick (the link window).
func link_open() -> bool:
	if chain_step() == 0 or _is_last_step():
		return false
	return _tick >= _link_open() and _tick <= _link_close()

## True while a neutral press made now still joins the chain (before the link window
## closes, none queued yet): what the CPU checks before pressing.
func accepts_chain_press() -> bool:
	if chain_step() == 0 or _is_last_step() or _chain_queued:
		return false
	return _tick <= _link_close()

# Winding up: the glow starts after the tap threshold, the swing fires on release.
func _update_charge(delta: float) -> void:
	_hold_time += delta
	_charge = charge_for(_hold_time, profile)
	owner.charge_level = _charge
	owner.set_charge_visual(_charge if _hold_time >= profile.tap_threshold else -1.0)
	if not owner.intent.attack_held or not owner.is_on_floor():
		_fire()

## Charge (0..1) after holding the punch key for `hold` seconds: nothing up to the
## tap threshold, then linear up to the cap at max_charge_time.
static func charge_for(hold: float, p: FighterProfile) -> float:
	if hold < p.tap_threshold:
		return 0.0
	return clampf((hold - p.tap_threshold) / maxf(p.max_charge_time - p.tap_threshold, 0.001), 0.0, 1.0)

# Starts the swing with the variant for the aim held right now.
func _fire() -> void:
	phase = Phase.SWING
	_chain = []
	_step = 0
	_on_floor_at_fire = owner.is_on_floor()
	_attack = _select_attack(_start_aim)
	owner.charge_level = _charge
	owner.set_charge_visual(-1.0)
	_start_step()
	start_punch()

# Starts the swing (or the next chain step) `_attack`: its frame data, a fresh
# hit-once list and the hitbox. The step starts on tick 0; the first active tick is
# startup + 1.
func _start_step() -> void:
	if not _chain.is_empty():
		_attack = _chain[_step]
	_tick = 0
	_chain_queued = false
	_hit_targets.clear()
	_frames = _attack.resolved_frames(profile, punch_duration, punch_cooldown)
	owner.attack_cooldown_ticks = int(_frames["cooldown"])
	owner.last_attack_direction = _attack.direction
	_set_hitbox_active(false)
	_place_hitbox()

# A directional punch comes from the aim held at the press. A neutral punch is the
# charged single (grounded, held past the tap threshold), or step 0 of the jab chain
# (air chain in the air), or, with no chain, the kit's single or the legacy punch.
func _select_attack(aim: FighterIntent.Aim) -> AttackProfile:
	match aim:
		FighterIntent.Aim.UP:
			return profile.attack_up
		FighterIntent.Aim.DOWN:
			return profile.attack_down_ground if owner.is_on_floor() else profile.attack_down_air
		FighterIntent.Aim.SIDE:
			return profile.attack_side
	var charged := _on_floor_at_fire and _hold_time >= profile.tap_threshold
	if charged and profile.neutral_single != null:
		return profile.neutral_single
	var chain := profile.jab_chain if _on_floor_at_fire else profile.air_jab_chain
	if not chain.is_empty():
		_chain = chain
		return chain[0]
	return profile.neutral_single if profile.neutral_single != null else _neutral_attack()

# The ordinary punch, from the node overrides or the profile.
func _neutral_attack() -> AttackProfile:
	return AttackProfile.make(_damage(), _knockback(), Vector2(profile.punch_reach, profile.punch_hitbox_y), profile.punch_hitbox_size, &"neutral")

func _damage() -> float:
	return punch_damage if punch_damage >= 0.0 else profile.punch_damage

func _knockback() -> Vector2:
	return punch_knockback if punch_knockback != Vector2.ZERO else profile.punch_knockback

func start_punch() -> void:
	is_punching = true

# The swing ends this many ticks after it fired.
func _swing_ticks() -> int:
	return int(_frames["startup"]) + int(_frames["active"]) + int(_frames["endlag"])

# Single hitbox shape, mirrored by the swing's facing.
func _place_hitbox() -> void:
	if punch_area == null:
		return
	var shape_node: CollisionShape2D = punch_area.get_node("CollisionShape2D")
	shape_node.position = Vector2(_attack.hitbox_offset.x * _swing_facing, _attack.hitbox_offset.y)
	(shape_node.shape as RectangleShape2D).size = _attack.hitbox_size

func _set_hitbox_active(active: bool) -> void:
	if punch_area and punch_area.monitoring != active:
		punch_area.set_deferred("monitoring", active)

# The hitbox overlaps hurtboxes (Area2D on the hurtbox layer); the Fighter is
# the hurtbox's parent.
func _hit_overlapping_hurtboxes() -> void:
	if punch_area == null:
		return
	var damage_scale := lerpf(1.0, profile.charge_damage_max, _charge)
	var damage := _attack.damage * damage_scale
	var knockback := _attack.knockback * lerpf(1.0, profile.charge_knockback_max, _charge)
	# A set shield damage scales with the charge like the damage does.
	var shield_damage := _attack.shield_damage * damage_scale if _attack.shield_damage >= 0.0 else -1.0
	for area in punch_area.get_overlapping_areas():
		var target := area.get_parent() as Fighter
		if target == null or target == owner or _hit_targets.has(target):
			continue
		_hit_targets.append(target)
		Combat.resolve(Hit.punch(owner, damage, knockback, shield_damage, Hit.Source.PUNCH, _attack), target)

func end_punch() -> void:
	is_punching = false
	finished.emit("Idle" if is_on_floor() else "Fall")

func _exit() -> void:
	is_punching = false
	_chain_queued = false
	phase = Phase.SWING
	_set_hitbox_active(false)
	# Hit, or finished, while charging: the glow and the charge go away.
	owner.set_charge_visual(-1.0)
	owner.charge_level = 0.0
