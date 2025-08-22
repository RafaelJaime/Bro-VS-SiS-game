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
	ai_controller_2d.init(self)
	
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
	velocity = Vector2.ZERO
	position = initial_position

func reward_ai(amount: float):
	ai_controller_2d.reward += amount

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

#@export var character: CharacterGame
#const SPEED = 300.0
#const JUMP_VELOCITY = -800.0
#var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
#var controls = {
	#1: {
		#"left": KEY_A,
		#"right": KEY_D,
		#"jump": KEY_W,
		#"attack": KEY_F,
		#"shoot": KEY_G
	#},
	#2: {
		#"left": KEY_LEFT,
		#"right": KEY_RIGHT,
		#"jump": KEY_UP,
		#"attack": KEY_K,
		#"shoot": KEY_L
	#}
#}
#
#
#
#
#func handle_gravity(delta):
	#if not is_on_floor():
		#velocity.y += gravity * delta
#
#func handle_jump():
	#var should_jump = false
	#if ai_controller_2d.heuristic == "human":
		#should_jump = is_key_pressed("jump")
	#else:
		#should_jump = ai_controller_2d.jump_action > 0.5
	#
	#if should_jump and is_on_floor():
		#velocity.y = JUMP_VELOCITY
#
#func handle_movement():
	#var direction = 0
	#
	#if ai_controller_2d.heuristic == "human":
		#if is_key_pressed("left"):
			#direction -= 1
		#if is_key_pressed("right"):
			#direction += 1
	#else:
		#if ai_controller_2d.move_left_action > 0.5:
			#direction -= 1
		#if ai_controller_2d.move_right_action > 0.5:
			#direction += 1
		#
	#if direction != 0:
		#velocity.x = direction * SPEED
	#else:
		#velocity.x = move_toward(velocity.x, 0, SPEED)
#
#func handle_actions():
	#var should_attack = false
	#var should_shoot = false
	#
	#if ai_controller_2d.heuristic == "human":
		#should_attack = is_key_just_pressed("attack")
		#should_shoot = is_key_just_pressed("shoot")
	#else:
		#should_attack = ai_controller_2d.attack_action > 0.5
		#should_shoot = ai_controller_2d.shoot_action > 0.5
	#
	#if should_attack:
		#attack()
	#if should_shoot:
		#shoot()
#
#func is_key_pressed(action: String) -> bool:
	#return Input.is_physical_key_pressed(controls[control_scheme][action])
#
#func is_key_just_pressed(action: String) -> bool:
	#return Input.is_key_pressed(controls[control_scheme][action])
#
#func attack():
	#ai_controller_2d.reward += 0.1
	#punch_area.monitoring = true
	#await get_tree().create_timer(0.2).timeout
	#punch_area.monitoring = false
#
#func shoot():
	#print("Shooting with scheme ", control_scheme)
	#ai_controller_2d.reward += 0.1
#
#func take_damage(enemy: Fighter):
	#if character:
		#character.health -= 10
	#velocity = Vector2(2000 if position.x > enemy.position.x else -2000, -400)
#
#
#func _on_punch_area_body_entered(body: Node2D) -> void:
	#if body != self and body is Fighter:
		#body.take_damage(self)
