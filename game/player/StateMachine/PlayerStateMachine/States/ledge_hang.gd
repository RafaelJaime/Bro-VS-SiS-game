extends Motion
class_name LedgeHang

## Hanging from a table leg (Smash ledge), and the way back up. The fighter snaps
## to the leg (`owner.ledge_anchor`), is invulnerable for a while (shorter with
## every grab since the ground), refills its air actions and then chooses:
##   up, or toward the table   climb onto the tabletop
##   jump                      ledge jump (a jump toward the table)
##   punch                     climb attack (climb and hit whoever waits there)
##   down, or away             let go
## Hanging too long also lets go. A hit ends the state like any other. The climb is
## a second phase of this state: the fighter is invulnerable and no longer counts as
## hanging, so it cannot be trumped by the other fighter.

enum Phase { HANG, CLIMB }

const HANG_TINT := Color(0.75, 0.9, 1.0)

var phase: Phase = Phase.HANG
var hang_time: float = 0.0

var _side: int = 0
var _climb_time: float = 0.0
var _climb_total: float = 0.45
var _climb_attack: bool = false
var _attack_done: bool = false
var _start: Vector2
var _top: Vector2
var _end: Vector2

func _enter() -> void:
	animation_state_changed.emit("jump")
	phase = Phase.HANG
	hang_time = 0.0
	_side = owner.ledge_side
	owner.restore_air_actions()
	owner.position = owner.ledge_anchor
	state_machine.velocity = Vector2.ZERO
	velocity_updated.emit(state_machine.velocity)
	# Face the table, hanging by one raised arm.
	owner.facing = -_side
	var invuln: float = owner.ledge_invulnerability()
	if invuln > 0.0:
		owner.grant_invulnerability(invuln, false)
	owner.animated_sprite_2d.modulate = HANG_TINT
	Sfx.play_event(&"ledge", owner)

func _exit() -> void:
	owner.ledge_side = 0
	owner.animated_sprite_2d.modulate = Color.WHITE

func _update(delta: float) -> void:
	super._update(delta)
	state_machine.velocity = Vector2.ZERO
	velocity_updated.emit(state_machine.velocity)
	if phase == Phase.CLIMB:
		_update_climb(delta)
		return

	owner.position = owner.ledge_anchor
	hang_time += delta
	if hang_time >= profile.ledge_max_hang:
		_let_go()
		return
	if hang_time < profile.ledge_min_hang:
		return

	var intent: FighterIntent = owner.intent
	var toward := intent.move_x * -_side # +1 when pushing toward the table.
	if intent.attack_pressed:
		_start_climb(true)
	elif intent.jump_pressed:
		_ledge_jump()
	elif intent.aim == FighterIntent.Aim.DOWN or toward < -0.5:
		_let_go()
	elif intent.aim == FighterIntent.Aim.UP or toward > 0.5:
		_start_climb(false)

# Falls straight down along the leg; the same legs stay out of reach for a moment.
func _let_go() -> void:
	owner.block_ledge_grab(profile.ledge_regrab_lockout)
	state_machine.velocity = Vector2(_side * 60.0, 0.0)
	velocity_updated.emit(state_machine.velocity)
	finished.emit("Fall")

# A ground jump from the leg, drifting toward the table. The air jump stays free.
func _ledge_jump() -> void:
	owner.block_ledge_grab(profile.ledge_regrab_lockout)
	state_machine.velocity = Vector2(-_side * profile.ledge_jump_drift, 0.0)
	velocity_updated.emit(state_machine.velocity)
	# Coyote time makes it a GROUND jump, so the air jump stays unspent.
	owner.coyote_timer = profile.coyote_time
	owner.jump_velocity_override = profile.ledge_jump_velocity
	owner.jump_buffer_timer = profile.jump_buffer
	finished.emit("Jump")

func _start_climb(with_attack: bool) -> void:
	phase = Phase.CLIMB
	_climb_attack = with_attack
	_attack_done = false
	_climb_time = 0.0
	_climb_total = profile.ledge_attack_climb_time if with_attack else profile.ledge_climb_time
	var ledge := _ledge_of_side()
	var inward := float(-_side)
	var feet_offset: float = owner._feet_offset
	_start = owner.position
	_end = Vector2(ledge["x"] + inward * profile.ledge_climb_land_x, ledge["top"] - feet_offset - 0.5)
	# Straight up the leg, clear of the table, then over the edge.
	_top = Vector2(_start.x, _end.y - 60.0)
	owner.ledge_side = 0
	owner.grant_invulnerability(profile.ledge_climb_invulnerability, false)

func _ledge_of_side() -> Dictionary:
	for ledge: Dictionary in owner.get_parent().get_ledges():
		if ledge["side"] == _side:
			return ledge
	return {"x": owner.position.x, "top": owner.position.y}

func _update_climb(delta: float) -> void:
	_climb_time += delta
	var t := clampf(_climb_time / _climb_total, 0.0, 1.0)
	if t < 0.6:
		owner.position = _start.lerp(_top, ease(t / 0.6, -2.0))
	else:
		owner.position = _top.lerp(_end, ease((t - 0.6) / 0.4, -2.0))
		if _climb_attack and not _attack_done:
			_attack_done = true
			_climb_hit()
	if t >= 1.0:
		owner.position = _end
		finished.emit("Idle")

# The climb attack hits whoever stands in front of the landing spot.
func _climb_hit() -> void:
	var target := owner.enemy as Fighter
	if target == null or target.stocks <= 0:
		return
	var dx := target.position.x - _end.x
	var in_front := dx * (-_side) >= -20.0 and absf(dx) <= profile.ledge_attack_reach
	if in_front and absf(target.position.y - _end.y) <= 100.0:
		Combat.apply_hit(owner, target, profile.ledge_attack_damage, profile.ledge_attack_knockback)
