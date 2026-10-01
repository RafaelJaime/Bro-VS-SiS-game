extends CanvasLayer
class_name FighterHud

## Smash-style fighter panel, built in code and anchored to the bottom of the
## screen (P1 left, P2 right). It lives on a CanvasLayer, so camera zoom and
## movement never touch it. Shows the face portrait, the name, a big damage %
## whose colour climbs from white through yellow to dark red (and pops on every
## hit) and one mini face per stock.

const FACE_DIR := "res://assets/images/game/characters/%s/face/%s_014.png"
const PANEL_SIZE := Vector2(268.0, 130.0)
const PANEL_MARGIN := 12.0
const PORTRAIT_SIZE := 92.0
const STOCK_SIZE := 24.0
const PERCENT_FONT_SIZE := 56

# Damage % at which the number reaches each colour of the ramp.
const COLOR_STOPS: Array[Dictionary] = [
	{"percent": 0.0, "color": Color(1.0, 1.0, 1.0)},
	{"percent": 60.0, "color": Color(1.0, 0.92, 0.2)},
	{"percent": 120.0, "color": Color(1.0, 0.15, 0.1)},
	{"percent": 200.0, "color": Color(0.45, 0.0, 0.05)},
]

var panel: Control
var portrait: TextureRect
var name_label: Label
var percent_label: Label
var stock_icons: HBoxContainer

var _pop_tween: Tween
var _stock_texture: Texture2D

## White at 0%, yellow near 60%, red near 120% and dark red from 200% on.
static func damage_color(percent: float) -> Color:
	var last := COLOR_STOPS.size() - 1
	if percent <= COLOR_STOPS[0]["percent"]:
		return COLOR_STOPS[0]["color"]
	for i in range(1, COLOR_STOPS.size()):
		var upper: Dictionary = COLOR_STOPS[i]
		if percent <= upper["percent"]:
			var lower: Dictionary = COLOR_STOPS[i - 1]
			var t := inverse_lerp(lower["percent"], upper["percent"], percent)
			return (lower["color"] as Color).lerp(upper["color"], t)
	return COLOR_STOPS[last]["color"]

func _ready() -> void:
	# AI training runs dozens of Game rows at once; nobody watches their HUD.
	var game := owner.get_parent() if owner else null
	if game and game.get("training") == true:
		visible = false
		return
	_build()
	_refresh_character()

func _is_left() -> bool:
	return owner.control_scheme == Fighter.PlayerNumber.JUGADOR1

