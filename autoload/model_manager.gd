extends Node

## Everything the game gets from the Hugging Face Hub, plus the bundled default.
##
## Two jobs:
##   1. Discovery: the picker's list of BVS models (`fetch_hub_models`).
##   2. Model loading: a per-slot state machine (`request_model`) that turns a repo
##      id into a validated, ready-to-play OnnxPolicyModel, and the bundled default
##      (`bundled_default`) that never touches the network.
##
## Model cache: `user://models/<owner>__<name>/<sha>/{model.onnx,bvs.json}`, keyed by
## repo and the revision sha resolved by one metadata call per selection. Files are
## validated (sidecar, graph, schema dimensions) before they are stored, written as
## `.part` and renamed, so an entry is trusted only when both final files exist. A
## different sha of the same repo downloads again; the old one stays untouched.
## `user://Agent<N>.onnx` files of older versions are never read and are deleted at
## startup. A failure is always a visible FAILED state with a reason: nothing here
## ever substitutes the scripted CPU.

enum ModelState { IDLE, RESOLVING, DOWNLOADING, VALIDATING, READY, FAILED }
enum ModelFailure { OFFLINE, SERVER, RATE_LIMITED, NOT_FOUND, MISSING_FILES, BAD_SIDECAR, SCHEMA_MISMATCH, BAD_ONNX, UNSUPPORTED_OP, TOO_LARGE }

## `slot` is the player (0 or 1). `detail` is a short line for the loading UI.
signal model_state_changed(slot: int, state: ModelState, detail: String)
signal model_ready(slot: int, model: OnnxPolicyModel)
signal model_failed(slot: int, reason: ModelFailure, message: String)

const MODEL_FILE := "model.onnx"
const SIDECAR_FILE := "bvs.json"
const BUNDLED_DIR := "res://game/ai/models/bvs_default"
const MAX_MODEL_BYTES := 16 * 1024 * 1024
const MAX_SIDECAR_BYTES := 64 * 1024
const MAX_INFO_BYTES := 1024 * 1024
## Seconds of silence after which a real transfer is abandoned.
const INFO_TIMEOUT := 15.0
const FILE_TIMEOUT := 60.0

## Where validated models are cached. Smoke scripts point it at a throwaway directory.
var models_root := "user://models"
## Where the bundled default lives; tests point it at a corrupted copy.
var bundled_dir := BUNDLED_DIR
## Why the bundled default could not be loaded ("" while it can).
var bundled_error := ""

var _slots := {}
var _bundled: OnnxPolicyModel
var _bundled_tried := false

class Slot extends RefCounted:
	var repo := ""
	var state: int = 0
	var detail := ""
	var failure := -1
	var message := ""
	var model: OnnxPolicyModel
	## Incremented by every request and cancel: an answer carrying an older token is dropped.
	var token := 0
	var http: HTTPRequest
	var last_kb := -1

func _ready() -> void:
	cleanup_legacy_files()

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

## Sends one GET through the transport (tests) or a real HTTPRequest, which is
## returned so the caller can cancel it (null with a transport).
func _request(url: String, done: Callable, max_bytes: int = 0, timeout: float = INFO_TIMEOUT) -> HTTPRequest:
	if hub_transport.is_valid():
		hub_transport.call(url, done)
		return null
	var http_request := HTTPRequest.new()
	http_request.timeout = timeout
	if max_bytes > 0:
		http_request.body_size_limit = max_bytes
	add_child(http_request)
	http_request.request_completed.connect(_on_http_request_completed.bind(http_request, done))
	var error := http_request.request(url)
	if error != OK:
		http_request.queue_free()
		done.call(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())
		return null
	return http_request

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


# ---------------------------------------------------------------------------
# Model loading (play): repo id -> validated OnnxPolicyModel, one slot per player
# ---------------------------------------------------------------------------

func state_of(slot: int) -> ModelState:
	return _slots[slot].state if _slots.has(slot) else ModelState.IDLE

func model_of(slot: int) -> OnnxPolicyModel:
	return _slots[slot].model if _slots.has(slot) else null

func repo_of(slot: int) -> String:
	return _slots[slot].repo if _slots.has(slot) else ""

