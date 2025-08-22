extends Button
class_name SoundsButton

@export var hover_sound: AudioStream = preload("res://assets/sounds/button.mp3")
var player: AudioStreamPlayer

func _ready() -> void:
	player = AudioStreamPlayer.new()
	add_child(player)

	self.connect("mouse_entered", _on_mouse_entered)

func _on_mouse_entered() -> void:
	if hover_sound:
		player.stream = hover_sound
		player.play()
