extends Node

signal model_downloaded(player_id: int, success: bool)

var download_queue := []
var current_downloads := {}

## Hub discovery. Without a username, `filter=BVS` lists every model carrying the
## BVS tag. With one, the BVS models of that user are requested server-side
## (`author=<user>`); when the user has none, their other reinforcement-learning
## models are requested too and listed as unusable ("related"). A request is one
## `hub_models_loaded` (an Array of HubModel, possibly empty) or one
## `hub_models_failed`.
signal hub_models_loaded(models: Array)
signal hub_models_failed(failure: HubModel.Failure, message: String)

## How the list is fetched: a Callable taking (url: String, done: Callable) that
## ends by calling done(result: int, response_code: int, body: PackedByteArray).
## Empty means a real HTTPRequest; tests inject a fake so they never touch the network.
var hub_transport: Callable = Callable()
var _hub_loading := false
## The username of the request in flight ("" for the tag discovery).
var _hub_author := ""

## Where the last searched username is remembered. Smoke scripts point it at a
## throwaway file so they never touch the player's real preference.
var prefs_path := "user://hub_picker.cfg"

func is_loading_hub_models() -> bool:
	return _hub_loading

## The username typed in the picker last time ("" when none).
func load_last_author() -> String:
	var config := ConfigFile.new()
	if config.load(prefs_path) != OK:
		return ""
	return String(config.get_value("picker", "author", ""))

func save_last_author(author: String) -> void:
	var config := ConfigFile.new()
	config.set_value("picker", "author", author.strip_edges())
	config.save(prefs_path)

## Loads the models: by tag when `author` is empty, else the models of that user.
func fetch_hub_models(author: String = "") -> void:
	if _hub_loading:
		return
	_hub_loading = true
	_hub_author = author.strip_edges()
	var url := HubModel.DISCOVERY_URL if _hub_author.is_empty() else HubModel.author_url(_hub_author)
	_request(url, _on_hub_models_fetched)

## Sends one GET through the transport (tests) or a real HTTPRequest.
func _request(url: String, done: Callable) -> void:
	if hub_transport.is_valid():
		hub_transport.call(url, done)
		return
	var http_request := HTTPRequest.new()
	http_request.timeout = 15.0
	add_child(http_request)
	http_request.request_completed.connect(_on_http_request_completed.bind(http_request, done))
	var error := http_request.request(url)
	if error != OK:
		http_request.queue_free()
		done.call(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())

func _on_http_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest, done: Callable) -> void:
	http_request.queue_free()
	done.call(result, response_code, body)

func _on_hub_models_fetched(result: int, response_code: int, body: PackedByteArray) -> void:
	var failure: Variant = _failure_of(result, response_code)
	if failure != null:
		_hub_loading = false
		hub_models_failed.emit(failure[0], failure[1])
		return
	var models: Variant = HubModel.parse_list(body.get_string_from_utf8())
	if models == null:
		_hub_loading = false
		hub_models_failed.emit(HubModel.Failure.BAD_DATA, "Hugging Face sent a list the game cannot read")
		return
	if (models as Array).is_empty() and not _hub_author.is_empty():
		# No BVS model for this user: also list their other RL models, unusable.
		_request(HubModel.author_rl_url(_hub_author), _on_related_fetched)
		return
	_hub_loading = false
	hub_models_loaded.emit(models)

## The user's other models are a courtesy: when they cannot be read, the answer is
## simply "no models".
func _on_related_fetched(result: int, response_code: int, body: PackedByteArray) -> void:
	_hub_loading = false
	var related: Variant = null
	if _failure_of(result, response_code) == null:
		related = HubModel.parse_related_list(body.get_string_from_utf8())
	hub_models_loaded.emit(related if related != null else [])

## [Failure, message] for a request that did not produce a usable 200; else null.
func _failure_of(result: int, response_code: int) -> Variant:
	if result != HTTPRequest.RESULT_SUCCESS:
		return [HubModel.Failure.OFFLINE, "Could not reach Hugging Face (network error %d)" % result]
	if response_code != 200:
		return [HubModel.Failure.SERVER, "Hugging Face answered HTTP %d" % response_code]
	return null

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
