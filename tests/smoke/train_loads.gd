extends SceneTree
## (g) train.tscn loads and runs without script errors. The Sync node is removed
## because it would try to reach a training server; everything else is real. The
## arena is built at run time by TrainArena (rows, opponent kinds, spacing), the
## training episode ends with `done` on a defeat and on a timeout, and the reward
## tracker reports damage, stock, win and loss terms. run_all.sh also fails this
## script on any SCRIPT ERROR in the engine output.

const Smoke := preload("res://tests/smoke/smoke_util.gd")

func _initialize() -> void:
	_run()

func _agent_of(game: Game) -> Fighter:
	for fighter_name in ["Fighter1", "Fighter2"]:
		var fighter: Fighter = game.get_node(fighter_name)
		if fighter.ai_controller_2d.control_mode == AIController2D.ControlModes.TRAINING:
			return fighter
	return null

func _agent_count(game: Game) -> int:
	var count := 0
	for fighter_name in ["Fighter1", "Fighter2"]:
		if game.get_node(fighter_name).ai_controller_2d.control_mode == AIController2D.ControlModes.TRAINING:
			count += 1
	return count

func _run() -> void:
	var s := Smoke.new(self)
	var train: Node = load("res://train.tscn").instantiate()
	var sync := train.get_node_or_null("Sync")
	if sync:
		train.remove_child(sync)
		sync.free()
	root.add_child(train)
	await s.frames(120)

	var arena := train as TrainArena
	s.check("the Train root runs the TrainArena script", arena != null)
	var games: Array = []
	for child in train.get_children():
		if child.has_method("get_state_snapshot"):
			games.append(child)
	s.check("the default arena builds 8 Game rows", games.size() == 8 and arena.games.size() == 8, "games=%d" % games.size())
	s.check("no hand-placed Row nodes remain", train.get_node_or_null("Row") == null and train.get_node_or_null("Camera2D") != null and train.get_node_or_null("CanvasLayer/Label") != null)
	s.check("the default arena has no errors", arena.errors.is_empty(), str(arena.errors))

	var all_training := true
	var no_backdrop := true
	var standing := 0
	var running := true
	for game: Game in games:
		all_training = all_training and game.training
		no_backdrop = no_backdrop and game.get_node_or_null("Backdrop") == null and game.get_node_or_null("BackdropExtension") == null
		# Only self-play rows stay calm: the scripted CPUs already walk, jump and punch.
		if _agent_count(game) == 2:
			for fighter_name in ["Fighter1", "Fighter2"]:
				if game.get_node(fighter_name).is_on_floor():
					standing += 1
		running = running and game.phase == Game.Phase.PLAYING and not game.timer.is_stopped() and not game.get_node("UI/CountdownLabel").visible
	s.check("every Game is in training mode", all_training)
	s.check("training rows start at once: no countdown, timer running", running)
	s.check("training games free the backdrop", no_backdrop)
	s.check("the 4 idle fighters of the self-play rows stand on their own floor", standing == 4, "standing=%d" % standing)

	# Opponent kinds: 6 scripted CPU Easy rows and 2 self-play rows by default.
	var agents := 0
	var scripted := 0
	var policy_driven := 0
	var cpu_rows := 0
	var self_rows := 0
	for game: Game in games:
		var row_agents := 0
		var row_scripted := 0
		for fighter_name in ["Fighter1", "Fighter2"]:
			var fighter: Fighter = game.get_node(fighter_name)
			if fighter.ai_controller_2d.control_mode == AIController2D.ControlModes.TRAINING:
				row_agents += 1
				if fighter.controller != null and fighter.controller.kind_name() == "policy":
					policy_driven += 1
			elif fighter.controller != null and fighter.controller.kind_name() == "cpu" and fighter.ai_controller_2d.control_mode == AIController2D.ControlModes.HUMAN:
				row_scripted += 1
		agents += row_agents
		scripted += row_scripted
		cpu_rows += 1 if (row_agents == 1 and row_scripted == 1) else 0
		self_rows += 1 if row_agents == 2 else 0
	s.check("6 rows hold one agent and one scripted CPU, 2 rows are self-play", cpu_rows == 6 and self_rows == 2, "cpu=%d self=%d" % [cpu_rows, self_rows])
	s.check("10 agents are policy-driven (no keyboard) and 6 fighters are scripted", agents == 10 and policy_driven == 10 and scripted == 6, "agents=%d policy=%d scripted=%d" % [agents, policy_driven, scripted])
	var both_sides := {}
	for row: Dictionary in arena.rows:
		if row["opponent"] != "self":
			both_sides[row["agent_side"]] = true
	s.check("the agent alternates between Fighter1 and Fighter2 across rows", both_sides.size() == 2)

	# Spacing: one constant pitch, larger than a blast zone, so no body, area or
	# projectile of one row can reach another.
	var offsets: Array[Vector2] = []
	for game: Game in games:
		offsets.append(game.global_position)
	var constant := true
	var pitch: Vector2 = offsets[1] - offsets[0]
	for i in range(1, offsets.size()):
		constant = constant and (offsets[i] - offsets[i - 1]).is_equal_approx(pitch)
	var sample_game: Game = games[0]
	var blast := Vector2(sample_game.blast_right - sample_game.blast_left, sample_game.blast_bottom - sample_game.blast_top)
	s.check("consecutive rows differ by one constant spacing", constant, "pitch=%s" % pitch)
	s.check("the spacing clears the blast zone (1320 x 1210)", absf(pitch.x) >= blast.x or absf(pitch.y) >= blast.y, "pitch=%s blast=%s" % [pitch, blast])
	s.check("the grid pitch is at least the blast zone on both axes", TrainArena.PITCH.x >= blast.x and TrainArena.PITCH.y >= blast.y)

	# Ledges exist in training, using the default ledge depth.
	var ledges: Array = sample_game.get_ledges()
	s.check("training rows have both ledges at the default depth", ledges.size() == 2 and is_equal_approx(ledges[0]["bottom"] - ledges[0]["top"], sample_game.ledge_depth), str(ledges))
	s.check("the training snapshot reports the ledges and the stage edges", sample_game.get_state_snapshot()["ledges"].size() == 2 and sample_game.get_state_snapshot()["stage"].has("left"))

	# Observations come from the schema and are the same through the controller.
	var probe: Game = games[6] # a self-play row: nobody attacks the agent
	var probe_agent := _agent_of(probe)
	var probe_index := 1 if probe_agent == probe.fighter_2 else 0
	var via_controller: Array = probe_agent.ai_controller_2d.get_obs()["obs"]
	var via_schema := BvsSchemaV2.build_obs(probe.get_state_snapshot(), probe_index)
	var same_obs := via_controller.size() == via_schema.size() and via_schema.size() == 102
	for i in via_schema.size():
		same_obs = same_obs and is_equal_approx(float(via_controller[i]), via_schema[i])
	s.check("the AI controller observation equals BvsSchemaV2.build_obs for the same fighter", same_obs)
	var space: Dictionary = probe_agent.ai_controller_2d.get_action_space()
	s.check("the AI controller action space is the schema's", space == BvsSchemaV2.action_space() and probe_agent.ai_controller_2d.get_obs_space()["obs"]["size"] == [102])

	# set_action stores the branch indices and bumps the sequence.
	var ai := probe_agent.ai_controller_2d as PlayerAIController
	var seq_before := ai.action_seq
	ai.set_action({"a0_move": 2, "a1_vertical": 0, "a2_jump": 0, "a3_attack": 0, "a4_special": 0, "a5_throw": 0, "a6_block": 0, "a7_dash": 0})
	s.check("set_action keeps the indices and bumps the sequence", ai.latest_action == PackedInt32Array([2, 0, 0, 0, 0, 0, 0, 0]) and ai.action_seq == seq_before + 1)
	var start_x := probe_agent.position.x
	await s.frames(8)
	s.check("the policy controller walks the agent right on a move-right decision", probe_agent.position.x > start_x + 5.0, "dx=%.1f" % (probe_agent.position.x - start_x))
	ai.set_action({"a0_move": 1, "a1_vertical": 0, "a2_jump": 0, "a3_attack": 0, "a4_special": 0, "a5_throw": 0, "a6_block": 0, "a7_dash": 0})

	# Per-decision terms: time, approach (potential-based) and off-stage, read when Sync asks for the reward.
	var probe_tracker := ai.reward_tracker
	var probe_foe: Fighter = probe_agent.enemy
	ai.get_reward()
	s.check("every decision costs the time penalty", is_equal_approx(probe_tracker.totals["time"], -0.001), str(probe_tracker.totals))
	var toward := signf(probe_foe.position.x - probe_agent.position.x)
	probe_agent.position.x += 100.0 * toward
	ai.get_reward()
	s.check("closing 100 px earns the approach term (0.02 x 100 / 400)", is_equal_approx(probe_tracker.totals["approach"], 0.005), str(probe_tracker.totals["approach"]))
	probe_agent.position.x -= 100.0 * toward
	ai.get_reward()
	s.check("backing away gives the same amount back (potential-based)", is_equal_approx(probe_tracker.totals["approach"], 0.0), str(probe_tracker.totals["approach"]))
	probe_agent.position = Vector2(sample_game.get_state_snapshot()["stage"]["left"] - 120.0, 100.0)
	await s.frames(3)
	ai.get_reward()
	s.check("an airborne fighter past the table edge pays the off-stage term", is_equal_approx(probe_tracker.totals["off_stage"], -0.002), str(probe_tracker.totals["off_stage"]))
	probe_agent.position = probe_agent.initial_position
	await s.frames(30)
	var idle_policy := PolicyController.new()
	idle_policy.bind(games[0].get_node("Fighter1") if _agent_of(games[0]) != games[0].get_node("Fighter1") else games[0].get_node("Fighter2"))
	var idle_intent := idle_policy.sample(0.016)
	s.check("a policy controller with no training source stays neutral", idle_intent.move_x == 0.0 and not idle_intent.attack_pressed and not idle_intent.jump_pressed)

	# Damage terms come from the damage signals; a reset is ignored.
	var duel: Game = games[7] # a self-play row: nobody else touches the damage
	var duel_agent := _agent_of(duel)
	var duel_foe: Fighter = duel_agent.enemy
	var duel_ai := duel_agent.ai_controller_2d as PlayerAIController
	var tracker := duel_ai.reward_tracker
	s.check("a training agent owns a reward tracker", tracker != null)
	var logged: Array[Dictionary] = []
	tracker.episode_logged.connect(func(record: Dictionary) -> void: logged.append(record))
	var ended: Array = []
	duel.training_episode_ended.connect(func(winner: Fighter) -> void: ended.append(winner))
	duel_foe.add_damage(10.0)
	duel_agent.add_damage(5.0)
	s.check("damage dealt and taken are rewarded per percent", is_equal_approx(tracker.totals["damage_dealt"], 0.1) and is_equal_approx(tracker.totals["damage_taken"], -0.05), str(tracker.totals))

	# Elimination ends the episode: the agent knocks the opponent out of its last stock.
	duel_foe.stocks = 1
	duel_foe.position = Vector2(duel.blast_right + 500.0, 0.0)
	await s.frames(2)
	s.check("the defeat ended the episode once, with the agent as winner", ended.size() == 1 and ended[0] == duel_agent, str(ended))
	s.check("done is set on both fighters of the row", duel_agent.ai_controller_2d.done and duel_foe.ai_controller_2d.done)
	s.check("the tracker logged the episode with KO, stock and win terms", logged.size() == 1 and logged[0]["outcome"] == "win" and logged[0]["terms"]["ko_given"] == 1.0 and logged[0]["terms"]["win"] == 3.0, str(logged))
	s.check("the episode record carries length, winner and every term", logged.size() == 1 and logged[0].has("length") and logged[0].has("winner") and logged[0]["terms"].has("stock_lost") and logged[0]["terms"].has("time"))
	s.check("the agent's reward holds the KO and win terms (consumed by Sync later)", duel_ai.reward > 3.9, "reward=%.3f" % duel_ai.reward)
	var reward_at_end := duel_ai.reward
	await s.frames(4)
	s.check("the row resets: stocks refilled and nobody stays in Defeated", duel_foe.stocks == Fighter.MAX_STOCKS and duel_agent.stocks == Fighter.MAX_STOCKS and s.state_of(duel_foe) != "Defeated" and s.state_of(duel_agent) != "Defeated", "foe=%s" % s.state_of(duel_foe))
	s.check("the defeated fighter is back on its start spot", duel_foe.position.distance_to(duel_foe.initial_position) < 200.0)
	s.check("the reset did not reward the refilled stocks or the cleared damage", is_equal_approx(duel_ai.reward, reward_at_end) and tracker.totals["damage_dealt"] == 0.0 and tracker.totals["ko_given"] == 0.0)

	# The agent being knocked out is a loss.
	var loser_game: Game = games[4]
	var loser := _agent_of(loser_game)
	var loser_tracker := (loser.ai_controller_2d as PlayerAIController).reward_tracker
	var loser_logged: Array[Dictionary] = []
	loser_tracker.episode_logged.connect(func(record: Dictionary) -> void: loser_logged.append(record))
	loser.stocks = 1
	loser.position = Vector2(loser_game.blast_left - 500.0, 0.0)
	await s.frames(2)
	s.check("losing the last stock logs a loss with the stock terms", loser_logged.size() == 1 and loser_logged[0]["outcome"] == "loss" and loser_logged[0]["terms"]["loss"] == -3.0 and loser_logged[0]["terms"]["stock_lost"] == -0.5 and loser_logged[0]["terms"]["ko_taken"] == -0.5, str(loser_logged))
	await s.frames(4)

	# A timeout is one `done` as well.
	var timed: Game = games[1]
	var timed_ended: Array = []
	timed.training_episode_ended.connect(func(winner: Fighter) -> void: timed_ended.append(winner))
	var timed_agent := _agent_of(timed)
	timed.timer.start(0.05)
	timed.timer.wait_time = 99.0 # start(t) sets wait_time; the restart must not stay at 0.05 s
	await s.sim(0.3)
	s.check("a timeout ended the episode exactly once", timed_ended.size() == 1, str(timed_ended))
	s.check("done was sent on the timeout", timed_agent.ai_controller_2d.done)
	s.check("the timer restarted for the next episode", not timed.timer.is_stopped())

	# BVS_TRAIN_CONFIG: rows, seeds and reward weights are data.
	var config_path := "user://smoke_train_config.json"
	var config_file := FileAccess.open(config_path, FileAccess.WRITE)
	config_file.store_string(JSON.stringify({"rows": [{"opponent": "cpu_normal", "seed": 5}, {"opponent": "cpu_hard", "seed": 6}, {"opponent": "self"}], "reward": {"win": 7.0}}))
	config_file.close()
	OS.set_environment("BVS_TRAIN_CONFIG", ProjectSettings.globalize_path(config_path))
	var custom := TrainArena.new()
	custom.name = "CustomTrain"
	custom.position = Vector2(0.0, 30000.0) # far from the default rows' physics
	root.add_child(custom)
	await s.frames(3)
	OS.unset_environment("BVS_TRAIN_CONFIG")
	s.check("BVS_TRAIN_CONFIG selects the rows", custom.games.size() == 3 and custom.errors.is_empty(), str(custom.errors))
	var normal_fighter: Fighter = null
	for fighter_name in ["Fighter1", "Fighter2"]:
		var candidate: Fighter = (custom.games[0] as Game).get_node(fighter_name)
		if candidate.ai_controller_2d.control_mode != AIController2D.ControlModes.TRAINING:
			normal_fighter = candidate
	var normal_bot := normal_fighter.controller as ScriptedController if normal_fighter != null else null
	var hard_fighter: Fighter = null
	for fighter_name in ["Fighter1", "Fighter2"]:
		var candidate: Fighter = (custom.games[1] as Game).get_node(fighter_name)
		if candidate.ai_controller_2d.control_mode != AIController2D.ControlModes.TRAINING:
			hard_fighter = candidate
	var hard_bot := hard_fighter.controller as ScriptedController if hard_fighter != null else null
	s.check("cpu_normal and cpu_hard rows get scripted CPUs of those levels", normal_bot != null and hard_bot != null and is_equal_approx(normal_bot.difficulty.decision_interval, CpuDifficulty.preset(CpuDifficulty.Level.NORMAL).decision_interval) and is_equal_approx(hard_bot.difficulty.decision_interval, CpuDifficulty.preset(CpuDifficulty.Level.HARD).decision_interval))
	var custom_agent := _agent_of(custom.games[0])
	s.check("the reward block of the config overrides the defaults", (custom_agent.ai_controller_2d as PlayerAIController).reward_tracker.config.win == 7.0 and (custom_agent.ai_controller_2d as PlayerAIController).reward_tracker.config.loss == -3.0)
	custom.queue_free()
	await s.frames(2)

	# An unknown opponent kind is an error naming the row, never a silent CPU Easy.
	var broken := TrainArena.new()
	broken.name = "BrokenTrain"
	broken.position = Vector2(0.0, 60000.0)
	broken.config = {"rows": [{"opponent": "cpu_easy"}, {"opponent": "cpu_impossible"}, {"opponent": "snapshot:/nowhere.onnx"}]}
	root.add_child(broken)
	await s.frames(3)
	s.check("an unknown opponent kind names its row and kind", broken.errors.size() >= 1 and broken.errors[0].contains("row 1") and broken.errors[0].contains("cpu_impossible"), str(broken.errors))
	s.check("the snapshot kind reports that it is not available yet, naming its row", broken.errors.size() == 2 and broken.errors[1].contains("row 2") and broken.errors[1].contains("snapshot"), str(broken.errors))
	s.check("the invalid rows are not built, so no CPU Easy was substituted", broken.games.size() == 1)
	broken.queue_free()
	await s.frames(2)
	s.finish()
