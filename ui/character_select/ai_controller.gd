extends Control

## The per-player controller choice of the character select: Human, a CPU level,
## the bundled "AI: BVS default" model, or a Hugging Face model from the picker.
##
## A Hub model is requested the moment it is picked (prefetch), and each panel
## shows where it is: "Resolving...", "Downloading N KB...", "Checking model...",
## ready, or the reason it failed. Cancel stops the transfer and goes back to the
## previous controller; Back does the same after a failure. Play stays disabled
## while any selected model is not ready, so a match never starts with a pending or
## invalid model, and a failed model is never replaced by a scripted CPU.

## Something changed that decides whether Play may be pressed.
signal selection_changed

# P1
@onready var ai_button_p1: Button = $ControlP1/AIButton
@onready var option_button_p1: OptionButton = $ControlP1/OptionButton
@onready var back_button_p1: Button = $ControlP1/BackButton
@onready var controller_option_p1: OptionButton = $ControlP1/ControllerOption
@onready var status_label_p1: Label = $ControlP1/StatusLabel
@onready var cancel_button_p1: Button = $ControlP1/CancelButton

# P2
@onready var ai_button_p2: Button = $ControlP2/AIButton
@onready var option_button_p2: OptionButton = $ControlP2/OptionButton
@onready var back_button_p2: Button = $ControlP2/BackButton
@onready var controller_option_p2: OptionButton = $ControlP2/ControllerOption
@onready var status_label_p2: Label = $ControlP2/StatusLabel
@onready var cancel_button_p2: Button = $ControlP2/CancelButton

# Entries of ControllerOption, in order: Human, CPU Easy, Normal, Hard, then the
# bundled model. Entries 1..3 are the CpuDifficulty.Level N - 1.
const OPTION_HUMAN := 0
const OPTION_BVS_DEFAULT := 4

const COLOR_FAILED := Color(1.0, 0.45, 0.4)
const COLOR_BUSY := Color(1.0, 0.9, 0.4)
const COLOR_READY := Color(0.55, 0.95, 0.6)

## The Hub model list (shared by both players); the choice is applied to whoever opened it.
@onready var model_picker: Control = $"../ModelPicker"
var _picking_p2 := false

func _ready() -> void:
	ModelManager.model_state_changed.connect(_on_model_state_changed)
	model_picker.model_chosen.connect(_on_model_chosen)
	model_picker.cancelled.connect(_on_picker_cancelled)
	controller_option_p1.item_selected.connect(_on_controller_selected.bind(false))
	controller_option_p2.item_selected.connect(_on_controller_selected.bind(true))
	cancel_button_p1.pressed.connect(_on_cancel_pressed.bind(false))
	cancel_button_p2.pressed.connect(_on_cancel_pressed.bind(true))
	# A match keeps its model in its ControllerConfig, so a previous visit leaves nothing to reuse here.
	ModelManager.cancel(0)
	ModelManager.cancel(1)
	refresh_status(false)
	refresh_status(true)

func _get_player_controls(is_p2: bool) -> Dictionary:
	var ai_button = ai_button_p2 if is_p2 else ai_button_p1
	var option_button = option_button_p2 if is_p2 else option_button_p1
	var back_button = back_button_p2 if is_p2 else back_button_p1

	return {
		"ai_button": ai_button,
		"option_button": option_button,
		"back_button": back_button,
		"controller_option": controller_option_p2 if is_p2 else controller_option_p1,
		"status_label": status_label_p2 if is_p2 else status_label_p1,
		"cancel_button": cancel_button_p2 if is_p2 else cancel_button_p1,
	}

static func _slot_of(is_p2: bool) -> int:
	return 1 if is_p2 else 0

## True when this player's controller is a Hub model chosen in the picker.
func uses_hub_model(is_p2: bool) -> bool:
	return _get_player_controls(is_p2).option_button.selected >= 0

## True when this player picked the bundled default.
func uses_bundled_model(is_p2: bool) -> bool:
	var controls = _get_player_controls(is_p2)
	return controls.option_button.selected < 0 and controls.controller_option.selected == OPTION_BVS_DEFAULT

