class_name ScriptedController
extends FighterController

## Scripted CPU opponent (openspec cpu-opponent, design Decision 13).
##
## It only ever emits a FighterIntent, the same seam the keyboard and the RL
## policy use, and it reads the match through `Game.get_state_snapshot()`: stage
## extents, blast zones, both fighters, food and projectiles. No stage
## coordinate is hardcoded here; body and punch sizes come from the fighter's own
## colliders and FighterProfile, personality comes from a CpuDifficulty.
##
## Every `difficulty.decision_interval` seconds (the reaction time) it picks ONE
## plan by priority:
##   LEDGE    hanging from a table leg: wait a moment, then climb, ledge jump or
##            climb attack
##   RECOVER  off the stage or about to leave it: steer to the stage or a table leg,
##            double jump, up-recovery, air dash
##   DODGE_BOMB (Hard) a sudden-death bomb about to land on it: step out of the
##            impact column, or air dodge it
##   PUNISH   the opponent is dizzy (its shield broke) and the roll succeeded: walk
##            over and hit it
##   DEFEND   an incoming punch or thrown food: maybe block (only while the shield
##            meter is above the difficulty's release ratio)
##   THROW    holding food with the opponent in line: maybe throw (more often at a
##            shielding opponent, see food_pressure_chance)
##   PICKUP   food closer than the opponent: walk over and grab it (from twice as far
##            once the opponent has turtled behind its shield)
##   ATTACK   opponent in punch range: punch
##   APPROACH walk toward the opponent, never past the stage edge
## Between decisions the held flags (move, block, jump) persist. Pressed flags are
## one-frame latches that wait for their precondition (facing, a free frame) and
## are always followed by a release frame. The bot never charges: attack_held
## stays false. Normal and Hard also use directional punches and the up-recovery
## (CpuDifficulty.use_directional / use_up_recovery).

enum Plan { IDLE, LEDGE, RECOVER, DODGE_BOMB, PUNISH, DEFEND, THROW, PICKUP, ATTACK, APPROACH }

## States in which the fighter cannot act; presses would only be swallowed.
const NO_ACTION_STATES: Array[String] = ["Hurt", "Defeated", "Dizzy"]
## After releasing the shield at its release ratio the bot waits for the meter to
## climb this far above it before shielding again.
const SHIELD_HYSTERESIS := 0.15
## Half the hurtbox width, used to size the safe distance from a bomb's blast.
const BOMB_HURTBOX_HALF_WIDTH := 60.0
## A bomb lands on the bot's body this far above its position (its head).
const BOMB_IMPACT_HEIGHT := 70.0
## Air dodge a bomb that lands within this many seconds.
const BOMB_AIR_DODGE_TIME := 0.3
## How long a queued press waits for its precondition before it is dropped.
const PRESS_PATIENCE := 0.35
## Jump key hold after a press (a full hop, not a short hop).
const JUMP_HOLD := 0.5
## Extra distance to the punch hitbox reach that still counts as in range, and
## how far past it a low-accuracy bot may whiff.
const STRIKE_SLACK := 20.0
const WHIFF_RANGE_FACTOR := 1.6
## Recovery decisions run this much faster than ordinary ones (falling is urgent).
const RECOVERY_REACTION_FACTOR := 0.5
const MIN_RECOVERY_INTERVAL := 0.05
## Below the stage the recovery miss chance is multiplied by this.
const LAST_CHANCE_MISS_FACTOR := 0.35
## Within this distance of its recovery target the bot stops steering.
const RECOVER_DEADZONE := 14.0
## Failed pickups on one spot before the bot ignores food for a while.
const MAX_PICKUP_TRIES := 3
const PICKUP_BLOCK_TIME := 4.0
## Ledge: seconds hanging before an option is chosen is this many reaction times
## (never less than LEDGE_MIN_WAIT), a hard bot may ledge jump instead of climbing.
const LEDGE_WAIT_REACTIONS := 2.0
const LEDGE_MIN_WAIT := 0.3
const LEDGE_JUMP_CHANCE := 0.25
## Vertical strike windows for the up punch and the down-air spike (dy from the
## fighter to the opponent) and the horizontal window of both.
const UP_STRIKE_DY := Vector2(-175.0, -60.0)
const DOWN_STRIKE_DY := Vector2(60.0, 170.0)
const VERTICAL_STRIKE_DX := 80.0
## The side punch is for opponents above this damage % near a table end.
const SIDE_PUNCH_DAMAGE := 60.0
const SIDE_PUNCH_EDGE_DISTANCE := 140.0

