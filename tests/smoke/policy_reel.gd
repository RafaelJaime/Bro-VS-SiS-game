extends SceneTree
## Gameplay reel of a policy model against the scripted CPU, windowed: one PNG per
## second of game time, to eyeball the play style. Not part of run_all.sh.
##
##   godot --path . --resolution 800x600 --fixed-fps 60 --script res://tests/smoke/policy_reel.gd \
##     -- model=res://game/ai/models/bvs_default/model.onnx level=easy out=/some/dir [seconds=45] [seed=1000] [side=0]
##
## User arguments after `--` are used instead of environment variables because a
## macOS `open -g` launch (see run_all.sh) does not forward the shell environment.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const LEVELS := {"easy": CpuDifficulty.Level.EASY, "normal": CpuDifficulty.Level.NORMAL, "hard": CpuDifficulty.Level.HARD}

func _initialize() -> void:
	_run()

func _arg(args: Dictionary, key: String, fallback: String) -> String:
	return String(args.get(key, fallback))

func _run() -> void:
	var args := {}
	for raw in OS.get_cmdline_user_args():
		var parts := raw.split("=", true, 1)
		if parts.size() == 2:
			args[parts[0]] = parts[1]
	var model_path := _arg(args, "model", "res://game/ai/models/bvs_default/model.onnx")
	var level_name := _arg(args, "level", "easy")
	var out_dir := _arg(args, "out", ProjectSettings.globalize_path("user://reel"))
	var seconds := int(_arg(args, "seconds", "45"))
	var cpu_seed := int(_arg(args, "seed", "1000"))
	var side := int(_arg(args, "side", "0"))
	var s := Smoke.new(self, float(seconds) + 60.0)
	if not LEVELS.has(level_name):
		s.check("level is easy, normal or hard", false, level_name)
		s.finish()
		return
	var sidecar_path := model_path.get_base_dir().path_join("bvs.json")
	var sidecar: Dictionary = {}
	if FileAccess.file_exists(sidecar_path):
		sidecar = JSON.parse_string(FileAccess.get_file_as_string(sidecar_path))
	var loaded := OnnxPolicyModel.load_bytes(FileAccess.get_file_as_bytes(model_path), sidecar)
	s.check("model loads", loaded.model != null, str(loaded.error))
	if loaded.model == null:
		s.finish()
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var game: Node2D = s.spawn_game()
	var fighters: Array[Fighter] = [game.get_node("Fighter1"), game.get_node("Fighter2")]
	var controller := PolicyController.new(loaded.model)
	fighters[side].set_controller(controller)
	s.set_cpu(fighters[1 - side], LEVELS[level_name], cpu_seed)
	var over := {"done": false}
	game.match_over.connect(func(_winner: Fighter) -> void: over["done"] = true)
	var shots := 0
	for second in seconds:
		if over["done"]:
			break
		await s.frames(Engine.physics_ticks_per_second)
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join("frame_%03d.png" % shots)
		root.get_texture().get_image().save_png(path)
		shots += 1
	print("INFO reel: %d frames in %s (match over: %s, stocks policy %d, cpu %d)" % [shots, out_dir, str(over["done"]), fighters[side].stocks, fighters[1 - side].stocks])
	s.check("the reel recorded frames", shots > 0)
	s.check("the policy never failed", controller.error == "", controller.error)
	s.finish()
