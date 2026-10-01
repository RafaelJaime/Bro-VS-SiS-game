class_name FighterShadows
extends Node2D

## Smash-style ground shadows: a dark ellipse on the tabletop under each fighter
## that stands over the table. It shrinks and fades as the fighter rises, so a
## jump reads as height. Drawn with the table, behind the fighters.

## Half size of the shadow of a fighter standing on the table.
const BASE_RADIUS := Vector2(46.0, 8.0)
const BASE_ALPHA := 0.4
## Height above the tabletop at which the shadow reaches its smallest size.
const FADE_HEIGHT := 520.0
const MIN_SCALE := 0.35
## A fighter this far under the tabletop already fell off the table.
const BELOW_TOLERANCE := 6.0

var _table: TableStage
var _fighters: Array[Fighter] = []

func _ready() -> void:
	_table = get_parent() as TableStage
	for child in _table.get_parent().get_children():
		if child is Fighter:
			_fighters.append(child)

func _process(_delta: float) -> void:
	queue_redraw()

## Shadow of `fighter` as {center, radius, alpha}, or an empty dictionary when
## it is not over the table (off an end, below the tabletop, or out of play).
func shadow_for(fighter: Fighter) -> Dictionary:
	if _table == null or not is_instance_valid(fighter) or fighter.stocks <= 0:
		return {}
	var feet_y := fighter.position.y + _feet_offset(fighter)
	if feet_y > _table.top_y + BELOW_TOLERANCE:
		return {}
	var x := fighter.position.x
	if x < _table.left_x or x > _table.right_x:
		return {}
	var height := maxf(0.0, _table.top_y - feet_y)
	var scale := clampf(1.0 - height / FADE_HEIGHT, MIN_SCALE, 1.0)
	return {
		"center": Vector2(x, _table.top_y + 2.0),
		"radius": BASE_RADIUS * scale,
		"alpha": BASE_ALPHA * scale,
	}

# Distance from the fighter's origin to the bottom of its movement body.
func _feet_offset(fighter: Fighter) -> float:
	var shape_node := fighter.get_node("CollisionShape2D") as CollisionShape2D
	var rect := shape_node.shape as RectangleShape2D
	return shape_node.position.y + rect.size.y / 2.0

func _draw() -> void:
	for fighter in _fighters:
		var shadow := shadow_for(fighter)
		if shadow.is_empty():
			continue
		draw_colored_polygon(TableStage._ellipse(shadow["center"], shadow["radius"]), Color(0.0, 0.0, 0.0, shadow["alpha"]))
