extends SceneTree
## The Hugging Face model picker, windowed. The Hub is faked: ModelManager's
## transport is replaced by a fixture, so the script never touches the network.
## Covers the discovery request, the rows (repo id, author, downloads, badge), the
## incompatible models disabled, the username search (URL-encoded server-side
## author query, Search button and Enter, remembered username, the zero-BVS
## fallback listing the user's other models disabled), choosing a model (explicit
## Policy config), and the loading / empty / error / offline states with retry.
## Also the model loading behind a pick: the repo + revision cache, the
## RESOLVING / DOWNLOADING / VALIDATING / READY states, every failure reason, cancel,
## the legacy Agent<N>.onnx cleanup, and the loading UX of the character select.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const SELECT_SCENE := "res://ui/character_select/character_select.tscn"
const EXPECTED_URL := "https://huggingface.co/api/models?filter=BVS&sort=downloads&limit=50"
const ALICE_URL := "https://huggingface.co/api/models?author=alice&filter=BVS&sort=downloads&limit=100"
const ALICE_RL_URL := "https://huggingface.co/api/models?author=alice&filter=reinforcement-learning&sort=downloads&limit=100"
## A username with a space and a slash must be encoded, not break the query.
const ODD_NAME := "Ana Maria/x"
const ODD_URL := "https://huggingface.co/api/models?author=Ana%20Maria%2Fx&filter=BVS&sort=downloads&limit=100"
const NOBVS_URL := "https://huggingface.co/api/models?author=zed&filter=BVS&sort=downloads&limit=100"
const NOBVS_RL_URL := "https://huggingface.co/api/models?author=zed&filter=reinforcement-learning&sort=downloads&limit=100"
const NOTHING_URL := "https://huggingface.co/api/models?author=nobody&filter=BVS&sort=downloads&limit=100"
const NOTHING_RL_URL := "https://huggingface.co/api/models?author=nobody&filter=reinforcement-learning&sort=downloads&limit=100"

## The model loading half: a throwaway cache and the random-weight fixture as "the repo".
const MODELS_ROOT := "user://smoke_models_picker"
const REPO := "alice/bvs-brawler"
const SHA1 := "1111111111111111111111111111111111111111"
const SHA2 := "2222222222222222222222222222222222222222"
const SHA3 := "3333333333333333333333333333333333333333"
const ONNX_PATH := "res://tests/fixtures/onnx/random_policy_v3.onnx"
const SIDECAR_PATH := "res://tests/fixtures/onnx/random_policy_v3.bvs.json"
const OPS_DIR := "res://tests/fixtures/onnx/ops/"

## alice's own BVS models (server-side author query).
const ALICE_BODY := """[
	{"id": "alice/bvs-brawler", "author": "alice", "downloads": 3400, "tags": ["onnx", "BVS", "bvs-schema-3"]},
	{"id": "alice/bvs-v0", "author": "alice", "downloads": 20, "tags": ["onnx", "BVS", "bvs-schema-2"]}
]"""
## zed has no BVS model; the second query lists the other RL models.
const ZED_RL_BODY := """[
	{"id": "zed/cartpole-ppo", "author": "zed", "downloads": 500, "tags": ["reinforcement-learning", "onnx"]},
	{"id": "zed/lunar-dqn", "author": "zed", "downloads": 41, "tags": ["reinforcement-learning", "stable-baselines3"]}
]"""

## Hub listing as the API returns it (most downloaded first), plus a model that
## lost its BVS tag (never listed).
const FIXTURE := """[
	{"id": "alice/bvs-brawler", "author": "alice", "downloads": 3400, "tags": ["onnx", "BVS", "bvs-schema-3"]},
	{"id": "RafaelJaime/BVS_SB3", "author": "RafaelJaime", "downloads": 87, "tags": ["stable-baselines3", "BVS", "BVS.1"]},
	{"id": "bob/old-fighter", "downloads": 12, "tags": ["BVS", "bvs-schema-0"]},
	{"id": "carol/from-the-future", "author": "carol", "downloads": 2, "tags": ["BVS", "bvs-schema-4"]},
	{"id": "dave/not-ours", "author": "dave", "downloads": 9000, "tags": ["onnx"]}
]"""

var s: RefCounted
var manager: Node
var fake := {"urls": [], "hold": false, "pending": Callable(), "result": HTTPRequest.RESULT_SUCCESS, "code": 200, "body": FIXTURE, "by_url": {}, "bytes_by_url": {}, "offline": false}

func _initialize() -> void:
	_run()

func _install_fake() -> void:
	manager.hub_transport = func(url: String, done: Callable) -> void:
		fake.urls.append(url)
		if fake.hold:
			fake.pending = done
		elif fake.offline:
			done.call(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())
		elif fake.bytes_by_url.has(url):
			var entry: Dictionary = fake.bytes_by_url[url]
			done.call(HTTPRequest.RESULT_SUCCESS, entry["code"], entry["body"])
		else:
			var body: String = fake.by_url.get(url, fake.body)
			done.call(fake.result, fake.code, body.to_utf8_buffer())

func _answer(result: int, code: int, body: String) -> void:
	fake.result = result
	fake.code = code
	fake.body = body

func _row_ids(picker: Control) -> Array[String]:
	var ids: Array[String] = []
	for row in picker.rows():
		ids.append((row.get_meta("model") as HubModel).id)
	return ids

func _row_for(picker: Control, id: String) -> Button:
	for row in picker.rows():
		if (row.get_meta("model") as HubModel).id == id:
			return row
	return null

func _badge(row: Button) -> String:
	return (row.find_child("Badge", true, false) as Label).text

