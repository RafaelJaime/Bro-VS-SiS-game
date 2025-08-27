extends Node

signal model_downloaded(player_id: int, success: bool)
signal models_loaded(player_id: int, models: Array)

var models_cache := {}
var download_queue := []
var current_downloads := {}

func fetch_user_models(username: String, player_id: int) -> void:
	if username in models_cache:
		models_loaded.emit(player_id, models_cache[username])
		return
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_models_fetched.bind(http_request, username, player_id))
	
	var url = "https://huggingface.co/api/models?author=%s" % username
	var error = http_request.request(url)
	if error != OK:
		print("Request failed for", username, "Error:", error)
		models_loaded.emit(player_id, [])

func _on_models_fetched(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest, username: String, player_id: int) -> void:
	http_request.queue_free()
	
	if response_code == 200:
		var models_body = JSON.parse_string(body.get_string_from_utf8())
		if typeof(models_body) == TYPE_ARRAY:
			var bvs_models := []
			for model in models_body:
				if "tags" in model and "BVS" in model["tags"]:
					bvs_models.append(model["id"])
			
			models_cache[username] = bvs_models
			models_loaded.emit(player_id, bvs_models)
	else:
		print("Failed to fetch models for", username, "HTTP code:", response_code)
		models_loaded.emit(player_id, [])

func download_model(model_id: String, player_id: int) -> void:
	if player_id in current_downloads:
		print("Download already in progress for player", player_id)
		return
	
	var file_path = "user://Agent%d.onnx" % player_id
	if FileAccess.file_exists(file_path):
		model_downloaded.emit(player_id, true)
		return
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	current_downloads[player_id] = http_request
	http_request.request_completed.connect(_on_model_downloaded.bind(player_id, file_path, http_request))
	
	var url = "https://huggingface.co/%s/resolve/main/model.onnx" % model_id
	print("Downloading model:", url)
	var error = http_request.request(url)
	if error != OK:
		print("Download request failed for", model_id, "Error:", error)
		current_downloads.erase(player_id)
		http_request.queue_free()
		model_downloaded.emit(player_id, false)

func _on_model_downloaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, player_id: int, file_path: String, http_request: HTTPRequest) -> void:
	current_downloads.erase(player_id)
	http_request.queue_free()
	
	if result != HTTPRequest.RESULT_SUCCESS:
		print("Download failed for player", player_id, "Result:", result)
		model_downloaded.emit(player_id, false)
		return
	
	if response_code == 200:
		var file = FileAccess.open(file_path, FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()
			print("Model saved for player", player_id, "at:", file_path)
			model_downloaded.emit(player_id, true)
		else:
			print("Could not open file for writing:", file_path)
			model_downloaded.emit(player_id, false)
	else:
		print("HTTP response code:", response_code, "for player", player_id)
		model_downloaded.emit(player_id, false)

func get_model_path(player_id: int) -> String:
	return "user://Agent%d.onnx" % player_id

func model_exists(player_id: int) -> bool:
	return FileAccess.file_exists(get_model_path(player_id))

func clear_models_cache() -> void:
	models_cache.clear()

func cancel_download(player_id: int) -> void:
	if player_id in current_downloads:
		current_downloads[player_id].queue_free()
		current_downloads.erase(player_id)
