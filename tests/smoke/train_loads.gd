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

## The PolicyController of the snapshot opponent of a row (the non-agent fighter).
func _policy_of(game: Game) -> PolicyController:
	var agent := _agent_of(game)
	var foe: Fighter = game.fighter_2 if agent == game.fighter_1 else game.fighter_1
	return foe.controller as PolicyController

func _agent_count(game: Game) -> int:
	var count := 0
	for fighter_name in ["Fighter1", "Fighter2"]:
		if game.get_node(fighter_name).ai_controller_2d.control_mode == AIController2D.ControlModes.TRAINING:
			count += 1
	return count

func _run() -> void:
	var s := Smoke.new(self)
	var train: Node = load("res://game/ai/training/train.tscn").instantiate()
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
	var current_schema: Object = BvsSchema.current()
	var via_schema: Array = current_schema.build_obs(probe.get_state_snapshot(), probe_index)
	var same_obs: bool = via_controller.size() == via_schema.size() and via_schema.size() == current_schema.OBS_DIM
	for i in via_schema.size():
		same_obs = same_obs and is_equal_approx(float(via_controller[i]), via_schema[i])
	s.check("the AI controller observation equals the current schema build_obs for the same fighter", same_obs)
	var space: Dictionary = probe_agent.ai_controller_2d.get_action_space()
	s.check("the AI controller action space is the schema's", space == current_schema.action_space() and probe_agent.ai_controller_2d.get_obs_space()["obs"]["size"] == [current_schema.OBS_DIM])

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
	# A tied expiry now enters sudden death by default; this row turns it off to keep
	# checking the plain timeout (the draw) path.
	timed.training_sudden_death = false
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
	broken.config = {"rows": [{"opponent": "cpu_easy"}, {"opponent": "cpu_impossible"}, {"opponent": "snapshot:/nowhere.onnx"}, {"opponent": "snapshot"}, {"opponent": "snapshot", "model": "res://tests/fixtures/onnx/ops/gemm_no_c.onnx"}]}
	root.add_child(broken)
	await s.frames(3)
	s.check("an unknown opponent kind names its row and kind", broken.errors.size() >= 1 and broken.errors[0].contains("row 1") and broken.errors[0].contains("cpu_impossible"), str(broken.errors))
	s.check("a snapshot whose file is missing names its row and path", broken.errors.size() >= 2 and broken.errors[1].contains("row 2") and broken.errors[1].contains("/nowhere.onnx"), str(broken.errors))
	s.check("a snapshot row without a model path says so", broken.errors.size() >= 3 and broken.errors[2].contains("row 3") and broken.errors[2].contains("model path"), str(broken.errors))
	s.check("a snapshot that does not fit the current schema is rejected, naming its row", broken.errors.size() == 4 and broken.errors[3].contains("row 4") and broken.errors[3].contains("schema %d" % BvsSchema.CURRENT_VERSION), str(broken.errors))
	s.check("the invalid rows are not built, so no CPU Easy was substituted", broken.games.size() == 1)
	broken.queue_free()
	await s.frames(2)

	# A snapshot row: the opponent is a PolicyController running the frozen model.
	var snapshot_path := "res://tests/fixtures/onnx/random_policy_v3.onnx"
	var snapshot_arena := TrainArena.new()
	snapshot_arena.name = "SnapshotTrain"
	snapshot_arena.position = Vector2(0.0, 80000.0)
	snapshot_arena.config = {"rows": [{"opponent": "snapshot", "model": snapshot_path}, {"opponent": "snapshot:" + snapshot_path}, {"opponent": "cpu_easy"}]}
	root.add_child(snapshot_arena)
	await s.frames(30)
	s.check("snapshot rows are built from `model` and from `snapshot:<path>` with no errors", snapshot_arena.games.size() == 3 and snapshot_arena.errors.is_empty(), str(snapshot_arena.errors))
	for row_index in 2:
		var row_game: Game = snapshot_arena.games[row_index]
		var row_agent := _agent_of(row_game)
		var foe: Fighter = row_game.fighter_2 if row_agent == row_game.fighter_1 else row_game.fighter_1
		var foe_policy := foe.controller as PolicyController
		s.check("snapshot row %d: the opponent is a PolicyController with the frozen model" % row_index, foe_policy != null and foe_policy.model != null and foe_policy.model.validate(BvsSchema.current()) == "" and foe.ai_controller_2d.control_mode == AIController2D.ControlModes.HUMAN, str(foe.controller))
		s.check("snapshot row %d: the model decides every 4 frames and does not fail" % row_index, foe_policy != null and foe_policy.decisions >= 5 and foe_policy.error == "", "decisions=%d" % (foe_policy.decisions if foe_policy != null else -1))
		s.check("snapshot row %d: the other fighter is the training agent" % row_index, row_agent != null and row_agent.ai_controller_2d.control_mode == AIController2D.ControlModes.TRAINING)
	s.check("two rows naming the same snapshot share one loaded model", _policy_of(snapshot_arena.games[0]).model == _policy_of(snapshot_arena.games[1]).model)
	snapshot_arena.queue_free()
	await s.frames(2)

	await _sudden_death_episodes(s)
	await _combat_rewards(s)
	await _schema_3_rows(s)
	await _sudden_death_start_rows(s)
	s.finish()