## The username field: the main input of the picker.
func _username_search(picker: Control, ai: Control, chosen: Array) -> void:
	_answer(HTTPRequest.RESULT_SUCCESS, 200, FIXTURE)
	fake.by_url = {ALICE_URL: ALICE_BODY, ODD_URL: "[]", NOBVS_URL: "[]", NOBVS_RL_URL: ZED_RL_BODY, NOTHING_URL: "[]", NOTHING_RL_URL: "[]"}
	manager.prefs_path = "user://smoke_hf_picker_test.cfg"
	DirAccess.remove_absolute(manager.prefs_path)
	s.check("the username box sits right under the title, with the placeholder", picker.author_edit.placeholder_text == "Hugging Face username" and picker.author_edit.get_parent().get_index() == 1)
	s.check("nothing is remembered yet", manager.load_last_author() == "")

	# search by Search button
	fake.urls.clear()
	ai.open_model_picker(false)
	await s.frames(3)
	s.check("an empty field lists the tag (global list)", fake.urls == [EXPECTED_URL] and picker.rows().size() == 4, str(fake.urls))
	picker.author_edit.text = "alice"
	picker.search_button.pressed.emit()
	await s.frames(3)
	s.check("Search queries the author server-side", fake.urls.back() == ALICE_URL, str(fake.urls))
	s.check("the user's models are listed", _row_ids(picker) == ["alice/bvs-brawler", "alice/bvs-v0"], str(_row_ids(picker)))
	s.check("their compat badges stay", _badge(_row_for(picker, "alice/bvs-brawler")) == "Compatible" and not _row_for(picker, "alice/bvs-brawler").disabled and _row_for(picker, "alice/bvs-v0").disabled and _badge(_row_for(picker, "alice/bvs-v0")) == "Trained for an older version")
	s.check("the status names the user", picker.status_label.text.contains("by alice"), picker.status_label.text)
	s.check("the username is remembered", manager.load_last_author() == "alice")
	await s.screenshot("hf_picker_username")

	# Enter in the field, with an odd name
	picker.author_edit.text = ODD_NAME
	picker.author_edit.text_submitted.emit(ODD_NAME)
	await s.frames(3)
	s.check("Enter searches too, with the name URL-encoded", fake.urls.has(ODD_URL), str(fake.urls))

	# a user with no BVS model: hint plus their other RL models, disabled
	fake.urls.clear()
	picker.author_edit.text = "zed"
	picker.search_button.pressed.emit()
	await s.frames(3)
	s.check("zero BVS models: the RL models are asked for next", fake.urls == [NOBVS_URL, NOBVS_RL_URL], str(fake.urls))
	s.check("zero BVS models: the other models are listed", _row_ids(picker) == ["zed/cartpole-ppo", "zed/lunar-dqn"], str(_row_ids(picker)))
	var all_disabled: bool = picker.rows().all(func(row: Button): return row.disabled and _badge(row) == "Not a BVS model")
	s.check("zero BVS models: they are all disabled and badged", all_disabled)
	s.check("zero BVS models: a hint says there are no BVS models", picker.state == picker.PickerState.READY and picker.status_label.text.contains("no BVS models") and picker.is_related_fallback(), picker.status_label.text)
	var chosen_before := chosen.size()
	_row_for(picker, "zed/cartpole-ppo").pressed.emit()
	await s.frames(2)
	s.check("an unrelated model cannot be chosen", picker.visible and chosen.size() == chosen_before)
	await s.screenshot("hf_picker_zero_bvs")

	# nothing at all for that user
	picker.author_edit.text = "nobody"
	picker.search_button.pressed.emit()
	await s.frames(3)
	s.check("a user with no models shows the empty state", picker.state == picker.PickerState.EMPTY and picker.status_label.text.contains("nobody has no models") and picker.rows().is_empty())

	# reopening restores the last username
	picker.cancel()
	await s.frames(2)
	picker.author_edit.text = ""
	fake.urls.clear()
	ai.open_model_picker(false)
	await s.frames(3)
	s.check("reopening fills the remembered username and searches it", picker.author_edit.text == "nobody" and fake.urls.front() == NOTHING_URL, str(fake.urls))

	# emptying the field goes back to the tag list, and that is remembered too
	picker.author_edit.text = ""
	fake.urls.clear()
	picker.search_button.pressed.emit()
	await s.frames(3)
	s.check("an empty field is the global tag list again", fake.urls == [EXPECTED_URL] and picker.rows().size() == 4 and manager.load_last_author() == "", str(fake.urls))

	# a failure on the author query is a normal error state
	_answer(HTTPRequest.RESULT_SUCCESS, 500, "")
	fake.by_url = {}
	picker.author_edit.text = "alice"
	picker.search_button.pressed.emit()
	await s.frames(3)
	s.check("a failing author query shows the error state", picker.state == picker.PickerState.ERROR and picker.retry_button.visible)
	_answer(HTTPRequest.RESULT_SUCCESS, 200, "<html>oops</html>")
	picker.author_edit.text = ""
	picker.retry_button.pressed.emit()
	await s.frames(3)
	DirAccess.remove_absolute(manager.prefs_path)
	manager.prefs_path = "user://smoke_hub_picker.cfg"