var difficulty: CpuDifficulty
var plan: Plan = Plan.IDLE

var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _think_left := 0.0

# Last snapshot, refreshed on every decision.
var _stage: Dictionary = {}
var _blast: Dictionary = {}
var _me: Dictionary = {}
var _enemy: Dictionary = {}
var _ledges: Array = []
var _foods: Array = []
var _projectiles: Array = []
var _bombs: Array = []
var _my_number := 1

# Body geometry, read once from the fighter's own colliders and profile.
var _body_half_width := 28.0
var _feet_offset := 94.0
var _strike_height := 84.0
var _pickup_reach := 40.0

# Held flags.
var _move_x := 0.0
var _block_left := 0.0
var _jump_hold_left := 0.0
# Queued presses: time left before the press is dropped. 0.0 = nothing queued.
var _want_attack := 0.0
var _want_throw := 0.0
var _want_jump := 0.0
var _want_dash := 0.0
var _want_block := 0.0
var _want_special := 0.0
## Aim the queued attack is thrown with.
var _attack_aim: FighterIntent.Aim = FighterIntent.Aim.NEUTRAL
## Time left on a ledge decision (the option is being carried out).
var _ledge_decision := 0.0
## Where RECOVER steers (the stage center, or the hang point of a table leg).
var _recover_x := 0.0
var _hang_time := 0.0
# Direction the queued attack or throw must face (-1, 0, 1).
var _face_dir := 0
var _release_frame := false

var _threat_active := false
var _pickup_tries := 0
var _pickup_blocked_until := 0.0

# Shield meter discipline: true while the meter is below the release ratio (and has
# not climbed back above the hysteresis band), no shield is raised then.
var _shield_locked := false
# Punishing a dizzy opponent: decided once, when it goes dizzy.
var _enemy_was_dizzy := false
var _punishing := false
# How long the opponent has been shielding (the clock when it started, -1 when not)
# and whether the pressure roll for this stretch succeeded.
var _enemy_shield_since := -1.0
var _pressure_roll := false
# Direction of the bomb dodge in progress (0 = none).
var _dodge_dir := 0.0

## `rng_seed` makes a bot reproducible (tests); a negative value takes its seed
## from GameRng, which is random in real play and fixed once a test seeds it.
func _init(d: CpuDifficulty = null, rng_seed: int = -1) -> void:
	difficulty = d if d != null else CpuDifficulty.preset(CpuDifficulty.Level.NORMAL)
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.seed = GameRng.next_seed()

func kind_name() -> String:
	return "cpu"

func bind(f: Fighter) -> void:
	super.bind(f)
	_read_body_geometry()

func sample(delta: float) -> FighterIntent:
	var intent := FighterIntent.new()
	if fighter == null:
		return intent
	_clock += delta
	_think_left -= delta
	_hang_time = _hang_time + delta if _is_hanging() else 0.0
	# Falling off the stage cannot wait for a slow decision: a fighter that just
	# left the stage is noticed within the (shorter) recovery reaction time.
	if plan != Plan.RECOVER and _think_left > _recovery_interval() and _is_off_stage():
		_think_left = _recovery_interval()
	if _think_left <= 0.0:
		_think()
	_tick_timers(delta)
	_fill_intent(intent)
	return intent

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func _read_body_geometry() -> void:
	var body := fighter.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body and body.shape is RectangleShape2D:
		var size := (body.shape as RectangleShape2D).size
		_body_half_width = size.x / 2.0
		_feet_offset = body.position.y + size.y / 2.0
	var hurt_shape := fighter.get_node_or_null("Hurtbox/CollisionShape2D") as CollisionShape2D
	if hurt_shape and hurt_shape.shape is RectangleShape2D and fighter.profile:
		var hurt_h := (hurt_shape.shape as RectangleShape2D).size.y
		_strike_height = (hurt_h + fighter.profile.punch_hitbox_size.y) * 0.5 * 0.8
	# Walk to within 80% of the fighter's own pickup reach before pressing the key.
	if fighter.profile:
		_pickup_reach = fighter.profile.pickup_reach_x * 0.8

# ---------------------------------------------------------------------------
# Decision tick
# ---------------------------------------------------------------------------

