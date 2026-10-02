extends CharacterBody2D
class_name Fighter

signal updated_characterUI
signal damage_changed(new_percent: float)
signal stocks_changed(player_instance: Fighter, stocks_left: int)
signal player_defeated(player_instance: Fighter)

@export var character_ui: CharacterUI:
	set(value):
		character_ui = value
		if character_ui != null:
			_apply_character_ui_settings()
			updated_characterUI.emit()
	get:
		return character_ui
@export var enemy: CharacterBody2D
## Tuning and moveset flags. When unset, a default FighterProfile (baseline
## values) is created, so no .tres is required.
@export var profile: FighterProfile
enum PlayerNumber { JUGADOR1, JUGADOR2 }
@export var control_scheme: PlayerNumber = PlayerNumber.JUGADOR1
## Where this fighter's intent comes from. AUTO resolves from the scene's
## AIController2D control mode (see _resolve_auto_controller).
enum ControllerKind { AUTO, HUMAN, CPU, POLICY }
@export var controller_kind: ControllerKind = ControllerKind.AUTO

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var ai_controller_2d: AIController2D = $AIController2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var punch_area: Area2D = $PunchArea
@onready var pickup_area: Area2D = $PickupArea
@onready var held_food_sprite: Sprite2D = $HeldFoodSprite
@onready var charge_glow: Sprite2D = $ChargeGlow
@onready var state_machine: Node = $StateMachine

const MAX_STOCKS: int = 3
const RESPAWN_HEIGHT_OFFSET: float = -250.0
# Fighters pass through each other (Smash). While their centers are closer than
# PUSH_DISTANCE and at similar height they are nudged apart. PUSH_SPEED is each
# fighter's push at full overlap; it must stay below half the run speed so a
# runner can still cross an opponent.
const PUSH_DISTANCE: float = 60.0
const PUSH_HEIGHT: float = 120.0
const PUSH_SPEED: float = 90.0
# Smash: you face the way you move. No turning while an action owns the body.
const TURN_DEADZONE: float = 0.1
const TURN_LOCKED_STATES: Array[String] = ["Punch", "Shoot", "Hurt", "Protect", "Defeated", "LedgeHang"]
# Air states a fighter can grab a table leg from. Punches, throws and blocks in the
# air finish first (Smash), a hit never grabs.
const LEDGE_GRAB_STATES: Array[String] = ["Jump", "Fall", "Recovery", "Helpless", "Dash"]
const INVULNERABILITY_BLINK_INTERVAL: float = 0.15

## How a jump request resolves this frame (see peek_jump / consume_jump).
enum JumpKind { NONE, GROUND, AIR }

var initial_position: Vector2
# Ring-out bounds (blast zone). Falling or being knocked past any side costs a
# stock, whether it happened by walking off or by knockback. Local to the
# owning Game (which overwrites this default from its exports) so offset Game
# rows (train.tscn) work.
var blast_zone: Rect2 = Rect2(-100.0, -400.0, 1376.0, 1210.0)
# Damage % (Smash-style ring-out combat). Starts at 0 and has no upper cap;
# it never kills by itself, it only scales knockback (see get_knockback_scale).
var damage_percent: float = 0.0
var stocks: int = MAX_STOCKS
var is_invulnerable: bool = false
# Controller seam: the controller is sampled exactly once per physics frame and
# the resulting intent is what every state reads. Locked fighters get a neutral
# intent (used by the match countdown).
var controller: FighterController
var intent: FighterIntent = FighterIntent.new()
var controls_locked: bool = false
# +1 facing right, -1 facing left. Starts toward the enemy, then follows the
# move input (see _update_facing), so the enemy can be behind.
var facing: int = 1
# Name of the food currently held above the head, or "" when empty-handed.
var held_food: String = ""

# Air bookkeeping, ticked once per frame by _tick_movement. Tuning is in the
# profile; these are only the counters.
var jumps_left: int = 0
var air_dash_available: bool = true
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
# Set by a ground jump so the floor contact of the take-off frame cannot refill
# the coyote time (that would allow ground jump + coyote jump + double jump).
var _coyote_blocked: bool = false

# Smash moves. `recovery_available` is the once-per-airtime up-recovery; it comes
# back on landing, on being hit and on a ledge grab. `charge_level` is 0..1 while
# a punch is charging. `fast_falling` lasts until the fighter lands or acts.
var recovery_available: bool = true
var charge_level: float = 0.0
var last_attack_direction: StringName = &"neutral"
var fast_falling: bool = false
# Set by a ledge jump for the next Jump._enter (0.0 = use the profile's jump).
var jump_velocity_override: float = 0.0

