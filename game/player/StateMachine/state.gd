extends Node
class_name State

@warning_ignore("unused_signal")
signal finished(next_state: String)

func _enter() -> void:
	return

func _exit() -> void:
	return

# Gate checked by Motion.handle_actions() before switching into this state.
func can_enter() -> bool:
	return true

func _update(_delta: float) -> void:
	return
