extends SceneTree
## MatchMetrics: the character-kits fields (combos from combo_ended with single hits as
## length 1, an open combo flushed by stop(), shield raises, the longest continuous
## Hurt, the kit of each fighter and damage by kit) and their aggregation (histogram
## with the 7+ bucket, maximum, multi-hit count, combo damage by kit, per fighter-minute
## rates). Headless.

const Smoke := preload("res://tests/smoke/smoke_util.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var s := Smoke.new(self)
	await _live(s)
	_aggregate(s)
	s.finish()

func _live(s: RefCounted) -> void:
	var game: Game = s.spawn_game(NAN, NAN, false, true)
	var attacker: Fighter = game.get_node("Fighter1")
	var victim: Fighter = game.get_node("Fighter2")
	await s.frames(30)
	game.food_spawner.stop()
	var metrics := MatchMetrics.new()
	metrics.setup(game)
	s.check("the kits of both fighters are recorded (Rafael, Matilde)", metrics.kits == ["rafael", "matilde"], str(metrics.kits))

	# One hit: a combo of length 1 once the hitstun ends.
	Combat.resolve(Hit.punch(attacker, 4.0, Vector2(80.0, -30.0)), victim)
	await s.sim(1.5)
	s.check("a single hit is a combo of length 1 with its damage and attacker kit", metrics.combos.size() == 1 and metrics.combos[0]["hits"] == 1 and is_equal_approx(float(metrics.combos[0]["damage"]), 4.0) and metrics.combos[0]["attacker_kit"] == "rafael" and metrics.combos[0]["victim_index"] == 1, str(metrics.combos))
	s.check("the longest Hurt run is recorded in ticks and stays under the 90 tick cap", metrics.max_hurt_ticks[1] > 0 and metrics.max_hurt_ticks[1] <= MatchMetrics.HURT_CAP_TICKS and metrics.max_hurt_ticks[0] == 0 and metrics.hurt_over_cap == 0, str(metrics.max_hurt_ticks))

	# Damage by the attacker's kit.
	s.check("damage by kit counts the FULL hit under the attacker's kit", is_equal_approx(float(metrics.damage_by_kit.get("rafael", 0.0)), 4.0) and not metrics.damage_by_kit.has("matilde"), str(metrics.damage_by_kit))

	# A combo of three hits is still open when the match is stopped: stop() flushes it.
	for i in 3:
		Combat.resolve(Hit.punch(attacker, 2.0, Vector2(40.0, -10.0)), victim)
		await s.frames(2)
	s.check("an open combo is not recorded before it ends", metrics.combos.size() == 1 and victim.combo.is_active() and victim.combo.hits == 3)
	attacker.shield_raises += 3
	victim.shield_raises += 1
	metrics.stop()
	s.check("stop() flushes the open combo of three hits", metrics.combos.size() == 2 and metrics.combos[1]["hits"] == 3 and is_equal_approx(float(metrics.combos[1]["damage"]), 6.0), str(metrics.combos))
	s.check("the tracker of the fighter is left as it was (stop does not end the combo)", victim.combo.is_active())
	s.check("shield raises are the delta per fighter since setup", metrics.shield_raises == [3, 1], str(metrics.shield_raises))
	var record := metrics.to_dict()
	s.check("to_dict carries the new fields", record["shield_raises"] == [3, 1] and record["combos"].size() == 2 and record["kits"] == ["rafael", "matilde"] and record.has("max_hurt_ticks") and record.has("damage_by_kit") and record.has("hurt_over_cap"))
	var sum_before := metrics.combos.size()
	metrics.stop()
	s.check("a second stop() records nothing again", metrics.combos.size() == sum_before)
	await s.despawn(game)

func _record(combos: Array, raises: Array, hurt: Array, over: int, seconds: float = 60.0) -> Dictionary:
	return {
		"seconds": seconds, "sd_seconds": 0.0, "pickups": [0, 0], "throws": [0, 0], "shield_breaks": [0, 0],
		"full_hits": 0, "blocked_hits": 0, "broke_hits": 0, "ignored_hits": 0,
		"damage_by_source": {"punch": 0.0, "ledge": 0.0, "food": 0.0, "bomb": 0.0},
		"shield_raises": raises, "combos": combos, "max_hurt_ticks": hurt, "hurt_over_cap": over,
		"kits": ["rafael", "matilde"], "damage_by_kit": {"rafael": 10.0, "matilde": 6.0},
	}

func _combo(hits: int, damage: float, kit: String) -> Dictionary:
	return {"hits": hits, "damage": damage, "attacker_kit": kit, "victim_index": 0}

func _aggregate(s: RefCounted) -> void:
	var records := [
		_record([_combo(1, 3.0, "rafael"), _combo(2, 6.0, "rafael"), _combo(6, 20.0, "matilde")], [4, 2], [30, 12], 0),
		_record([_combo(7, 25.0, "matilde"), _combo(9, 31.0, "rafael"), _combo(3, 9.0, "matilde")], [2, 0], [95, 10], 1),
	]
	var out := MatchMetrics.aggregate(records)
	s.check("shield raises per fighter-minute = total raises over all fighter time", out["shield_raises"] == 8 and is_equal_approx(float(out["shield_raises_per_fighter_minute"]), 8.0 / 4.0), str(out["shield_raises_per_fighter_minute"]))
	s.check("the histogram has buckets 1..6 and 7+", out["combo_histogram"] == {"1": 1, "2": 1, "3": 1, "4": 0, "5": 0, "6": 1, "7+": 2}, str(out["combo_histogram"]))
	s.check("the longest combo and the 2+ hit combo count", out["max_combo"] == 9 and out["multi_hit_combos"] == 5)
	s.check("the longest continuous Hurt is in seconds and over-cap runs are summed", is_equal_approx(float(out["max_hurt_seconds"]), 95.0 / 60.0) and out["hurt_over_cap"] == 1, str(out["max_hurt_seconds"]))
	s.check("damage by kit sums the records", is_equal_approx(float(out["damage_by_kit"]["rafael"]), 20.0) and is_equal_approx(float(out["damage_by_kit"]["matilde"]), 12.0))
	s.check("combo damage by kit is the mean of the multi-hit combos (single hits excluded)", is_equal_approx(float(out["combo_damage_by_kit"]["rafael"]), 18.5) and is_equal_approx(float(out["combo_damage_by_kit"]["matilde"]), 18.0) and out["combo_count_by_kit"] == {"rafael": 2, "matilde": 3}, str(out["combo_damage_by_kit"]))
	var empty := MatchMetrics.aggregate([])
	s.check("an empty aggregate is zeros with an empty histogram", empty["shield_raises_per_fighter_minute"] == 0.0 and empty["max_combo"] == 0 and empty["multi_hit_combos"] == 0 and empty["combo_damage_by_kit"].is_empty() and empty["combo_histogram"]["7+"] == 0)
	var legacy := MatchMetrics.aggregate([{
		"seconds": 60.0, "sd_seconds": 0.0, "pickups": [0, 0], "throws": [0, 0], "shield_breaks": [0, 0],
		"full_hits": 0, "blocked_hits": 0, "broke_hits": 0, "ignored_hits": 0,
		"damage_by_source": {"punch": 0.0, "ledge": 0.0, "food": 0.0, "bomb": 0.0},
	}])
	s.check("a record without the new fields still aggregates", legacy["max_combo"] == 0 and legacy["shield_raises"] == 0)