# Ledge (table leg) bookkeeping. `ledge_side` is -1 for the left end, +1 for the
# right end and 0 when not hanging. `ledge_grabs` counts grabs since the last
# time the fighter touched the ground or was hit (it shortens the invulnerability).
var ledge_side: int = 0
var ledge_grabs: int = 0
var ledge_anchor: Vector2 = Vector2.ZERO
var _ledge_lockout: float = 0.0
var _feet_offset: float = 94.0

var _invuln_timer: Timer
var _blink_tween: Tween

# Runs parent-first, before the state machine children use `profile`.
func _enter_tree() -> void:
	if profile == null:
		profile = FighterProfile.new()

func _ready():
	initial_position = position
	var body := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body and body.shape is RectangleShape2D:
		_feet_offset = body.position.y + (body.shape as RectangleShape2D).size.y / 2.0
	jumps_left = profile.max_air_jumps if profile.can_double_jump else 0
	air_dash_available = profile.can_dash

	# One node-owned timer ends invulnerability, so it pauses with the game, dies
	# with the fighter and a newer grant can never be cut short by an older one.
	_invuln_timer = Timer.new()
	_invuln_timer.one_shot = true
	add_child(_invuln_timer)
	_invuln_timer.timeout.connect(_on_invulnerability_timeout)

	# Aplicar configuración del personaje si ya está asignado
	if character_ui:
		_apply_character_ui_settings()

	if controller == null:
		set_controller(_resolve_controller())

	if enemy:
		facing = 1 if enemy.global_position.x >= global_position.x else -1
	animated_sprite_2d.flip_h = facing < 0

func _physics_process(delta: float) -> void:
	# The only controller sample per frame; parent-first physics order makes
	# this intent visible to the state machine child in the same frame.
	intent = FighterIntent.new() if (controls_locked or controller == null) else controller.sample(delta)
	_tick_movement(delta)

	if ai_controller_2d.needs_reset:
		ai_controller_2d.reset()
		reset_player()
		return

	_update_facing()
	move_and_slide()
	_apply_soft_push(delta)
	_try_ledge_grab()
	_check_blast_zone()

# Floor contact is the result of the previous frame's move_and_slide. Landing
# refills the air jump, air dash and coyote time; leaving the floor only runs the
# coyote time down. A press always refreshes the jump buffer.
func _tick_movement(delta: float) -> void:
	if intent.jump_pressed:
		jump_buffer_timer = profile.jump_buffer
	else:
		jump_buffer_timer = maxf(0.0, jump_buffer_timer - delta)

	_ledge_lockout = maxf(0.0, _ledge_lockout - delta)
	if is_on_floor():
		if not _coyote_blocked:
			coyote_timer = profile.coyote_time
		restore_air_actions()
		ledge_grabs = 0
	else:
		_coyote_blocked = false
		coyote_timer = maxf(0.0, coyote_timer - delta)

## Refills the double jump and the air dash (landing, being hit, respawning).
func restore_air_actions() -> void:
	jumps_left = profile.max_air_jumps if profile.can_double_jump else 0
	air_dash_available = profile.can_dash
	recovery_available = true
	fast_falling = false

## What a jump would be right now, without spending anything. NONE unless a jump
## was requested within the buffer window. GROUND on the floor or inside the
## coyote window; AIR only on a fresh press with an air jump left.
func peek_jump() -> JumpKind:
	if jump_buffer_timer <= 0.0:
		return JumpKind.NONE
	if is_on_floor() or coyote_timer > 0.0:
		return JumpKind.GROUND
	if intent.jump_pressed and jumps_left > 0:
		return JumpKind.AIR
	return JumpKind.NONE

## Resolves and spends the jump. Called once from Jump._enter.
func consume_jump() -> JumpKind:
	var kind := peek_jump()
	match kind:
		JumpKind.GROUND:
			coyote_timer = 0.0
			_coyote_blocked = true
			jump_buffer_timer = 0.0
		JumpKind.AIR:
			jumps_left -= 1
			jump_buffer_timer = 0.0
	return kind

func _update_facing() -> void:
	if absf(intent.move_x) > TURN_DEADZONE and not _is_turn_locked():
		facing = 1 if intent.move_x > 0.0 else -1
	animated_sprite_2d.flip_h = facing < 0

func _is_turn_locked() -> bool:
	return TURN_LOCKED_STATES.has(_state_name())

func _state_name() -> String:
	if state_machine == null or state_machine.current_state == null:
		return ""
	return String(state_machine.current_state.name)

# --------------------------------------------------------------------- ledge

