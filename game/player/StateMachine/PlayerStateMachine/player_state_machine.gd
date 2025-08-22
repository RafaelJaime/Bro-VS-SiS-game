extends StateMachine

@warning_ignore("unused_signal")
signal player_defeated

@export var animated_sprite_2d: AnimatedSprite2D

var input_dir: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	for child: Motion in get_children():
		child.animation_state_changed.connect(play_animated_sprite)
	
	return super._ready()

func play_animated_sprite(animation_name: String) -> void:
	if animated_sprite_2d.sprite_frames.has_animation(animation_name.capitalize()):
		animated_sprite_2d.play(animation_name.capitalize())
