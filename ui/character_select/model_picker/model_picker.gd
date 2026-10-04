extends Control
## The AI model picker, in two steps and in the look of the rest of the app (the
## shared menu background behind a dim, outlined text, pizza-slice buttons).
##
## STEP 1 asks for a Hugging Face username: one big input (the last username is
## remembered). Continue (or Enter) lists that user's BVS models; "Browse all"
## lists every model carrying the BVS tag instead.
## STEP 2 lists the models as cards: repo id, author, downloads and a compatibility
## badge. Models trained for another schema are listed but disabled. When the user
## has no BVS model, their other reinforcement-learning models are listed too,
## disabled, with a hint. It has loading, empty, error and offline states, each
## with a retry. Back returns to step 1 (and, on step 1, closes the picker).

## The player picked a compatible model.
signal model_chosen(model: HubModel)
## The player closed the picker without choosing.
signal cancelled

enum Step { USER, MODELS }
enum PickerState { LOADING, READY, EMPTY, ERROR, OFFLINE, IDLE }

const BUTTON_CONTINUE := preload("res://assets/images/ui/buttons/button6.png")
const BUTTON_BACK := preload("res://assets/images/ui/buttons/button4.png")
const BUTTON_RETRY := preload("res://assets/images/ui/buttons/button5.png")
const SOUNDS_BUTTON := preload("res://ui/global/custom_button/custom_button.gd")
const BUTTON_SIZE := Vector2(150, 106)
## Focus-highlight scale of a pizza button (the same as the results screen).
const FOCUS_SCALE := 1.12

const COLOR_OK := Color(0.45, 0.9, 0.5)
const COLOR_OLD := Color(1.0, 0.7, 0.3)
const COLOR_DIM := Color(0.8, 0.8, 0.8)
const COLOR_YELLOW := Color(1, 0.9, 0.2)
const COLOR_CRUST := Color(0.45, 0.27, 0.16)
const COLOR_FAIL := Color(1.0, 0.45, 0.4)

var step: Step = Step.USER
var state: PickerState = PickerState.IDLE
var models: Array = []

var title_label: Label
var author_edit: LineEdit
## Continue on step 1.
var search_button: Button
var browse_button: Button
var status_label: Label
var status_panel: PanelContainer
var retry_button: Button
## Back on both steps.
var back_button: Button
var list: VBoxContainer
var user_page: Control
var models_page: Control
var _failure_message := ""
## Siblings (the character select's own controls) hidden while the picker is open.
var _hidden_siblings: Array[CanvasItem] = []
## The username the current list (or the request in flight) is for; "" is the tag list.
var _query := ""

func _ready() -> void:
	visible = false
	z_index = 4096
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	ModelManager.hub_models_loaded.connect(_on_models_loaded)
	ModelManager.hub_models_failed.connect(_on_models_failed)

