extends Control

# P1
@onready var ai_button_p1: Button = $ControlP1/AIButton
@onready var text_edit_p1: TextEdit = $ControlP1/TextEdit
@onready var search_button_p1: Button = $ControlP1/SearchButton
@onready var option_button_p1: OptionButton = $ControlP1/OptionButton
@onready var back_button_p1: Button = $ControlP1/BackButton
@onready var controller_option_p1: OptionButton = $ControlP1/ControllerOption

# P2
@onready var ai_button_p2: Button = $ControlP2/AIButton
@onready var text_edit_p2: TextEdit = $ControlP2/TextEdit
@onready var search_button_p2: Button = $ControlP2/SearchButton
@onready var option_button_p2: OptionButton = $ControlP2/OptionButton
@onready var back_button_p2: Button = $ControlP2/BackButton
@onready var controller_option_p2: OptionButton = $ControlP2/ControllerOption

# Entries of ControllerOption, in order: Human, then CPU Easy, Normal, Hard.
# Entry N (N >= 1) is the CpuDifficulty.Level N - 1.
const OPTION_HUMAN := 0

func _ready() -> void:
	ModelManager.models_loaded.connect(_on_models_loaded)
	ModelManager.model_downloaded.connect(_on_model_downloaded)

func _get_player_controls(is_p2: bool) -> Dictionary:
	var text_edit = text_edit_p2 if is_p2 else text_edit_p1
	var ai_button = ai_button_p2 if is_p2 else ai_button_p1
	var search_button = search_button_p2 if is_p2 else search_button_p1
	var option_button = option_button_p2 if is_p2 else option_button_p1
	var back_button = back_button_p2 if is_p2 else back_button_p1

	return {
		"text_edit": text_edit,
		"ai_button": ai_button,
		"search_button": search_button,
		"option_button": option_button,
		"back_button": back_button,
		"controller_option": controller_option_p2 if is_p2 else controller_option_p1,
	}

## The controller this player picked: Human, a CPU level, or (when a model was
## chosen from the HuggingFace list) the policy that model drives. The model is
## explicit: it only wins when the user selected one, never because a file exists.
func get_controller_config(is_p2: bool) -> ControllerConfig:
	var controls = _get_player_controls(is_p2)
	if controls.option_button.selected >= 0:
		return ControllerConfig.policy(ModelManager.get_model_path(1 if is_p2 else 0))
	var index: int = controls.controller_option.selected
	if index <= OPTION_HUMAN:
		return ControllerConfig.human()
	return ControllerConfig.cpu(index - 1)

func _on_models_loaded(player_id: int, models: Array) -> void:
	var is_p2 = player_id == 1
	var controls = _get_player_controls(is_p2)
	
	# Show back and option buttons
	controls.back_button.visible = true
	controls.option_button.visible = true

	if !models.is_empty():
		update_menu_button(controls.option_button, models)

func _on_model_downloaded(player_id: int, success: bool) -> void:
	if success:
		print("Model downloaded successfully for player", player_id)
		check_both_models_ready()
	else:
		print("Failed to download model for player", player_id)

func update_menu_button(menu_button: OptionButton, model_ids: Array) -> void:
	menu_button.clear()
	var popup := menu_button.get_popup()
	for model_id in model_ids:
		popup.add_item(model_id)

func check_both_models_ready() -> void:
	if ModelManager.model_exists(0) and ModelManager.model_exists(1):
		print("Both models ready! Starting fight...")

# Show initial AI button only
func initial_menu(is_p2: bool = false) -> void:
	var controls = _get_player_controls(is_p2)
	
	controls.ai_button.visible = true
	controls.controller_option.visible = true
	controls.text_edit.visible = false
	controls.search_button.visible = false
	controls.option_button.visible = false
	controls.back_button.visible = false
	controls.option_button.selected = -1

# Show username input and search button
func search_user_menu(is_p2: bool = false) -> void:
	var controls = _get_player_controls(is_p2)
	
	controls.ai_button.visible = false
	controls.controller_option.visible = false
	controls.text_edit.visible = true
	controls.search_button.visible = true
	controls.option_button.visible = false
	controls.back_button.visible = true
	controls.option_button.selected = -1

# Show model selection menu
func select_model_menu(is_p2: bool = false) -> void:
	var controls = _get_player_controls(is_p2)
	
	controls.text_edit.visible = false
	controls.search_button.visible = false
	controls.option_button.visible = true
	controls.back_button.visible = true

# Public method to show AI UI (used externally?)
func show_ai_ui(player_1: bool = false):
	initial_menu(not player_1) # if player_1 is true -> show P1 menu, else P2

func on_play_pressed() -> void:
	if option_button_p1.selected >= 0:
		var model_1 = option_button_p1.get_item_text(option_button_p1.selected)
		ModelManager.download_model(model_1, 0)
	if option_button_p2.selected >= 0:
		var model_2 = option_button_p2.get_item_text(option_button_p2.selected)
		ModelManager.download_model(model_2, 1)

# --- SIGNAL HANDLERS ---

func _on_ai_button_pressed(is_p2: bool) -> void:
	search_user_menu(is_p2)

func _on_search_button_pressed(is_p2: bool) -> void:
	var controls = _get_player_controls(is_p2)
	var user = controls.text_edit.text.strip_edges()
	
	if user.is_empty():
		return  # Prevent empty search

	controls.text_edit.visible = false
	controls.search_button.visible = false
	controls.back_button.visible = true  # Keep back visible

	ModelManager.fetch_user_models(user, is_p2)

func _on_back_button_pressed(is_p2: bool) -> void:
	var controls = _get_player_controls(is_p2)
	
	if !controls.search_button.visible:
		# Currently in model selection → go back to search
		select_model_to_search(is_p2)
	else:
		# Currently in search → go back to AI button (initial)
		initial_menu(is_p2)

# Helper: go from model selection back to search
func select_model_to_search(is_p2: bool) -> void:
	var controls = _get_player_controls(is_p2)
	controls.text_edit.visible = true
	controls.search_button.visible = true
	controls.option_button.visible = false
	controls.option_button.selected = -1
