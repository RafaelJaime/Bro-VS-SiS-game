extends Label

@export var timer: Timer

func _process(_delta: float) -> void:
	text = "%.0f" % timer.time_left