## The Hub answer for `repo` at revision `sha`: its info (with the file list) and files.
func _serve(repo: String, sha: String, sidecar: PackedByteArray, onnx: PackedByteArray, files: Array = ["model.onnx", "bvs.json", "README.md"]) -> void:
	var siblings: Array = []
	for file_name in files:
		siblings.append({"rfilename": file_name})
	var info := JSON.stringify({"id": repo, "sha": sha, "siblings": siblings})
	fake.bytes_by_url[HubModel.info_url(repo)] = {"code": 200, "body": info.to_utf8_buffer()}
	fake.bytes_by_url[HubModel.file_url(repo, sha, "bvs.json")] = {"code": 200, "body": sidecar}
	fake.bytes_by_url[HubModel.file_url(repo, sha, "model.onnx")] = {"code": 200, "body": onnx}

func _only_download_urls() -> Array:
	return fake.urls.filter(func(url: String): return url.contains("/resolve/"))

func _states(events: Array) -> Array:
	return events.map(func(event: Array): return event[1])

## Loads a model through ModelManager and waits for the answer (the fake is synchronous).
func _request(slot: int, repo: String) -> void:
	fake.urls.clear()
	manager.request_model(slot, repo)
	await s.frames(1)

func _model_loading() -> void:
	var sidecar := FileAccess.get_file_as_bytes(SIDECAR_PATH)
	var onnx := FileAccess.get_file_as_bytes(ONNX_PATH)
	var State = manager.ModelState
	var Failure = manager.ModelFailure
	manager.models_root = MODELS_ROOT
	_remove_tree(MODELS_ROOT)
	_install_fake()
	var events: Array = []
	var readies: Array = []
	var failures: Array = []
	manager.model_state_changed.connect(func(slot: int, state: int, detail: String): events.append([slot, state, detail]))
	manager.model_ready.connect(func(slot: int, model: OnnxPolicyModel): readies.append([slot, model]))
	manager.model_failed.connect(func(slot: int, reason: int, message: String): failures.append([slot, reason, message]))

	s.check("the hub helpers build the info and pinned file URLs", HubModel.info_url(REPO) == "https://huggingface.co/api/models/alice/bvs-brawler" and HubModel.file_url(REPO, SHA1, "model.onnx") == "https://huggingface.co/alice/bvs-brawler/resolve/%s/model.onnx" % SHA1)
	s.check("the cache directory is user://models/<owner>__<name>/<sha>", manager.cache_dir(REPO, SHA1) == MODELS_ROOT + "/alice__bvs-brawler/" + SHA1)

	# --- a first pick: RESOLVING -> DOWNLOADING -> VALIDATING -> READY, pinned URLs
	_serve(REPO, SHA1, sidecar, onnx)
	await _request(0, REPO)
	var seen: Array = _states(events)
	s.check("pick: the states go RESOLVING, DOWNLOADING, VALIDATING, READY", seen.has(State.RESOLVING) and seen.has(State.DOWNLOADING) and seen.has(State.VALIDATING) and seen.back() == State.READY and seen.find(State.RESOLVING) < seen.find(State.DOWNLOADING) and seen.find(State.DOWNLOADING) < seen.find(State.VALIDATING) and seen.find(State.VALIDATING) < seen.find(State.READY), str(seen))
	s.check("pick: one metadata call, then the sidecar and the model at the pinned sha", fake.urls == [HubModel.info_url(REPO), HubModel.file_url(REPO, SHA1, "bvs.json"), HubModel.file_url(REPO, SHA1, "model.onnx")], str(fake.urls))
	var first_model: OnnxPolicyModel = manager.model_of(0)
	s.check("pick: READY with a validated model that knows its repo and revision", manager.state_of(0) == State.READY and first_model != null and first_model.repo_id == REPO and first_model.revision == SHA1 and readies.size() == 1 and readies[0][1] == first_model and first_model.validate(BvsSchema.current()) == "")
	var dir1: String = manager.cache_dir(REPO, SHA1)
	s.check("pick: both files are cached at the repo + sha directory, no .part left", manager.is_cache_complete(dir1) and not FileAccess.file_exists(dir1 + "/model.onnx.part") and not FileAccess.file_exists(dir1 + "/bvs.json.part"))
	s.check("pick: the index remembers the revision for offline use", manager.cached_sha(REPO) == SHA1)

	# --- a second pick of the same revision: no download at all
	events.clear()
	await _request(1, REPO)
	s.check("cache hit: only the metadata call, no file download", _only_download_urls().is_empty() and fake.urls == [HubModel.info_url(REPO)], str(fake.urls))
	s.check("cache hit: READY at once, noted as cached", manager.state_of(1) == State.READY and manager.detail_of(1).contains("cached") and manager.model_of(1).revision == SHA1, manager.detail_of(1))

	# --- a new revision downloads again and leaves the old one alone
	var sha1_files := FileAccess.get_file_as_bytes(dir1 + "/model.onnx").size()
	_serve(REPO, SHA2, sidecar, onnx)
	await _request(0, REPO)
	var dir2: String = manager.cache_dir(REPO, SHA2)
	s.check("new revision: both files are downloaded from the new sha", _only_download_urls() == [HubModel.file_url(REPO, SHA2, "bvs.json"), HubModel.file_url(REPO, SHA2, "model.onnx")], str(fake.urls))
	s.check("new revision: stored in its own directory, the old one untouched", manager.is_cache_complete(dir2) and manager.is_cache_complete(dir1) and FileAccess.get_file_as_bytes(dir1 + "/model.onnx").size() == sha1_files and manager.model_of(0).revision == SHA2)

	# --- offline with a cached revision still plays
	fake.offline = true
	await _request(0, REPO)
	s.check("offline with a cached sha: READY, noted as offline and cached", manager.state_of(0) == State.READY and manager.detail_of(0).contains("offline, cached") and manager.model_of(0).revision == SHA2, manager.detail_of(0))
	s.check("offline: nothing was downloaded", _only_download_urls().is_empty())
	await _request(0, "alice/never-seen")
	s.check("offline with nothing cached: FAILED (OFFLINE), a visible reason", manager.state_of(0) == State.FAILED and manager.failure_of(0) == Failure.OFFLINE and manager.message_of(0).contains("reach Hugging Face"), manager.message_of(0))
	fake.offline = false

	# --- a partial download is not trusted
	var partial_dir: String = manager.cache_dir(REPO, SHA3)
	DirAccess.make_dir_recursive_absolute(partial_dir)
	var partial := FileAccess.open(partial_dir + "/model.onnx", FileAccess.WRITE)
	partial.store_buffer(onnx)
	partial.close()
	var partial_part := FileAccess.open(partial_dir + "/bvs.json.part", FileAccess.WRITE)
	partial_part.store_string("{")
	partial_part.close()
	s.check("a directory with only the model and a .part sidecar is not complete", not manager.is_cache_complete(partial_dir))
	_serve(REPO, SHA3, sidecar, onnx)
	await _request(0, REPO)
	s.check("partial entry: the files are downloaded again", _only_download_urls().size() == 2 and manager.is_cache_complete(partial_dir) and manager.state_of(0) == State.READY, str(fake.urls))

	# --- a different model in the same slot uses its own files
	var other_repo := "bob/other-fighter"
	_serve(other_repo, SHA1, sidecar, onnx)
	await _request(0, other_repo)
	s.check("different model, same slot: the new repo's files are used", manager.model_of(0).repo_id == other_repo and manager.repo_of(0) == other_repo and manager.is_cache_complete(manager.cache_dir(other_repo, SHA1)))

	# --- failures: each has its reason and nothing is cached as ready
	failures.clear()
	var before_dirs := _list_dirs(MODELS_ROOT)
	fake.bytes_by_url[HubModel.info_url("carol/missing")] = {"code": 404, "body": PackedByteArray()}
	await _request(0, "carol/missing")
	s.check("failure NOT_FOUND on HTTP 404", manager.failure_of(0) == Failure.NOT_FOUND and manager.state_of(0) == State.FAILED, manager.message_of(0))
	fake.bytes_by_url[HubModel.info_url("carol/limited")] = {"code": 429, "body": PackedByteArray()}
	await _request(0, "carol/limited")
	s.check("failure RATE_LIMITED on HTTP 429 states the rate limit", manager.failure_of(0) == Failure.RATE_LIMITED and manager.message_of(0).to_lower().contains("rate limit"), manager.message_of(0))
	fake.bytes_by_url[HubModel.info_url("carol/broken")] = {"code": 500, "body": PackedByteArray()}
	await _request(0, "carol/broken")
	s.check("failure SERVER on HTTP 500", manager.failure_of(0) == Failure.SERVER and manager.message_of(0).contains("500"), manager.message_of(0))
	await _request(0, "not a repo id")
	s.check("a malformed repo id fails without a request", manager.state_of(0) == State.FAILED and fake.urls.is_empty(), manager.message_of(0))
	_serve("carol/nosidecar", SHA1, sidecar, onnx, ["model.onnx", "README.md"])
	await _request(0, "carol/nosidecar")
	s.check("failure MISSING_FILES names the file the repo lacks", manager.failure_of(0) == Failure.MISSING_FILES and manager.message_of(0).contains("bvs.json") and _only_download_urls().is_empty(), manager.message_of(0))
	_serve("carol/notjson", SHA1, "not json".to_utf8_buffer(), onnx)
	await _request(0, "carol/notjson")
	s.check("failure BAD_SIDECAR for a bvs.json that is not JSON", manager.failure_of(0) == Failure.BAD_SIDECAR, manager.message_of(0))
	var missing_key: Dictionary = JSON.parse_string(sidecar.get_string_from_utf8())
	missing_key.erase("action_repeat")
	_serve("carol/nokey", SHA1, JSON.stringify(missing_key).to_utf8_buffer(), onnx)
	await _request(0, "carol/nokey")
	s.check("failure BAD_SIDECAR for a missing key, naming it", manager.failure_of(0) == Failure.BAD_SIDECAR and manager.message_of(0).contains("action_repeat"), manager.message_of(0))
	var wrong_dim: Dictionary = JSON.parse_string(sidecar.get_string_from_utf8())
	wrong_dim["obs_dim"] = 13
	_serve("carol/sidecar13", SHA1, JSON.stringify(wrong_dim).to_utf8_buffer(), onnx)
	await _request(0, "carol/sidecar13")
	s.check("failure SCHEMA_MISMATCH when the sidecar declares another obs_dim", manager.failure_of(0) == Failure.SCHEMA_MISMATCH and manager.message_of(0).contains("expects 13 inputs; this game provides 136"), manager.message_of(0))
	var wrong_schema: Dictionary = JSON.parse_string(sidecar.get_string_from_utf8())
	wrong_schema["schema_version"] = 1
	_serve("carol/schema1", SHA1, JSON.stringify(wrong_schema).to_utf8_buffer(), onnx)
	await _request(0, "carol/schema1")
	s.check("failure SCHEMA_MISMATCH for another schema version", manager.failure_of(0) == Failure.SCHEMA_MISMATCH, manager.message_of(0))
	var small_model := FileAccess.get_file_as_bytes(OPS_DIR + "gemm_no_c.onnx")
	var plain_sidecar: Dictionary = JSON.parse_string(sidecar.get_string_from_utf8())
	plain_sidecar.erase("onnx")
	_serve("carol/small", SHA1, JSON.stringify(plain_sidecar).to_utf8_buffer(), small_model)
	await _request(0, "carol/small")
	s.check("failure SCHEMA_MISMATCH when the ONNX takes another input size", manager.failure_of(0) == Failure.SCHEMA_MISMATCH and manager.message_of(0).contains("expects") and manager.message_of(0).contains("this game provides 136"), manager.message_of(0))
	_serve("carol/lstm", SHA1, sidecar, FileAccess.get_file_as_bytes(OPS_DIR + "reject_unknown_op_lstm.onnx"))
	await _request(0, "carol/lstm")
	s.check("failure UNSUPPORTED_OP names the operation", manager.failure_of(0) == Failure.UNSUPPORTED_OP and manager.message_of(0).contains("LSTM"), manager.message_of(0))
	_serve("carol/truncated", SHA1, sidecar, onnx.slice(0, onnx.size() / 2))
	await _request(0, "carol/truncated")
	s.check("failure BAD_ONNX for a truncated model", manager.failure_of(0) == Failure.BAD_ONNX, manager.message_of(0))
	var huge := PackedByteArray()
	huge.resize(manager.MAX_MODEL_BYTES + 1)
	_serve("carol/huge", SHA1, sidecar, huge)
	await _request(0, "carol/huge")
	s.check("failure TOO_LARGE above the size cap", manager.failure_of(0) == Failure.TOO_LARGE, manager.message_of(0))
	s.check("every failure emitted model_failed with its reason", failures.size() >= 12 and failures.all(func(entry: Array): return entry[0] == 0 and String(entry[2]) != ""), str(failures.size()))
	s.check("no failure left anything in the cache", _list_dirs(MODELS_ROOT) == before_dirs, str(_list_dirs(MODELS_ROOT)))
	s.check("a failed slot has no model", manager.model_of(0) == null)

	# --- cancel: the transfer stops, nothing is marked ready, a late answer is dropped
	_serve("dora/cancelled", SHA1, sidecar, onnx)
	events.clear()
	readies.clear()
	fake.hold = true
	fake.urls.clear()
	manager.request_model(1, "dora/cancelled")
	s.check("held request: RESOLVING", manager.state_of(1) == State.RESOLVING and manager.is_busy(1))
	var late_info: Callable = fake.pending
	manager.cancel(1)
	s.check("cancel while resolving: the slot is IDLE again", manager.state_of(1) == State.IDLE and not manager.is_busy(1) and manager.model_of(1) == null)
	late_info.call(HTTPRequest.RESULT_SUCCESS, 200, (fake.bytes_by_url[HubModel.info_url("dora/cancelled")]["body"] as PackedByteArray))
	await s.frames(1)
	s.check("an answer after cancel is ignored: no download, no ready model", manager.state_of(1) == State.IDLE and _only_download_urls().is_empty() and readies.is_empty() and not manager.is_cache_complete(manager.cache_dir("dora/cancelled", SHA1)))
	fake.hold = false
	# Cancel while the model file is downloading.
	manager.request_model(1, "dora/cancelled")
	await s.frames(1)
	s.check("the fake answered everything: READY (cache primed)", manager.state_of(1) == State.READY)
	_remove_tree(manager.cache_dir("dora/cancelled", SHA1))
	fake.hold = true
	manager.request_model(1, "dora/cancelled")
	var info_answer: Callable = fake.pending
	info_answer.call(HTTPRequest.RESULT_SUCCESS, 200, (fake.bytes_by_url[HubModel.info_url("dora/cancelled")]["body"] as PackedByteArray))
	var sidecar_answer: Callable = fake.pending
	sidecar_answer.call(HTTPRequest.RESULT_SUCCESS, 200, sidecar)
	s.check("held transfer: DOWNLOADING the model", manager.state_of(1) == State.DOWNLOADING, str(manager.state_of(1)))
	var model_answer: Callable = fake.pending
	manager.cancel(1)
	model_answer.call(HTTPRequest.RESULT_SUCCESS, 200, onnx)
	await s.frames(1)
	s.check("cancel while downloading: the model answer is dropped and no cache entry exists", manager.state_of(1) == State.IDLE and not manager.is_cache_complete(manager.cache_dir("dora/cancelled", SHA1)) and manager.model_of(1) == null)
	fake.hold = false

	# --- a legacy Agent<N>.onnx is never read and is cleaned up
	var legacy_path := "user://Agent1.onnx"
	var legacy := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy.store_string("not an onnx file")
	legacy.close()
	await _request(1, REPO)
	s.check("a legacy user://Agent1.onnx does not influence a selection", manager.state_of(1) == State.READY and manager.model_of(1).repo_id == REPO)
	s.check("the startup cleanup deletes legacy Agent<N>.onnx files", manager.cleanup_legacy_files() >= 1 and not FileAccess.file_exists(legacy_path))

	manager.cancel(0)
	manager.cancel(1)
	_remove_tree(MODELS_ROOT)
	fake.urls.clear()
	fake.hold = false
	fake.offline = false