## A TrainArena built from `config` far away from the other rows.
func _arena(s: RefCounted, arena_name: String, y: float, config: Dictionary) -> TrainArena:
	var arena := TrainArena.new()
	arena.name = arena_name
	arena.position = Vector2(0.0, y)
	arena.config = config
	root.add_child(arena)
	await s.frames(3)
	return arena

func _fighters_of(game: Game) -> Array[Fighter]:
	return [game.fighter_1, game.fighter_2]

# ------------------------------------------------- tied expiry and the SD cap

func _sudden_death_episodes(s: RefCounted) -> void:
	var arena := await _arena(s, "SdArena", 100000.0, {"rows": [{"opponent": "self"}], "match": {"sudden_death": true, "sd_safety_cap": 0.5}})
	var game: Game = arena.games[0]
	var agent: Fighter = game.fighter_1
	var tracker := (agent.ai_controller_2d as PlayerAIController).reward_tracker
	var logged: Array[Dictionary] = []
	tracker.episode_logged.connect(func(record: Dictionary) -> void: logged.append(record))
	var ended: Array = []
	game.training_episode_ended.connect(func(winner: Fighter) -> void: ended.append(winner))
	s.check("the match block reaches the row: sudden death on a tie, the safety cap in seconds", game.training_sudden_death and not game.training_start_in_sudden_death and is_equal_approx(game.hazards.training_cap, 0.5), "cap=%s" % str(game.hazards.training_cap))
	await s.frames(30)

	# A tied timer expiry enters sudden death and sends no `done`.
	game.timer.start(0.05)
	game.timer.wait_time = 99.0
	await s.sim(0.3)
	s.check("a tied timer expiry enters sudden death", game.phase == Game.Phase.SUDDEN_DEATH and game.hazards.is_active(), "phase=%d" % game.phase)
	s.check("the expiry sent no done and ended no episode", ended.is_empty() and not agent.ai_controller_2d.done and logged.is_empty(), str(ended))
	s.check("sudden death put both fighters at 300% and one stock", is_equal_approx(game.fighter_1.damage_percent, game.sudden_death_damage) and game.fighter_1.stocks == 1 and game.fighter_2.stocks == 1)

	# The safety cap (0.5 s here) ends the episode as a truncated draw.
	await s.sim(0.6)
	s.check("the cap ended the episode once, with no winner", ended.size() == 1 and ended[0] == null, str(ended))
	s.check("the end reason is sd_cap", game.last_episode_end_reason == &"sd_cap", str(game.last_episode_end_reason))
	s.check("done was sent on the cap", agent.ai_controller_2d.done)
	s.check("the record is a truncated draw", logged.size() == 1 and logged[0]["outcome"] == "draw" and logged[0].get("truncated", false) == true and logged[0]["winner"] == "none", str(logged))
	var terms: Dictionary = logged[0]["terms"] if logged.size() == 1 else {}
	s.check("a truncated draw earns no win, loss or timeout reward", terms.get("win", 1.0) == 0.0 and terms.get("loss", 1.0) == 0.0 and terms.get("timeout", 1.0) == 0.0, str(terms))
	s.check("the stage is clean for the next episode: back to playing, no hazards, timer running", game.phase == Game.Phase.PLAYING and not game.hazards.is_active() and game.hazards.alive_count() == 0 and not game.timer.is_stopped())
	await s.frames(4)

	# A KO episode is not truncated.
	game.fighter_2.stocks = 1
	game.fighter_2.position = Vector2(game.blast_right + 500.0, 0.0)
	await s.frames(3)
	s.check("an ordinary KO keeps the reason ko and is not flagged truncated", game.last_episode_end_reason == &"ko" and logged.size() == 2 and logged[1]["outcome"] == "win" and not logged[1].has("truncated"), str(logged.slice(1)))
	arena.queue_free()
	await s.frames(2)

	# With sudden death turned off a tied expiry is a plain draw (reason timeout).
	var off := await _arena(s, "SdOffArena", 110000.0, {"rows": [{"opponent": "self"}], "match": {"sudden_death": false}})
	var off_game: Game = off.games[0]
	var off_ended: Array = []
	off_game.training_episode_ended.connect(func(winner: Fighter) -> void: off_ended.append(winner))
	off_game.timer.start(0.05)
	off_game.timer.wait_time = 99.0
	await s.sim(0.3)
	s.check("match.sudden_death = false: a tie ends the episode as a timeout draw", not off_game.training_sudden_death and off_ended.size() == 1 and off_game.last_episode_end_reason == &"timeout" and off_game.phase == Game.Phase.PLAYING, str(off_game.last_episode_end_reason))
	off.queue_free()
	await s.frames(2)

