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
enum PlayerNumber { JUGADOR1, JUGADOR2 }
@export var control_scheme: PlayerNumber = PlayerNumber.JUGADOR1

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
# Name of the food currently held above the head, or "" when empty-handed.
var held_food: String = ""

func _ready():
	initial_position = position

	# Aplicar configuración del personaje si ya está asignado
	if character_ui:
		_apply_character_ui_settings()

func _physics_process(_delta: float) -> void:
	if ai_controller_2d.needs_reset:
		ai_controller_2d.reset()
		reset_player()
		return

	if enemy:
		animated_sprite_2d.flip_h = enemy.global_position.x < global_position.x
	move_and_slide()
	_check_blast_zone()

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
	return 1.0 + damage_percent / 50.0

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
			print(animated_sprite_2d.animation)
		elif animated_sprite_2d:
			push_error("No se encontraron SpriteFrames para el personaje ", character_ui.name)
