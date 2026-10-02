extends Control
## The AI model picker, in the spirit of the Hugging Face Space Huggy. The username
## field at the top is the main input: typing a Hugging Face username (Search or
## Enter) lists that user's BVS models. When the user has none, their other
## reinforcement-learning models are listed too, disabled, with a hint. An empty
## field lists every model carrying the BVS tag. Each row shows the repo id,
## author, downloads and a compatibility badge; models trained for another schema
## are listed but disabled. It has loading, empty, error and offline states, each
## with a retry. The last username is remembered.

## The player picked a compatible model.
signal model_chosen(model: HubModel)
## The player closed the picker without choosing.
signal cancelled

enum PickerState { LOADING, READY, EMPTY, ERROR, OFFLINE }

const COLOR_OK := Color(0.45, 0.9, 0.5)
const COLOR_OLD := Color(1.0, 0.7, 0.3)
const COLOR_DIM := Color(0.75, 0.75, 0.75)

var state: PickerState = PickerState.LOADING
var models: Array = []

var author_edit: LineEdit
var search_button: Button
var status_label: Label
var retry_button: Button
var cancel_button: Button
var list: VBoxContainer
var _failure_message := ""
## The username the current list (or the request in flight) is for; "" is the tag list.
var _query := ""

func _ready() -> void:
	visible = false
	z_index = 4096
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	ModelManager.hub_models_loaded.connect(_on_models_loaded)
	ModelManager.hub_models_failed.connect(_on_models_failed)

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.position = Vector2(90, 50)
	panel.size = Vector2(620, 500)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.14, 0.98)
	style.border_color = Color(1, 0.9, 0.2)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title := Label.new()
	title.text = "Choose an AI model"
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)

	var bar := HBoxContainer.new()
	column.add_child(bar)
	author_edit = LineEdit.new()
	author_edit.placeholder_text = "Hugging Face username"
	author_edit.clear_button_enabled = true
	author_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	author_edit.text_submitted.connect(func(_text: String) -> void: search())
	bar.add_child(author_edit)
	search_button = Button.new()
	search_button.text = "Search"
	search_button.pressed.connect(search)
	bar.add_child(search_button)

	var subtitle := Label.new()
	subtitle.text = "Type a username to list their %s models, or leave it empty for every model tagged %s." % [HubModel.TAG, HubModel.TAG]
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", COLOR_DIM)
	column.add_child(subtitle)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 16)
	column.add_child(status_label)
	retry_button = Button.new()
	retry_button.text = "Retry"
	retry_button.pressed.connect(reload)
	column.add_child(retry_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(cancel)
	column.add_child(cancel_button)

## Shows the picker and loads the list, for the username used last time (if any).
func open() -> void:
	visible = true
	author_edit.text = ModelManager.load_last_author()
	reload()

func close() -> void:
	visible = false

func cancel() -> void:
	close()
	cancelled.emit()

## The Search button and Enter in the username field: remembers the username and
## loads its models (every BVS model when the field is empty).
func search() -> void:
	if state == PickerState.LOADING:
		return
	ModelManager.save_last_author(author_edit.text)
	reload()

## Asks the Hub for the list again, for the username in the field (Retry, Search).
func reload() -> void:
	_query = author_edit.text.strip_edges()
	state = PickerState.LOADING
	_render()
	ModelManager.fetch_hub_models(_query)

## True when the list holds only the user's other, unusable models (they have no
## BVS model of their own).
func is_related_fallback() -> bool:
	return not models.is_empty() and models.all(func(model: HubModel) -> bool: return not model.is_bvs)

func _on_models_loaded(loaded: Array) -> void:
	if not visible or state != PickerState.LOADING:
		return
	models = loaded
	state = PickerState.READY if not models.is_empty() else PickerState.EMPTY
	_render()

func _on_models_failed(failure: HubModel.Failure, message: String) -> void:
	if not visible or state != PickerState.LOADING:
		return
	models = []
	_failure_message = message
	state = PickerState.OFFLINE if failure == HubModel.Failure.OFFLINE else PickerState.ERROR
	_render()

## The model rows currently listed, in order.
func rows() -> Array[Button]:
	var found: Array[Button] = []
	for child in list.get_children():
		if child is Button:
			found.append(child)
	return found

func _status_text(shown: int) -> String:
	match state:
		PickerState.LOADING:
			return "Loading models from Hugging Face..."
		PickerState.EMPTY:
			if not _query.is_empty():
				return "%s has no models on the Hub that the game can use." % _query
			return "No BVS models were found on the Hub yet."
		PickerState.ERROR:
			return "Something went wrong: %s." % _failure_message
		PickerState.OFFLINE:
			return "You seem to be offline. %s." % _failure_message
	if is_related_fallback():
		return "%s has no %s models yet. Their other reinforcement-learning models are listed below, but this game cannot use them." % [_query, HubModel.TAG]
	if not _query.is_empty():
		return "%d model%s by %s. Pick one that is compatible with this version of the game." % [shown, "" if shown == 1 else "s", _query]
	return "%d model%s. Pick one that is compatible with this version of the game." % [shown, "" if shown == 1 else "s"]

func _render() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var shown: Array = models if state == PickerState.READY else []
	for model: HubModel in shown:
		list.add_child(_make_row(model))
	status_label.text = _status_text(shown.size())
	retry_button.visible = state == PickerState.ERROR or state == PickerState.OFFLINE or state == PickerState.EMPTY
	search_button.disabled = state == PickerState.LOADING
	author_edit.editable = state != PickerState.LOADING
	_focus_first()

func _focus_first() -> void:
	if not visible:
		return
	for row in rows():
		if not row.disabled:
			row.grab_focus.call_deferred()
			return
	if retry_button.visible:
		retry_button.grab_focus.call_deferred()
	else:
		cancel_button.grab_focus.call_deferred()

func _make_row(model: HubModel) -> Button:
	var row := Button.new()
	row.name = "Row_" + model.id.replace("/", "__").replace(".", "_")
	row.custom_minimum_size = Vector2(0, 54)
	row.disabled = not model.is_compatible()
	row.set_meta("model", model)
	row.pressed.connect(_on_row_pressed.bind(model))
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10.0
	box.offset_right = -10.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 12)
	row.add_child(box)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(names)
	names.add_child(_label(model.id, 18, Color.WHITE))
	names.add_child(_label("by %s" % model.author, 13, COLOR_DIM))
	box.add_child(_label("%s downloads" % HubModel.format_downloads(model.downloads), 14, COLOR_DIM))
	var badge := _label(model.badge_text(), 14, COLOR_OK if model.is_compatible() else (COLOR_OLD if model.is_bvs else COLOR_DIM))
	badge.name = "Badge"
	badge.custom_minimum_size = Vector2(170, 0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(badge)
	return row

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _on_row_pressed(model: HubModel) -> void:
	if not model.is_compatible():
		return
	close()
	model_chosen.emit(model)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()
