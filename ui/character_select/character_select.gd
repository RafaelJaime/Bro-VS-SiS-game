extends Control

@export var character_select_item_scene: PackedScene
@export_dir var characters_folder: String

@onready var characters_container: GridContainer = $Control/CenterContainer/CharactersContainer
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_player_2: AnimationPlayer = $AnimationPlayer2
@onready var player_1_ilustration: Sprite2D = $P1_movable/player1_ilustration
@onready var player_2_ilustration: Sprite2D = $P2_movable/player2_ilustration
@onready var play_button: Button = $PlayButton
@onready var ai_controller: Control = $AIController

var characters: Array[CharacterUI] = []
var player1_selected: CharacterUI
var player2_selected: CharacterUI

func _ready():
	var dir = DirAccess.open(characters_folder)
	if dir:
		dir.list_dir_begin()
		var folder_name = dir.get_next()
		while folder_name != "":
			if dir.current_is_dir():
				var folder_path = characters_folder + "/" + folder_name
				var json_path = folder_path + "/character.json"

				if FileAccess.file_exists(json_path):
					var file = FileAccess.open(json_path, FileAccess.READ)
					if file:
						var json_str = file.get_as_text()
						var result = JSON.parse_string(json_str)

						if typeof(result) == TYPE_DICTIONARY:
							var character = CharacterUI.new()
							character.name = result.get("name", folder_name)
							character.dir = folder_path

							var color_array = result.get("color", [1, 1, 1, 1])
							if color_array.size() == 4:
								character.color = Color(color_array[0], color_array[1], color_array[2], color_array[3])
							else:
								character.color = Color.WHITE

							characters.append(character)
				else:
					push_warning("Falta el archivo character.json en: " + folder_path)
			folder_name = dir.get_next()
		dir.list_dir_end()

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
	if !player1_selected:
		player1_selected = item.character
		set_ilustration(item.character, player_1_ilustration)
		animation_player.play("player1_selected")
		ai_controller.show_ai_ui(true)
	else:
		player2_selected = item.character.duplicate()
		print(player2_selected)
		player2_selected.color = item.character.color.inverted()
		if item.character.equals(player1_selected):
			player_2_ilustration.modulate = player2_selected.color
		else:
			player_2_ilustration.modulate = Color.WHITE
		set_ilustration(player2_selected, player_2_ilustration)
		animation_player_2.play("player2_selected")
		play_button.visible = true
		ai_controller.show_ai_ui(false)


func set_ilustration(character: CharacterUI, sprite: Sprite2D):
	var ilustration_folder = character.dir + "/ilustration"
	var dir = DirAccess.open(ilustration_folder)
	
	if dir:
		dir.list_dir_begin()
		var valid_image_count = 0
		while true:
			var file_name = dir.get_next()
			if file_name == "":
				break
			if not dir.current_is_dir() and file_name.get_extension() in ["png", "webp", "jpg", "jpeg"]:
				valid_image_count += 1
				if valid_image_count == 2:
					var image_path = ilustration_folder + "/" + file_name
					var texture = load(image_path)
					if texture is Texture2D:
						sprite.texture = texture
					break
		dir.list_dir_end()
	else:
		print("No se pudo abrir la carpeta:", ilustration_folder)

func _on_play_button_pressed() -> void:
	ai_controller.on_play_pressed()
	SceneManager.play_game(player1_selected, player2_selected)