# --------------------------------------------------------- combat reward terms

func _combat_rewards(s: RefCounted) -> void:
	var arena := await _arena(s, "CombatRewards", 120000.0, {"rows": [{"opponent": "self"}], "reward": {"pickup_cap": 3, "shield_hold_threshold": 1.0}})
	var game: Game = arena.games[0]
	game.food_spawner.stop()
	var me: Fighter = game.fighter_1
	var foe: Fighter = game.fighter_2
	var tracker := (me.ai_controller_2d as PlayerAIController).reward_tracker
	var foe_tracker := (foe.ai_controller_2d as PlayerAIController).reward_tracker
	tracker.print_log = false
	foe_tracker.print_log = false
	var config := tracker.config
	s.check("the reward block accepts the new terms and the non-term parameters", config.pickup == 0.05 and config.food_hit == 0.15 and config.shield_break_dealt == 0.4 and config.shield_break_taken == -0.4 and config.shield_hold == -0.003 and config.pickup_cap == 3 and is_equal_approx(config.shield_hold_threshold, 1.0))
	s.check("every combat term is logged per episode", tracker.totals.has("pickup") and tracker.totals.has("food_hit") and tracker.totals.has("shield_break_dealt") and tracker.totals.has("shield_break_taken") and tracker.totals.has("shield_hold") and not tracker.totals.has("pickup_cap"))
	await s.frames(60)

	# Pickups, capped per episode.
	for i in 5:
		me.food_picked_up.emit("pizza")
	s.check("a pickup earns 0.05, at most pickup_cap (3) per episode", is_equal_approx(tracker.totals["pickup"], 0.15), str(tracker.totals["pickup"]))
	s.check("the opponent's pickups are not mine", foe_tracker.totals["pickup"] == 0.0)

	# A thrown food of mine that reaches the opponent.
	var before: float = tracker.totals["food_hit"]
	Combat.resolve(Hit.food(me, "pizza", me.global_position), foe)
	s.check("my food reaching the opponent earns food_hit", is_equal_approx(tracker.totals["food_hit"], before + 0.15), str(tracker.totals["food_hit"]))
	s.check("the victim's tracker does not earn it", foe_tracker.totals["food_hit"] == 0.0)
	await s.frames(40)
	var punch_before: float = tracker.totals["food_hit"]
	Combat.resolve(Hit.punch(me, 8.0, Vector2(220.0, -120.0)), foe)
	s.check("a punch is not a food hit", is_equal_approx(tracker.totals["food_hit"], punch_before))
	foe.is_invulnerable = true
	var ignored_before: float = tracker.totals["food_hit"]
	var ignored := Combat.resolve(Hit.food(me, "pizza", me.global_position), foe)
	foe.is_invulnerable = false
	s.check("an ignored food hit earns nothing", ignored == Combat.Outcome.IGNORED and is_equal_approx(tracker.totals["food_hit"], ignored_before))

	# Shield breaks: dealt only by my hit, taken always.
	var dealt_before: float = tracker.totals["shield_break_dealt"]
	foe.break_shield(Hit.punch(me, 8.0, Vector2.ZERO))
	s.check("breaking the opponent's shield with my hit earns shield_break_dealt", is_equal_approx(tracker.totals["shield_break_dealt"], dealt_before + 0.4))
	s.check("the opponent's tracker pays shield_break_taken for it", is_equal_approx(foe_tracker.totals["shield_break_taken"], -0.4))
	var taken_before: float = tracker.totals["shield_break_taken"]
	me.break_shield(null)
	s.check("my own shield breaking (hold drain, no cause) pays shield_break_taken", is_equal_approx(tracker.totals["shield_break_taken"], taken_before - 0.4) and is_equal_approx(tracker.totals["shield_break_dealt"], dealt_before + 0.4))
	var no_credit: float = foe_tracker.totals["shield_break_dealt"]
	me.break_shield(Hit.bomb(Vector2.ZERO, 12.0, Vector2.ZERO))
	s.check("a bomb break credits nobody", is_equal_approx(foe_tracker.totals["shield_break_dealt"], no_credit))
	await s.sim(2.5)

	# Shield hold: only past the threshold, per decision.
	me.shield.held_ticks = 0
	var hold_before: float = tracker.totals["shield_hold"]
	tracker.on_decision()
	s.check("a short hold costs nothing", is_equal_approx(tracker.totals["shield_hold"], hold_before))
	me.shield.held_ticks = 60
	tracker.on_decision()
	s.check("exactly at the threshold still costs nothing", is_equal_approx(tracker.totals["shield_hold"], hold_before))
	me.shield.held_ticks = 61
	tracker.on_decision()
	s.check("a hold past the threshold pays shield_hold per decision", is_equal_approx(tracker.totals["shield_hold"], hold_before - 0.003), str(tracker.totals["shield_hold"]))
	me.shield.held_ticks = 0

	# A new episode starts from zero (pickup cap included).
	var ended: Array = []
	game.training_episode_ended.connect(func(winner: Fighter) -> void: ended.append(winner))
	foe.stocks = 1
	foe.position = Vector2(game.blast_right + 500.0, 0.0)
	await s.frames(4)
	s.check("the episode ended and every term restarted at zero", ended.size() == 1 and tracker.totals["pickup"] == 0.0 and tracker.totals["food_hit"] == 0.0 and tracker.totals["shield_break_dealt"] == 0.0)
	me.food_picked_up.emit("pizza")
	s.check("the pickup allowance is back after the episode", is_equal_approx(tracker.totals["pickup"], 0.05))

	# The reward block rejects an unknown key by name and still accepts the parameters.
	var parsed := RewardConfig.from_dict({"pickup": 0.5, "pickup_cap": 7, "shield_hold_threshold": 2.5})
	s.check("from_dict reads terms and parameters", parsed.pickup == 0.5 and parsed.pickup_cap == 7 and is_equal_approx(parsed.shield_hold_threshold, 2.5))
	arena.queue_free()
	await s.frames(2)

