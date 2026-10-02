class_name BvsSchema
extends RefCounted

## Registry of the observation/action schemas this build knows. A model declares
## `schema_version` in its bvs.json sidecar; only CURRENT_VERSION can be played.
## A new schema is a new file (bvs_schema_v3.gd) plus one entry here, and never
## edits an older version.

const CURRENT_VERSION := 2

## Version -> schema script. Only the test hooks below touch it at run time.
static var _registry := {2: BvsSchemaV2}

## The schema script for `version`, or null when the version is unsupported (never
## a default layout).
static func get_schema(version: int) -> Object:
	return _registry.get(version)

## Test-only: registers a stub schema (for the extensibility checks).
static func register_test_stub(version: int, schema: Object) -> void:
	_registry[version] = schema

## Test-only: removes a stub again. Version 2 can never be removed.
static func unregister_test_stub(version: int) -> void:
	if version != CURRENT_VERSION:
		_registry.erase(version)

## "" when the sidecar describes a model for the current schema, otherwise a short
## human reason (shown to the player). Checks schema_version, obs_dim, the action
## branches (names and sizes, in order) and action_repeat.
static func validate_sidecar(sidecar: Dictionary) -> String:
	for key in ["schema_version", "obs_dim", "action_branches", "action_repeat"]:
		if not sidecar.has(key):
			return "bvs.json is missing '%s'" % key
	var declared := _as_int(sidecar["schema_version"])
	if declared != CURRENT_VERSION:
		if declared < 0 or get_schema(declared) == null:
			return "Unsupported schema version %s" % str(sidecar["schema_version"])
		return "Trained for schema %d; this game uses schema %d" % [declared, CURRENT_VERSION]
	var schema := BvsSchemaV2
	var obs_dim := _as_int(sidecar["obs_dim"])
	if obs_dim != schema.OBS_DIM:
		return "This model expects %s inputs; this game provides %d" % [str(obs_dim if obs_dim >= 0 else sidecar["obs_dim"]), schema.OBS_DIM]
	var branches: Variant = sidecar["action_branches"]
	if not (branches is Array) or branches.size() != schema.BRANCHES.size():
		return "action_branches must list %d branches" % schema.BRANCHES.size()
	for i in schema.BRANCHES.size():
		var want: Dictionary = schema.BRANCHES[i]
		var got: Variant = branches[i]
		if not (got is Dictionary) or String(got.get("name", "")) != String(want["name"]):
			return "action_branches[%d] must be named %s" % [i, want["name"]]
		if _as_int(got.get("size", -1)) != int(want["size"]):
			return "action_branches[%d] (%s) must have size %d" % [i, want["name"], want["size"]]
	if _as_int(sidecar["action_repeat"]) != schema.ACTION_REPEAT:
		return "action_repeat must be %d" % schema.ACTION_REPEAT
	return ""

## JSON numbers arrive as floats; -1 for anything that is not a whole number.
static func _as_int(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_finite(value) and value == floorf(value):
		return int(value)
	return -1
