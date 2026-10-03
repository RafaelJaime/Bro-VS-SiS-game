extends Motion
class_name Defeated
## The final KO: the fighter loses all control, drops and lies there with the
## defeated pose. Over the table it rests on the tabletop; elsewhere it drops to
## the room floor. A KO through a side blast zone first puts the body just inside
## the camera view so it can be seen.

## World pixels kept between the body and the view's side edge.
const VIEW_PAD := 170.0
## Short drop for a body that left through the bottom, so it visibly falls.
const BOTTOM_DROP := 140.0

var _saved_mask: int = 0
var _mask_released: bool = false
## Surface (Game-local y) the body comes to rest on; negative when there is none.
var _rest_surface_y: float = -1.0

func _enter() -> void:
	super._enter()
	state_machine.velocity = Vector2.ZERO
	var fighter: Fighter = owner
	if fighter.defeat_floor_y >= 0.0:
		# The landing is resolved by _rest_surface_y, not by collisions, so the
		# body can drop past the tabletop and the legs to the room floor.
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
	_rest_surface_y = fighter.defeat_floor_y
	if _rest_surface_y >= 0.0:
		if _is_over_table(fighter):
			_rest_surface_y = float(fighter.defeat_table["top"])
		else:
			var rest_y := fighter.origin_for_floor(_rest_surface_y)
			if fighter.position.y > rest_y - BOTTOM_DROP:
				fighter.position.y = rest_y - BOTTOM_DROP
	velocity_updated.emit(state_machine.velocity)

## True when the body is above the tabletop and within its horizontal extent, so
## it lies on the table instead of falling through it.
func _is_over_table(fighter: Fighter) -> bool:
	var table: Dictionary = fighter.defeat_table
	if table.is_empty():
		return false
	var x := fighter.position.x
	if x < float(table["left"]) or x > float(table["right"]):
		return false
	return fighter.position.y <= fighter.origin_for_floor(float(table["top"])) + 1.0

func _exit() -> void:
	if _mask_released:
		(owner as Fighter).collision_mask = _saved_mask
		_mask_released = false

func _update(delta: float) -> void:
	var fighter: Fighter = owner
	state_machine.velocity.x = 0.0
	calculate_gravity(delta)
	if _rest_surface_y >= 0.0:
		var rest_y := fighter.origin_for_floor(_rest_surface_y)
		var landing := rest_y - fighter.position.y
		if landing <= state_machine.velocity.y * delta:
			# Lands exactly on the surface this tick and stays there.
			state_machine.velocity.y = maxf(landing, 0.0) / delta
			if landing <= 0.0:
				state_machine.velocity.y = 0.0
	velocity_updated.emit(state_machine.velocity)
