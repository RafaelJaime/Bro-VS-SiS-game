extends RichTextLabel
class_name LinksRichTextLabel

func _on_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))