# ------------------------------------------------------------ schema 3 rows

func _schema_3_rows(s: RefCounted) -> void:
	var v3_model := "res://tests/fixtures/onnx/random_policy_v3.onnx"
	var arena := await _arena(s, "Schema3", 130000.0, {
		"schema_version": 3,
		"rows": [{"opponent": "self"}, {"opponent": "cpu_easy", "seed": 3}, {"opponent": "snapshot", "model": v3_model}],
	})
	s.check("schema_version 3 builds every row with no error", arena.schema_version == 3 and arena.games.size() == 3 and arena.errors.is_empty(), str(arena.errors))
	await s.frames(30)
	var all_v3 := true
	var obs_ok := true
	var space_ok := true
	for game: Game in arena.games:
		for fighter in _fighters_of(game):
			var ai := fighter.ai_controller_2d as PlayerAIController
			all_v3 = all_v3 and ai.schema_version == 3
		var agent := _agent_of(game)
		var index := 1 if agent == game.fighter_2 else 0
		var obs: Array = agent.ai_controller_2d.get_obs()["obs"]
		var expected := BvsSchemaV3.build_obs(game.get_state_snapshot(), index)
		obs_ok = obs_ok and obs.size() == 136 and expected.size() == 136
		for i in expected.size():
			obs_ok = obs_ok and is_equal_approx(float(obs[i]), expected[i])
		space_ok = space_ok and agent.ai_controller_2d.get_action_space() == BvsSchemaV3.action_space()
		var shape: Array = agent.ai_controller_2d.get_obs_space()["obs"]["size"]
		space_ok = space_ok and shape == [136]
	s.check("every fighter of a schema 3 arena carries schema_version 3", all_v3)
	s.check("schema 3 rows build 136-float observations equal to BvsSchemaV3.build_obs", obs_ok)
	s.check("schema 3 rows expose the v3 action space and a 136 observation space", space_ok)
	var snapshot_game: Game = arena.games[2]
	var snapshot_foe: Fighter = snapshot_game.fighter_2 if _agent_of(snapshot_game) == snapshot_game.fighter_1 else snapshot_game.fighter_1
	var snapshot_policy := snapshot_foe.controller as PolicyController
	s.check("a schema 3 snapshot opponent decodes through the v3 module", snapshot_policy != null and snapshot_policy.error == "" and snapshot_policy.decisions >= 5 and snapshot_policy._decoder is BvsActionDecoderV3, str(snapshot_policy.error if snapshot_policy != null else "none"))
	var agent_game: Game = arena.games[0]
	var agent := _agent_of(agent_game)
	var ai := agent.ai_controller_2d as PlayerAIController
	ai.set_action({"a0_move": 2, "a1_vertical": 0, "a2_jump": 0, "a3_attack": 0, "a4_special": 0, "a5_throw": 0, "a6_block": 0, "a7_dash": 0})
	var start_x := agent.position.x
	await s.frames(8)
	s.check("the training agent walks right through the v3 decoder", agent.position.x > start_x + 5.0 and (agent.controller as PolicyController).error == "", "dx=%.1f" % (agent.position.x - start_x))
	arena.queue_free()
	await s.frames(2)

	# A v2 snapshot is refused by a schema 3 arena, naming the row and the schema.
	var mixed := await _arena(s, "Schema3Mixed", 140000.0, {
		"schema_version": 3,
		"rows": [{"opponent": "cpu_easy"}, {"opponent": "snapshot", "model": "res://tests/fixtures/onnx/random_policy.onnx"}],
	})
	s.check("a schema 2 snapshot is rejected by a schema 3 arena, naming its row", mixed.errors.size() == 1 and mixed.errors[0].contains("row 1") and mixed.errors[0].contains("schema 3"), str(mixed.errors))
	mixed.queue_free()
	await s.frames(2)

	# An unregistered schema builds nothing; an unknown start is a row error.
	var unknown := await _arena(s, "SchemaUnknown", 150000.0, {"schema_version": 99, "rows": [{"opponent": "cpu_easy"}]})
	s.check("an unregistered schema_version is an error and builds no row", unknown.games.is_empty() and unknown.errors.size() == 1 and unknown.errors[0].contains("99"), str(unknown.errors))
	unknown.queue_free()
	await s.frames(2)
	var bad_start := await _arena(s, "BadStart", 160000.0, {"rows": [{"opponent": "cpu_easy", "start": "midair"}, {"opponent": "cpu_easy"}]})
	s.check("an unknown start names its row and value; the other row is built", bad_start.errors.size() == 1 and bad_start.errors[0].contains("row 0") and bad_start.errors[0].contains("midair") and bad_start.games.size() == 1, str(bad_start.errors))
	bad_start.queue_free()
	await s.frames(2)

	# No schema_version in the config: the playable version, as before.
	var plain := await _arena(s, "SchemaDefault", 170000.0, {"rows": [{"opponent": "cpu_easy"}]})
	var plain_agent := _agent_of(plain.games[0])
	s.check("without schema_version the agents use the playable schema", plain.schema_version == BvsSchema.CURRENT_VERSION and (plain_agent.ai_controller_2d as PlayerAIController).schema_version == BvsSchema.CURRENT_VERSION)
	plain.queue_free()
	await s.frames(2)

