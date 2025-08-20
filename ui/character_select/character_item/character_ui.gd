extends Resource
class_name CharacterUI

@export var name: String
@export var dir: String
@export var color: Color = Color.WHITE

func equals(other: CharacterUI) -> bool:
	if other == null:
		return false
	return name == other.name and dir == other.dir
