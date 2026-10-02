extends SceneTree
## The Hugging Face model picker, windowed. The Hub is faked: ModelManager's
## transport is replaced by a fixture, so the script never touches the network.
## Covers the discovery request, the rows (repo id, author, downloads, badge), the
## incompatible models disabled, the username search (URL-encoded server-side
## author query, Search button and Enter, remembered username, the zero-BVS
## fallback listing the user's other models disabled), choosing a model (explicit
## Policy config), and the loading / empty / error / offline states with retry.

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

## alice's own BVS models (server-side author query).
const ALICE_BODY := """[
	{"id": "alice/bvs-brawler", "author": "alice", "downloads": 3400, "tags": ["onnx", "BVS", "bvs-schema-1"]},
	{"id": "alice/bvs-v0", "author": "alice", "downloads": 20, "tags": ["onnx", "BVS", "bvs-schema-0"]}
]"""
## zed has no BVS model; the second query lists the other RL models.
const ZED_RL_BODY := """[
	{"id": "zed/cartpole-ppo", "author": "zed", "downloads": 500, "tags": ["reinforcement-learning", "onnx"]},
	{"id": "zed/lunar-dqn", "author": "zed", "downloads": 41, "tags": ["reinforcement-learning", "stable-baselines3"]}
]"""

## Hub listing as the API returns it (most downloaded first), plus a model that
## lost its BVS tag (never listed).
const FIXTURE := """[
	{"id": "alice/bvs-brawler", "author": "alice", "downloads": 3400, "tags": ["onnx", "BVS", "bvs-schema-1"]},
	{"id": "RafaelJaime/BVS_SB3", "author": "RafaelJaime", "downloads": 87, "tags": ["stable-baselines3", "BVS", "BVS.1"]},
	{"id": "bob/old-fighter", "downloads": 12, "tags": ["BVS", "bvs-schema-0"]},
	{"id": "carol/from-the-future", "author": "carol", "downloads": 2, "tags": ["BVS", "bvs-schema-2"]},
	{"id": "dave/not-ours", "author": "dave", "downloads": 9000, "tags": ["onnx"]}
]"""

var s: RefCounted
var manager: Node
var fake := {"urls": [], "hold": false, "pending": Callable(), "result": HTTPRequest.RESULT_SUCCESS, "code": 200, "body": FIXTURE, "by_url": {}}

func _initialize() -> void:
	_run()

func _install_fake() -> void:
	manager.hub_transport = func(url: String, done: Callable) -> void:
		fake.urls.append(url)
		if fake.hold:
			fake.pending = done
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
	s.check("their compat badges stay", _badge(_row_for(picker, "alice/bvs-brawler")) == "Compatible" and not _row_for(picker, "alice/bvs-brawler").disabled and _row_for(picker, "alice/bvs-v0").disabled)
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

func _run() -> void:
	s = Smoke.new(self)
	manager = root.get_node("ModelManager")
	DirAccess.remove_absolute(manager.prefs_path)
	_install_fake()

	# --- the listing logic, without any UI
	s.check("the current schema version is a constant", HubModel.BVS_SCHEMA_VERSION == 1)
	s.check("discovery is by tag, most downloaded first, no username", HubModel.DISCOVERY_URL == EXPECTED_URL and not HubModel.DISCOVERY_URL.contains("author="), HubModel.DISCOVERY_URL)
	var models: Array = HubModel.parse_list(FIXTURE)
	s.check("the parser keeps the BVS-tagged models in the Hub's order", models.map(func(m: HubModel): return m.id) == ["alice/bvs-brawler", "RafaelJaime/BVS_SB3", "bob/old-fighter", "carol/from-the-future"])
	s.check("compat comes from the bvs-schema-N tag", models[0].compat() == HubModel.Compat.COMPATIBLE and models[1].compat() == HubModel.Compat.OLDER and models[2].compat() == HubModel.Compat.OLDER and models[3].compat() == HubModel.Compat.NEWER)
	s.check("RafaelJaime/BVS_SB3 (tags BVS, BVS.1) is 'trained for an older version'", models[1].schema == -1 and models[1].badge_text() == "Trained for an older version")
	s.check("the author falls back to the repo owner", models[2].author == "bob")
	s.check("downloads read well", HubModel.format_downloads(87) == "87" and HubModel.format_downloads(3400) == "3.4k" and HubModel.format_downloads(2500000) == "2.5M")
	s.check("the author query is server-side, BVS-tagged and URL-encoded", HubModel.author_url("alice") == ALICE_URL and HubModel.author_url(ODD_NAME) == ODD_URL and HubModel.author_url("  alice ") == ALICE_URL, HubModel.author_url(ODD_NAME))
	s.check("the related query asks for the user's reinforcement-learning models", HubModel.author_rl_url("alice") == ALICE_RL_URL)
	var related: Array = HubModel.parse_related_list(ZED_RL_BODY)
	s.check("related models are listed, none usable, badged 'Not a BVS model'", related.size() == 2 and related.all(func(m: HubModel): return not m.is_compatible() and m.badge_text() == "Not a BVS model"))
	s.check("a body that is not a list is rejected", HubModel.parse_list("{\"error\": \"x\"}") == null and HubModel.parse_list("oops") == null)

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
	s.check("it builds the explicit Policy config", config.kind == ControllerConfig.Kind.POLICY and config.onnx_model_path == manager.get_model_path(0), "kind=%d path=%s" % [config.kind, config.onnx_model_path])
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
	s.check("every tag-list request used the discovery URL", fake.urls.all(func(url: String): return url == EXPECTED_URL or url.contains("author=")), str(fake.urls.size()))
	manager.hub_transport = Callable()
	s.finish()
