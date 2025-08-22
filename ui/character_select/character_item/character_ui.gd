extends Resource
class_name CharacterUI

@export var name: String = "Character"
@export var color: Color = Color.WHITE
@export var illustration: Texture2D
@export var face_texture: Texture2D
@export var sprite_frames: SpriteFrames

func equals(other: CharacterUI) -> bool:
	if other == null:
		return false
	return name == other.name
