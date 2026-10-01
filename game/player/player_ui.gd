extends CanvasLayer

@export var leftHealth: Control
@export var rightHealth: Control
@export var leftTextureRect: TextureRect
@export var rightTextureRect: TextureRect
@export var leftNameLabel: Label
@export var rightNameLabel: Label
@export var leftProgressBar: ProgressBar
@export var rightProgressBar: ProgressBar
@export var leftPercentLabel: Label
@export var rightPercentLabel: Label
@export var leftStockIcons: HBoxContainer
@export var rightStockIcons: HBoxContainer

func _ready() -> void:
	set_ui_with_control_scheme()

func set_ui_with_control_scheme() -> void:
	match owner.control_scheme:
		0:
			leftHealth.visible = true
			rightHealth.visible = false
			set_ui(leftNameLabel, leftProgressBar, leftTextureRect, leftPercentLabel, leftStockIcons)
		1:
			leftHealth.visible = false
			set_ui(rightNameLabel, rightProgressBar, rightTextureRect, rightPercentLabel, rightStockIcons)

func set_ui(label: Label, progressBar: ProgressBar, textureRect: TextureRect, percentLabel: Label, stockIcons: HBoxContainer) -> void:
	var character = owner.character_ui
	label.text = character.name

	# Clonar el stylebox del background existente
	var bg_style: StyleBoxFlat = progressBar.get_theme_stylebox("background").duplicate()
	bg_style.bg_color = Color(character.color.inverted(), 0.1)
	bg_style.border_color = character.color.inverted()

	# Clonar el stylebox del fill existente
	var fill_style: StyleBoxFlat = progressBar.get_theme_stylebox("fill").duplicate()
	fill_style.bg_color = character.color
	fill_style.border_color = character.color.inverted()

	# Sobrescribir con los modificados
	progressBar.add_theme_stylebox_override("background", bg_style)
	progressBar.add_theme_stylebox_override("fill", fill_style)

	# Valores de la barra (damage %). 200 is a visual-only scaling cap for the
	# bar fill; actual damage % has no gameplay cap.
	progressBar.max_value = 200.0
	progressBar.value = owner.damage_percent

	_tint_stock_icons(stockIcons, character.color)
	update_percent_label(percentLabel, owner.damage_percent)
	update_stock_icons(stockIcons, owner.stocks)

	create_gradient(textureRect)

func _tint_stock_icons(stockIcons: HBoxContainer, color: Color) -> void:
	if not stockIcons:
		return
	for icon in stockIcons.get_children():
		if icon is ColorRect:
			icon.color = color

func create_gradient(textureRect: TextureRect) -> void:
	var gradient = Gradient.new()
	
	# Configurar los offsets (posiciones) y colores
	gradient.offsets = [0.0, 1.0]
	match owner.control_scheme:
		0:
			gradient.colors = [
				owner.character_ui.color,
				Color(owner.character_ui.color, 0),    # Transparente
			]
		1:
			gradient.colors = [
				Color(owner.character_ui.color, 0),    # Transparente
				owner.character_ui.color
			]
	

	# Crear la textura de gradiente 1D
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 512  # Ancho de la textura generada

	# Asignar la textura al TextureRect
	textureRect.texture = gradient_texture

func update_damage(new_percent: float) -> void:
	match owner.control_scheme:
		0:
			leftProgressBar.value = new_percent
			update_percent_label(leftPercentLabel, new_percent)
		1:
			rightProgressBar.value = new_percent
			update_percent_label(rightPercentLabel, new_percent)

func update_percent_label(percentLabel: Label, new_percent: float) -> void:
	if percentLabel:
		percentLabel.text = "%d%%" % int(round(new_percent))

func update_stock_icons(stockIcons: HBoxContainer, stocks_left: int) -> void:
	if not stockIcons:
		return
	var icons = stockIcons.get_children()
	for i in icons.size():
		icons[i].visible = i < stocks_left

func _on_damage_changed(new_percent: float) -> void:
	update_damage(new_percent)

func _on_stocks_changed(_player_instance: Fighter, stocks_left: int) -> void:
	match owner.control_scheme:
		0:
			update_stock_icons(leftStockIcons, stocks_left)
		1:
			update_stock_icons(rightStockIcons, stocks_left)

func _on_player_updated_character_ui() -> void:
	set_ui_with_control_scheme()
