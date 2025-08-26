extends Control

func _on_rafael_button_pressed() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open('https://huggingface.co/spaces/RafaelJaime', '_blank')")

func _on_matilde_button_pressed() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open('https://linktr.ee/mati_mola', '_blank')")
