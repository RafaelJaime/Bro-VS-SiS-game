extends Control

@export var game_over_scene: Control
## The match this pause menu belongs to. Pausing is ignored once the match is
## decided ("GAME!" and the results own the screen from then on).
@export var game: Node2D

func _on_unpause_button_pressed() -> void:
	_set_open(false)

# Esc (keyboard) or Start (gamepad), through the `pause` action, toggles: the
# first press opens the menu and freezes the match (countdown and timer
# included, they all live in the pausable tree), the second one resumes.
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause") or event.is_echo():
		return
	if _match_is_over():
		return
	_set_open(not visible)
	get_viewport().set_input_as_handled()

func _match_is_over() -> bool:
	if game_over_scene and game_over_scene.visible:
		return true
	return game != null and game.get("phase") == Game.Phase.OVER

func _set_open(open: bool) -> void:
	visible = open
	get_tree().paused = open
