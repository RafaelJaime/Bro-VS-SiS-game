extends Motion
class_name Shoot

## Despite the node/class name (kept to avoid churning player.tscn's node
## tree + the "shoot" input action), this state no longer fires a free
## projectile. Design: the shoot key now picks up nearby food when
## empty-handed, or throws the held food when holding one.

@export var food_projectile_scene: PackedScene
@export var shoot_duration: float = 0.3
@export var shoot_cooldown: float = 0.4
@export var throw_distance: float = 30.0
@export var right_mark: Marker2D
@export var left_mark: Marker2D

var action_timer: Timer
var cooldown_timer: Timer

# Cooldown gate used by Motion.handle_actions() (no re-entrant reject emit).
func can_enter() -> bool:
	return cooldown_timer == null or cooldown_timer.is_stopped()

func _enter() -> void:
	setup_timers()
	super._enter()

	if owner.is_holding_food():
		_throw_food()
	else:
		_try_pickup()

	start_action()

func _update(delta: float) -> void:
	super._update(delta)
	# Grounded throws plant the fighter; air throws keep falling with air control.
	calculate_gravity(delta)
	if is_on_floor():
		calculate_velocity(0.0, Vector2.ZERO, delta)
	else:
		set_direction()
		calculate_velocity(profile.run_speed, state_machine.direction, delta)

func setup_timers() -> void:
	if not action_timer:
		action_timer = Timer.new()
		action_timer.one_shot = true
		add_child(action_timer)

	if not cooldown_timer:
		cooldown_timer = Timer.new()
		cooldown_timer.one_shot = true
		add_child(cooldown_timer)

func start_action() -> void:
	if not action_timer.is_connected("timeout", _on_action_timer_timeout):
		action_timer.connect("timeout", _on_action_timer_timeout)

	action_timer.start(shoot_duration)
	cooldown_timer.start(shoot_cooldown)

func _try_pickup() -> void:
	if not owner.pickup_area:
		return

	var bodies = owner.pickup_area.get_overlapping_bodies()
	for body in bodies:
		if body is FoodPickup and not body.picked_up:
			owner.pick_up_food(body)
			return

func _throw_food() -> void:
	if not food_projectile_scene:
		push_warning("No food_projectile_scene assigned to Shoot state.")
		return

	if not owner:
		push_warning("Owner not found.")
		return

	var food_name = owner.held_food
	owner.clear_held_food()

	# Smash: items are thrown the way the fighter faces.
	var direction: int = owner.facing
	var spawn_marker = right_mark if direction > 0 else left_mark

	var food_projectile = food_projectile_scene.instantiate()
	food_projectile.food_name = food_name
	food_projectile.direction = direction

	if spawn_marker:
		food_projectile.global_position = spawn_marker.global_position
	else:
		var spawn_position = owner.global_position
		spawn_position.x += throw_distance * direction
		food_projectile.global_position = spawn_position

	food_projectile.set_shooter(owner)
	owner.get_parent().add_child(food_projectile)

func _on_action_timer_timeout() -> void:
	end_action()

func end_action() -> void:
	exit_to_neutral()
