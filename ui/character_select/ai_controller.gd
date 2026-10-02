extends Control

# P1
@onready var ai_button_p1: Button = $ControlP1/AIButton
@onready var option_button_p1: OptionButton = $ControlP1/OptionButton
@onready var back_button_p1: Button = $ControlP1/BackButton
@onready var controller_option_p1: OptionButton = $ControlP1/ControllerOption

# P2
@onready var ai_button_p2: Button = $ControlP2/AIButton
@onready var option_button_p2: OptionButton = $ControlP2/OptionButton
@onready var back_button_p2: Button = $ControlP2/BackButton
@onready var controller_option_p2: OptionButton = $ControlP2/ControllerOption

# Entries of ControllerOption, in order: Human, then CPU Easy, Normal, Hard.
# Entry N (N >= 1) is the CpuDifficulty.Level N - 1.
const OPTION_HUMAN := 0

## The Hub model list (shared by both players); the choice is applied to whoever opened it.
@onready var model_picker: Control = $"../ModelPicker"
var _picking_p2 := false

func _ready() -> void:
	ModelManager.model_downloaded.connect(_on_model_downloaded)
	model_picker.model_chosen.connect(_on_model_chosen)
	model_picker.cancelled.connect(_on_picker_cancelled)

func _get_player_controls(is_p2: bool) -> Dictionary:
	var ai_button = ai_button_p2 if is_p2 else ai_button_p1
	var option_button = option_button_p2 if is_p2 else option_button_p1
	var back_button = back_button_p2 if is_p2 else back_button_p1

	return {
		"ai_button": ai_button,
		"option_button": option_button,
		"back_button": back_button,
		"controller_option": controller_option_p2 if is_p2 else controller_option_p1,
	}

## The controller this player picked: Human, a CPU level, or (when a model was
## chosen from the Hugging Face picker) the policy that model drives. The model is
## explicit: it only wins when the user selected one, never because a file exists.
func get_controller_config(is_p2: bool) -> ControllerConfig:
	var controls = _get_player_controls(is_p2)
	if controls.option_button.selected >= 0:
		return ControllerConfig.policy(ModelManager.get_model_path(1 if is_p2 else 0))
	var index: int = controls.controller_option.selected
	if index <= OPTION_HUMAN:
		return ControllerConfig.human()
	return ControllerConfig.cpu(index - 1)

## The player picked a compatible model in the picker: it becomes this player's
## explicit controller (shown in the option button, with Back to undo it).
func _on_model_chosen(model: HubModel) -> void:
	var controls = _get_player_controls(_picking_p2)
	update_menu_button(controls.option_button, [model.id])
	controls.option_button.select(0)
	select_model_menu(_picking_p2)

func _on_picker_cancelled() -> void:
	initial_menu(_picking_p2)

func _on_model_downloaded(player_id: int, success: bool) -> void:
	if success:
		check_both_models_ready()
	else:
		push_warning("Failed to download model for player %d" % player_id)

func update_menu_button(menu_button: OptionButton, model_ids: Array) -> void:
	menu_button.clear()
	for model_id in model_ids:
		menu_button.add_item(model_id)

func check_both_models_ready() -> void:
	# Nothing to do here: the match starts from the play button.
	pass

# Show initial AI button only
func initial_menu(is_p2: bool = false) -> void:
	var controls = _get_player_controls(is_p2)

	controls.ai_button.visible = true
	controls.controller_option.visible = true
	controls.option_button.visible = false
	controls.back_button.visible = false
	controls.option_button.selected = -1

# Open the Hub model picker for this player; the CPU option hides while it is open.
func open_model_picker(is_p2: bool = false) -> void:
	var controls = _get_player_controls(is_p2)
	_picking_p2 = is_p2
	controls.ai_button.visible = false
	controls.controller_option.visible = false
	controls.option_button.visible = false
	controls.back_button.visible = true
	controls.option_button.selected = -1
	model_picker.open()

# Show the chosen model with its Back button
func select_model_menu(is_p2: bool = false) -> void:
	var controls = _get_player_controls(is_p2)

	controls.ai_button.visible = false
	controls.controller_option.visible = false
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
	open_model_picker(is_p2)

# Back drops the chosen model and returns to the Human / CPU options.
func _on_back_button_pressed(is_p2: bool) -> void:
	model_picker.close()
	initial_menu(is_p2)
