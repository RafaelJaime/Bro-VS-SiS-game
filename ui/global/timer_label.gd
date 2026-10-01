extends Label

@export var timer: Timer

# Shows the time left while the match clock runs and the full match length while
# it is stopped (countdown), so the HUD never flashes a stale or zero value.
func _process(_delta: float) -> void:
	var seconds := timer.wait_time if timer.is_stopped() else timer.time_left
	text = "%.0f" % seconds