func _think() -> void:
	_think_left = difficulty.decision_interval
	var game := fighter.get_parent()
	if game == null or not game.has_method("get_state_snapshot"):
		plan = Plan.IDLE
		_clear_flags()
		return
	var snap: Dictionary = game.get_state_snapshot()
	var fighters: Array = snap.get("fighters", [])
	_stage = snap.get("stage", {})
	if _stage.is_empty() or fighters.size() < 2:
		plan = Plan.IDLE
		_clear_flags()
		return
	_blast = snap.get("blast_zone", {})
	_ledges = snap.get("ledges", [])
	_foods = snap.get("foods", [])
	_projectiles = snap.get("projectiles", [])
	_bombs = snap.get("bombs", [])
	var my_index := 0 if game.get("fighter_1") == fighter else 1
	_my_number = my_index + 1
	_me = fighters[my_index]
	_enemy = fighters[1 - my_index]

	if _me.get("stocks", 0) <= 0 or _enemy.get("stocks", 0) <= 0:
		plan = Plan.IDLE
		_clear_flags()
		return

	_track_enemy()
	plan = _choose_plan()
	if plan == Plan.RECOVER:
		_think_left = _recovery_interval()

func _recovery_interval() -> float:
	return maxf(MIN_RECOVERY_INTERVAL, difficulty.decision_interval * RECOVERY_REACTION_FACTOR)

# Airborne and beside or below the stage, from the live fighter and the last
# stage rectangle.
func _is_off_stage() -> bool:
	if _stage.is_empty() or fighter.is_on_floor():
		return false
	var x := fighter.position.x
	var feet := fighter.position.y + _feet_offset
	return x < _stage.left or x > _stage.right or feet > _stage.top + 2.0

func _is_hanging() -> bool:
	return fighter.ledge_side != 0 and _state_name() == "LedgeHang"

func _choose_plan() -> Plan:
	if _plan_ledge():
		return Plan.LEDGE
	if _plan_recover():
		return Plan.RECOVER
	if _plan_dodge_bomb():
		return Plan.DODGE_BOMB
	if _plan_punish():
		return Plan.PUNISH
	if _plan_defend():
		return Plan.DEFEND
	if _plan_throw():
		return Plan.THROW
	if _plan_pickup():
		return Plan.PICKUP
	if _plan_attack():
		return Plan.ATTACK
	_plan_approach()
	return Plan.APPROACH

func _clear_flags() -> void:
	_move_x = 0.0
	_block_left = 0.0
	_jump_hold_left = 0.0
	_want_attack = 0.0
	_want_throw = 0.0
	_want_jump = 0.0
	_want_dash = 0.0
	_want_block = 0.0
	_want_special = 0.0
	_ledge_decision = 0.0
	_dodge_dir = 0.0

# --- LEDGE -----------------------------------------------------------------

# Hanging from a leg: after a short wait, climb (push toward the table), ledge jump
# (hard bots, now and then) or climb attack (an opponent waits at the landing
# spot). Only the keys a plain keyboard uses are pressed: no aim, no special.
func _plan_ledge() -> bool:
	if not _is_hanging():
		_ledge_decision = 0.0
		return false
	_block_left = 0.0
	var side: int = fighter.ledge_side
	if _ledge_decision > 0.0:
		return true # The option is already running.
	_move_x = 0.0
	var wait := maxf(LEDGE_MIN_WAIT, difficulty.decision_interval * LEDGE_WAIT_REACTIONS)
	if _hang_time < wait:
		return true
	_ledge_decision = 0.5
	var land_x: float = _me.position.x + float(-side) * (fighter.profile.ledge_climb_land_x + 34.0)
	var enemy_waits := absf(_enemy.position.x - land_x) < fighter.profile.ledge_attack_reach * 0.8 \
			and absf(_enemy.position.y - (_me.position.y - 150.0)) < 140.0
	_attack_aim = FighterIntent.Aim.NEUTRAL
	if enemy_waits and difficulty.use_directional and _rng.randf() < difficulty.action_accuracy:
		_want_attack = PRESS_PATIENCE
		_face_dir = 0
	elif difficulty.use_directional and difficulty.action_accuracy > 0.9 and _rng.randf() < LEDGE_JUMP_CHANCE:
		_move_x = float(-side)
		_want_jump = PRESS_PATIENCE
		_jump_hold_left = JUMP_HOLD
	else:
		_move_x = float(-side)
	return true