# --- construction ---------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.76)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 60.0
	column.offset_right = -60.0
	column.offset_top = 18.0
	column.offset_bottom = -160.0
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	title_label = _outlined("Choose an AI model", 46, Color.WHITE, 9)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title_label)

	user_page = _build_user_page()
	user_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(user_page)
	models_page = _build_models_page()
	models_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(models_page)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -158.0
	bar.offset_left = 10.0
	bar.offset_right = -30.0
	bar.offset_bottom = 0.0
	add_child(bar)
	back_button = _pizza_button(BUTTON_BACK, "Back")
	back_button.pressed.connect(back)
	bar.add_child(back_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	retry_button = _pizza_button(BUTTON_RETRY, "Retry")
	retry_button.pressed.connect(reload)
	bar.add_child(retry_button)
	search_button = _pizza_button(BUTTON_CONTINUE, "Continue")
	search_button.pressed.connect(search)
	bar.add_child(search_button)

func _build_user_page() -> Control:
	var page := VBoxContainer.new()
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_theme_constant_override("separation", 12)
	var prompt := _outlined("Your Hugging Face username", 26, COLOR_YELLOW, 6)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(prompt)

	author_edit = LineEdit.new()
	author_edit.placeholder_text = "Hugging Face username"
	author_edit.clear_button_enabled = true
	author_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	author_edit.custom_minimum_size = Vector2(0, 68)
	author_edit.add_theme_font_size_override("font_size", 32)
	author_edit.add_theme_color_override("font_color", Color.WHITE)
	author_edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.4))
	author_edit.add_theme_color_override("caret_color", COLOR_YELLOW)
	author_edit.add_theme_stylebox_override("normal", _box(Color(0, 0, 0, 0.55), COLOR_CRUST, 4, 14))
	author_edit.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0.7), COLOR_YELLOW, 5, 14))
	author_edit.add_theme_stylebox_override("read_only", _box(Color(0, 0, 0, 0.4), COLOR_CRUST, 4, 14))
	author_edit.text_submitted.connect(func(_text: String) -> void: search())
	author_edit.gui_input.connect(_on_author_input)
	page.add_child(author_edit)

	var hint := _outlined("We list the AI models that user trained for this game.", 16, COLOR_DIM, 4)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(hint)

	browse_button = Button.new()
	browse_button.set_script(SOUNDS_BUTTON)
	browse_button.text = "Browse all %s models" % HubModel.TAG
	browse_button.flat = true
	browse_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	browse_button.add_theme_font_size_override("font_size", 22)
	browse_button.add_theme_color_override("font_color", Color.WHITE)
	for color_name in ["font_hover_color", "font_pressed_color", "font_focus_color"]:
		browse_button.add_theme_color_override(color_name, COLOR_YELLOW)
	browse_button.add_theme_color_override("font_outline_color", Color.BLACK)
	browse_button.add_theme_constant_override("outline_size", 6)
	browse_button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0.45), COLOR_YELLOW, 3, 12))
	browse_button.pressed.connect(browse_all)
	page.add_child(browse_button)
	return page

# A single-line field keeps the arrow keys to itself; Down leaves it for the buttons.
func _on_author_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		browse_button.grab_focus()
		author_edit.accept_event()

