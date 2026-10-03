extends Motion
class_name Defeated
## The final KO: the fighter loses all control, drops to the room floor and lies
## there with the defeated pose. A KO through a side blast zone first puts the body
## just inside the camera view so it can be seen.

## World pixels kept between the body and the view's side edge.
const VIEW_PAD := 170.0
## Short drop for a body that left through the bottom, so it visibly falls.
const BOTTOM_DROP := 140.0

var _saved_mask: int = 0
var _mask_released: bool = false

func _enter() -> void:
	super._enter()
	state_machine.velocity = Vector2.ZERO
	var fighter: Fighter = owner
	if fighter.defeat_floor_y >= 0.0:
		# The room floor is below the table: the body drops past the tabletop (and
		# the legs) instead of landing on it, wherever the camera put it.
		_saved_mask = fighter.collision_mask
		_mask_released = true
		fighter.collision_mask = 0
	var camera := fighter.get_viewport().get_camera_2d()
	if camera != null:
		var half_width := fighter.get_viewport_rect().size.x / (2.0 * camera.zoom.x)
		var center := camera.get_screen_center_position().x
		var low := center - half_width + VIEW_PAD
		var high := center + half_width - VIEW_PAD
		fighter.global_position.x = clampf(fighter.global_position.x, low, high)
	if fighter.defeat_floor_y >= 0.0:
		var rest_y := fighter.origin_for_floor(fighter.defeat_floor_y)
		if fighter.position.y > rest_y - BOTTOM_DROP:
			fighter.position.y = rest_y - BOTTOM_DROP
	velocity_updated.emit(state_machine.velocity)

func _exit() -> void:
	if _mask_released:
		(owner as Fighter).collision_mask = _saved_mask
		_mask_released = false

func _update(delta: float) -> void:
	var fighter: Fighter = owner
	state_machine.velocity.x = 0.0
	calculate_gravity(delta)
	if fighter.defeat_floor_y >= 0.0:
		var rest_y := fighter.origin_for_floor(fighter.defeat_floor_y)
		var landing := rest_y - fighter.position.y
		if landing <= state_machine.velocity.y * delta:
			# Lands exactly on the floor line this tick and stays there.
			state_machine.velocity.y = maxf(landing, 0.0) / delta
			if landing <= 0.0:
				state_machine.velocity.y = 0.0
	velocity_updated.emit(state_machine.velocity)
