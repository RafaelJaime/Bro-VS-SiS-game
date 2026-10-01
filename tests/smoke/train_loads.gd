extends SceneTree
## (g) train.tscn loads and runs without script errors. The Sync node is removed
## because it would try to reach a training server; everything else is real.
## run_all.sh also fails this script on any SCRIPT ERROR in the engine output.

const Smoke := preload("res://tests/smoke/smoke_util.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	var train: Node = load("res://train.tscn").instantiate()
	var sync := train.get_node_or_null("Sync")
	if sync:
		train.remove_child(sync)
		sync.free()
	root.add_child(train)
	await s.frames(120)

	var games: Array = []
	for row in train.get_children():
		for child in row.get_children():
			if child.has_method("get_state_snapshot"):
				games.append(child)
	s.check("train.tscn holds 25 Game instances", games.size() == 25, "games=%d" % games.size())

	var all_training := true
	var no_backdrop := true
	var standing := 0
	for game in games:
		all_training = all_training and game.training
		no_backdrop = no_backdrop and game.get_node_or_null("Backdrop") == null
		for fighter_name in ["Fighter1", "Fighter2"]:
			if game.get_node(fighter_name).is_on_floor():
				standing += 1
	var running := true
	for game in games:
		running = running and game.phase == Game.Phase.PLAYING and not game.timer.is_stopped() and not game.get_node("UI/CountdownLabel").visible
	s.check("every Game is in training mode", all_training)
	s.check("training rows start at once: no countdown, timer running", running)
	s.check("training games free the backdrop", no_backdrop)
	s.check("all 50 fighters stand on their own floor", standing == 50, "standing=%d" % standing)

	var xs := {}
	for game in games:
		xs[snappedf(game.global_position.x, 1.0)] = true
	var columns := xs.keys()
	columns.sort()
	var spaced := columns.size() == 5
	for i in range(1, columns.size()):
		spaced = spaced and is_equal_approx(columns[i] - columns[i - 1], 1400.0)
	s.check("games sit on 5 columns spaced 1400 apart", spaced, "columns=%s" % [columns])
	s.finish()
