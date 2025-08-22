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

var player1_selected: CharacterUI
var player2_selected: CharacterUI

func _ready():
	for character in characters:
		_load_character(character)
	print("Total de personajes:", characters.size())

func _load_character(character: CharacterUI):
	if character_select_item_scene:
		var item = character_select_item_scene.instantiate() as CharacterSelectItem
		item.set_data(character)
		item.connect("pressed", _on_character_pressed.bind(item))
		characters_container.add_child(item)
	else:
		push_error("No se ha asignado la escena de CharacterSelectItem")

func _on_character_pressed(item: CharacterSelectItem):
	var character = item.character
	
	if !player1_selected:
		player1_selected = character
		set_ilustration(character, player_1_ilustration)
		animation_player.play("player1_selected")
		ai_controller.show_ai_ui(true)
	else:
		# Si ya hay un personaje seleccionado para player2, limpiamos antes
		if player2_selected:
			pass  # opcional: resetear algo si es necesario

		# Creamos una copia del personaje para evitar modificar el original
		player2_selected = character.duplicate()

		if player2_selected.equals(player1_selected):
			# Invertimos el color solo visualmente
			player_2_ilustration.modulate = player2_selected.color.inverted()
		else:
			player_2_ilustration.modulate = Color.WHITE

		set_ilustration(player2_selected, player_2_ilustration)
		animation_player_2.play("player2_selected")
		play_button.visible = true
		ai_controller.show_ai_ui(false)

func set_ilustration(character: CharacterUI, sprite: Sprite2D):
	sprite.texture = character.illustration

func _on_play_button_pressed() -> void:
	ai_controller.on_play_pressed()
	
	if player1_selected.equals(player2_selected):
		var player2_copy = player2_selected.duplicate()
		player2_copy.color = player2_selected.color.inverted()
		SceneManager.play_game(player1_selected, player2_copy)
	else:
		SceneManager.play_game(player1_selected, player2_selected)
