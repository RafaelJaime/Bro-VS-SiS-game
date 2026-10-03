extends Node2D
class_name SuddenDeathHazards

## Sudden-death escalation (Smash Ultimate style). `Game` owns this node at its
## origin, so every bomb is Game-local and rows at different offsets (train.tscn)
## never share or cross-hit bombs. It holds no global state.
##
## Schedule, all counted in physics ticks (CombatClock), never in `Timer`s, so
## hit-stop changes nothing: a grace period with no bombs, then the n-th spawn waits
## `max(floor, round(start * decay^n))` ticks after the previous one, never more than
## `max_alive` at once. A share of the bombs (`target_chance`) falls above a fighter
## (jittered), the rest anywhere over the table, so an idle or turtling fighter is
## KO'd in seconds while one that moves can dodge. Bombs are unblockable and, at the
## 300% sudden death starts with, lethal (see Bomb).
##
## A real match has no cap. In training only, `training_cap_reached` fires once when
## the elapsed time reaches `training_cap`, so a row can end its episode.

signal training_cap_reached

@export var bomb_scene: PackedScene
## Seconds of sudden death before the first bomb, then the spawn interval: starts at
## `start_interval`, is multiplied by `interval_decay` after every spawn and never
## drops below `min_interval`.
@export var grace_time: float = 20.0
@export var start_interval: float = 2.0
@export var interval_decay: float = 0.88
@export var min_interval: float = 0.4
@export var max_alive: int = 6
## Chance that a bomb falls above a fighter (within `target_jitter` px).
@export_range(0.0, 1.0) var target_chance: float = 0.6
@export var target_jitter: float = 60.0
## Spawn height above the table top, and the fall speed: the fall takes
## fall_height / fall_speed seconds, which is the telegraph (at least `min_telegraph`).
@export var fall_height: float = 760.0
@export var fall_speed: float = 420.0
@export var min_telegraph: float = 1.0
@export var explosion_radius: float = 90.0
@export var bomb_damage: float = 12.0
@export var bomb_knockback: Vector2 = Vector2(120.0, -560.0)
## Training safety cap, seconds after sudden death starts.
@export var training_cap: float = 60.0

## Ticks since `begin()` (0 while inactive).
var elapsed_ticks: int = 0
## Ticks between consecutive spawns, in order (tests read it).
var spawn_intervals: Array[int] = []
var bombs_spawned: int = 0

var _active: bool = false
var _next_spawn_tick: int = 0
var _target_index: int = 0
var _cap_emitted: bool = false
var _rng := RandomNumberGenerator.new()

## True in a training row (read by Sfx.is_training through the bombs).
var training: bool:
	get:
		var game := get_parent()
		return game != null and game.get("training") == true

## Starts the escalation: the grace period begins now. Clears any bomb left over.
## The generator is seeded here (from GameRng, so a seeded run is reproducible)
## and not earlier, so a regulation match draws nothing extra from GameRng.
func begin() -> void:
	stop_and_clear()
	_rng.seed = GameRng.next_seed()
	_target_index = 0
	_active = true
	elapsed_ticks = 0
	bombs_spawned = 0
	spawn_intervals.clear()
	_next_spawn_tick = CombatClock.ticks(grace_time)
	_cap_emitted = false

## Stops the escalation and frees every bomb and explosion effect (match end, row
## reset, a new sudden death).
func stop_and_clear() -> void:
	_active = false
	elapsed_ticks = 0
	for child in get_children():
		child.queue_free()

func is_active() -> bool:
	return _active

## 0 when idle, 1 during the grace period, 2 once bombs fall.
func phase() -> int:
	if not _active:
		return 0
	return 1 if elapsed_ticks < CombatClock.ticks(grace_time) else 2

func elapsed_seconds() -> float:
	return CombatClock.seconds(elapsed_ticks)

## Seeds this node's own generator (tests make two Games identical).
func seed_rng(value: int) -> void:
	_rng.seed = value

func _physics_process(_delta: float) -> void:
	if not _active:
		return
	elapsed_ticks += 1
	if training and not _cap_emitted and elapsed_ticks >= CombatClock.ticks(training_cap):
		_cap_emitted = true
		training_cap_reached.emit()
	if elapsed_ticks >= _next_spawn_tick and alive_count() < max_alive:
		spawn_bomb(_pick_x())
		var interval := maxi(CombatClock.ticks(min_interval), roundi(CombatClock.ticks(start_interval) * pow(interval_decay, bombs_spawned - 1)))
		spawn_intervals.append(interval)
		_next_spawn_tick = elapsed_ticks + interval

## Bombs currently falling.
func alive_count() -> int:
	var count := 0
	for child in get_children():
		if child is Bomb and not child.is_queued_for_deletion():
			count += 1
	return count

## Seconds a bomb takes from its spawn height to the table top.
func telegraph_seconds() -> float:
	return fall_height / fall_speed

## Drops a bomb above `x` (Game-local) now. `from_y` overrides the spawn height
## (Game-local y; NAN uses the default above the table).
func spawn_bomb(x: float, from_y: float = NAN) -> Bomb:
	if bomb_scene == null:
		return null
	var game := get_parent()
	var stage: Dictionary = game.get_stage_bounds()
	var bomb: Bomb = bomb_scene.instantiate()
	bomb.fall_speed = fall_speed
	bomb.explosion_radius = explosion_radius
	bomb.damage = bomb_damage
	bomb.knockback = bomb_knockback
	bomb.stage_top = stage["top"]
	bomb.stage_left = stage["left"]
	bomb.stage_right = stage["right"]
	bomb.stage_center_x = to_global(Vector2((stage["left"] + stage["right"]) / 2.0, 0.0)).x
	bomb.blast_bottom = game.blast_bottom
	bomb.visuals = not training
	bomb.fighters = [game.fighter_1, game.fighter_2]
	bomb.spawn_y = from_y if not is_nan(from_y) else stage["top"] - fall_height
	bomb.position = Vector2(clampf(x, stage["left"], stage["right"]), bomb.spawn_y)
	add_child(bomb)
	bombs_spawned += 1
	return bomb

# A fighter's x (round-robin over the fighters still alive, jittered) with
# `target_chance`, otherwise uniform over the table. Drawn from this node's own
# generator, so a run is reproducible.
func _pick_x() -> float:
	var game := get_parent()
	var stage: Dictionary = game.get_stage_bounds()
	var targets: Array = []
	for fighter in [game.fighter_1, game.fighter_2]:
		if fighter != null and fighter.stocks > 0:
			targets.append(fighter)
	var uniform_x := _rng.randf_range(stage["left"], stage["right"])
	if targets.is_empty() or _rng.randf() >= target_chance:
		return uniform_x
	var target: Fighter = targets[_target_index % targets.size()]
	_target_index += 1
	return target.position.x + _rng.randf_range(-target_jitter, target_jitter)

## The falling bombs for the Game snapshot: Game-local position and velocity.
func snapshot_bombs() -> Array:
	var game := get_parent()
	var bombs: Array = []
	for child in get_children():
		if child is Bomb and not child.is_queued_for_deletion():
			bombs.append({
				"position": game.to_local(child.global_position),
				"velocity": child.velocity(),
				"radius": explosion_radius,
			})
	return bombs