## Grabs a table leg when an airborne fighter falls past the end of the table
## within reach (Smash ledge grab). Only holding down (fast fall) skips it: pushing away does not,
## and the fighter turns to face the stage on the grab.
func _try_ledge_grab() -> void:
	if not profile.can_ledge_grab or _ledge_lockout > 0.0 or stocks <= 0:
		return
	if is_on_floor() or velocity.y < -profile.ledge_max_rise:
		return
	if not LEDGE_GRAB_STATES.has(_state_name()) or intent.aim == FighterIntent.Aim.DOWN:
		return
	var game := get_parent()
	if game == null or not game.has_method("get_ledges"):
		return
	for ledge: Dictionary in game.get_ledges():
		var side: int = ledge["side"]
		var hang_x: float = ledge["x"] + side * profile.ledge_hang_offset
		var top: float = ledge["top"]
		var lowest: float = ledge["bottom"] - _feet_offset
		var highest: float = top + profile.ledge_hang_depth - profile.ledge_snap_up
		if absf(position.x - hang_x) > profile.ledge_reach_x or position.y < highest or position.y > lowest:
			continue
		_grab_ledge(side, Vector2(hang_x, maxf(position.y, top + profile.ledge_hang_depth)))
		return

func _grab_ledge(side: int, anchor: Vector2) -> void:
	# One fighter per leg: the newcomer kicks the one hanging there (ledge trump).
	if enemy is Fighter and enemy.ledge_side == side:
		enemy.trump_off_ledge()
	ledge_side = side
	ledge_anchor = anchor
	ledge_grabs += 1
	state_machine._change_state("LedgeHang")

## Kicked off the leg by another fighter: falls away and cannot regrab at once.
func trump_off_ledge() -> void:
	if ledge_side == 0:
		return
	var side := ledge_side
	state_machine.velocity = Vector2(side * 120.0, 0.0)
	velocity = state_machine.velocity
	state_machine._change_state("Fall")
	block_ledge_grab(profile.ledge_regrab_lockout)

## No ledge grab for `seconds` (after letting go of a leg or being trumped).
func block_ledge_grab(seconds: float) -> void:
	_ledge_lockout = maxf(_ledge_lockout, seconds)

## Invulnerability of the current grab: the first one gets the full time, every
## further grab since the ground (or a hit) gets `ledge_invuln_decay` less.
func ledge_invulnerability() -> float:
	return maxf(0.0, profile.ledge_invuln_first - profile.ledge_invuln_decay * (ledge_grabs - 1))

## Glow while charging a smash: `charge` 0..1 shows it and grows it with the
## charge; a negative value hides it.
func set_charge_visual(charge: float) -> void:
	if charge_glow == null:
		return
	if charge < 0.0:
		charge_glow.visible = false
		animated_sprite_2d.modulate = Color.WHITE
		animated_sprite_2d.offset = Vector2.ZERO
		return
	# The fighter keeps its own colors: a bright flash (modulate above 1 brightens
	# the sprite) at 10-15 Hz that speeds up with the charge, plus a tiny shake.
	var seconds := Time.get_ticks_msec() / 1000.0
	var hz := lerpf(profile.charge_flash_hz.x, profile.charge_flash_hz.y, charge)
	var flash_on := sin(seconds * TAU * hz) > 0.0
	var boost := lerpf(profile.charge_flash_boost.x, profile.charge_flash_boost.y, charge) if flash_on else 0.0
	animated_sprite_2d.modulate = Color(1.0 + boost, 1.0 + boost, 1.0 + boost, 1.0)
	var shake := lerpf(profile.charge_shake.x, profile.charge_shake.y, charge)
	animated_sprite_2d.offset = Vector2(GameRng.randf_range(-shake, shake), GameRng.randf_range(-shake, shake))
	# A small additive glow at the fist: white-hot with a hint of the fighter's color.
	var tint: Color = character_ui.color if character_ui else Color.WHITE
	var alpha := lerpf(profile.charge_glow_alpha.x, profile.charge_glow_alpha.y, charge)
	var pulse := 1.0 + 0.1 * sin(seconds * TAU * hz)
	charge_glow.modulate = Color(Color.WHITE.lerp(tint, 0.25), alpha)
	charge_glow.position = Vector2(profile.charge_glow_offset.x * facing, profile.charge_glow_offset.y)
	charge_glow.scale = Vector2.ONE * lerpf(profile.charge_glow_scale.x, profile.charge_glow_scale.y, charge) * pulse
	charge_glow.visible = true

