class_name FighterKits
extends RefCounted

## Registry of the per-character kits: `FighterProfile` resources (`rafael_profile.tres`,
## `matilde_profile.tres`) resolved from the character's name. A character without a
## kit gets a fresh default profile and no error. Loaded kits are cached and handed out
## by reference: profiles are read-only at run time, so sharing them is safe.

const PATHS := {
	&"rafael": "res://game/player/profiles/rafael_profile.tres",
	&"matilde": "res://game/player/profiles/matilde_profile.tres",
}

static var _cache: Dictionary = {}

## The kit of `ui` (looked up by its lower-cased name); the default profile when the
## character is null or has no kit.
static func for_character(ui: CharacterUI) -> FighterProfile:
	if ui == null:
		return FighterProfile.new()
	var kit := _load(StringName(ui.name.to_lower()))
	return kit if kit != null else FighterProfile.new()

## The kit with `kit_id`, or the default profile for an unknown id.
static func by_id(kit_id: int) -> FighterProfile:
	for kit_name: StringName in PATHS:
		var kit := _load(kit_name)
		if kit != null and kit.kit_id == kit_id:
			return kit
	return FighterProfile.new()

## The ids of the shipped kits, ascending.
static func ids() -> PackedInt32Array:
	var found := PackedInt32Array()
	for kit_name: StringName in PATHS:
		var kit := _load(kit_name)
		if kit != null:
			found.append(kit.kit_id)
	found.sort()
	return found

## A uniformly random shipped kit (training randomizes the kit of each side).
static func random(rng: RandomNumberGenerator) -> FighterProfile:
	var all := ids()
	return by_id(all[rng.randi_range(0, all.size() - 1)])

static func _load(kit_name: StringName) -> FighterProfile:
	if not PATHS.has(kit_name):
		return null
	if not _cache.has(kit_name):
		_cache[kit_name] = load(String(PATHS[kit_name])) as FighterProfile
	return _cache[kit_name]
