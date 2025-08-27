extends CharacterBody2D
class_name Fighter

signal updated_characterUI

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
@onready var state_machine: Node = $StateMachine

var initial_position: Vector2
var max_health: int = 100
var health: int = 100

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

func set_velocity_from_motion(vel: Vector2) -> void:
	velocity = vel

func reset_player():
	health = max_health
	velocity = Vector2.ZERO
	position = initial_position

func game_over():
	ai_controller_2d.done = true
	ai_controller_2d.needs_reset = true

# Método simplificado que solo usa los recursos
func _apply_character_ui_settings():
	if character_ui:
		
		# Usar directamente los SpriteFrames del recurso (sin acceso al sistema de archivos)
		if animated_sprite_2d and character_ui.sprite_frames:
			animated_sprite_2d.sprite_frames = character_ui.sprite_frames
			print(animated_sprite_2d.animation)
		elif animated_sprite_2d:
			push_error("No se encontraron SpriteFrames para el personaje ", character_ui.name)
