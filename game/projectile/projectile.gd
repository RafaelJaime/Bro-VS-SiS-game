extends Area2D

@export var color: Color = Color(0, 0, 1, 1)
@export var gradient: Gradient
@export var speed: float = 600

@onready var vfx_dynamic_fire: GPUParticles2D = $VFX_dynamic_fire

var direction: int = 1
var shooter: Node2D

func _ready() -> void:
	connect("body_entered", _on_body_entered)
	# Añade un pequeño delay para evitar colisiones inmediatas
	set_physics_process(false)
	await get_tree().create_timer(0.1).timeout
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if direction != 0:
		position.x += speed * delta * direction

func set_direction(dir: int) -> void:
	direction = dir
	if has_node("Sprite2D"):
		$Sprite2D.flip_h = dir < 0

func set_shooter(shooter_node: Node2D) -> void:
	shooter = shooter_node

func _on_body_entered(body: Node) -> void:
	# Debug para ver qué nodos están colisionando
	print("Proyectil colisiona con: ", body.name)
	
	# Evitar hacer daño al que disparó
	if body == shooter:
		return
		
	# Evitar hacer daño a sí mismo (por si acaso)
	if body == self:
		return
		
	if body is Fighter and body != shooter:
		print("¡Daño a enemigo!")
		if body.state_machine.current_state.name != "Protect":
			body.state_machine._change_state("Hurt")
		else:
			var current_state = body.state_machine.current_state
			if current_state is Motion:
				current_state.finished.emit("Idle")
		queue_free()
	elif body is TileMap or body.name == "Wall":
		queue_free()

func set_color(character_color: Color) -> void:
	self.color = character_color
	
	# Detener emisión temporalmente
	vfx_dynamic_fire.emitting = false
	
	# Crear una copia del material original
	var original_material = vfx_dynamic_fire.process_material
	var vfx_material := original_material.duplicate()
	
	# Crear gradiente dinámico único
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, character_color)                # Color base
	color_ramp.set_color(1, character_color.darkened(0.7))  # Versión más oscura
	
	# Crear textura de gradiente
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = color_ramp
	
	# Asignar el gradiente al material copiado
	vfx_material.color_ramp = grad_tex
	
	# Asignar el material copiado al sistema de partículas
	vfx_dynamic_fire.process_material = vfx_material
	
	# Reiniciar y empezar emisión
	vfx_dynamic_fire.restart()
	vfx_dynamic_fire.one_shot = false
	vfx_dynamic_fire.emitting = true
