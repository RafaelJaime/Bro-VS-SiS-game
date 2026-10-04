class_name BvsSchema
extends RefCounted

## Registry of the observation/action schemas this build knows. A model declares
## `schema_version` in its bvs.json sidecar; only CURRENT_VERSION can be played from
## the picker and the model manager, while a model's own version selects its schema
## module and decoder at run time (PolicyController). A new schema is a new file
## (bvs_schema_vN.gd plus its decoder) and one entry in each table here, and never
## edits an older version.

## The playable schema (what the picker, the model manager and the bundled default
## accept). It flipped to 3 in the commit that bundled the retrained schema 3 model
## after every acceptance gate passed; schema 2 stays registered and frozen. Schema 4
## is registered (training and tools run it) but is not playable yet: it becomes
## current in the commit that bundles the gated schema 4 model.
const CURRENT_VERSION := 3

## Version -> schema script / action decoder script. Only the test hooks below
## touch them at run time (and never for the built-in versions).
static var _registry := {2: BvsSchemaV2, 3: BvsSchemaV3, 4: BvsSchemaV4}
static var _decoders := {2: BvsActionDecoderV2, 3: BvsActionDecoderV3, 4: BvsActionDecoderV4}

## The schema script for `version`, or null when the version is unsupported (never
## a default layout).
static func get_schema(version: int) -> Object:
	return _registry.get(version)

## A fresh action decoder for `version`, or null when the version has none (an
## unsupported version or a test stub).
static func new_decoder(version: int) -> RefCounted:
	var script: Variant = _decoders.get(version)
	if script == null:
		return null
	return (script as GDScript).new()

## The schema script of the playable version.
static func current() -> Object:
	return get_schema(CURRENT_VERSION)

## True for the versions this build ships (2, 3 and 4); stubs are never built-in.
static func is_builtin(version: int) -> bool:
	return _decoders.has(version)

## Test-only: registers a stub schema (for the extensibility checks). A built-in
## version is never replaced.
static func register_test_stub(version: int, schema: Object) -> void:
	if not is_builtin(version):
		_registry[version] = schema

## Test-only: removes a stub again. A built-in version can never be removed.
static func unregister_test_stub(version: int) -> void:
	if not is_builtin(version):
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
	return validate_sidecar_for(sidecar, CURRENT_VERSION)

## Like validate_sidecar, but against the registered schema `version` instead of the
## playable one: the structural checks only (obs_dim, branches, action_repeat, and
## that the declared schema_version is `version`). Used by tools that run a model of
## a registered schema other than the current one (training, evaluation, harness).
static func validate_sidecar_for(sidecar: Dictionary, version: int) -> String:
	var schema := get_schema(version)
	if schema == null:
		return "Unsupported schema version %d" % version
	for key in ["schema_version", "obs_dim", "action_branches", "action_repeat"]:
		if not sidecar.has(key):
			return "bvs.json is missing '%s'" % key
	if _as_int(sidecar["schema_version"]) != version:
		return "Trained for schema %s; expected schema %d" % [str(sidecar["schema_version"]), version]
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