func _list_dirs(path: String) -> Array:
	var found: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		return found
	for sub in dir.get_directories():
		found.append(sub)
		for deeper in _list_dirs(path + "/" + sub):
			found.append(sub + "/" + deeper)
	found.sort()
	return found

func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path + "/" + sub)
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)

## The character select's loading UX: prefetch on pick, status line, Cancel, Play gating, failure with Back.
func _loading_ux(select: Control, picker: Control, ai: Control) -> void:
	var State = manager.ModelState
	var sidecar := FileAccess.get_file_as_bytes(SIDECAR_PATH)
	var onnx := FileAccess.get_file_as_bytes(ONNX_PATH)
	manager.models_root = MODELS_ROOT
	_remove_tree(MODELS_ROOT)
	_serve(REPO, SHA1, sidecar, onnx)
	var play: Button = select.play_button
	s.check("Play is enabled with the default controllers", not play.disabled and ai.is_ready_to_play())

	# Pick: the request starts at once and the panel shows it; Play waits.
	_answer(HTTPRequest.RESULT_SUCCESS, 200, FIXTURE)
	fake.by_url = {}
	ai.open_model_picker(false)
	await s.frames(3)
	fake.hold = true
	fake.urls.clear()
	picker.rows()[0].pressed.emit()  # alice/bvs-brawler, the first compatible row
	await s.frames(2)
	var chosen_id: String = ai.option_button_p1.get_item_text(0)
	s.check("choosing a model prefetches it at once (resolving)", manager.state_of(0) == State.RESOLVING and manager.repo_of(0) == chosen_id and fake.urls.back() == HubModel.info_url(chosen_id), str(fake.urls))
	s.check("the panel shows 'Resolving...' with a Cancel button", ai.status_label_p1.visible and ai.status_label_p1.text.contains("Resolving") and ai.cancel_button_p1.visible)
	s.check("Play is disabled while the model is pending", play.disabled and not ai.is_ready_to_play())
	select._on_play_button_pressed()
	s.check("pressing Play while pending does not start a match", not (root.get_node("SceneManager").current_scene is Game))
	var answer: Callable = fake.pending
	answer.call(HTTPRequest.RESULT_SUCCESS, 200, (fake.bytes_by_url[HubModel.info_url(chosen_id)]["body"] as PackedByteArray))
	var sidecar_answer: Callable = fake.pending
	sidecar_answer.call(HTTPRequest.RESULT_SUCCESS, 200, sidecar)
	await s.frames(1)
	s.check("the panel shows the download", ai.status_label_p1.text.contains("Downloading") and ai.cancel_button_p1.visible, ai.status_label_p1.text)
	var model_answer: Callable = fake.pending
	model_answer.call(HTTPRequest.RESULT_SUCCESS, 200, onnx)
	await s.frames(2)
	s.check("READY: the status says so, Cancel is gone, Play is enabled", manager.state_of(0) == State.READY and ai.status_label_p1.text.contains("Ready") and not ai.cancel_button_p1.visible and not play.disabled and ai.is_ready_to_play(), ai.status_label_p1.text)
	var ready_config: ControllerConfig = ai.get_controller_config(false)
	s.check("the ready model builds the explicit Policy config with its handle", ready_config.kind == ControllerConfig.Kind.POLICY and ready_config.model != null and ready_config.model.repo_id == chosen_id and ready_config.model.revision == SHA1 and ready_config.is_playable())
	fake.hold = false
	ai._on_back_button_pressed(false)
	await s.frames(1)
	s.check("Back drops the model: the slot is idle and Human is back", manager.state_of(0) == State.IDLE and ai.get_controller_config(false).kind == ControllerConfig.Kind.HUMAN and not ai.status_label_p1.visible)

	# Cancel while loading: the previous controller returns, a late answer changes nothing.
	ai.open_model_picker(false)
	await s.frames(3)
	fake.hold = true
	picker.rows()[0].pressed.emit()
	await s.frames(2)
	var late: Callable = fake.pending
	s.check("a new pick shows the loading state again", manager.state_of(0) == State.RESOLVING and ai.cancel_button_p1.visible and play.disabled)
	ai.cancel_button_p1.pressed.emit()
	await s.frames(1)
	s.check("Cancel reverts the selection: Human, CPU options back, nothing pending", ai.get_controller_config(false).kind == ControllerConfig.Kind.HUMAN and ai.controller_option_p1.visible and not ai.option_button_p1.visible and manager.state_of(0) == State.IDLE and not ai.cancel_button_p1.visible)
	s.check("Play is enabled again after Cancel", not play.disabled)
	late.call(HTTPRequest.RESULT_SUCCESS, 200, (fake.bytes_by_url[HubModel.info_url(chosen_id)]["body"] as PackedByteArray))
	await s.frames(1)
	s.check("the late answer after Cancel changes nothing", manager.state_of(0) == State.IDLE and ai.get_controller_config(false).kind == ControllerConfig.Kind.HUMAN)
	fake.hold = false

	# A failure (rate limit): the reason is visible, Play stays disabled, no CPU swap, Back recovers.
	fake.bytes_by_url[HubModel.info_url(chosen_id)] = {"code": 429, "body": PackedByteArray()}
	ai.open_model_picker(true)
	await s.frames(3)
	picker.rows()[0].pressed.emit()
	await s.frames(2)
	s.check("a failing model shows the reason on the panel", manager.state_of(1) == State.FAILED and ai.status_label_p2.visible and ai.status_label_p2.text.to_lower().contains("rate limit"), ai.status_label_p2.text)
	s.check("Play is disabled and the failed selection is not a CPU", play.disabled and not ai.is_ready_to_play() and ai.get_controller_config(true).kind == ControllerConfig.Kind.POLICY and not ai.get_controller_config(true).is_playable())
	ai._on_back_button_pressed(true)
	await s.frames(1)
	s.check("after Back the second player is a CPU again and Play is enabled", ai.get_controller_config(true).kind == ControllerConfig.Kind.CPU and not play.disabled and not ai.status_label_p2.visible)
	_remove_tree(MODELS_ROOT)
	manager.cancel(0)
	manager.cancel(1)