# --- RECOVER ---------------------------------------------------------------

# Airborne and either outside the stage, about to be, or still too low. It steers
# toward the stage or, when the stage is out of reach, toward the nearest table
# leg, and spends the double jump, the up-recovery and the air dash only when the
# current trajectory would reach neither.
func _plan_recover() -> bool:
	if _me.on_floor:
		return false
	var left: float = _stage.left
	var right: float = _stage.right
	var top: float = _stage.top
	var center := (left + right) * 0.5
	var x: float = _me.position.x
	var feet: float = _me.position.y + _feet_offset
	var vx: float = _me.velocity.x
	var vy: float = _me.velocity.y
	var profile := fighter.profile

	# Where horizontal speed would end if the bot only braked: catches a fighter
	# that is still inside but launched outward.
	var proj_x := x + vx * absf(vx) / (2.0 * profile.air_acceleration)
	var gap := maxf(left - proj_x, proj_x - right)
	var below := feet > top + 2.0
	var near_edge := x < left + _body_half_width or x > right - _body_half_width
	if gap <= 0.0 and not below and not near_edge:
		return false

	_block_left = 0.0
	_want_attack = 0.0
	_want_throw = 0.0
	_recover_x = center
	_move_x = signf(center - x)
	if gap <= 0.0 and not below:
		return true # Steering inward is enough.

	var t_land := _time_to_level(feet, vy, top)
	var stage_ok := not is_inf(t_land) and gap <= profile.run_speed * t_land * 0.85
	var ledge := _nearest_ledge(x)
	var ledge_ok := false
	if not ledge.is_empty():
		var hang_x: float = ledge.x + ledge.side * profile.ledge_hang_offset
		var hang_gap := maxf(0.0, absf(proj_x - hang_x) - profile.ledge_reach_x * 0.7)
		var t_zone := _time_to_level(feet, vy, ledge.bottom)
		ledge_ok = not is_inf(t_zone) and hang_gap <= profile.run_speed * t_zone * 0.85
		# The leg is the target once the stage cannot be reached (or the fighter is
		# already under the tabletop).
		if ledge_ok and (not stage_ok or below):
			_recover_x = hang_x
	if stage_ok or ledge_ok:
		return true

	# Neither is reachable on the current trajectory. Once the fighter is under the
	# stage it is in "last chance" focus: the miss chance shrinks to a third.
	var skill := difficulty.recovery_skill
	if below:
		skill = 1.0 - (1.0 - skill) * LAST_CHANCE_MISS_FACTOR
	if _rng.randf() >= skill:
		return true

	var urgent := _near_blast_side(x) or feet > top + _double_jump_rise() * 0.6
	var may_jump: bool = _me.jumps_left > 0 and vy >= -50.0 and (feet >= top - 30.0 or urgent)
	var may_recover: bool = difficulty.use_up_recovery and fighter.profile.can_recover \
			and _me.recovery_available and vy >= -50.0 and _me.jumps_left == 0
	var may_dash: bool = _me.air_dash_available and gap > 40.0 and feet <= top + 2.0 and vy >= -150.0
	if may_jump:
		_want_jump = PRESS_PATIENCE
		_jump_hold_left = JUMP_HOLD
	elif may_dash and not (may_recover and below):
		_want_dash = PRESS_PATIENCE
	elif may_recover:
		_want_special = PRESS_PATIENCE
	return true

# The table leg closest to `x` that is not taken by the opponent (an occupied leg
# would only be a trump), or {} when there is none.
func _nearest_ledge(x: float) -> Dictionary:
	var best := {}
	var best_distance := INF
	for ledge: Dictionary in _ledges:
		var distance := absf(x - float(ledge.x))
		if distance < best_distance:
			best_distance = distance
			best = ledge
	return best

# Seconds until the feet fall to `level` (a y), INF when they never get there.
func _time_to_level(feet: float, vy: float, level: float) -> float:
	var g := fighter.profile.gravity
	var fall_g := g * fighter.profile.fall_gravity_multiplier
	var t := 0.0
	var y := feet
	var v := vy
	if v < 0.0:
		t = -v / g
		y -= v * v / (2.0 * g)
		v = 0.0
	var drop := level - y
	if drop < 0.0:
		return INF
	return t + (-v + sqrt(v * v + 2.0 * fall_g * drop)) / fall_g