func detail_of(slot: int) -> String:
	return _slots[slot].detail if _slots.has(slot) else ""

## The reason of the last failure of `slot` (-1 when it has not failed) and its text.
func failure_of(slot: int) -> int:
	return _slots[slot].failure if _slots.has(slot) else -1

func message_of(slot: int) -> String:
	return _slots[slot].message if _slots.has(slot) else ""

func is_busy(slot: int) -> bool:
	var state := state_of(slot)
	return state == ModelState.RESOLVING or state == ModelState.DOWNLOADING or state == ModelState.VALIDATING

## Starts preparing `repo_id` for `slot` (any earlier request of the slot is
## dropped): resolve the revision sha, reuse or download the files, validate, then
## READY or FAILED. Progress is reported by `model_state_changed`.
func request_model(slot: int, repo_id: String) -> void:
	var entry := _abort(slot)
	entry.repo = repo_id.strip_edges()
	entry.model = null
	entry.failure = -1
	entry.message = ""
	var token := entry.token
	if not _is_repo_id(entry.repo):
		_fail(slot, ModelFailure.NOT_FOUND, "'%s' is not a Hugging Face repo id (owner/name)" % entry.repo)
		return
	_set_state(slot, ModelState.RESOLVING, "Resolving...")
	var http := _request(HubModel.info_url(entry.repo), _on_info.bind(slot, token), MAX_INFO_BYTES)
	_track(slot, token, http)

## Stops the transfer of `slot` and forgets its model: the slot is IDLE again and
## nothing of the request is marked ready.
func cancel(slot: int) -> void:
	if not _slots.has(slot):
		return
	var entry := _abort(slot)
	entry.model = null
	entry.failure = -1
	entry.message = ""
	if entry.state != ModelState.IDLE:
		_set_state(slot, ModelState.IDLE, "Cancelled")

## The bundled default model (res://game/ai/models/bvs_default), loaded and
## validated once, with no network. Null when it fails validation: `bundled_error`
## says why, and nothing falls back to the CPU.
func bundled_default() -> OnnxPolicyModel:
	if _bundled_tried:
		return _bundled
	_bundled_tried = true
	bundled_error = ""
	var sidecar_path := bundled_dir.path_join(SIDECAR_FILE)
	var onnx_path := bundled_dir.path_join(MODEL_FILE)
	if not FileAccess.file_exists(sidecar_path) or not FileAccess.file_exists(onnx_path):
		bundled_error = "The bundled BVS default model is missing"
		push_error("ModelManager: %s (%s)" % [bundled_error, bundled_dir])
		return null
	var checked := _validate_files(FileAccess.get_file_as_bytes(sidecar_path), FileAccess.get_file_as_bytes(onnx_path))
	if checked.model == null:
		bundled_error = "The bundled BVS default model is not valid: %s" % checked.message
		push_error("ModelManager: %s" % bundled_error)
		return null
	_bundled = checked.model
	_bundled.repo_id = "bundled"
	_bundled.revision = "res"
	if _bundled.label == "":
		_bundled.label = "BVS default"
	return _bundled

## Forgets the bundled default so the next call loads it again (tests).
func reload_bundled() -> void:
	_bundled = null
	_bundled_tried = false

## Deletes `user://Agent<N>.onnx` files of older versions (best effort). They are
## never read. Returns how many were removed.
func cleanup_legacy_files() -> int:
	var removed := 0
	var dir := DirAccess.open("user://")
	if dir == null:
		return 0
	for file_name in dir.get_files():
		if file_name.begins_with("Agent") and file_name.ends_with(".onnx"):
			if dir.remove(file_name) == OK:
				removed += 1
	return removed

## `user://models/<owner>__<name>/<sha>` for a repo and revision.
func cache_dir(repo_id: String, sha: String) -> String:
	return models_root.path_join(repo_id.replace("/", "__")).path_join(sha)

## True when `dir` holds both final files and no unfinished `.part` file.
func is_cache_complete(dir: String) -> bool:
	return FileAccess.file_exists(dir.path_join(MODEL_FILE)) and FileAccess.file_exists(dir.path_join(SIDECAR_FILE)) \
		and not FileAccess.file_exists(dir.path_join(MODEL_FILE + ".part")) and not FileAccess.file_exists(dir.path_join(SIDECAR_FILE + ".part"))

