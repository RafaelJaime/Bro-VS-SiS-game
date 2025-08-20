extends CanvasLayer

@export var leftHealth: Control
@export var rightHealth: Control
@export var leftTextureRect: TextureRect
@export var rightTextureRect: TextureRect
@export var leftNameLabel: Label
@export var rightNameLabel: Label
@export var leftProgressBar: ProgressBar
@export var rightProgressBar: ProgressBar

func _ready() -> void:
	set_ui_with_control_scheme()

func set_ui_with_control_scheme() -> void:
	match owner.control_scheme:
		0:
			rightHealth.visible = false
			set_ui(leftNameLabel, leftProgressBar, leftTextureRect)
		1:
			leftHealth.visible = false
			set_ui(rightNameLabel, rightProgressBar, rightTextureRect)

func set_ui(label: Label, progressBar: ProgressBar, textureRect: TextureRect) -> void:
	label.text = owner.player_name

	# Clonar el stylebox del background existente
	var bg_style: StyleBoxFlat = progressBar.get_theme_stylebox("background").duplicate()
	bg_style.bg_color = Color(owner.color.inverted(), 0.1)
	bg_style.border_color = owner.color.inverted()

	# Clonar el stylebox del fill existente
	var fill_style: StyleBoxFlat = progressBar.get_theme_stylebox("fill").duplicate()
	fill_style.bg_color = owner.color
	fill_style.border_color = owner.color.inverted()

	# Sobrescribir con los modificados
	progressBar.add_theme_stylebox_override("background", bg_style)
	progressBar.add_theme_stylebox_override("fill", fill_style)

	# Valores de la barra
	progressBar.max_value = owner.max_health
	progressBar.value = owner.health

	create_gradient(textureRect)

func create_gradient(textureRect: TextureRect) -> void:
	var gradient = Gradient.new()
	
	# Configurar los offsets (posiciones) y colores
	gradient.offsets = [0.0, 1.0]
	match owner.control_scheme:
		0:
			gradient.colors = [
				owner.color,
				Color(owner.color, 0),    # Transparente
			]
		1:
			gradient.colors = [
				Color(owner.color, 0),    # Transparente
				owner.color
			]
	

	# Crear la textura de gradiente 1D
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 512  # Ancho de la textura generada

	# Asignar la textura al TextureRect
	textureRect.texture = gradient_texture

func update_health() -> void:
	match owner.control_scheme:
		0:
			leftProgressBar.value = owner.health
		1:
			rightProgressBar.value = owner.health

func _on_hurt_update_health() -> void:
	update_health()

func _on_player_updated_character_ui() -> void:
	set_ui_with_control_scheme()
