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

static func play(stream_path: String, requester: Node) -> void:
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
	player.finished.connect(player.queue_free)
	tree.root.add_child(player)
	player.play()
