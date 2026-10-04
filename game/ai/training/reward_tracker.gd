class_name RewardTracker
extends RefCounted

## Reward terms of one training agent, driven by the damage, stock, combat and
## episode signals (not by observation reads) plus a few per-decision shaping terms.
## Only a damage increase and a stock decrease count, so a reset that clears
## damage or refills stocks is never rewarded. Weights come from a RewardConfig.
##
## Combat-depth terms: `pickup` (food_picked_up, capped per episode), `food_hit`
## (the foe's hit_received with a FOOD hit of mine that was not ignored),
## `shield_break_dealt` / `shield_break_taken` (shield_broken of the foe / of me) and
## `shield_hold` (my shield held past a threshold, read per decision). Character-kits
## terms: `combo_hit` (the foe's combo_updated with me as the attacker, one small
## reward per extra hit, capped per combo and per episode) and `shield_raise` (the
## `Fighter.shield_raises` delta per decision, a lever against shield spam). An episode
## that the sudden-death safety cap ended (`sd_cap`) is a draw: outcome "draw",
## `"truncated": true` in the record, and no win, loss or timeout reward.
##
## Every episode ends with one `BVS_EPISODE {json}` line on stdout (and the
## `episode_logged` signal): the totals per term, the outcome, the winner and the
## length in decisions. That is how the KO, stock and win terms are inspected in a
## training log.

## Emitted at the end of every episode with the record printed as BVS_EPISODE.
signal episode_logged(record: Dictionary)

var config: RewardConfig
## Totals per term (RewardConfig.TERMS) of the running episode.
var totals: Dictionary = {}
## Print the BVS_EPISODE line (tests turn it off).
var print_log := true

var _agent: AIController2D
var _me: Fighter
var _foe: Fighter
var _game: Game
var _decisions := 0
var _last_damage_me := 0.0
var _last_damage_foe := 0.0
var _last_stocks_me := 0
var _last_stocks_foe := 0
var _previous_distance := -1.0
var _pickups := 0
var _last_raises := 0
var _stage_left := 0.0
var _stage_right := 0.0
var _stage_top := 0.0
var _stage_known := false

## Connects to the fighters and the Game. `agent.reward` is where every term lands
## (Sync reads and zeroes it once per decision).
func setup(agent: AIController2D, me: Fighter, reward_config: RewardConfig = null) -> void:
	_agent = agent
	_me = me
	_foe = me.enemy as Fighter
	_game = me.get_parent() as Game
	config = reward_config if reward_config != null else RewardConfig.new()
	_begin_episode()
	me.damage_changed.connect(_on_my_damage)
	me.stocks_changed.connect(_on_my_stocks)
	me.food_picked_up.connect(_on_food_picked_up)
	me.shield_broken.connect(_on_my_shield_broken)
	if _foe != null:
		_foe.damage_changed.connect(_on_foe_damage)
		_foe.stocks_changed.connect(_on_foe_stocks)
		_foe.hit_received.connect(_on_foe_hit_received)
		_foe.combo_updated.connect(_on_foe_combo_updated)
		_foe.shield_broken.connect(_on_foe_shield_broken)
	if _game != null:
		_game.training_episode_ended.connect(_on_episode_ended)

## Called once per decision, right before Sync reads the reward: the time,
## off-stage and approach terms.
func on_decision() -> void:
	_decisions += 1
	_add("time", config.time)
	if _me.shield.held_ticks > CombatClock.ticks(config.shield_hold_threshold):
		_add("shield_hold", config.shield_hold)
	var raises: int = _me.shield_raises
	if raises > _last_raises:
		_add("shield_raise", config.shield_raise * float(raises - _last_raises))
	_last_raises = raises
	_read_stage()
	if not _stage_known or _foe == null:
		return
	if _is_off_stage():
		_add("off_stage", config.off_stage)
	var distance := absf(_foe.position.x - _me.position.x)
	if _previous_distance >= 0.0:
		_add("approach", config.approach * (_previous_distance - distance) / _half_width())
	_previous_distance = distance

func _begin_episode() -> void:
	totals.clear()
	for term in RewardConfig.TERMS:
		totals[term] = 0.0
	_decisions = 0
	_pickups = 0
	_last_raises = _me.shield_raises
	_previous_distance = -1.0
	_last_damage_me = _me.damage_percent
	_last_stocks_me = _me.stocks
	if _foe != null:
		_last_damage_foe = _foe.damage_percent
		_last_stocks_foe = _foe.stocks

func _add(term: String, amount: float) -> void:
	totals[term] += amount
	_agent.reward += amount