# Smash-style fighter collision: bodies do not collide, they only push each
# other gently apart on the ground plane. Both fighters run this, so the push is
# symmetric. A fighter running through the opponent is slowed, not stopped.
func _apply_soft_push(delta: float) -> void:
	if enemy == null or stocks <= 0 or enemy.get("stocks") == 0:
		return
	if ledge_side != 0:
		return
	var offset_x := global_position.x - enemy.global_position.x
	if absf(offset_x) >= PUSH_DISTANCE or absf(global_position.y - enemy.global_position.y) > PUSH_HEIGHT:
		return
	var away := signf(offset_x)
	if is_zero_approx(away):
		away = -1.0 if control_scheme == PlayerNumber.JUGADOR1 else 1.0
	var overlap := 1.0 - absf(offset_x) / PUSH_DISTANCE
	move_and_collide(Vector2(away * PUSH_SPEED * overlap * delta, 0.0))

func set_controller(new_controller: FighterController) -> void:
	controller = new_controller
	controller.bind(self)

func _resolve_controller() -> FighterController:
	match controller_kind:
		ControllerKind.HUMAN:
			return HumanController.new()
		ControllerKind.POLICY:
			return PolicyController.new()
		ControllerKind.CPU:
			return ScriptedController.new(CpuDifficulty.preset(CpuDifficulty.Level.NORMAL))
	return _resolve_auto_controller()

# AUTO: follow the AIController2D mode set by the scene. TRAINING, ONNX and
# INHERIT_FROM_SYNC are driven by the RL stack, anything else is the keyboard.
func _resolve_auto_controller() -> FighterController:
	var mode := ai_controller_2d.control_mode
	if mode == AIController2D.ControlModes.TRAINING \
			or mode == AIController2D.ControlModes.ONNX_INFERENCE \
			or mode == AIController2D.ControlModes.INHERIT_FROM_SYNC:
		return PolicyController.new()
	return HumanController.new()

## Read-only view of this fighter for consumers such as the CPU and the future
## schema module. Unversioned and not a schema: it is an open Dictionary, keys
## may be added later, and nothing here is a stable contract yet.
func get_state_snapshot() -> Dictionary:
	var state_name: StringName = &""
	if state_machine and state_machine.current_state:
		state_name = StringName(state_machine.current_state.name)
	return {
		"position": position, # Game-local: the Fighter is a child of Game.
		"velocity": velocity,
		"facing": facing,
		"on_floor": is_on_floor(),
		"damage_percent": damage_percent,
		"stocks": stocks,
		"held_food": held_food,
		"state": state_name,
		"cooldowns": {
			"punch": _cooldown_left("Punch"),
			"shoot": _cooldown_left("Shoot"),
		},
		"jumps_left": jumps_left,
		"air_dash_available": air_dash_available,
		"charge_level": charge_level,
		"recovery_available": recovery_available,
		"last_attack_direction": last_attack_direction,
		"fast_falling": fast_falling,
		"ledge_side": ledge_side,
		"ledge_grabs": ledge_grabs,
		"is_invulnerable": is_invulnerable,
		"controller": controller.kind_name() if controller else "none",
	}

func _cooldown_left(state_name: String) -> float:
	var state = state_machine.state_map.get(state_name) if state_machine else null
	if state == null:
		return 0.0
	var cooldown_timer: Timer = state.cooldown_timer
	return cooldown_timer.time_left if cooldown_timer else 0.0

func set_velocity_from_motion(vel: Vector2) -> void:
	velocity = vel

func reset_player():
	damage_percent = 0.0
	damage_changed.emit(damage_percent)
	stocks = MAX_STOCKS
	stocks_changed.emit(self, stocks)
	_stop_invulnerability()
	restore_air_actions()
	clear_held_food()
	velocity = Vector2.ZERO
	position = initial_position
	ledge_side = 0
	ledge_grabs = 0
	# The state machine owns the velocity the states integrate and a defeated
	# fighter is still in Defeated: start the next episode falling onto the stage.
	if state_machine:
		state_machine.velocity = Vector2.ZERO
		state_machine._change_state("Fall")

func game_over():
	ai_controller_2d.done = true
	ai_controller_2d.needs_reset = true

## Sets the stock count and notifies listeners (HUD, etc.). Does not touch the
## state machine, so lowering it to 0 does not defeat the fighter by itself.
func set_stocks(count: int) -> void:
	stocks = count
	stocks_changed.emit(self, stocks)

## Sets the damage % outright (sudden death) and notifies listeners.
func set_damage_percent(percent: float) -> void:
	damage_percent = percent
	damage_changed.emit(damage_percent)

