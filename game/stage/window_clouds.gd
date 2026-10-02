class_name WindowClouds
extends Sprite2D

## The sky seen through the kitchen window: the cloud picture slides slowly
## sideways behind the wall layer, whose window is transparent. The sprite uses a
## region (the window's size) with texture repeat on, so the clouds wrap around.
## Game-local and in world space (the camera moves over it, it does not follow
## the camera). Freed by `Game` in training together with the backdrop.

## Pixels per second the clouds drift to the left.
@export var speed: float = 16.0

var _offset: float = 0.0

func _process(delta: float) -> void:
	if texture == null:
		return
	_offset = fposmod(_offset + speed * delta, texture.get_size().x)
	region_rect.position.x = _offset
