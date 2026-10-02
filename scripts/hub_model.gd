class_name HubModel
extends RefCounted
## A model listed by the Hugging Face Hub under the BVS tag, and what the game can
## tell about it from the listing alone (no download): who made it, how popular
## it is and whether it was trained for this version of the game.
##
## Compatibility comes from a `bvs-schema-N` tag. N is the observation/action
## schema the model was trained against; it must equal BVS_SCHEMA_VERSION. A model
## with no such tag (for example RafaelJaime/BVS_SB3, tagged BVS and BVS.1) predates
## the schema and is shown as trained for an older version.

## The observation/action schema this build of the game understands. Raised only
## when the schema changes (the later hf-ai-opponents change freezes it).
const BVS_SCHEMA_VERSION := 1
## The tag every BVS model carries on the Hub.
const TAG := "BVS"
const SCHEMA_TAG_PREFIX := "bvs-schema-"
## Models discovered by tag, most downloaded first (no username needed).
const DISCOVERY_URL := "https://huggingface.co/api/models?filter=%s&sort=downloads&limit=50" % TAG

## A user's other reinforcement-learning models (no BVS tag), shown disabled when
## the user has no BVS model at all.
const RL_TAG := "reinforcement-learning"

enum Compat { COMPATIBLE, OLDER, NEWER, NOT_BVS }
## Why a listing could not be loaded.
enum Failure { OFFLINE, SERVER, BAD_DATA }

var id: String = ""
var author: String = ""
var downloads: int = 0
var tags: PackedStringArray = PackedStringArray()
## The N of the `bvs-schema-N` tag, or -1 when the model has none.
var schema: int = -1
## False for a model listed only as "related" (no BVS tag): never usable.
var is_bvs: bool = true

## Request for every BVS model of one Hub user, most downloaded first. The
## username is URL-encoded.
static func author_url(username: String) -> String:
	return "https://huggingface.co/api/models?author=%s&filter=%s&sort=downloads&limit=100" % [username.strip_edges().uri_encode(), TAG]

## Request for a user's other reinforcement-learning models (the zero-BVS fallback).
static func author_rl_url(username: String) -> String:
	return "https://huggingface.co/api/models?author=%s&filter=%s&sort=downloads&limit=100" % [username.strip_edges().uri_encode(), RL_TAG]

func compat() -> Compat:
	if not is_bvs:
		return Compat.NOT_BVS
	if schema == BVS_SCHEMA_VERSION:
		return Compat.COMPATIBLE
	if schema > BVS_SCHEMA_VERSION:
		return Compat.NEWER
	return Compat.OLDER

func is_compatible() -> bool:
	return compat() == Compat.COMPATIBLE

func badge_text() -> String:
	match compat():
		Compat.COMPATIBLE:
			return "Compatible"
		Compat.NEWER:
			return "Needs a newer game"
		Compat.NOT_BVS:
			return "Not a BVS model"
	return "Trained for an older version"

## The highest `bvs-schema-N` among the tags, -1 when there is none.
static func schema_of(model_tags: PackedStringArray) -> int:
	var found := -1
	for tag in model_tags:
		if tag.begins_with(SCHEMA_TAG_PREFIX):
			var number := tag.trim_prefix(SCHEMA_TAG_PREFIX)
			if number.is_valid_int():
				found = maxi(found, number.to_int())
	return found

## One entry of the Hub's model list; null when it has no usable id.
static func from_entry(entry: Variant) -> HubModel:
	if typeof(entry) != TYPE_DICTIONARY:
		return null
	var model_id := String(entry.get("id", entry.get("modelId", "")))
	if model_id.is_empty():
		return null
	var model := HubModel.new()
	model.id = model_id
	model.author = String(entry.get("author", model_id.get_slice("/", 0) if model_id.contains("/") else ""))
	model.downloads = int(entry.get("downloads", 0))
	for tag in entry.get("tags", []):
		model.tags.append(String(tag))
	model.schema = schema_of(model.tags)
	model.is_bvs = TAG in model.tags
	return model

## The models of a Hub list response, in the Hub's order; null when the text is
## not a JSON array. Entries without the BVS tag are dropped.
static func parse_list(text: String) -> Variant:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		return null
	var models: Array[HubModel] = []
	for entry in parsed:
		var model := from_entry(entry)
		if model != null and TAG in model.tags:
			models.append(model)
	return models

## The models of an "other models" response: every entry, none usable (they are
## listed without the BVS tag, so the game cannot know their schema); null when
## the text is not a JSON array.
static func parse_related_list(text: String) -> Variant:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		return null
	var models: Array[HubModel] = []
	for entry in parsed:
		var model := from_entry(entry)
		if model != null:
			model.is_bvs = false
			models.append(model)
	return models

static func format_downloads(count: int) -> String:
	if count >= 1000000:
		return "%.1fM" % (count / 1000000.0)
	if count >= 1000:
		return "%.1fk" % (count / 1000.0)
	return str(count)