## Sudden death (Smash rule): one stock, 300% damage, back on the start spot and
## standing in the air like a respawn, with no hit or invulnerability left over.
func prepare_sudden_death(damage: float) -> void:
	ledge_grabs = 0
	set_stocks(1)
	set_damage_percent(damage)
	_stop_invulnerability()
	clear_held_food()
	restore_air_actions()
	velocity = Vector2.ZERO
	if state_machine:
		state_machine.velocity = Vector2.ZERO
	position = initial_position
	if state_machine:
		state_machine._change_state("Fall")

# Adds damage and notifies listeners (HUD, etc.).
func add_damage(amount: float) -> void:
	damage_percent += amount
	damage_changed.emit(damage_percent)

# Smash-style knockback scaling: the higher the accumulated damage %,
# the stronger any knockback applied to this fighter becomes.
func get_knockback_scale() -> float:
	return profile.knockback_scale * (1.0 + damage_percent / 50.0)

# Ring-out detection: falling off stage or being knocked past the blast zone
# (in any direction) costs a stock.
func _check_blast_zone() -> void:
	if stocks <= 0:
		return
	if not blast_zone.has_point(position):
		_lose_stock()

func _lose_stock() -> void:
	stocks -= 1
	stocks_changed.emit(self, stocks)
	# Sfx skips itself under AI training (dozens of train.tscn Game rows run in
	# parallel, so it would just be noise).
	Sfx.play_event(&"ko", self)
	if stocks <= 0:
		velocity = Vector2.ZERO
		if state_machine and state_machine.state_map.has("Defeated"):
			state_machine._change_state("Defeated")
		player_defeated.emit(self)
	else:
		_respawn()

func _respawn() -> void:
	ledge_grabs = 0
	damage_percent = 0.0
	damage_changed.emit(damage_percent)
	clear_held_food()
	restore_air_actions()
	velocity = Vector2.ZERO
	# The state machine owns the velocity the states integrate; a stale knockback
	# there would carry the respawned fighter straight back out.
	if state_machine:
		state_machine.velocity = Vector2.ZERO
	position = initial_position + Vector2(0, RESPAWN_HEIGHT_OFFSET)
	if state_machine:
		state_machine._change_state("Fall")
	grant_invulnerability(profile.respawn_invulnerability)

## Makes the fighter immune to hits for `duration` seconds. A newer grant never
## shortens a running one (the longer remaining time wins), and an older timer
## can never end a newer grant because there is only one timer. The blink tween
## is owned by this node, so it pauses with the game and dies with the fighter.
func grant_invulnerability(duration: float, blink: bool = true) -> void:
	is_invulnerable = true
	_invuln_timer.start(maxf(_invuln_timer.time_left, duration))
	if _blink_tween:
		_blink_tween.kill()
		_blink_tween = null
	if blink:
		_blink_tween = create_tween().set_loops()
		_blink_tween.tween_property(animated_sprite_2d, "visible", false, 0.0)
		_blink_tween.tween_interval(INVULNERABILITY_BLINK_INTERVAL / 2.0)
		_blink_tween.tween_property(animated_sprite_2d, "visible", true, 0.0)
		_blink_tween.tween_interval(INVULNERABILITY_BLINK_INTERVAL / 2.0)

func _on_invulnerability_timeout() -> void:
	_stop_invulnerability()

func _stop_invulnerability() -> void:
	if _invuln_timer:
		_invuln_timer.stop()
	if _blink_tween:
		_blink_tween.kill()
		_blink_tween = null
	is_invulnerable = false
	animated_sprite_2d.visible = true

func is_holding_food() -> bool:
	return held_food != ""

## Picks up a FoodPickup from the stage: disables it, shows its sprite
## above the fighter's head, and frees the ground pickup node.
func pick_up_food(pickup: FoodPickup) -> void:
	if is_holding_food() or pickup == null:
		return
	pickup.mark_picked_up()
	pickup.visible = false
	pickup.set_physics_process(false)
	held_food = pickup.food_name
	held_food_sprite.texture = FoodCatalog.get_texture(held_food)
	held_food_sprite.visible = true
	Sfx.play_event(&"pickup", self)
	pickup.queue_free()

func clear_held_food() -> void:
	held_food = ""
	held_food_sprite.visible = false
	held_food_sprite.texture = null

# Método simplificado que solo usa los recursos
func _apply_character_ui_settings():
	if character_ui:
		
		# Usar directamente los SpriteFrames del recurso (sin acceso al sistema de archivos)
		if animated_sprite_2d and character_ui.sprite_frames:
			animated_sprite_2d.sprite_frames = character_ui.sprite_frames
		elif animated_sprite_2d:
			push_error("No se encontraron SpriteFrames para el personaje ", character_ui.name)