func _double_jump_rise() -> float:
	var v := fighter.profile.double_jump_velocity
	return v * v / (2.0 * fighter.profile.gravity)

# Close to the side blast zone (outside the stage and nearly out of the match).
func _near_blast_side(x: float) -> bool:
	if _blast.is_empty():
		return false
	var danger := _double_jump_rise() * 0.5
	return x < _blast.left + danger or x > _blast.right - danger

# --- Opponent tracking -------------------------------------------------------

# Once per decision: notices when the opponent goes dizzy (and rolls whether to
# punish it) and how long it has been shielding (and rolls the food pressure). The
# dice are only thrown at those moments, so a match without shields or dizzies draws
# exactly what it did before.
func _track_enemy() -> void:
	var enemy_state: StringName = _enemy.get("state", &"")
	var dizzy := enemy_state == &"Dizzy"
	if dizzy and not _enemy_was_dizzy:
		_punishing = _rng.randf() < difficulty.punish_dizzy_chance
	if not dizzy:
		_punishing = false
	_enemy_was_dizzy = dizzy
	if enemy_state == &"Protect":
		if _enemy_shield_since < 0.0:
			_enemy_shield_since = _clock
			_pressure_roll = _rng.randf() < difficulty.food_pressure_chance
	else:
		_enemy_shield_since = -1.0
		_pressure_roll = false

# The opponent has hidden behind its shield long enough to count as turtling.
func _enemy_turtling() -> bool:
	return _enemy_shield_since >= 0.0 and _clock - _enemy_shield_since >= difficulty.turtle_time

# --- DODGE_BOMB ----------------------------------------------------------------

# Hard only. A bomb that is above the bot and will go off within the lookahead and
# within reach: walk out of its blast (the nearest side that is on the stage and can
# be reached in time), or air dodge when airborne and it is about to land.
func _plan_dodge_bomb() -> bool:
	_dodge_dir = 0.0
	if not difficulty.bomb_dodge or _bombs.is_empty() or _stage.is_empty():
		return false
	var me_x: float = _me.position.x
	var me_y: float = _me.position.y
	var table_top: float = _stage.top
	var soonest := INF
	var threat := {}
	for bomb: Dictionary in _bombs:
		var fall_speed: float = bomb.velocity.y
		if fall_speed <= 0.0:
			continue
		var reach := float(bomb.radius) + BOMB_HURTBOX_HALF_WIDTH + difficulty.bomb_margin
		var dx: float = bomb.position.x - me_x
		if absf(dx) >= reach:
			continue
		# It goes off on the first thing it touches: this fighter's head if it falls
		# onto it, otherwise the table top.
		var impact_y := table_top - 22.0
		if absf(dx) < BOMB_HURTBOX_HALF_WIDTH + 22.0:
			impact_y = minf(impact_y, me_y - BOMB_IMPACT_HEIGHT)
		var time_left: float = (impact_y - float(bomb.position.y)) / fall_speed
		if time_left < 0.0 or time_left > difficulty.bomb_lookahead or time_left >= soonest:
			continue
		soonest = time_left
		threat = bomb
	if threat.is_empty():
		return false

	_block_left = 0.0
	_want_attack = 0.0
	_want_throw = 0.0
	_want_block = 0.0
	if not _me.on_floor and fighter.air_dodge_available and soonest <= BOMB_AIR_DODGE_TIME:
		_want_block = PRESS_PATIENCE
	var reach := float(threat.radius) + BOMB_HURTBOX_HALF_WIDTH + difficulty.bomb_margin
	var edge_margin := _body_half_width + 12.0
	var best_x := me_x
	var best_travel := INF
	for side in [-1.0, 1.0]:
		var target_x: float = float(threat.position.x) + side * reach
		if target_x < _stage.left + edge_margin or target_x > _stage.right - edge_margin:
			continue
		var travel := absf(target_x - me_x)
		# Prefer a side that can be reached in time, then the shorter walk.
		if travel / fighter.profile.run_speed > soonest:
			travel += 10000.0
		if travel < best_travel:
			best_travel = travel
			best_x = target_x
	if is_inf(best_travel):
		# No room on either side: at least move away from the bomb's column.
		best_x = me_x + signf(me_x - float(threat.position.x)) * reach
	_dodge_dir = signf(best_x - me_x)
	_move_x = _dodge_dir
	return true

