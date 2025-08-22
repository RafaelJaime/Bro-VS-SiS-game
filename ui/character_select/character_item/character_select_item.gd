extends Button
class_name CharacterSelectItem

var character: CharacterUI

func set_data(characterUI: CharacterUI):
	self.character = characterUI
	set_colors()
	set_icon()

func set_colors():
	var original_normal = get("theme_override_styles/normal")
	if original_normal and original_normal is StyleBoxFlat and character:
		var stylebox_normal = original_normal.duplicate()
		stylebox_normal.bg_color = character.color
		add_theme_stylebox_override("normal", stylebox_normal)

	var original_hover = get("theme_override_styles/hover")
	if original_hover and original_hover is StyleBoxFlat and character:
		var stylebox_hover = original_hover.duplicate()
		var color_con_alpha = character.color
		color_con_alpha.a = 0.7
		stylebox_hover.bg_color = color_con_alpha
		add_theme_stylebox_override("hover", stylebox_hover)

func set_icon():
	# Ahora usamos directamente la textura de face del recurso
	if character and character.face_texture:
		icon = character.face_texture

func _on_pressed():
	emit_signal("pressed")
