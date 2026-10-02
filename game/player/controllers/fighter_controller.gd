class_name FighterController
extends RefCounted

## Source of a fighter's FighterIntent. A Fighter owns exactly one controller
## and samples it once per physics frame. Subclasses: HumanController,
## PolicyController and ScriptedController (the CPU).

var fighter: Fighter

func bind(f: Fighter) -> void:
	fighter = f

func sample(_delta: float) -> FighterIntent:
	return FighterIntent.new()

func kind_name() -> String:
	return "none"
