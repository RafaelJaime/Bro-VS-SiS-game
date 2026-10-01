extends Motion

@export var punch_area: Area2D
@export var punch_duration: float = 0.3
@export var punch_cooldown: float = 0.7
@export var punch_distance: float = 50.0
@export var punch_damage: float = 8.0
@export var punch_knockback: Vector2 = Vector2(220, -120)

var punch_timer: Timer
var cooldown_timer: Timer
var is_punching: bool = false

func _enter() -> void:
	setup_timers()
	
	if cooldown_timer.is_stopped() or cooldown_timer.time_left <= 0:
		super._enter()
		
		if owner.enemy.global_position.x > owner.global_position.x:
			move_punch_offset(punch_distance)
		else:
			move_punch_offset(-punch_distance)
		
		start_punch()
	else:
		finished.emit("Idle")

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
	
	punch_timer.start(punch_duration)
	cooldown_timer.start(punch_cooldown)
	
	if punch_area:
		if punch_area.is_connected("body_entered", _on_punch_area_body_entered):
			punch_area.body_entered.disconnect(_on_punch_area_body_entered)
		punch_area.body_entered.connect(_on_punch_area_body_entered)
		check_overlapping_bodies()

func move_punch_offset(distance: float) -> void:
	if owner and owner is Node2D:
		var direction = 1 if owner.scale.x > 0 else -1
		owner.position.x += distance * direction

func check_overlapping_bodies() -> void:
	if punch_area:
		var bodies = punch_area.get_overlapping_bodies()
		for body in bodies:
			_on_punch_area_body_entered(body)

func end_punch() -> void:
	is_punching = false
	if owner.enemy.global_position.x > owner.global_position.x:
		move_punch_offset(-punch_distance)
	else:
		move_punch_offset(punch_distance)
	finished.emit("Idle")

func _on_punch_timer_timeout() -> void:
	end_punch()

func _on_punch_area_body_entered(body: Node2D) -> void:
	if owner != null and body != owner and body is Fighter:
		print("¡Hace daño a ", body.name, "!")
		Combat.apply_hit(owner, body, punch_damage, punch_knockback)

func _exit() -> void:
	if punch_area and punch_area.is_connected("body_entered", _on_punch_area_body_entered):
		punch_area.body_entered.disconnect(_on_punch_area_body_entered)
