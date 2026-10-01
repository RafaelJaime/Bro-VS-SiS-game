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
@onready var punch_area: Area2D = $PunchArea
@onready var pickup_area: Area2D = $PickupArea
@onready var held_food_sprite: Sprite2D = $HeldFoodSprite
@onready var state_machine: Node = $StateMachine

# Ring-out stage bounds (blast zone). Falling or being knocked past these
# costs a stock, whether it happened by walking off or by knockback.
# Bounds are local to the owning Game so offset Game rows (train.tscn) work.
const MAX_STOCKS: int = 3
const BLAST_LEFT: float = -150.0
const BLAST_RIGHT: float = 950.0
const BLAST_BOTTOM: float = 750.0
const RESPAWN_HEIGHT_OFFSET: float = -250.0
const RESPAWN_INVULNERABILITY: float = 1.5
const INVULNERABILITY_BLINK_INTERVAL: float = 0.15

var initial_position: Vector2
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
# +1 when the enemy is to the right, -1 when to the left.
var facing: int = 1
# Name of the food currently held above the head, or "" when empty-handed.
var held_food: String = ""

# Runs parent-first, before the state machine children use `profile`.
func _enter_tree() -> void:
	if profile == null:
		profile = FighterProfile.new()

func _ready():
	initial_position = position

	# Aplicar configuración del personaje si ya está asignado
	if character_ui:
		_apply_character_ui_settings()

	if controller == null:
		set_controller(_resolve_controller())

func _physics_process(delta: float) -> void:
	# The only controller sample per frame; parent-first physics order makes
	# this intent visible to the state machine child in the same frame.
	intent = FighterIntent.new() if (controls_locked or controller == null) else controller.sample(delta)

	if ai_controller_2d.needs_reset:
		ai_controller_2d.reset()
		reset_player()
		return

	if enemy:
		facing = 1 if enemy.global_position.x >= global_position.x else -1
		animated_sprite_2d.flip_h = enemy.global_position.x < global_position.x
	move_and_slide()
	_check_blast_zone()

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
			# TODO(S3): ScriptedController. Human placeholder until then.
			return HumanController.new()
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
		"jumps_left": 0, # Placeholder until the double jump exists.
		"air_dash_available": false, # Placeholder until the air dash exists.
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
	is_invulnerable = false
	animated_sprite_2d.visible = true
	clear_held_food()
	velocity = Vector2.ZERO
	position = initial_position

func game_over():
	ai_controller_2d.done = true
	ai_controller_2d.needs_reset = true

# Adds damage and notifies listeners (HUD, etc.).
func add_damage(amount: float) -> void:
	damage_percent += amount
	damage_changed.emit(damage_percent)

# Smash-style knockback scaling: the higher the accumulated damage %,
# the stronger any knockback applied to this fighter becomes.
func get_knockback_scale() -> float:
	return profile.knockback_scale * (1.0 + damage_percent / 50.0)

# Ring-out detection: falling off stage or being knocked past the visible
# play area (in any direction) costs a stock.
func _check_blast_zone() -> void:
	if stocks <= 0:
		return
	if position.x < BLAST_LEFT or position.x > BLAST_RIGHT or position.y > BLAST_BOTTOM:
		_lose_stock()

func _lose_stock() -> void:
	stocks -= 1
	stocks_changed.emit(self, stocks)
	# Skip SFX under AI training (see Combat._is_training: dozens of
	# train.tscn's Game rows run in parallel, so this would just be noise).
	var parent = get_parent()
	if not (parent and parent.get("training") == true):
		Sfx.play(Sfx.EXPLOSION, self)
	if stocks <= 0:
		velocity = Vector2.ZERO
		if state_machine and state_machine.state_map.has("Defeated"):
			state_machine._change_state("Defeated")
		player_defeated.emit(self)
	else:
		_respawn()

func _respawn() -> void:
	damage_percent = 0.0
	damage_changed.emit(damage_percent)
	clear_held_food()
	velocity = Vector2.ZERO
	position = initial_position + Vector2(0, RESPAWN_HEIGHT_OFFSET)
	if state_machine:
		state_machine._change_state("Fall")
	_start_invulnerability()

func _start_invulnerability() -> void:
	is_invulnerable = true
	var blink_tween = get_tree().create_tween()
	var loops = int(RESPAWN_INVULNERABILITY / INVULNERABILITY_BLINK_INTERVAL)
	blink_tween.set_loops(loops)
	blink_tween.tween_property(animated_sprite_2d, "visible", false, 0.0)
	blink_tween.tween_interval(INVULNERABILITY_BLINK_INTERVAL / 2.0)
	blink_tween.tween_property(animated_sprite_2d, "visible", true, 0.0)
	blink_tween.tween_interval(INVULNERABILITY_BLINK_INTERVAL / 2.0)
	await get_tree().create_timer(RESPAWN_INVULNERABILITY).timeout
	animated_sprite_2d.visible = true
	is_invulnerable = false

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
