class_name RewardConfig
extends Resource

## Reward weights of a training agent. Plain data: the defaults live here, and
## BVS_TRAIN_CONFIG.reward can override any of them with no code change. Weights
## are signed (a penalty is negative) and are applied by RewardTracker.

## Per percent of damage dealt to / taken from the opponent.
@export var damage_dealt: float = 0.01
@export var damage_taken: float = -0.01
## Per stock taken from the opponent.
@export var ko_given: float = 1.0
## Per stock lost: split in two terms (ko_taken + stock_lost = -1.0) so each is
## logged on its own and can be tuned separately.
@export var ko_taken: float = -0.5
@export var stock_lost: float = -0.5
## Match resolution by elimination.
@export var win: float = 3.0
@export var loss: float = -3.0
## Time up with both fighters alive: this weight times the sign of the stock
## difference.
@export var timeout: float = 0.5
## Per decision (one every ACTION_REPEAT physics frames).
@export var time: float = -0.001
## Per decision while off the stage.
@export var off_stage: float = -0.002
## Potential-based shaping: this weight times the closed horizontal distance
## (previous |dx| minus |dx|, over the stage half width) per decision.
@export var approach: float = 0.02

## The terms in the order they are logged.
const TERMS: PackedStringArray = [
	"damage_dealt", "damage_taken", "ko_given", "ko_taken", "stock_lost",
	"win", "loss", "timeout", "time", "off_stage", "approach",
]

## A config with the weights found in `data` (a Dictionary from BVS_TRAIN_CONFIG).
## An unknown or non-numeric key is reported by name and ignored.
static func from_dict(data: Dictionary) -> RewardConfig:
	var config := RewardConfig.new()
	for key: Variant in data.keys():
		if not TERMS.has(String(key)):
			push_error("RewardConfig: unknown reward weight '%s'" % str(key))
			continue
		var value: Variant = data[key]
		if not (value is float or value is int):
			push_error("RewardConfig: reward weight '%s' must be a number" % str(key))
			continue
		config.set(String(key), float(value))
	return config