func _build() -> void:
	var left := _is_left()
	panel = Control.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.anchor_left = 0.0 if left else 1.0
	panel.anchor_right = panel.anchor_left
	panel.offset_left = PANEL_MARGIN if left else -(PANEL_MARGIN + PANEL_SIZE.x)
	panel.offset_right = panel.offset_left + PANEL_SIZE.x
	panel.offset_bottom = -PANEL_MARGIN
	panel.offset_top = panel.offset_bottom - PANEL_SIZE.y
	add_child(panel)

	var background := Panel.new()
	background.name = "Background"
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.07, 0.62)
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 1.0, 1.0, 0.25)
	background.add_theme_stylebox_override("panel", style)
	panel.add_child(background)

	var portrait_x := 10.0 if left else PANEL_SIZE.x - 10.0 - PORTRAIT_SIZE
	var text_x := PORTRAIT_SIZE + 20.0 if left else 10.0
	var text_width := PANEL_SIZE.x - PORTRAIT_SIZE - 30.0

	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.position = Vector2(portrait_x, (PANEL_SIZE.y - PORTRAIT_SIZE) / 2.0 - 4.0)
	portrait.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	panel.add_child(portrait)

	name_label = _make_label("NameLabel", 22, text_x, 2.0, text_width, left)
	percent_label = _make_label("PercentLabel", PERCENT_FONT_SIZE, text_x, 22.0, text_width, left)
	percent_label.text = "0%"
	percent_label.add_theme_constant_override("outline_size", 10)
	percent_label.resized.connect(_center_percent_pivot)

	stock_icons = HBoxContainer.new()
	stock_icons.name = "Stocks"
	stock_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stock_icons.alignment = BoxContainer.ALIGNMENT_BEGIN if left else BoxContainer.ALIGNMENT_END
	stock_icons.add_theme_constant_override("separation", 6)
	stock_icons.position = Vector2(text_x, PANEL_SIZE.y - STOCK_SIZE - 8.0)
	stock_icons.size = Vector2(text_width, STOCK_SIZE)
	panel.add_child(stock_icons)
	for i in Fighter.MAX_STOCKS:
		var icon := TextureRect.new()
		icon.name = "Stock%d" % i
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.custom_minimum_size = Vector2(STOCK_SIZE, STOCK_SIZE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		stock_icons.add_child(icon)

func _make_label(label_name: String, font_size: int, x: float, y: float, width: float, left: bool) -> Label:
	var label := Label.new()
	label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(x, y)
	label.size = Vector2(width, font_size + 12.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	panel.add_child(label)
	return label

func _center_percent_pivot() -> void:
	percent_label.pivot_offset = percent_label.size / 2.0

# Fills portrait, name and stock faces from the fighter's CharacterUI. Runs again
# whenever the match swaps the character (updated_characterUI).
func _refresh_character() -> void:
	if panel == null or owner.character_ui == null:
		return
	var character: CharacterUI = owner.character_ui
	name_label.text = character.name
	name_label.add_theme_color_override("font_color", character.color.lightened(0.45))
	(panel.get_node("Background") as Panel).get_theme_stylebox("panel").border_color = character.color
	_stock_texture = _face_texture(character)
	portrait.texture = _stock_texture
	for icon in stock_icons.get_children():
		icon.texture = _stock_texture
	_show_damage(owner.damage_percent, false)
	update_stock_icons(owner.stocks)

# The character select supplies face_texture; the scenes' built-in fighters do
# not, so fall back to the face art that sits next to the sprites.
func _face_texture(character: CharacterUI) -> Texture2D:
	if character.face_texture:
		return character.face_texture
	var lower := character.name.to_lower()
	if lower.is_empty():
		return null
	var path := FACE_DIR % [lower, lower.left(1)]
	return load(path) if ResourceLoader.exists(path) else null

func update_damage(new_percent: float) -> void:
	_show_damage(new_percent, true)

func _show_damage(new_percent: float, pop: bool) -> void:
	if percent_label == null:
		return
	percent_label.text = "%d%%" % int(round(new_percent))
	percent_label.add_theme_color_override("font_color", damage_color(new_percent))
	if pop and new_percent > 0.0:
		_pop()

# Hit feedback: the number jumps up and wobbles, then settles. The tween belongs
# to this layer, so it pauses with the game.
func _pop() -> void:
	if _pop_tween:
		_pop_tween.kill()
	percent_label.scale = Vector2.ONE * 1.45
	percent_label.rotation = deg_to_rad(-7.0 if _is_left() else 7.0)
	_pop_tween = create_tween().set_parallel(true)
	_pop_tween.tween_property(percent_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(percent_label, "rotation", 0.0, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func update_stock_icons(stocks_left: int) -> void:
	if stock_icons == null:
		return
	var icons := stock_icons.get_children()
	for i in icons.size():
		icons[i].visible = i < stocks_left

func visible_stock_count() -> int:
	if stock_icons == null:
		return 0
	return stock_icons.get_children().filter(func(icon): return icon.visible).size()

func _on_damage_changed(new_percent: float) -> void:
	update_damage(new_percent)

func _on_stocks_changed(_player_instance: Fighter, stocks_left: int) -> void:
	update_stock_icons(stocks_left)

func _on_player_updated_character_ui() -> void:
	_refresh_character()