func _run() -> void:
	s = Smoke.new(self)
	manager = root.get_node("ModelManager")
	DirAccess.remove_absolute(manager.prefs_path)
	_install_fake()

	# --- the listing logic, without any UI
	s.check("the current schema version is a constant", HubModel.BVS_SCHEMA_VERSION == 3 and HubModel.BVS_SCHEMA_VERSION == BvsSchema.CURRENT_VERSION)
	s.check("discovery is by tag, most downloaded first, no username", HubModel.DISCOVERY_URL == EXPECTED_URL and not HubModel.DISCOVERY_URL.contains("author="), HubModel.DISCOVERY_URL)
	var models: Array = HubModel.parse_list(FIXTURE)
	s.check("the parser keeps the BVS-tagged models in the Hub's order", models.map(func(m: HubModel): return m.id) == ["alice/bvs-brawler", "RafaelJaime/BVS_SB3", "bob/old-fighter", "carol/from-the-future"])
	s.check("compat comes from the bvs-schema-N tag", models[0].compat() == HubModel.Compat.COMPATIBLE and models[1].compat() == HubModel.Compat.OLDER and models[2].compat() == HubModel.Compat.OLDER and models[3].compat() == HubModel.Compat.NEWER)
	var v2_listing: Array = HubModel.parse_list("[{\"id\": \"erin/bvs-v2\", \"author\": \"erin\", \"tags\": [\"BVS\", \"bvs-schema-2\"]}]")
	s.check("a schema 2 model is 'Trained for an older version' now that the game uses schema 3", v2_listing.size() == 1 and v2_listing[0].compat() == HubModel.Compat.OLDER and v2_listing[0].badge_text() == "Trained for an older version" and not v2_listing[0].is_compatible())
	s.check("RafaelJaime/BVS_SB3 (tags BVS, BVS.1) is 'trained for an older version'", models[1].schema == -1 and models[1].badge_text() == "Trained for an older version")
	s.check("the author falls back to the repo owner", models[2].author == "bob")
	s.check("downloads read well", HubModel.format_downloads(87) == "87" and HubModel.format_downloads(3400) == "3.4k" and HubModel.format_downloads(2500000) == "2.5M")
	s.check("the author query is server-side, BVS-tagged and URL-encoded", HubModel.author_url("alice") == ALICE_URL and HubModel.author_url(ODD_NAME) == ODD_URL and HubModel.author_url("  alice ") == ALICE_URL, HubModel.author_url(ODD_NAME))
	s.check("the related query asks for the user's reinforcement-learning models", HubModel.author_rl_url("alice") == ALICE_RL_URL)
	var related: Array = HubModel.parse_related_list(ZED_RL_BODY)
	s.check("related models are listed, none usable, badged 'Not a BVS model'", related.size() == 2 and related.all(func(m: HubModel): return not m.is_compatible() and m.badge_text() == "Not a BVS model"))
	s.check("a body that is not a list is rejected", HubModel.parse_list("{\"error\": \"x\"}") == null and HubModel.parse_list("oops") == null)

	# --- the model loading behind a pick (cache, states, failures, cancel)
	await _model_loading()
	manager.models_root = MODELS_ROOT
	_remove_tree(MODELS_ROOT)
	_serve(REPO, SHA1, FileAccess.get_file_as_bytes(SIDECAR_PATH), FileAccess.get_file_as_bytes(ONNX_PATH))

	# --- the picker inside the character select
	var select: Control = load(SELECT_SCENE).instantiate()
	root.add_child(select)
	await s.frames(3)
	var picker: Control = select.get_node("ModelPicker")
	var ai: Control = select.get_node("AIController")
	select.select_player1(select.characters[0])
	select.select_player2(select.characters[1])
	await s.frames(2)
	s.check("the username box and search button are gone", ai.get_node("ControlP1").get_node_or_null("TextEdit") == null and ai.get_node("ControlP1").get_node_or_null("SearchButton") == null and ai.get_node("ControlP2").get_node_or_null("TextEdit") == null)
	s.check("the picker starts closed", not picker.visible)

	# loading state (the answer is held back)
	fake.hold = true
	var chosen: Array = []
	picker.model_chosen.connect(func(model: HubModel): chosen.append(model))
	ai.open_model_picker(false)
	await s.frames(2)
	s.check("Use AI opens the picker and asks the Hub by tag", picker.visible and fake.urls.size() == 1 and fake.urls[0] == EXPECTED_URL, str(fake.urls))
	s.check("loading: the state is LOADING with a message and no rows", picker.state == picker.PickerState.LOADING and picker.status_label.text.contains("Loading") and picker.rows().is_empty() and picker.search_button.disabled)
	await s.screenshot("hf_picker_loading")
	fake.hold = false
	fake.pending.call(HTTPRequest.RESULT_SUCCESS, 200, FIXTURE.to_utf8_buffer())
	await s.frames(3)

	# ready state
	s.check("ready: one row per BVS model, in the Hub's order", _row_ids(picker) == ["alice/bvs-brawler", "RafaelJaime/BVS_SB3", "bob/old-fighter", "carol/from-the-future"], str(_row_ids(picker)))
	var good := _row_for(picker, "alice/bvs-brawler")
	var legacy := _row_for(picker, "RafaelJaime/BVS_SB3")
	var future := _row_for(picker, "carol/from-the-future")
	s.check("ready: a compatible model is enabled and badged 'Compatible'", good != null and not good.disabled and _badge(good) == "Compatible")
	s.check("ready: the old model is disabled, badged 'Trained for an older version'", legacy != null and legacy.disabled and _badge(legacy) == "Trained for an older version")
	s.check("ready: a model for a newer schema is disabled too", future != null and future.disabled and _badge(future) == "Needs a newer game")
	var texts := ""
	for node in good.find_children("*", "Label", true, false):
		texts += (node as Label).text + "|"
	s.check("each row shows the repo id, author and downloads", texts.contains("alice/bvs-brawler") and texts.contains("by alice") and texts.contains("3.4k downloads"), texts)
	s.check("ready: the first enabled row has the focus", good.has_focus())
	await s.screenshot("hf_picker_ready")

	# an incompatible model can never be chosen
	legacy.pressed.emit()
	await s.frames(2)
	s.check("pressing a disabled (older) model chooses nothing", chosen.is_empty() and picker.visible)

	# no more client-side filter: typing alone changes nothing until Search
	picker.author_edit.text = "alice"
	picker.author_edit.text_changed.emit("alice")
	await s.frames(2)
	s.check("typing a username does not query or filter by itself", picker.rows().size() == 4 and fake.urls.size() == 1)
	picker.author_edit.text = ""

	# choosing a compatible model
	_row_for(picker, "alice/bvs-brawler").pressed.emit()
	await s.frames(3)
	s.check("choosing a compatible model emits it and closes the picker", chosen.size() == 1 and (chosen[0] as HubModel).id == "alice/bvs-brawler" and not picker.visible)
	var option: OptionButton = ai.get_node("ControlP1/OptionButton")
	s.check("the chosen model is shown for that player", option.visible and option.selected == 0 and option.get_item_text(0) == "alice/bvs-brawler")
	var config: ControllerConfig = ai.get_controller_config(false)
	s.check("it builds the explicit Policy config with the prepared model", config.kind == ControllerConfig.Kind.POLICY and config.model != null and config.model.repo_id == "alice/bvs-brawler" and config.is_playable(), "kind=%d model=%s" % [config.kind, str(config.model)])
	s.check("the other player is untouched (CPU Normal)", ai.get_controller_config(true).kind == ControllerConfig.Kind.CPU)
	ai._on_back_button_pressed(false)
	s.check("Back drops the model: Human again, CPU options back", ai.get_controller_config(false).kind == ControllerConfig.Kind.HUMAN and ai.get_node("ControlP1/ControllerOption").visible)

	# error state: HTTP 500, then a retry that works
	_answer(HTTPRequest.RESULT_SUCCESS, 500, "")
	ai.open_model_picker(true)
	await s.frames(3)
	s.check("error: HTTP 500 shows the error state with a Retry", picker.state == picker.PickerState.ERROR and picker.status_label.text.contains("500") and picker.retry_button.visible and picker.rows().is_empty(), picker.status_label.text)
	s.check("error: the Retry button has the focus", picker.retry_button.has_focus())
	await s.screenshot("hf_picker_error")
	_answer(HTTPRequest.RESULT_SUCCESS, 200, FIXTURE)
	picker.retry_button.pressed.emit()
	await s.frames(3)
	s.check("error: Retry loads the list", picker.state == picker.PickerState.READY and picker.rows().size() == 4 and not picker.retry_button.visible)
	_row_for(picker, "alice/bvs-brawler").pressed.emit()
	await s.frames(2)
	s.check("the second player's choice lands on the second player", ai.get_node("ControlP2/OptionButton").get_item_text(0) == "alice/bvs-brawler" and ai.get_controller_config(true).kind == ControllerConfig.Kind.POLICY)
	ai._on_back_button_pressed(true)

	# offline state
	_answer(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	ai.open_model_picker(false)
	await s.frames(3)
	s.check("offline: a connection failure shows the offline state with a Retry", picker.state == picker.PickerState.OFFLINE and picker.status_label.text.to_lower().contains("offline") and picker.retry_button.visible)
	await s.screenshot("hf_picker_offline")

	# empty state
	_answer(HTTPRequest.RESULT_SUCCESS, 200, "[]")
	picker.retry_button.pressed.emit()
	await s.frames(3)
	s.check("empty: no models shows the empty state with a Retry", picker.state == picker.PickerState.EMPTY and picker.status_label.text.contains("No BVS models") and picker.retry_button.visible)
	await s.screenshot("hf_picker_empty")

	# unreadable answer is an error, not an empty list
	_answer(HTTPRequest.RESULT_SUCCESS, 200, "<html>oops</html>")
	picker.retry_button.pressed.emit()
	await s.frames(3)
	s.check("a garbled answer is an error with a Retry", picker.state == picker.PickerState.ERROR and picker.retry_button.visible)

	await _username_search(picker, ai, chosen)

	# the loading UX of a pick: prefetch, status, Cancel, Play gating, failure
	await _loading_ux(select, picker, ai)

	# cancel
	picker.cancel_button.pressed.emit()
	await s.frames(2)
	s.check("Cancel closes the picker and restores the options", not picker.visible and ai.get_node("ControlP1/ControllerOption").visible and ai.get_controller_config(false).kind == ControllerConfig.Kind.HUMAN)

	# the whole script stayed off the network
	var http_nodes := 0
	for child in manager.get_children():
		if child is HTTPRequest:
			http_nodes += 1
	s.check("no HTTPRequest was ever created (the Hub was faked)", http_nodes == 0)
	var list_urls: Array = fake.urls.filter(func(url: String): return not url.contains("/api/models/") and not url.contains("/resolve/"))
	s.check("every tag-list request used the discovery URL", list_urls.all(func(url: String): return url == EXPECTED_URL or url.contains("author=")), str(list_urls.size()))
	_remove_tree(MODELS_ROOT)
	manager.models_root = "user://models"
	manager.hub_transport = Callable()
	s.finish()
