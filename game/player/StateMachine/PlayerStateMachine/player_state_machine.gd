extends StateMachine
class_name PlayerStateMachine

@export var animated_sprite_2d: AnimatedSprite2D
@export var ai_controller_2d: AIController2D

var input_dir: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	ai_controller_2d.init(owner)
	for child: Motion in get_children():
		child.animation_state_changed.connect(play_animated_sprite)
	
	return super._ready()

func play_animated_sprite(animation_name: String) -> void:
	if animated_sprite_2d.sprite_frames.has_animation(animation_name.capitalize()):
		animated_sprite_2d.play(animation_name.capitalize())
