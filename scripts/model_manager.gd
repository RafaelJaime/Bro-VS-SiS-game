extends Node

signal model_downloaded(player_id: int, success: bool)

var download_queue := []
var current_downloads := {}

## Hub discovery: `filter=BVS` lists every model carrying the BVS tag, so the
## player never types a username. A request is one `hub_models_loaded` (an Array
## of HubModel, possibly empty) or one `hub_models_failed`.
signal hub_models_loaded(models: Array)
signal hub_models_failed(failure: HubModel.Failure, message: String)

## How the list is fetched: a Callable taking (url: String, done: Callable) that
## ends by calling done(result: int, response_code: int, body: PackedByteArray).
## Empty means a real HTTPRequest; tests inject a fake so they never touch the network.
var hub_transport: Callable = Callable()
var _hub_loading := false

func is_loading_hub_models() -> bool:
	return _hub_loading

func fetch_hub_models() -> void:
	if _hub_loading:
		return
	_hub_loading = true
	if hub_transport.is_valid():
		hub_transport.call(HubModel.DISCOVERY_URL, _on_hub_models_fetched)
		return
	var http_request := HTTPRequest.new()
	http_request.timeout = 15.0
	add_child(http_request)
	http_request.request_completed.connect(_on_http_request_completed.bind(http_request))
	var error := http_request.request(HubModel.DISCOVERY_URL)
	if error != OK:
		http_request.queue_free()
		_on_hub_models_fetched(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())

func _on_http_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:
	http_request.queue_free()
	_on_hub_models_fetched(result, response_code, body)

func _on_hub_models_fetched(result: int, response_code: int, body: PackedByteArray) -> void:
	_hub_loading = false
	if result != HTTPRequest.RESULT_SUCCESS:
		hub_models_failed.emit(HubModel.Failure.OFFLINE, "Could not reach Hugging Face (network error %d)" % result)
		return
	if response_code != 200:
		hub_models_failed.emit(HubModel.Failure.SERVER, "Hugging Face answered HTTP %d" % response_code)
		return
	var models: Variant = HubModel.parse_list(body.get_string_from_utf8())
	if models == null:
		hub_models_failed.emit(HubModel.Failure.BAD_DATA, "Hugging Face sent a list the game cannot read")
		return
	hub_models_loaded.emit(models)

func download_model(model_id: String, player_id: int) -> void:
	if player_id in current_downloads:
		push_warning("ModelManager: download already in progress for player %s" % player_id)
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
	var error = http_request.request(url)
	if error != OK:
		push_warning("ModelManager: download request failed for %s (error %s)" % [model_id, error])
		current_downloads.erase(player_id)
		http_request.queue_free()
		model_downloaded.emit(player_id, false)

func _on_model_downloaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, player_id: int, file_path: String, http_request: HTTPRequest) -> void:
	current_downloads.erase(player_id)
	http_request.queue_free()
	
	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("ModelManager: download failed for player %s (result %s)" % [player_id, result])
		model_downloaded.emit(player_id, false)
		return
	
	if response_code == 200:
		var file = FileAccess.open(file_path, FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()
			model_downloaded.emit(player_id, true)
		else:
			push_warning("ModelManager: could not open %s for writing" % file_path)
			model_downloaded.emit(player_id, false)
	else:
		push_warning("ModelManager: HTTP %s for player %s" % [response_code, player_id])
		model_downloaded.emit(player_id, false)

func get_model_path(player_id: int) -> String:
	return "user://Agent%d.onnx" % player_id

func model_exists(player_id: int) -> bool:
	return FileAccess.file_exists(get_model_path(player_id))

func cancel_download(player_id: int) -> void:
	if player_id in current_downloads:
		current_downloads[player_id].queue_free()
		current_downloads.erase(player_id)
