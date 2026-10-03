extends Node


func _ready() -> void:
	SceneManager.scene_container = self
	SceneManager.change_scene("res://ui/main_menu/main_menu.tscn")
