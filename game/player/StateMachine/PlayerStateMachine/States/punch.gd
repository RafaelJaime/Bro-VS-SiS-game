extends Motion

@export var punch_area: Area2D
# Node-level overrides (train.tscn sets punch_duration/cooldown). An unset value
# (negative, or ZERO for the knockback) falls back to the owner's
# FighterProfile, which is the single source of the default numbers.
@export var punch_duration: float = -1.0
@export var punch_cooldown: float = -1.0
@export var punch_damage: float = -1.0
@export var punch_knockback: Vector2 = Vector2.ZERO

var punch_timer: Timer
var cooldown_timer: Timer
var is_punching: bool = false

# One swing = one hit per target, however long the hitbox overlaps.
var _hit_targets: Array[Fighter] = []
var _elapsed: float = 0.0
var _swing_facing: int = 1

# Cooldown gate used by Motion.handle_actions() (no re-entrant reject emit).
func can_enter() -> bool:
	return cooldown_timer == null or cooldown_timer.is_stopped()

func _enter() -> void:
	setup_timers()
	super._enter()

	# Facing is locked for the whole swing (the Fighter does not turn during
	# Punch), so the hitbox is placed once and mirrored by it. The owner is not
	# moved: reach comes from the hitbox, never from teleporting the fighter.
	_swing_facing = owner.facing
	_hit_targets.clear()
	_elapsed = 0.0
	_place_hitbox()
	_set_hitbox_active(false)
	start_punch()

func _update(delta: float) -> void:
	super._update(delta)
	# Grounded punches stop where the fighter stands; air punches keep falling.
	calculate_gravity(delta)
	calculate_velocity(0.0, Vector2.ZERO, delta)

	_elapsed += delta
	var duration := _duration()
	var active := _elapsed >= duration * profile.punch_active_start \
			and _elapsed < duration * profile.punch_active_end
	_set_hitbox_active(active)
	if active:
		_hit_overlapping_hurtboxes()

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
	shape_node.position = Vector2(profile.punch_reach * _swing_facing, profile.punch_hitbox_y)
	(shape_node.shape as RectangleShape2D).size = profile.punch_hitbox_size

func _set_hitbox_active(active: bool) -> void:
	if punch_area and punch_area.monitoring != active:
		punch_area.set_deferred("monitoring", active)

# The hitbox overlaps hurtboxes (Area2D on the hurtbox layer); the Fighter is
# the hurtbox's parent.
func _hit_overlapping_hurtboxes() -> void:
	if punch_area == null:
		return
	for area in punch_area.get_overlapping_areas():
		var target := area.get_parent() as Fighter
		if target == null or target == owner or _hit_targets.has(target):
			continue
		_hit_targets.append(target)
		Combat.apply_hit(owner, target, _damage(), _knockback())

func end_punch() -> void:
	is_punching = false
	finished.emit("Idle" if is_on_floor() else "Fall")

func _on_punch_timer_timeout() -> void:
	end_punch()

func _exit() -> void:
	is_punching = false
	if punch_timer and not punch_timer.is_stopped():
		punch_timer.stop()
	_set_hitbox_active(false)
