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
## Combat-depth terms, all driven by signals (never by observation reads).
## Per food picked up (at most `pickup_cap` per episode, so hoarding is not farmed).
@export var pickup: float = 0.05
## Per thrown food of mine that reached the opponent (blocked or not, never ignored).
@export var food_hit: float = 0.15
## Per opponent shield broken by one of my hits / per shield of mine that broke
## (a hit or the hold drain).
@export var shield_break_dealt: float = 0.4
@export var shield_break_taken: float = -0.4
## Per decision while my shield has been held longer than `shield_hold_threshold`.
@export var shield_hold: float = -0.003
## Character-kits terms, signal driven. Per extra hit (hits >= 2) of a combo I deal,
## at most `combo_hit_cap` extra hits per combo and `combo_episode_cap` in total per
## episode, so jab restarts are not farmed.
@export var combo_hit: float = 0.02
## Per shield raise of mine (Fighter.shield_raises delta, read per decision). Zero in
## code so behavior is unchanged without a config; default.toml sets the lever.
@export var shield_raise: float = 0.0

## Non-term parameters (accepted by from_dict, never logged as a term).
## Seconds of continuous shielding before `shield_hold` starts to apply.
@export var shield_hold_threshold: float = 1.5
## Pickups rewarded per episode.
@export var pickup_cap: int = 20
## Extra combo hits rewarded per combo.
@export var combo_hit_cap: int = 4
## Total `combo_hit` reward per episode.
@export var combo_episode_cap: float = 1.0

## The terms in the order they are logged.
const TERMS: PackedStringArray = [
	"damage_dealt", "damage_taken", "ko_given", "ko_taken", "stock_lost",
	"win", "loss", "timeout", "time", "off_stage", "approach",
	"pickup", "food_hit", "shield_break_dealt", "shield_break_taken", "shield_hold",
	"combo_hit", "shield_raise",
]

## Settings that are not reward terms but live in the same `reward` block.
const PARAMS: PackedStringArray = ["shield_hold_threshold", "pickup_cap", "combo_hit_cap", "combo_episode_cap"]

## A config with the weights found in `data` (a Dictionary from BVS_TRAIN_CONFIG).
## An unknown or non-numeric key is reported by name and ignored.
static func from_dict(data: Dictionary) -> RewardConfig:
	var config := RewardConfig.new()
	for key: Variant in data.keys():
		if not TERMS.has(String(key)) and not PARAMS.has(String(key)):
			push_error("RewardConfig: unknown reward weight '%s'" % str(key))
			continue
		var value: Variant = data[key]
		if not (value is float or value is int):
			push_error("RewardConfig: reward weight '%s' must be a number" % str(key))
			continue
		if String(key) == "pickup_cap" or String(key) == "combo_hit_cap":
			config.set(String(key), int(value))
		else:
			config.set(String(key), float(value))
	return config
