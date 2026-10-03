extends RefCounted
class_name Sfx

## One-shot sound effect playback without needing a persistent
## AudioStreamPlayer node: spawns a temporary one under the scene tree root
## and frees it when playback finishes.
##
## Streams are loaded via load() at RUNTIME only (never preload()/ext_resource
## in a .tscn): these freesound assets have no .import files yet, same caveat
## as T0's food sprites (see odd/tasks/kitchen-food-fight.md).

const PUNCH := "res://assets/sounds/freesound/563356__nicholasdaryl__cartoonpunch.wav"
const EXPLOSION := "res://assets/sounds/freesound/431174__highpixel__fireball-explosion.wav"
const CLICK := "res://assets/sounds/button.mp3"

## Event -> [stream, pitch_min, pitch_max]. The game only owns three sounds, so
## every cue is one of them at its own pitch band; each play picks a random pitch
## inside the band, so repeats vary but events stay audibly distinct. Bands of
## the same source sound never overlap (the audit in tests/smoke/match_flow.gd
## enforces it).
const EVENTS := {
	# Cartoon punch: low thud for a block, then rising through the light cues.
	&"game": [PUNCH, 0.45, 0.55],
	&"block": [PUNCH, 0.62, 0.72],
	&"throw": [PUNCH, 0.80, 0.90],
	&"hit": [PUNCH, 0.96, 1.10],
	&"recovery": [PUNCH, 1.12, 1.20],
	&"pickup": [PUNCH, 1.22, 1.32],
	&"jump": [PUNCH, 1.42, 1.55],
	&"ledge": [PUNCH, 1.58, 1.65],
	&"double_jump": [PUNCH, 1.68, 1.80],
	# Explosion: a deep boom for a KO, the normal one for a heavy hit.
	&"ko": [EXPLOSION, 0.60, 0.72],
	# A bomb going off, between the KO boom and the heavy hit.
	&"bomb": [EXPLOSION, 0.78, 0.90],
	&"heavy_hit": [EXPLOSION, 0.96, 1.10],
	# The shield breaking: a bright crack above the heavy hit.
	&"shield_break": [EXPLOSION, 1.20, 1.32],
	# UI click: countdown ticks (the caller multiplies the pitch per digit) and GO.
	&"countdown": [CLICK, 0.95, 1.0],
	&"go": [CLICK, 1.55, 1.65],
}

## Plays a named cue from EVENTS with a random pitch inside its band. `pitch_mul`
## scales the picked pitch (the countdown rises with every digit). Silent in AI
## training: dozens of train.tscn Game rows run in parallel, so it is only noise.
static func play_event(event: StringName, requester: Node, pitch_mul: float = 1.0) -> void:
	if not EVENTS.has(event):
		push_warning("Sfx: unknown event " + String(event))
		return
	if is_training(requester):
		return
	play(EVENTS[event][0], requester, pick_pitch(event) * pitch_mul)

## A random pitch inside the event's band.
static func pick_pitch(event: StringName) -> float:
	var entry: Array = EVENTS[event]
	return GameRng.randf_range(entry[1], entry[2])

## True when `node` lives in a Game row that is running AI training.
static func is_training(node: Node) -> bool:
	var parent := node.get_parent() if node else null
	return parent != null and parent.get("training") == true

static func play(stream_path: String, requester: Node, pitch: float = 1.0) -> void:
	if requester == null or not is_instance_valid(requester):
		return
	var tree = requester.get_tree()
	if not tree:
		return
	var stream = load(stream_path)
	if not stream:
		push_warning("Sfx: could not load " + stream_path)
		return
	var player = AudioStreamPlayer.new()
	player.stream = stream
	player.pitch_scale = pitch
	player.finished.connect(player.queue_free)
	# Deferred: a cue fired from a _ready (the countdown's "3") would hit a root
	# that is still busy adding children. Autoplay starts it once it is in the tree.
	player.autoplay = true
	tree.root.add_child.call_deferred(player)
