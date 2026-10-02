class_name MenuBackground
extends Node2D
## The one menu backdrop (kitchen plus scrolling clouds). SceneManager owns a
## single instance below the current scene, so the clouds keep drifting across
## screen changes instead of restarting. It is hidden and paused during a match,
## which has its own layered backdrop.

## Shows it (and lets the clouds drift) or hides it and freezes the clouds. The
## ParallaxBackground is a CanvasLayer, so it needs its own visibility.
func set_active(active: bool) -> void:
	visible = active
	(get_node("ParallaxBackground") as ParallaxBackground).visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED

## How far the clouds have scrolled (grows while the background is active).
func cloud_offset() -> float:
	return (get_node("ParallaxBackground/ParallaxLayer") as ParallaxLayer).motion_offset.x
