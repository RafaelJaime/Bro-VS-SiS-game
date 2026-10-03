extends SceneTree
## In-game policy inference (headless, no Sync node anywhere): a PolicyController
## running the random-weight fixture model (tests/fixtures/onnx/random_policy_v3.onnx)
## plays a full match against the scripted CPU.
##
## Checks: the model loads and fits the current schema (3); a whole match runs with decisions
## flowing and no script errors; the model runs exactly once per ACTION_REPEAT
## frames with the intent held in between; two policy fighters never infer on the
## same frame; the observation of the play path (PolicyController) equals the one
## of the training path (PlayerAIController) for the same fighter in the same
## state; a run-time inference error is reported once and leaves the fighter
## neutral; a policy fighter with no model and no training source stays neutral.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const MODEL_PATH := "res://tests/fixtures/onnx/random_policy_v3.onnx"
const SIDECAR_PATH := "res://tests/fixtures/onnx/random_policy_v3.bvs.json"
## A full match ends by the 99 s timer at the latest.
const MATCH_LIMIT_SECONDS := 150.0

## A model that loads but fails when asked to infer (a run-time error).
class FailingModel extends OnnxPolicyModel:
	func infer_checked(_obs: PackedFloat32Array) -> Dictionary:
		return {"logits": PackedFloat32Array(), "error": "simulated run-time failure"}

func _initialize() -> void:
	_run()

func _load_model() -> OnnxPolicyModel:
	var sidecar: Variant = JSON.parse_string(FileAccess.get_file_as_string(SIDECAR_PATH))
	var loaded := OnnxPolicyModel.load_bytes(FileAccess.get_file_as_bytes(MODEL_PATH), sidecar if sidecar is Dictionary else {})
	return loaded.model

func _run() -> void:
	var s := Smoke.new(self, MATCH_LIMIT_SECONDS * 4.0)
	var model := _load_model()
	s.check("the random-weight fixture loads", model != null)
	if model == null:
		s.finish()
		return
	s.check("it fits the current schema (136 inputs, 21 logits)", model.validate(BvsSchema.current()) == "", model.validate(BvsSchema.current()))
	s.check("the scene tree has no Sync node", root.find_child("Sync", true, false) == null)

	await _cadence(s, model)
	await _stagger(s, model)
	await _parity(s, model)
	await _errors(s, model)
	await _full_match(s, model)
	s.finish()

## The model runs once per 4 frames; held flags stay put inside a window.
func _cadence(s: RefCounted, model: OnnxPolicyModel) -> void:
	var game: Node2D = s.spawn_game()
	var fighter: Fighter = game.get_node("Fighter1")
	var controller := PolicyController.new(model)
	fighter.set_controller(controller)
	game.get_node("Fighter2").set_controller(Smoke.IntentController.new())
	await s.frames(2)
	var start := controller.decisions
	var held: Array = []
	var decided_on: Array[int] = []
	var seen := start
	for frame in 12:
		await s.frames(1)
		held.append([fighter.intent.move_x, fighter.intent.jump_held, fighter.intent.block_held])
		if controller.decisions != seen:
			seen = controller.decisions
			decided_on.append(frame)
	s.check("3 x ACTION_REPEAT ticks run the model exactly 3 times", controller.decisions - start == 3, "runs=%d" % (controller.decisions - start))
	s.check("the decisions fall every ACTION_REPEAT frames", decided_on.size() == 3 and decided_on[1] - decided_on[0] == BvsSchemaV2.ACTION_REPEAT and decided_on[2] - decided_on[1] == BvsSchemaV2.ACTION_REPEAT, str(decided_on))
	var constant := true
	for window_start in range(decided_on[0], decided_on[0] + 8, BvsSchemaV2.ACTION_REPEAT):
		for offset in range(1, BvsSchemaV2.ACTION_REPEAT):
			constant = constant and held[window_start + offset] == held[window_start]
	s.check("the held intent is constant between two decisions", constant)
	s.check("the policy fighter reports kind 'policy' and a 21-logit decision", controller.kind_name() == "policy" and controller.last_action.size() == BvsSchemaV2.BRANCHES.size())
	await s.despawn(game)

## Two policy fighters never infer on the same frame.
func _stagger(s: RefCounted, model: OnnxPolicyModel) -> void:
	var game: Node2D = s.spawn_game()
	var controllers: Array[PolicyController] = [PolicyController.new(model), PolicyController.new(model)]
	game.get_node("Fighter1").set_controller(controllers[0])
	game.get_node("Fighter2").set_controller(controllers[1])
	await s.frames(2)
	var last := [controllers[0].decisions, controllers[1].decisions]
	var both := 0
	var first := 0
	var second := 0
	for frame in 80:
		await s.frames(1)
		var now := [controllers[0].decisions, controllers[1].decisions]
		var a: int = now[0] - last[0]
		var b: int = now[1] - last[1]
		both += 1 if (a > 0 and b > 0) else 0
		first += a
		second += b
		last = now
	s.check("two AI fighters never infer on the same frame", both == 0, "same-frame=%d" % both)
	s.check("each of them still decides every ACTION_REPEAT frames", first == 20 and second == 20, "first=%d second=%d" % [first, second])
	s.check("the fighter index staggers them (offsets 0 and 1)", controllers[0].phase_offset == 0 and controllers[1].phase_offset == 1)
	await s.despawn(game)