# --------------------------------------------------- sudden-death start rows

func _sudden_death_start_rows(s: RefCounted) -> void:
	var arena := await _arena(s, "SdStart", 180000.0, {"schema_version": 3, "rows": [{"opponent": "self", "start": "sudden_death"}, {"opponent": "self"}]})
	var game: Game = arena.games[0]
	var regular: Game = arena.games[1]
	await s.frames(20)
	s.check("a start: sudden_death row begins in sudden death; the other row in regulation", game.training_start_in_sudden_death and game.phase == Game.Phase.SUDDEN_DEATH and regular.phase == Game.Phase.PLAYING and not regular.training_start_in_sudden_death, "phase=%d" % game.phase)
	s.check("the SD row's fighters are at 300% and one stock, the bombs are armed", is_equal_approx(game.fighter_1.damage_percent, game.sudden_death_damage) and game.fighter_1.stocks == 1 and game.hazards.is_active())
	var snapshot := game.get_state_snapshot()
	s.check("the SD row observes sudden death (flag and grace phase)", BvsSchemaV3.build_obs(snapshot, 0)[133] == 1.0 and is_equal_approx(BvsSchemaV3.build_obs(snapshot, 0)[134], 0.5))

	# A KO ends the episode; the row re-enters sudden death once BOTH fighters have reset.
	var ended: Array = []
	game.training_episode_ended.connect(func(winner: Fighter) -> void: ended.append(winner))
	game.fighter_2.position = Vector2(game.blast_right + 500.0, 0.0)
	await s.frames(2)
	s.check("the KO ended the episode once, with Fighter1 as the winner", ended.size() == 1 and ended[0] == game.fighter_1, str(ended))
	await s.frames(6)
	s.check("after both resets the row is back in sudden death at 300% and one stock (the reset was not overwritten)", game.phase == Game.Phase.SUDDEN_DEATH and is_equal_approx(game.fighter_1.damage_percent, game.sudden_death_damage) and is_equal_approx(game.fighter_2.damage_percent, game.sudden_death_damage) and game.fighter_1.stocks == 1 and game.fighter_2.stocks == 1 and s.state_of(game.fighter_2) != "Defeated", "phase=%d d1=%.0f d2=%.0f st=%d/%d" % [game.phase, game.fighter_1.damage_percent, game.fighter_2.damage_percent, game.fighter_1.stocks, game.fighter_2.stocks])
	s.check("the regular row stayed in regulation", regular.phase == Game.Phase.PLAYING and regular.fighter_1.stocks == Fighter.MAX_STOCKS)

	# A double KO inside sudden death restarts it without a `done`.
	game.hazards.grace_time = 0.1
	await s.sim(0.5)
	var elapsed_before := game.hazards.elapsed_ticks
	var ended_before := ended.size()
	game.fighter_1.position = Vector2(game.blast_left - 500.0, 0.0)
	game.fighter_2.position = Vector2(game.blast_right + 500.0, 0.0)
	await s.frames(3)
	s.check("a double KO in sudden death restarts it with no done", ended.size() == ended_before and game.phase == Game.Phase.SUDDEN_DEATH and game.fighter_1.stocks == 1 and game.fighter_2.stocks == 1, "ended=%d phase=%d" % [ended.size() - ended_before, game.phase])
	s.check("the restart began a fresh grace period and escalation", game.hazards.is_active() and game.hazards.elapsed_ticks < elapsed_before and game.hazards.bombs_spawned == 0, "elapsed %d -> %d" % [elapsed_before, game.hazards.elapsed_ticks])
	arena.queue_free()
	await s.frames(2)
