extends Control

@export var game_over_scene: Control

func _on_unpause_button_pressed() -> void:
	visible = false
	get_tree().paused = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not game_over_scene.visible:
		get_tree().paused = true
		visible = true