## The controller this player picked: Human, a CPU level, the bundled model, or
## (when a model was chosen from the Hugging Face picker) the policy that model
## drives. The model is explicit: it only wins when the user selected one. A model
## that is not ready yields a Policy config in its error state, never a CPU.
func get_controller_config(is_p2: bool) -> ControllerConfig:
	var controls = _get_player_controls(is_p2)
	var slot := _slot_of(is_p2)
	if controls.option_button.selected >= 0:
		var model := ModelManager.model_of(slot)
		if model == null:
			var reason := ModelManager.message_of(slot)
			return ControllerConfig.policy_model(null, reason if reason != "" else "The model is not ready yet")
		return ControllerConfig.policy_model(model)
	var index: int = controls.controller_option.selected
	if index <= OPTION_HUMAN:
		return ControllerConfig.human()
	if index == OPTION_BVS_DEFAULT:
		return ControllerConfig.policy_model(ModelManager.bundled_default(), ModelManager.bundled_error)
	return ControllerConfig.cpu(index - 1)

## True when both players' controllers can start a match: every selected model is ready.
func is_ready_to_play() -> bool:
	return get_controller_config(false).is_playable() and get_controller_config(true).is_playable()

## The player picked a compatible model in the picker: it becomes this player's
## explicit controller (shown in the option button, with Back to undo it) and its
## files are prepared right away.
func _on_model_chosen(model: HubModel) -> void:
	var controls = _get_player_controls(_picking_p2)
	update_menu_button(controls.option_button, [model.id])
	controls.option_button.select(0)
	select_model_menu(_picking_p2)
	ModelManager.request_model(_slot_of(_picking_p2), model.id)
	refresh_status(_picking_p2)

func _on_picker_cancelled() -> void:
	initial_menu(_picking_p2)

func _on_model_state_changed(slot: int, _state: int, _detail: String) -> void:
	refresh_status(slot == 1)

func _on_controller_selected(_index: int, is_p2: bool) -> void:
	refresh_status(is_p2)

## Cancel while a model loads: the transfer stops and the previous controller returns.
func _on_cancel_pressed(is_p2: bool) -> void:
	initial_menu(is_p2)

func update_menu_button(menu_button: OptionButton, model_ids: Array) -> void:
	menu_button.clear()
	for model_id in model_ids:
		menu_button.add_item(model_id)

## Updates the status line and Cancel button of a player, then tells the screen
## that Play may have changed.
func refresh_status(is_p2: bool) -> void:
	var controls = _get_player_controls(is_p2)
	var label: Label = controls.status_label
	var cancel_button: Button = controls.cancel_button
	var slot := _slot_of(is_p2)
	var text := ""
	var color := COLOR_BUSY
	var busy := false
	if uses_hub_model(is_p2):
		match ModelManager.state_of(slot):
			ModelManager.ModelState.RESOLVING, ModelManager.ModelState.DOWNLOADING, ModelManager.ModelState.VALIDATING:
				text = ModelManager.detail_of(slot)
				busy = true
			ModelManager.ModelState.READY:
				text = ModelManager.detail_of(slot)
				color = COLOR_READY
			ModelManager.ModelState.FAILED:
				text = ModelManager.message_of(slot)
				color = COLOR_FAILED
	elif uses_bundled_model(is_p2):
		if ModelManager.bundled_default() == null:
			text = ModelManager.bundled_error
			color = COLOR_FAILED
		else:
			text = "Ready (bundled)"
			color = COLOR_READY
	label.text = text
	label.visible = text != ""
	label.add_theme_color_override("font_color", color)
	cancel_button.visible = busy
	selection_changed.emit()

# Show initial AI button only
func initial_menu(is_p2: bool = false) -> void:
	var controls = _get_player_controls(is_p2)

	ModelManager.cancel(_slot_of(is_p2))
	controls.ai_button.visible = true
	controls.controller_option.visible = true
	controls.option_button.visible = false
	controls.back_button.visible = false
	controls.option_button.selected = -1
	refresh_status(is_p2)

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

# --- SIGNAL HANDLERS ---

func _on_ai_button_pressed(is_p2: bool) -> void:
	open_model_picker(is_p2)

# Back drops the chosen model and returns to the Human / CPU options.
func _on_back_button_pressed(is_p2: bool) -> void:
	model_picker.close()
	initial_menu(is_p2)