func _build_models_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	status_label = _outlined("", 18, Color.WHITE, 5)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_panel = PanelContainer.new()
	status_panel.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.6), Color(0, 0, 0, 0), 0, 12))
	status_panel.add_child(status_label)
	page.add_child(status_panel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	page.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	return page

## A label in the app's text style: outlined, with a soft shadow.
func _outlined(text: String, size: int, color: Color, outline: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", outline)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _box(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style

## A pizza-slice button (flat, art as the icon, caption below, grows when focused),
## built like the results screen's Characters button.
func _pizza_button(art: Texture2D, caption: String) -> Button:
	var button := Button.new()
	button.set_script(SOUNDS_BUTTON)
	button.custom_minimum_size = BUTTON_SIZE
	button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	button.icon = art
	button.flat = true
	button.expand_icon = true
	button.pivot_offset = BUTTON_SIZE / 2.0
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var label := _outlined(caption, 20, Color.WHITE, 7)
	label.name = "Caption"
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label.offset_left = -BUTTON_SIZE.x / 2.0
	label.offset_right = BUTTON_SIZE.x / 2.0
	label.offset_top = 2.0
	label.offset_bottom = 32.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_child(label)
	button.focus_entered.connect(_highlight.bind(button, true))
	button.focus_exited.connect(_highlight.bind(button, false))
	button.mouse_entered.connect(button.grab_focus)
	return button

func _highlight(button: Button, on: bool) -> void:
	if not button.is_inside_tree():
		return
	var tween := button.create_tween().set_parallel(true)
	tween.tween_property(button, "scale", Vector2.ONE * (FOCUS_SCALE if on else 1.0), 0.1)
	var caption := button.get_node("Caption") as Label
	caption.add_theme_color_override("font_color", COLOR_YELLOW if on else Color.WHITE)

# --- flow -------------------------------------------------------------------

## Shows the picker on step 1, with the username used last time (if any).
func open() -> void:
	_hide_siblings()
	visible = true
	author_edit.text = ModelManager.load_last_author()
	_go_to(Step.USER)

func close() -> void:
	visible = false
	_restore_siblings()

# The picker is a screen of its own: the character select's controls step aside, so
# the shared menu background shows through the dim and nothing bleeds into the UI.
func _hide_siblings() -> void:
	if not _hidden_siblings.is_empty() or get_parent() == null:
		return
	for sibling in get_parent().get_children():
		if sibling != self and sibling is CanvasItem and (sibling as CanvasItem).visible:
			_hidden_siblings.append(sibling)
			(sibling as CanvasItem).visible = false

func _restore_siblings() -> void:
	for sibling in _hidden_siblings:
		if is_instance_valid(sibling):
			sibling.visible = true
	_hidden_siblings.clear()

## Closes the picker and tells the character select nothing was chosen.
func cancel() -> void:
	close()
	cancelled.emit()

## Back: from the list to the username (step 1), and from step 1 out of the picker.
func back() -> void:
	if step == Step.MODELS:
		_go_to(Step.USER)
	else:
		cancel()

## Continue (and Enter in the field): remembers the username and lists its models
## (every BVS model when the field is empty).
func search() -> void:
	if ModelManager.is_loading_hub_models():
		return
	ModelManager.save_last_author(author_edit.text)
	reload()

## "Browse all": the global list of every BVS model.
func browse_all() -> void:
	if ModelManager.is_loading_hub_models():
		return
	author_edit.text = ""
	search()

## Asks the Hub for the list again, for the username in the field (Retry, Continue).
func reload() -> void:
	if ModelManager.is_loading_hub_models():
		return
	_query = author_edit.text.strip_edges()
	step = Step.MODELS
	state = PickerState.LOADING
	_render()
	ModelManager.fetch_hub_models(_query)

func _go_to(new_step: Step) -> void:
	step = new_step
	if step == Step.USER:
		state = PickerState.IDLE
		models = []
	_render()

## True when the list holds only the user's other, unusable models (they have no
## BVS model of their own).
func is_related_fallback() -> bool:
	return not models.is_empty() and models.all(func(model: HubModel) -> bool: return not model.is_bvs)

func _on_models_loaded(loaded: Array) -> void:
	if not visible or step != Step.MODELS or state != PickerState.LOADING:
		_refresh_buttons()
		return
	models = loaded
	state = PickerState.READY if not models.is_empty() else PickerState.EMPTY
	_render()

func _on_models_failed(failure: HubModel.Failure, message: String) -> void:
	if not visible or step != Step.MODELS or state != PickerState.LOADING:
		_refresh_buttons()
		return
	models = []
	_failure_message = message
	state = PickerState.OFFLINE if failure == HubModel.Failure.OFFLINE else PickerState.ERROR
	_render()

## The model cards currently listed, in order.
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
	var on_user := step == Step.USER
	user_page.visible = on_user
	models_page.visible = not on_user
	if on_user:
		title_label.text = "Choose an AI model"
	else:
		title_label.text = "Models by %s" % _query if not _query.is_empty() else "All BVS models"
	var shown: Array = models if state == PickerState.READY else []
	for model: HubModel in shown:
		list.add_child(_make_row(model))
	status_label.text = "" if on_user else _status_text(shown.size())
	var failed := state == PickerState.ERROR or state == PickerState.OFFLINE
	status_label.add_theme_color_override("font_color", COLOR_FAIL if failed else (COLOR_YELLOW if state == PickerState.LOADING else Color.WHITE))
	retry_button.visible = not on_user and (failed or state == PickerState.EMPTY)
	search_button.visible = on_user
	_refresh_buttons()
	_wire_focus()
	_focus_first()

## Continue and Browse all wait while a request from an earlier visit is still out.
func _refresh_buttons() -> void:
	var waiting := ModelManager.is_loading_hub_models()
	search_button.disabled = waiting
	search_button.modulate = Color(1, 1, 1, 0.5) if waiting else Color.WHITE
	browse_button.disabled = waiting

# Keyboard / gamepad navigation: the username and Browse all stack above the
# bottom row; Back is left, Continue / Retry right; the cards fall into the bar.
func _wire_focus() -> void:
	var bottom: Array[Button] = [back_button]
	if search_button.visible:
		bottom.append(search_button)
	if retry_button.visible:
		bottom.append(retry_button)
	for index in bottom.size():
		var button := bottom[index]
		button.focus_neighbor_left = bottom[maxi(index - 1, 0)].get_path()
		button.focus_neighbor_right = bottom[mini(index + 1, bottom.size() - 1)].get_path()
		button.focus_neighbor_bottom = button.get_path()
	if step == Step.USER:
		author_edit.focus_neighbor_top = author_edit.get_path()
		author_edit.focus_neighbor_bottom = browse_button.get_path()
		browse_button.focus_neighbor_top = author_edit.get_path()
		browse_button.focus_neighbor_left = browse_button.get_path()
		browse_button.focus_neighbor_right = browse_button.get_path()
		browse_button.focus_neighbor_bottom = search_button.get_path()
		for button in bottom:
			button.focus_neighbor_top = browse_button.get_path()
	else:
		# Only the cards that can be chosen take part in the navigation.
		var cards: Array[Button] = []
		for row in rows():
			if not row.disabled:
				cards.append(row)
		for index in cards.size():
			var card := cards[index]
			card.focus_neighbor_left = card.get_path()
			card.focus_neighbor_right = card.get_path()
			card.focus_neighbor_top = cards[maxi(index - 1, 0)].get_path()
			card.focus_neighbor_bottom = cards[index + 1].get_path() if index + 1 < cards.size() else back_button.get_path()
		for button in bottom:
			button.focus_neighbor_top = cards.back().get_path() if not cards.is_empty() else button.get_path()

func _focus_first() -> void:
	if not visible:
		return
	if step == Step.USER:
		author_edit.grab_focus.call_deferred()
		return
	for row in rows():
		if not row.disabled:
			row.grab_focus.call_deferred()
			return
	if retry_button.visible:
		retry_button.grab_focus.call_deferred()
	else:
		back_button.grab_focus.call_deferred()

func _make_row(model: HubModel) -> Button:
	var usable := model.is_compatible()
	var row := Button.new()
	row.set_script(SOUNDS_BUTTON)
	row.name = "Row_" + model.id.replace("/", "__").replace(".", "_")
	row.custom_minimum_size = Vector2(0, 66)
	row.disabled = not usable
	row.set_meta("model", model)
	row.pressed.connect(_on_row_pressed.bind(model))
	row.mouse_entered.connect(func() -> void:
		if not row.disabled:
			row.grab_focus())
	var fill := Color(0.1, 0.07, 0.07, 0.92) if usable else Color(0.07, 0.07, 0.07, 0.8)
	row.add_theme_stylebox_override("normal", _box(fill, COLOR_CRUST, 3, 12))
	row.add_theme_stylebox_override("hover", _box(fill.lightened(0.08), COLOR_YELLOW, 4, 12))
	row.add_theme_stylebox_override("pressed", _box(fill.lightened(0.15), COLOR_YELLOW, 4, 12))
	row.add_theme_stylebox_override("focus", _box(fill.lightened(0.08), COLOR_YELLOW, 5, 12))
	row.add_theme_stylebox_override("disabled", _box(fill, COLOR_CRUST.darkened(0.3), 2, 12))
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16.0
	box.offset_right = -14.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 12)
	row.add_child(box)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_theme_constant_override("separation", -2)
	box.add_child(names)
	names.add_child(_outlined(model.id, 22, Color.WHITE if usable else COLOR_DIM, 5))
	names.add_child(_outlined("by %s  -  %s downloads" % [model.author, HubModel.format_downloads(model.downloads)], 14, COLOR_DIM, 3))
	var pill_color := COLOR_OK if usable else (COLOR_OLD if model.is_bvs else Color(0.6, 0.6, 0.6))
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pill_style := _box(pill_color.darkened(0.55), pill_color, 2, 14)
	pill_style.content_margin_top = 3.0
	pill_style.content_margin_bottom = 3.0
	pill.add_theme_stylebox_override("panel", pill_style)
	var badge := _outlined(model.badge_text(), 15, pill_color.lightened(0.3), 3)
	badge.name = "Badge"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pill.add_child(badge)
	box.add_child(pill)
	return row

func _on_row_pressed(model: HubModel) -> void:
	if not model.is_compatible():
		return
	close()
	model_chosen.emit(model)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		back()
		get_viewport().set_input_as_handled()
