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

var punch_timer: Timer
var cooldown_timer: Timer
var is_punching: bool = false
var phase: Phase = Phase.SWING

# One swing = one hit per target, however long the hitbox overlaps.
var _hit_targets: Array[Fighter] = []
var _elapsed: float = 0.0
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

# Cooldown gate used by Motion.handle_actions() (no re-entrant reject emit).
func can_enter() -> bool:
	if not (owner.is_on_floor() or profile.can_air_punch):
		return false
	return cooldown_timer == null or cooldown_timer.is_stopped()

func _enter() -> void:
	setup_timers()
	super._enter()

	# Facing is locked for the whole punch (the Fighter does not turn during
	# Punch), so the hitbox is placed once and mirrored by it. The owner is not
	# moved: reach comes from the hitbox, never from teleporting the fighter.
	_swing_facing = owner.facing
	_hit_targets.clear()
	_elapsed = 0.0
	_hold_time = 0.0
	_charge = 0.0
	_start_aim = owner.intent.aim
	_set_hitbox_active(false)

	# Charging only starts on the ground, from a held key (spec: no air charge).
	if owner.is_on_floor() and profile.can_charge and owner.intent.attack_held:
		phase = Phase.CHARGING
	else:
		_fire()

func _update(delta: float) -> void:
	super._update(delta)
	# Grounded punches stop where the fighter stands; air punches keep falling.
	calculate_gravity(delta)
	calculate_velocity(0.0, Vector2.ZERO, delta)

	if phase == Phase.CHARGING:
		_update_charge(delta)
		return

	_elapsed += delta
	var duration := _duration()
	var active := _elapsed >= duration * profile.punch_active_start \
			and _elapsed < duration * profile.punch_active_end
	_set_hitbox_active(active)
	# monitoring is switched deferred, so the area only reports overlaps from the
	# frame after it turned on.
	if active and punch_area.monitoring:
		_hit_overlapping_hurtboxes()

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
	_elapsed = 0.0
	_attack = _select_attack(_start_aim)
	owner.last_attack_direction = _attack.direction
	owner.charge_level = _charge
	owner.set_charge_visual(-1.0)
	_place_hitbox()
	start_punch()

func _select_attack(aim: FighterIntent.Aim) -> AttackProfile:
	match aim:
		FighterIntent.Aim.UP:
			return profile.attack_up
		FighterIntent.Aim.DOWN:
			return profile.attack_down_ground if owner.is_on_floor() else profile.attack_down_air
		FighterIntent.Aim.SIDE:
			return profile.attack_side
	return _neutral_attack()

# The ordinary punch, from the node overrides or the profile.
func _neutral_attack() -> AttackProfile:
	return AttackProfile.make(_damage(), _knockback(), Vector2(profile.punch_reach, profile.punch_hitbox_y), profile.punch_hitbox_size, &"neutral")

func _duration() -> float:
	return punch_duration if punch_duration >= 0.0 else profile.punch_duration

func _cooldown() -> float:
	return punch_cooldown if punch_cooldown >= 0.0 else profile.punch_cooldown

func _damage() -> float:
	return punch_damage if punch_damage >= 0.0 else profile.punch_damage

func _knockback() -> Vector2:
	return punch_knockback if punch_knockback != Vector2.ZERO else profile.punch_knockback

func setup_timers() -> void:
	if not punch_timer:
		punch_timer = Timer.new()
		punch_timer.one_shot = true
		add_child(punch_timer)
	
	if not cooldown_timer:
		cooldown_timer = Timer.new()
		cooldown_timer.one_shot = true
		add_child(cooldown_timer)

func start_punch() -> void:
	is_punching = true
	
	if not punch_timer.is_connected("timeout", _on_punch_timer_timeout):
		punch_timer.connect("timeout", _on_punch_timer_timeout)
	
	punch_timer.start(_duration())
	cooldown_timer.start(_cooldown())

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
		Combat.resolve(Hit.punch(owner, damage, knockback, shield_damage), target)

func end_punch() -> void:
	is_punching = false
	finished.emit("Idle" if is_on_floor() else "Fall")

func _on_punch_timer_timeout() -> void:
	end_punch()

func _exit() -> void:
	is_punching = false
	phase = Phase.SWING
	if punch_timer and not punch_timer.is_stopped():
		punch_timer.stop()
	_set_hitbox_active(false)
	# Hit, or finished, while charging: the glow and the charge go away.
	owner.set_charge_visual(-1.0)
	owner.charge_level = 0.0