# --- PUNISH --------------------------------------------------------------------

# The opponent's shield broke and the roll made when it went dizzy succeeded: walk
# over and hit it, no accuracy roll (the opponent cannot move). Tap punches only,
# neutral aim unless the difficulty uses directional punches.
func _plan_punish() -> bool:
	if not _punishing or _enemy.get("state", &"") != &"Dizzy":
		return false
	var dx: float = _enemy.position.x - _me.position.x
	var dy: float = _enemy.position.y - _me.position.y
	_face_dir = 1 if dx >= 0.0 else -1
	if absf(dy) < _strike_height and absf(dx) <= _strike_range():
		_move_x = 0.0
		if _me.cooldowns.punch <= 0.15:
			_want_attack = PRESS_PATIENCE
			_attack_aim = _horizontal_aim()
		return true
	_move_x = signf(dx)
	return true

# --- DEFEND ------------------------------------------------------------------

func _plan_defend() -> bool:
	var threat := _threat_present()
	var fresh := threat and not _threat_active
	_threat_active = threat
	# On the floor the shield must have meter left; in the air the dodge must be unspent.
	var can_block: bool = (not _shield_locked) if _me.on_floor else fighter.air_dodge_available
	if fresh and can_block and _rng.randf() < difficulty.block_chance:
		_block_left = difficulty.block_hold
		_want_block = PRESS_PATIENCE
	if _block_left > 0.0:
		_move_x = 0.0
		return true
	return false

func _threat_present() -> bool:
	var dx: float = _enemy.position.x - _me.position.x
	var dy: float = _enemy.position.y - _me.position.y
	var enemy_faces_me: bool = _enemy.facing == (1 if dx < 0.0 else -1)
	if _enemy.state == &"Punch" and enemy_faces_me \
			and absf(dx) < _strike_range() + 40.0 and absf(dy) < _strike_height + 30.0:
		return true
	for p in _projectiles:
		if p.shooter == _my_number:
			continue
		var pdx: float = p.position.x - _me.position.x
		var closing: bool = p.velocity.x * pdx < 0.0
		if closing and absf(pdx) < 160.0 and absf(p.position.y - _me.position.y) < 90.0:
			return true
	return false

# --- THROW and PICKUP --------------------------------------------------------

func _plan_throw() -> bool:
	if _me.held_food == "":
		return false
	var dx: float = _enemy.position.x - _me.position.x
	var dy: float = _enemy.position.y - _me.position.y
	if absf(dy) >= 80.0 or absf(dx) > difficulty.throw_range:
		return false
	# A shielding opponent is pressured with food more often than an open one.
	var chance := difficulty.throw_chance
	if _enemy.get("state", &"") == &"Protect":
		chance = maxf(chance, difficulty.food_pressure_chance)
	if _rng.randf() >= chance:
		return false
	_face_dir = 1 if dx >= 0.0 else -1
	_want_throw = PRESS_PATIENCE
	_move_x = 0.0
	return true

func _plan_pickup() -> bool:
	if _me.held_food != "":
		_pickup_tries = 0
		return false
	if _foods.is_empty() or _clock < _pickup_blocked_until:
		return false
	var x: float = _me.position.x
	var enemy_distance := absf(_enemy.position.x - x)
	# Against a turtle the bot looks twice as far, prefers heavy food (it takes a
	# shield down fastest) and no longer needs the food to be closer than the opponent.
	var pressuring := _enemy_turtling() and _pressure_roll
	var seek := difficulty.pickup_seek_distance * (2.0 if pressuring else 1.0)
	var best_dx := INF
	var best_weight := -1
	for food in _foods:
		var fdx: float = food.position.x - x
		var inside: bool = food.position.x >= _stage.left and food.position.x <= _stage.right
		var reachable: bool = absf(food.position.y - _me.position.y) < 140.0
		if not inside or not reachable:
			continue
		var weight: int = FoodCatalog.get_weight_class(food.get("name", "")) if pressuring else 0
		if weight > best_weight or (weight == best_weight and absf(fdx) < absf(best_dx)):
			best_weight = weight
			best_dx = fdx
	if is_inf(best_dx) or absf(best_dx) > seek or (not pressuring and absf(best_dx) >= enemy_distance):
		return false
	if absf(best_dx) > _pickup_reach:
		_move_x = signf(best_dx)
		return true
	_move_x = 0.0
	_want_throw = PRESS_PATIENCE
	_face_dir = 0
	_pickup_tries += 1
	if _pickup_tries >= MAX_PICKUP_TRIES:
		_pickup_tries = 0
		_pickup_blocked_until = _clock + PICKUP_BLOCK_TIME
	return true

