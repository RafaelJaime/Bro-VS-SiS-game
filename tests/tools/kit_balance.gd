extends SceneTree
## Manual kit balance sanity (not part of run_all.sh): full CPU matches on the real kits.
##
##   KIT_MATCHES=40 KIT_LEVEL=hard KIT_SEED=1 \
##   godot --headless --path . --fixed-fps 60 --script res://tests/tools/kit_balance.gd
##
## Matches alternate the kit pair: even matches Rafael is Fighter1 and Matilde Fighter2,
## odd matches they swap (so each kit plays each side). Both fighters are CPUs of KIT_LEVEL.
## Prints Rafael's win share over the decided matches, the mean multi-hit combo damage per
## kit and the longest combo. Target (fighter-kits spec): win share 40-60 %, damage gap <= 20 %.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const LEVELS := {"easy": CpuDifficulty.Level.EASY, "normal": CpuDifficulty.Level.NORMAL, "hard": CpuDifficulty.Level.HARD}
const MATCH_LIMIT_SECONDS := 400.0

func _initialize() -> void:
	_run()

func _run() -> void:
	var matches := int(OS.get_environment("KIT_MATCHES")) if OS.get_environment("KIT_MATCHES") != "" else 40
	var level: int = LEVELS.get(OS.get_environment("KIT_LEVEL").to_lower(), CpuDifficulty.Level.HARD)
	var base_seed := int(OS.get_environment("KIT_SEED")) if OS.get_environment("KIT_SEED") != "" else 1
	var s := Smoke.new(self, MATCH_LIMIT_SECONDS * float(matches + 2))
	var wins := {0: 0, 1: 0}
	var draws := 0
	var combo_damage := {0: [], 1: []}
	# Lambdas capture locals by value: the longest combo lives in an Array.
	var longest := [0]
	var seconds := 0.0
	for index in matches:
		GameRng.seed_all(base_seed * 100003 + index)
		var game: Node2D = s.spawn_game(NAN, NAN, false, true)
		var fighters: Array[Fighter] = [game.get_node("Fighter1"), game.get_node("Fighter2")]
		var swap := index % 2 == 1
		fighters[0].set_profile(FighterKits.by_id(1 if swap else 0))
		fighters[1].set_profile(FighterKits.by_id(0 if swap else 1))
		for side in 2:
			s.set_cpu(fighters[side], level, base_seed * 1000 + index * 2 + side)
		for victim in fighters:
			victim.combo_ended.connect(func(hits: int, damage: float, by: Fighter) -> void:
				longest[0] = maxi(longest[0], hits)
				if hits >= 2:
					combo_damage[by.profile.kit_id].append(damage))
		var done := {"over": false, "winner": null}
		game.match_over.connect(func(winner: Fighter) -> void:
			done["over"] = true
			done["winner"] = winner)
		var start := Engine.get_physics_frames()
		while not done["over"] and float(Engine.get_physics_frames() - start) / 60.0 < MATCH_LIMIT_SECONDS:
			await s.frames(1)
		seconds += float(Engine.get_physics_frames() - start) / 60.0
		var winner: Fighter = done["winner"]
		if winner == null:
			draws += 1
		else:
			wins[winner.profile.kit_id] += 1
		paused = false
		Combat.cancel_hit_stop()
		await s.despawn(game)
	var decided: int = wins[0] + wins[1]
	var share := float(wins[0]) / float(maxi(1, decided))
	var mean_r: float = _mean(combo_damage[0])
	var mean_m: float = _mean(combo_damage[1])
	var gap := absf(mean_r - mean_m) / maxf(0.001, maxf(mean_r, mean_m))
	print("KIT_BALANCE level=%s matches=%d decided=%d draws=%d mean_match_seconds=%.1f rafael_wins=%d matilde_wins=%d rafael_win_share=%.3f combos_rafael=%d combos_matilde=%d mean_combo_damage_rafael=%.2f mean_combo_damage_matilde=%.2f combo_damage_gap=%.3f longest_combo=%d" % [OS.get_environment("KIT_LEVEL"), matches, decided, draws, seconds / float(matches), wins[0], wins[1], share, combo_damage[0].size(), combo_damage[1].size(), mean_r, mean_m, gap, longest[0]])
	s.finish()

func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())
