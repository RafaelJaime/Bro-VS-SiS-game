extends SoundsButton

func _pressed() -> void:
	get_tree().paused = false
	SceneManager.go_back()