## The sha last stored for `repo_id` (the offline fallback), or "".
func cached_sha(repo_id: String) -> String:
	var index := ConfigFile.new()
	if index.load(models_root.path_join("index.cfg")) != OK:
		return ""
	return String(index.get_value("last", repo_id, ""))

func _process(_delta: float) -> void:
	for slot: int in _slots:
		var entry: Slot = _slots[slot]
		if entry.state == ModelState.DOWNLOADING and is_instance_valid(entry.http):
			var kb := int(entry.http.get_downloaded_bytes() / 1024)
			if kb != entry.last_kb:
				entry.last_kb = kb
				_set_state(slot, ModelState.DOWNLOADING, "Downloading %d KB..." % kb)

func _slot(slot: int) -> Slot:
	if not _slots.has(slot):
		_slots[slot] = Slot.new()
	return _slots[slot]

## Invalidates every pending answer of `slot` and frees its transfer.
func _abort(slot: int) -> Slot:
	var entry := _slot(slot)
	entry.token += 1
	if is_instance_valid(entry.http):
		entry.http.cancel_request()
		entry.http.queue_free()
	entry.http = null
	return entry

## Remembers the real transfer of a request, so cancel can stop it. An answer that
## already arrived (a transport answers at once) leaves nothing to track.
func _track(slot: int, token: int, http: HTTPRequest) -> void:
	var entry: Slot = _slots.get(slot)
	if entry != null and entry.token == token and is_instance_valid(http):
		entry.http = http

## The slot when `token` is still the current request, else null (a stale answer).
func _live(slot: int, token: int) -> Slot:
	var entry: Slot = _slots.get(slot)
	if entry == null or entry.token != token:
		return null
	entry.http = null
	return entry

func _set_state(slot: int, state: ModelState, detail: String) -> void:
	var entry := _slot(slot)
	entry.state = state
	entry.detail = detail
	model_state_changed.emit(slot, state, detail)

func _fail(slot: int, reason: ModelFailure, message: String) -> void:
	var entry := _slot(slot)
	entry.model = null
	entry.failure = reason
	entry.message = message
	push_warning("ModelManager: slot %d %s: %s" % [slot, entry.repo, message])
	_set_state(slot, ModelState.FAILED, message)
	model_failed.emit(slot, reason, message)

func _ready_with(slot: int, model: OnnxPolicyModel, detail: String) -> void:
	var entry := _slot(slot)
	entry.model = model
	_set_state(slot, ModelState.READY, detail)
	model_ready.emit(slot, model)

static func _is_repo_id(text: String) -> bool:
	var parts := text.split("/")
	if parts.size() != 2:
		return false
	for part in parts:
		if part.is_empty() or part.begins_with("."):
			return false
		for i in part.length():
			var c := part.unicode_at(i)
			var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 45 or c == 46 or c == 95
			if not ok:
				return false
	return true

## [ModelFailure, message] for an answer that is not a usable 200; else null.
func _download_failure(result: int, code: int, what: String) -> Variant:
	if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		return [ModelFailure.TOO_LARGE, "%s is too large" % what]
	if result != HTTPRequest.RESULT_SUCCESS:
		return [ModelFailure.OFFLINE, "Could not reach Hugging Face for %s (network error %d)" % [what, result]]
	match code:
		200:
			return null
		429:
			return [ModelFailure.RATE_LIMITED, "Hugging Face rate limit reached (HTTP 429), try again in a minute"]
		404:
			return [ModelFailure.NOT_FOUND, "%s was not found on Hugging Face" % what]
		401, 403:
			return [ModelFailure.NOT_FOUND, "%s is private or gated (HTTP %d)" % [what, code]]
	return [ModelFailure.SERVER, "Hugging Face answered HTTP %d for %s" % [code, what]]

