class_name CpuDifficulty
extends Resource

## Tunable personality of the scripted CPU (Smash-style CPU levels). Every field
## is plain data: edit a value here, or drop a CpuDifficulty `.tres` into
## `ControllerConfig.difficulty_resource`, and the bot changes with no script
## change. `preset(level)` holds the shipped defaults.

enum Level { EASY, NORMAL, HARD }

@export_group("Reaction")
## Seconds between two decisions. This is the bot's reaction time: Easy reads
## the match only 2.5 times a second, Hard more than 8 times.
@export var decision_interval: float = 0.22
## Chance, per decision, that the bot commits to an attack that is in range.
## Below 1.0 it hesitates, and it also swings early from too far (a whiff).
@export_range(0.0, 1.0) var action_accuracy: float = 0.80
## Chance, per decision while the opponent is far, that the bot closes in
## instead of standing still.
@export_range(0.0, 1.0) var aggression: float = 0.85

@export_group("Defence and items")
## Chance to start blocking once per incoming threat (a punch or a thrown food).
@export_range(0.0, 1.0) var block_chance: float = 0.40
## Seconds a started block is held.
@export var block_hold: float = 0.45
## Chance, per decision, to throw the held food when the opponent is in line.
@export_range(0.0, 1.0) var throw_chance: float = 0.60
## Farthest opponent the bot throws food at.
@export var throw_range: float = 380.0
## Food farther than this is ignored (it must also be closer than the opponent).
@export var pickup_seek_distance: float = 220.0

@export_group("Spacing")
## The bot stops walking toward the opponent at this distance.
@export var approach_stop_distance: float = 60.0

@export_group("Recovery")
## Chance, per recovery decision, that the bot uses its double jump or air dash
## when it is needed. Easy often fumbles it, Hard never does.
@export_range(0.0, 1.0) var recovery_skill: float = 0.97

## Shipped defaults for the three levels. Reaction delay is ordered
## Easy > Normal > Hard and accuracy the other way round.
static func preset(level: Level) -> CpuDifficulty:
	var d := CpuDifficulty.new()
	match level:
		Level.EASY:
			d.decision_interval = 0.40
			d.action_accuracy = 0.55
			d.aggression = 0.60
			d.block_chance = 0.15
			d.block_hold = 0.35
			d.throw_chance = 0.30
			d.pickup_seek_distance = 120.0
			d.approach_stop_distance = 75.0
			d.recovery_skill = 0.60
		Level.HARD:
			d.decision_interval = 0.12
			d.action_accuracy = 0.95
			d.aggression = 1.0
			d.block_chance = 0.70
			d.block_hold = 0.55
			d.throw_chance = 0.85
			d.pickup_seek_distance = 320.0
			d.approach_stop_distance = 55.0
			d.recovery_skill = 1.0
		_:
			pass # NORMAL: the field defaults above.
	return d

## Maps a plain int (ControllerConfig.difficulty) to a level, clamped.
static func level_from_int(value: int) -> Level:
	return clampi(value, Level.EASY, Level.HARD) as Level