# --- ATTACK and APPROACH -------------------------------------------------------

func _strike_range() -> float:
	var profile := fighter.profile
	return profile.punch_reach + profile.punch_hitbox_size.x * 0.5 + STRIKE_SLACK

func _plan_attack() -> bool:
	var dx: float = _enemy.position.x - _me.position.x
	var dy: float = _enemy.position.y - _me.position.y
	_attack_aim = FighterIntent.Aim.NEUTRAL
	if difficulty.use_directional and _plan_vertical_attack(dx, dy):
		return true
	var strike := _strike_range()
	if absf(dy) >= _strike_height or absf(dx) > strike * WHIFF_RANGE_FACTOR:
		return false
	_face_dir = 1 if dx >= 0.0 else -1
	if absf(dx) <= strike:
		_move_x = 0.0
		if _me.cooldowns.punch <= 0.15 and _rng.randf() < difficulty.action_accuracy:
			_want_attack = PRESS_PATIENCE
			_attack_aim = _horizontal_aim()
		return true
	# Too far for a real hit: a low-accuracy bot swings anyway and whiffs.
	if _me.cooldowns.punch <= 0.15 and _rng.randf() < (1.0 - difficulty.action_accuracy) * 0.5:
		_move_x = 0.0
		_want_attack = PRESS_PATIENCE
		return true
	return false

# The side punch is kept for a damaged opponent close to a table end, where its
# long launch is a ring-out; otherwise the ordinary punch.
func _horizontal_aim() -> FighterIntent.Aim:
	if not difficulty.use_directional or float(_enemy.damage_percent) < SIDE_PUNCH_DAMAGE:
		return FighterIntent.Aim.NEUTRAL
	var edge_distance := minf(absf(_enemy.position.x - float(_stage.left)), absf(_enemy.position.x - float(_stage.right)))
	return FighterIntent.Aim.SIDE if edge_distance < SIDE_PUNCH_EDGE_DISTANCE else FighterIntent.Aim.NEUTRAL

# Up punch at an opponent just above, the spike on one just below while airborne.
func _plan_vertical_attack(dx: float, dy: float) -> bool:
	if absf(dx) > VERTICAL_STRIKE_DX:
		return false
	var aim := FighterIntent.Aim.NEUTRAL
	if dy > UP_STRIKE_DY.x and dy < UP_STRIKE_DY.y:
		aim = FighterIntent.Aim.UP
	elif not _me.on_floor and dy > DOWN_STRIKE_DY.x and dy < DOWN_STRIKE_DY.y:
		aim = FighterIntent.Aim.DOWN
	if aim == FighterIntent.Aim.NEUTRAL:
		return false
	_face_dir = 1 if dx >= 0.0 else -1
	_move_x = 0.0
	if _me.cooldowns.punch <= 0.15 and _rng.randf() < difficulty.action_accuracy:
		_want_attack = PRESS_PATIENCE
		_attack_aim = aim
	return true

func _plan_approach() -> void:
	var edge_margin := _body_half_width + 12.0
	var target_x := clampf(_enemy.position.x, _stage.left + edge_margin, _stage.right - edge_margin)
	var gap: float = target_x - _me.position.x
	_face_dir = 0
	if absf(gap) > difficulty.approach_stop_distance and _rng.randf() < difficulty.aggression:
		_move_x = signf(gap)
	else:
		_move_x = 0.0

	# An enemy hovering above and close by: hop at it.
	var dx: float = _enemy.position.x - _me.position.x
	var dy: float = _enemy.position.y - _me.position.y
	if _me.on_floor and dy < -(_strike_height + 20.0) and absf(dx) < 160.0 \
			and _rng.randf() < difficulty.action_accuracy:
		_want_jump = PRESS_PATIENCE
		_jump_hold_left = JUMP_HOLD

# ---------------------------------------------------------------------------
# Per-frame output
# ---------------------------------------------------------------------------