func _on_info(result: int, code: int, body: PackedByteArray, slot: int, token: int) -> void:
	var entry := _live(slot, token)
	if entry == null:
		return
	var repo := entry.repo
	if result != HTTPRequest.RESULT_SUCCESS and result != HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		# Offline: a revision that was validated before still plays.
		var known := cached_sha(repo)
		if known != "" and is_cache_complete(cache_dir(repo, known)) and _load_cached(slot, repo, known, "offline, cached"):
			return
	var failure: Variant = _download_failure(result, code, "the model info")
	if failure != null:
		_fail(slot, failure[0], failure[1])
		return
	var info: Variant = JSON.parse_string(body.get_string_from_utf8())
	var revision := String(info.get("sha", "")) if info is Dictionary else ""
	if revision.length() < 7 or not revision.is_valid_hex_number():
		_fail(slot, ModelFailure.SERVER, "Hugging Face sent model info the game cannot read")
		return
	var listed := {}
	var siblings: Variant = (info as Dictionary).get("siblings", [])
	if siblings is Array:
		for sibling in siblings:
			if sibling is Dictionary:
				listed[String(sibling.get("rfilename", ""))] = true
	var missing: PackedStringArray = []
	for needed in [MODEL_FILE, SIDECAR_FILE]:
		if not listed.has(needed):
			missing.append(needed)
	if not missing.is_empty():
		_fail(slot, ModelFailure.MISSING_FILES, "The repo is missing %s" % " and ".join(missing))
		return
	if is_cache_complete(cache_dir(repo, revision)) and _load_cached(slot, repo, revision, "cached"):
		return
	_download_sidecar(slot, token, repo, revision)

## Loads a stored revision. False (after deleting it) when the stored files no
## longer validate, so the caller downloads again.
func _load_cached(slot: int, repo: String, sha: String, note: String) -> bool:
	var dir := cache_dir(repo, sha)
	_set_state(slot, ModelState.VALIDATING, "Checking model...")
	var checked := _validate_files(FileAccess.get_file_as_bytes(dir.path_join(SIDECAR_FILE)), FileAccess.get_file_as_bytes(dir.path_join(MODEL_FILE)))
	if checked.model == null:
		push_warning("ModelManager: the cached %s@%s is not valid (%s), downloading it again" % [repo, sha, checked.message])
		_remove_dir(dir)
		return false
	_finish(slot, checked.model, repo, sha, "Ready (%s)" % note)
	return true

func _download_sidecar(slot: int, token: int, repo: String, sha: String) -> void:
	_set_state(slot, ModelState.DOWNLOADING, "Downloading %s..." % SIDECAR_FILE)
	_slot(slot).last_kb = -1
	var http := _request(HubModel.file_url(repo, sha, SIDECAR_FILE), _on_sidecar.bind(slot, token, sha), MAX_SIDECAR_BYTES, FILE_TIMEOUT)
	_track(slot, token, http)

func _on_sidecar(result: int, code: int, body: PackedByteArray, slot: int, token: int, sha: String) -> void:
	var entry := _live(slot, token)
	if entry == null:
		return
	var failure: Variant = _download_failure(result, code, SIDECAR_FILE)
	if failure != null:
		_fail(slot, failure[0], failure[1])
		return
	var problem := _check_sidecar(body)
	if problem.message != "":
		_fail(slot, problem.failure, problem.message)
		return
	_set_state(slot, ModelState.DOWNLOADING, "Downloading 0 KB...")
	entry.last_kb = 0
	var http := _request(HubModel.file_url(entry.repo, sha, MODEL_FILE), _on_onnx.bind(slot, token, sha, body), MAX_MODEL_BYTES, FILE_TIMEOUT)
	_track(slot, token, http)

func _on_onnx(result: int, code: int, body: PackedByteArray, slot: int, token: int, sha: String, sidecar_bytes: PackedByteArray) -> void:
	var entry := _live(slot, token)
	if entry == null:
		return
	var failure: Variant = _download_failure(result, code, MODEL_FILE)
	if failure != null:
		_fail(slot, failure[0], failure[1])
		return
	_set_state(slot, ModelState.VALIDATING, "Checking model...")
	var checked := _validate_files(sidecar_bytes, body)
	if checked.model == null:
		_fail(slot, checked.failure, checked.message)
		return
	if _store(cache_dir(entry.repo, sha), sidecar_bytes, body):
		_remember(entry.repo, sha)
	else:
		# The model is fine; only the cache cannot be written (read-only storage).
		push_warning("ModelManager: could not write the cache for %s@%s, using it for this session only" % [entry.repo, sha])
	_finish(slot, checked.model, entry.repo, sha, "Ready")