func _on_my_damage(percent: float) -> void:
	if percent > _last_damage_me:
		_add("damage_taken", config.damage_taken * (percent - _last_damage_me))
	_last_damage_me = percent

func _on_foe_damage(percent: float) -> void:
	if percent > _last_damage_foe:
		_add("damage_dealt", config.damage_dealt * (percent - _last_damage_foe))
	_last_damage_foe = percent

func _on_my_stocks(_fighter: Fighter, stocks_left: int) -> void:
	if stocks_left < _last_stocks_me:
		_add("ko_taken", config.ko_taken)
		_add("stock_lost", config.stock_lost)
	_last_stocks_me = stocks_left

func _on_foe_stocks(_fighter: Fighter, stocks_left: int) -> void:
	if stocks_left < _last_stocks_foe:
		_add("ko_given", config.ko_given)
	_last_stocks_foe = stocks_left

func _on_food_picked_up(_food_name: String) -> void:
	if _pickups < config.pickup_cap:
		_pickups += 1
		_add("pickup", config.pickup)

## My thrown food reached the opponent (a blocked one counts, an ignored one does not).
func _on_foe_hit_received(hit: Hit, outcome: int) -> void:
	if hit.source == Hit.Source.FOOD and hit.attacker == _me and outcome != Combat.Outcome.IGNORED:
		_add("food_hit", config.food_hit)

## A combo I am dealing grew: every hit from the second on is one extra hit, rewarded
## up to `combo_hit_cap` per combo and `combo_episode_cap` per episode.
func _on_foe_combo_updated(hits: int, _damage: float, attacker: Fighter) -> void:
	if attacker != _me or hits < 2 or hits - 1 > config.combo_hit_cap:
		return
	var room: float = config.combo_episode_cap - float(totals["combo_hit"])
	var amount := minf(config.combo_hit, room)
	if amount > 0.0:
		_add("combo_hit", amount)

## The opponent's shield broke: rewarded only when one of my hits broke it.
func _on_foe_shield_broken(cause: Hit) -> void:
	if cause != null and cause.attacker == _me:
		_add("shield_break_dealt", config.shield_break_dealt)

## My shield broke (a hit or the hold drain).
func _on_my_shield_broken(_cause: Hit) -> void:
	_add("shield_break_taken", config.shield_break_taken)

## The match was decided (or time ran out): the win, loss or timeout term, then the
## episode record. Fighters are not reset yet, so their stocks tell the outcome.
func _on_episode_ended(winner: Fighter) -> void:
	var outcome := "draw"
	# The sudden-death safety cap truncates the episode: a draw with no outcome reward.
	var truncated := _game != null and _game.last_episode_end_reason == &"sd_cap"
	var timed_out := not truncated and _me.stocks > 0 and (_foe == null or _foe.stocks > 0)
	if truncated:
		pass
	elif timed_out:
		var lead := _me.stocks - (_foe.stocks if _foe != null else 0)
		outcome = "timeout"
		_add("timeout", config.timeout * signf(float(lead)))
	elif winner == _me:
		outcome = "win"
		_add("win", config.win)
	elif winner != null:
		outcome = "loss"
		_add("loss", config.loss)
	var record := {
		"outcome": outcome,
		"winner": "me" if winner == _me else ("opponent" if winner != null else "none"),
		"length": _decisions,
		"terms": totals.duplicate(),
		"total": _sum(totals),
	}
	if truncated:
		record["truncated"] = true
	if print_log:
		print("BVS_EPISODE ", JSON.stringify(record))
	episode_logged.emit(record)
	_begin_episode()

func _sum(terms: Dictionary) -> float:
	var total := 0.0
	for term: String in terms:
		total += float(terms[term])
	return total

func _read_stage() -> void:
	if _stage_known or _game == null:
		return
	var stage: Dictionary = _game.get_state_snapshot().get("stage", {})
	if stage.has("left") and stage.has("right") and stage.has("top"):
		_stage_left = float(stage["left"])
		_stage_right = float(stage["right"])
		_stage_top = float(stage["top"])
		_stage_known = true

func _half_width() -> float:
	return maxf((_stage_right - _stage_left) * 0.5, 1.0)

## Airborne and past a table edge or below the tabletop (same test as the schema).
func _is_off_stage() -> bool:
	if _me.is_on_floor():
		return false
	var pos := _me.position
	return pos.x < _stage_left or pos.x > _stage_right or pos.y + BvsSchemaV2.FEET_OFFSET > _stage_top + BvsSchemaV2.OFF_STAGE_SLACK