## The same fighter in the same state gets the same observation from both paths.
func _parity(s: RefCounted, model: OnnxPolicyModel) -> void:
	var game: Node2D = s.spawn_game()
	await s.frames(3)
	for side in 2:
		var fighter: Fighter = game.get_node("Fighter%d" % (side + 1))
		fighter.position += Vector2(37.0, -12.0 * side)
		fighter.damage_percent = 41.0
		var controller := PolicyController.new(model)
		fighter.set_controller(controller)
		# The fighters are frozen for the comparison: no physics frame runs between
		# the two observations, only these direct calls.
		for call_index in side + 1:
			controller.sample(0.0)
		var training_obs: Array = (fighter.ai_controller_2d as PlayerAIController).get_obs()["obs"]
		var obs_dim: int = BvsSchema.current().OBS_DIM
		var same: bool = controller.last_obs.size() == obs_dim and training_obs.size() == obs_dim
		for i in controller.last_obs.size():
			same = same and is_equal_approx(controller.last_obs[i], float(training_obs[i]))
		s.check("fighter %d: the play observation equals the training observation (136 values)" % (side + 1), same)
	await s.despawn(game)

func _errors(s: RefCounted, model: OnnxPolicyModel) -> void:
	var game: Node2D = s.spawn_game()
	await s.frames(2)
	var fighter: Fighter = game.get_node("Fighter1")
	var failing := FailingModel.new()
	var controller := PolicyController.new(failing)
	fighter.set_controller(controller)
	var intent := controller.sample(0.0)
	s.check("a run-time inference error gives a neutral intent", intent.move_x == 0.0 and not intent.attack_pressed and not intent.jump_held and intent.aim == FighterIntent.Aim.NEUTRAL)
	s.check("the error is kept (and was reported once)", controller.error.contains("simulated run-time failure") and controller.decisions == 0, controller.error)
	var first_error := controller.error
	for i in 5:
		controller.sample(0.0)
	s.check("later frames stay neutral and do not report again", controller.error == first_error and controller.decisions == 0)
	await s.frames(5)
	s.check("the game keeps running after the failure", is_instance_valid(game) and game.phase == Game.Phase.PLAYING)

	# No model, not a training agent: neutral and one error, never a CPU.
	var bare := PolicyController.new()
	game.get_node("Fighter2").set_controller(bare)
	var bare_intent := bare.sample(0.0)
	s.check("a policy fighter with no model and no training source is neutral", bare_intent.move_x == 0.0 and not bare_intent.attack_pressed and bare.decisions == 0)
	await s.despawn(game)

## One whole match through PolicyController (no Sync) against the scripted CPU.
func _full_match(s: RefCounted, model: OnnxPolicyModel) -> void:
	var game: Node2D = s.spawn_game()
	var policy_fighter: Fighter = game.get_node("Fighter1")
	var controller := PolicyController.new(model)
	policy_fighter.set_controller(controller)
	s.set_cpu(game.get_node("Fighter2"), CpuDifficulty.Level.EASY, 1234)
	var finished := {"over": false}
	game.match_over.connect(func(_winner: Fighter) -> void: finished["over"] = true)
	var start := Engine.get_physics_frames()
	var changes := 0
	var presses := 0
	var moving := 0
	var frames := 0
	var previous := PackedInt32Array()
	while not finished["over"] and float(Engine.get_physics_frames() - start) / 60.0 < MATCH_LIMIT_SECONDS:
		await s.frames(1)
		frames += 1
		var intent := policy_fighter.intent
		if intent.attack_pressed or intent.special_pressed:
			presses += 1
		if not is_zero_approx(intent.move_x):
			moving += 1
		if controller.last_action != previous:
			changes += 1
			previous = controller.last_action
	s.check("the match ran to its end with a model and no Sync", finished["over"], "frames=%d" % frames)
	s.check("the model decided throughout the match (one per 4 frames)", controller.decisions >= frames / 4 - 2 and controller.decisions <= frames / 4 + 2, "decisions=%d frames=%d" % [controller.decisions, frames])
	s.check("the policy fighter acted: decisions changed over time or attacks were pressed", changes > 1 or presses > 0, "changes=%d presses=%d moving=%d" % [changes, presses, moving])
	s.check("no inference error during the match", controller.error == "", controller.error)
	print("INFO policy match: %d frames, %d decisions, %d distinct decisions, %d attack frames, %d moving frames" % [frames, controller.decisions, changes, presses, moving])
	await s.despawn(game)
