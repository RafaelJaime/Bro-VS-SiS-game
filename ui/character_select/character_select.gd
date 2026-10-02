extends Control

@export var character_select_item_scene: PackedScene
@export var characters: Array[CharacterUI] = []

@onready var characters_container: GridContainer = $Control/CenterContainer/CharactersContainer
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_player_2: AnimationPlayer = $AnimationPlayer2
@onready var player_1_ilustration: Sprite2D = $P1_movable/player1_ilustration
@onready var player_2_ilustration: Sprite2D = $P2_movable/player2_ilustration
@onready var play_button: Button = $PlayButton
@onready var ai_controller: Control = $AIController
@onready var p_1_point_light_2d: PointLight2D = $p1_PointLight2D
@onready var p_2_point_light_2d: PointLight2D = $p2_PointLight2D

var player1_selected: CharacterUI
var player2_selected: CharacterUI

func _ready():
	# Asegurar que los sprites sean visibles
	player_1_ilustration.visible = true
	player_2_ilustration.visible = true
	
	# Asegurar que los nodos padre sean visibles
	player_1_ilustration.get_parent().visible = true
	player_2_ilustration.get_parent().visible = true
	
	# Asegurar que tenemos z_index correcto
	player_1_ilustration.z_index = 1
	player_2_ilustration.z_index = 1
	
	for character in characters:
		_load_character(character)
	# Play waits for every selected model (a Hub download or the bundled one) to be ready.
	ai_controller.selection_changed.connect(_update_play_button)
	_update_play_button()

## Play is disabled while a selected model is loading or failed to load.
func _update_play_button() -> void:
	var ready_to_play: bool = ai_controller.is_ready_to_play()
	play_button.disabled = not ready_to_play
	play_button.modulate.a = 1.0 if ready_to_play else 0.4

func _load_character(character: CharacterUI):
	if character_select_item_scene:
		var item = character_select_item_scene.instantiate() as CharacterSelectItem
		item.set_data(character)
		item.connect("pressed", _on_character_pressed.bind(item))
		characters_container.add_child(item)
	else:
		push_error("No se ha asignado la escena de CharacterSelectItem")

func _on_character_pressed(item: CharacterSelectItem) -> void:
	var character := item.character

	if player1_selected == null:
		select_player1(character)
	else:
		select_player2(character)

func select_player1(character: CharacterUI) -> void:
	player1_selected = character
	set_ilustration(character, player_1_ilustration)
	animation_player.play("player1_selected")
	ai_controller.show_ai_ui(true)
	p_1_point_light_2d.enabled = true
	p_1_point_light_2d.color = player1_selected.color

func select_player2(character: CharacterUI) -> void:
	player2_selected = character
	
	# Determinar si es el mismo personaje
	var is_same = player2_selected.equals(player1_selected)
	
	# Asignar la textura
	set_ilustration(player2_selected, player_2_ilustration)
	
	# Aplicar color apropiado
	if is_same:
		player_2_ilustration.modulate = player2_selected.color.inverted()
	else:
		player_2_ilustration.modulate = Color.WHITE
	
	animation_player_2.play("player2_selected")
	ai_controller.show_ai_ui(false)
	play_button.visible = true
	p_2_point_light_2d.enabled = true
	p_2_point_light_2d.color = player2_selected.color

func set_ilustration(character: CharacterUI, sprite: Sprite2D):
	if character == null:
		push_error("Personaje es nulo")
		return
	if sprite == null:
		push_error("Sprite es nulo")
		return
	
	# Asegurar que el sprite es visible
	sprite.visible = true
	sprite.modulate = Color.WHITE
	sprite.self_modulate = Color.WHITE
	
	# Intentar asignar la ilustración directamente
	if character.illustration != null:
		sprite.texture = character.illustration
		return
	
	# Si no funciona, intentar cargar manualmente por nombre de personaje
	var texture_path = ""
	match character.name.to_lower():
		"rafael":
			texture_path = "res://assets/images/game/characters/rafael/ilustration/Ilustracion_r1.png"
		"matilde":
			texture_path = "res://assets/images/game/characters/matilde/ilustration/Ilustracion_m1.png"
	
	if texture_path != "":
		var loaded_texture = load(texture_path)
		if loaded_texture:
			sprite.texture = loaded_texture
		else:
			push_error("No se pudo cargar textura: ", texture_path)
	else:
		push_error("No hay textura definida para ", character.name)

func _on_play_button_pressed() -> void:
	if not ai_controller.is_ready_to_play():
		return
	var config_1: ControllerConfig = ai_controller.get_controller_config(false)
	var config_2: ControllerConfig = ai_controller.get_controller_config(true)

	if player1_selected.equals(player2_selected):
		var player2_copy = player2_selected.duplicate()
		player2_copy.color = player2_selected.color.inverted()
		SceneManager.play_game(player1_selected, player2_copy, config_1, config_2)
	else:
		SceneManager.play_game(player1_selected, player2_selected, config_1, config_2)