func _finish(slot: int, model: OnnxPolicyModel, repo: String, sha: String, detail: String) -> void:
	model.repo_id = repo
	model.revision = sha
	if model.label == "":
		model.label = repo
	_ready_with(slot, model, detail)

## {"failure", "message"} for a sidecar that cannot be used ("" message: it is fine).
func _check_sidecar(bytes: PackedByteArray) -> Dictionary:
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not (parsed is Dictionary):
		return {"failure": ModelFailure.BAD_SIDECAR, "message": "bvs.json is not valid JSON"}
	var reason := BvsSchema.validate_sidecar(parsed)
	if reason == "":
		return {"failure": -1, "message": ""}
	var kind := ModelFailure.BAD_SIDECAR if reason.begins_with("bvs.json is missing") else ModelFailure.SCHEMA_MISMATCH
	return {"failure": kind, "message": reason}

## Sidecar, graph and schema checks on raw bytes, shared by Hub downloads, the cache and
## the bundled default: {"model": OnnxPolicyModel | null, "failure", "message"}.
func _validate_files(sidecar_bytes: PackedByteArray, onnx_bytes: PackedByteArray) -> Dictionary:
	var sidecar_problem := _check_sidecar(sidecar_bytes)
	if sidecar_problem.message != "":
		return {"model": null, "failure": sidecar_problem.failure, "message": sidecar_problem.message}
	if onnx_bytes.size() > MAX_MODEL_BYTES:
		return {"model": null, "failure": ModelFailure.TOO_LARGE, "message": "model.onnx is too large (%d bytes, limit %d)" % [onnx_bytes.size(), MAX_MODEL_BYTES]}
	var sidecar: Dictionary = JSON.parse_string(sidecar_bytes.get_string_from_utf8())
	var loaded := OnnxPolicyModel.load_bytes(onnx_bytes, sidecar)
	if loaded.model == null:
		var error := String(loaded.error)
		var kind := ModelFailure.BAD_ONNX
		if error.begins_with("unsupported operator"):
			kind = ModelFailure.UNSUPPORTED_OP
		elif error.contains("too large") or error.contains("(limit "):
			kind = ModelFailure.TOO_LARGE
		return {"model": null, "failure": kind, "message": error.substr(0, 1).to_upper() + error.substr(1)}
	var model: OnnxPolicyModel = loaded.model
	var mismatch := model.validate(BvsSchema.current())
	if mismatch != "":
		return {"model": null, "failure": ModelFailure.SCHEMA_MISMATCH, "message": mismatch}
	return {"model": model, "failure": -1, "message": ""}

## Writes both files as `.part`, then renames them (the model first, the sidecar last).
func _store(dir: String, sidecar_bytes: PackedByteArray, onnx_bytes: PackedByteArray) -> bool:
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return false
	var files := [[SIDECAR_FILE, sidecar_bytes], [MODEL_FILE, onnx_bytes]]
	for entry in files:
		var part := FileAccess.open(dir.path_join(String(entry[0]) + ".part"), FileAccess.WRITE)
		if part == null:
			return false
		part.store_buffer(entry[1])
		part.close()
	for entry in [files[1], files[0]]:
		var final_path := dir.path_join(String(entry[0]))
		if FileAccess.file_exists(final_path):
			DirAccess.remove_absolute(final_path)
		if DirAccess.rename_absolute(final_path + ".part", final_path) != OK:
			return false
	return true

func _remember(repo: String, sha: String) -> void:
	var index_path := models_root.path_join("index.cfg")
	var index := ConfigFile.new()
	index.load(index_path)
	index.set_value("last", repo, sha)
	index.save(index_path)

func _remove_dir(dir: String) -> void:
	var handle := DirAccess.open(dir)
	if handle == null:
		return
	for file_name in handle.get_files():
		handle.remove(file_name)
	DirAccess.remove_absolute(dir)