func _tick_timers(delta: float) -> void:
	_block_left = maxf(0.0, _block_left - delta)
	_jump_hold_left = maxf(0.0, _jump_hold_left - delta)
	_want_attack = maxf(0.0, _want_attack - delta)
	_want_throw = maxf(0.0, _want_throw - delta)
	_want_jump = maxf(0.0, _want_jump - delta)
	_want_dash = maxf(0.0, _want_dash - delta)
	_want_block = maxf(0.0, _want_block - delta)
	_want_special = maxf(0.0, _want_special - delta)
	_ledge_decision = maxf(0.0, _ledge_decision - delta)

func _state_name() -> String:
	var machine = fighter.state_machine
	if machine == null or machine.current_state == null:
		return ""
	return String(machine.current_state.name)

# The shield is released when the meter reaches the difficulty's release ratio and
# only raised again once it has climbed back SHIELD_HYSTERESIS above it. Checked
# every frame, not only at decisions: a hold drains the meter between them.
func _update_shield_lock() -> void:
	var ratio: float = fighter.shield.ratio()
	if _shield_locked:
		if ratio >= difficulty.shield_release_ratio + SHIELD_HYSTERESIS:
			_shield_locked = false
	elif ratio <= difficulty.shield_release_ratio:
		_shield_locked = true

func _fill_intent(intent: FighterIntent) -> void:
	var state := _state_name()
	var locked := NO_ACTION_STATES.has(state)
	_update_shield_lock()
	var shield_off := _shield_locked and fighter.is_on_floor()
	if locked or shield_off:
		_block_left = 0.0
	if shield_off:
		_want_block = 0.0

	var move := _move_x
	if plan == Plan.RECOVER and not _stage.is_empty():
		var to_target := _recover_x - fighter.position.x
		move = signf(to_target) if absf(to_target) > RECOVER_DEADZONE else 0.0
	# A queued attack or throw needs the fighter to face the target; walking a
	# frame toward it turns the fighter (facing follows the move input).
	if (_want_attack > 0.0 or _want_throw > 0.0) and _face_dir != 0 and fighter.facing != _face_dir:
		move = float(_face_dir)
	intent.move_x = _guard_edge(move)

	intent.jump_held = _jump_hold_left > 0.0
	intent.block_held = _block_left > 0.0
	intent.attack_held = false

	if _release_frame:
		_release_frame = false
		return
	if locked:
		return

	# One press per frame, by priority; the rest wait (or expire). A press is only
	# emitted when the current state accepts that action, so a queued jump is not
	# swallowed by a punch that is still running.
	if _want_jump > 0.0 and _accepts("jump"):
		intent.jump_pressed = true
		intent.jump_held = true
		_want_jump = 0.0
	elif _want_special > 0.0 and _accepts("recovery"):
		intent.special_pressed = true
		intent.aim = FighterIntent.Aim.UP
		_want_special = 0.0
	elif _want_dash > 0.0 and _accepts("dash"):
		intent.dash_pressed = true
		_want_dash = 0.0
	elif _want_block > 0.0 and (_accepts("protect") or _accepts("air_dodge")):
		intent.block_pressed = true
		intent.block_held = true
		_want_block = 0.0
	elif _want_throw > 0.0 and _accepts("shoot") and _facing_ok():
		intent.throw_pressed = true
		_want_throw = 0.0
	elif _want_attack > 0.0 and _accepts("punch") and _facing_ok():
		intent.attack_pressed = true
		intent.aim = _attack_aim
		_want_attack = 0.0
	else:
		return
	_release_frame = true

# Whether the current state lists `action` (see Motion.available_actions).
func _accepts(action: String) -> bool:
	var machine = fighter.state_machine
	if machine == null or machine.current_state == null:
		return false
	var actions = machine.current_state.get("available_actions")
	return actions != null and actions.has(action)

func _facing_ok() -> bool:
	return _face_dir == 0 or fighter.facing == _face_dir

# While grounded the bot never walks off the stage: movement toward an edge stops
# once the body (plus the distance it needs to brake) reaches it.
func _guard_edge(move: float) -> float:
	if move == 0.0 or _stage.is_empty() or not fighter.is_on_floor():
		return move
	var accel := fighter.profile.ground_acceleration
	var brake := fighter.velocity.x * absf(fighter.velocity.x) / (2.0 * accel)
	var x := fighter.position.x + brake
	if move > 0.0 and x > _stage.right - _body_half_width:
		return 0.0
	if move < 0.0 and x < _stage.left + _body_half_width:
		return 0.0
	return move
