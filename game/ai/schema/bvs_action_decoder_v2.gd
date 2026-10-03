class_name BvsActionDecoderV2
extends RefCounted

## Turns bvs-schema-2 branch indices into a FighterIntent, one physics frame at a
## time. Stateful: `begin_window(indices)` starts a decision window (ACTION_REPEAT
## frames), then `frame(fighter)` is called once per physics frame.
##
## Held flags (move, vertical aim, jump, block) last the whole window. Pressed
## flags (attack, special, throw, dash, and the jump / block presses) fire only on
## the first frame of the window. The same decoder runs in training and in play,
## so the frame-level semantics are identical.
##
##   a0_move      left / none / right      move_x -1 / 0 / +1
##   a1_vertical  none / up / down         held aim UP / DOWN
##   a2_jump      release / hold           jump_held; jump_pressed on the first
##                                         frame when the previous decision was
##                                         release or the fighter is on the floor
##   a3_attack    none / neutral / up / down / side
##                                         attack_pressed with that aim (first frame)
##   a4_special   no / yes                 special_pressed with aim UP (first frame),
##                                         overriding a3_attack
##   a5_throw     no / yes                 throw_pressed (first frame)
##   a6_block     no / yes                 block_held; block_pressed on a rising edge
##   a7_dash      no / yes                 dash_pressed (first frame)
## attack_held and attack_released stay false: no charged smash in schema 2.

const MOVE := 0
const VERTICAL := 1
const JUMP := 2
const ATTACK := 3
const SPECIAL := 4
const THROW := 5
const BLOCK := 6
const DASH := 7

## Aim of attack values 1..4 (index 0, "none", never presses).
const ATTACK_AIMS: Array[FighterIntent.Aim] = [
	FighterIntent.Aim.NEUTRAL,
	FighterIntent.Aim.NEUTRAL,
	FighterIntent.Aim.UP,
	FighterIntent.Aim.DOWN,
	FighterIntent.Aim.SIDE,
]

var _indices := PackedInt32Array()
var _valid := false
var _tick := 0
var _prev_jump := false
var _prev_block := false

## Starts a decision window. Returns "" on success, otherwise the reason the
## vector was rejected (also reported with push_error); a rejected window decodes
## to neutral intents until the next valid one.
func begin_window(indices: PackedInt32Array) -> String:
	_tick = 0
	_valid = false
	var problem := _check(indices)
	if problem != "":
		push_error("BvsActionDecoderV2: " + problem)
		_prev_jump = false
		_prev_block = false
		return problem
	_indices = indices
	_valid = true
	return ""

## The intent of the current physics frame of the window.
func frame(fighter: Fighter) -> FighterIntent:
	var intent := FighterIntent.new()
	if not _valid:
		return intent
	var first := _tick == 0
	_tick += 1

	intent.move_x = float(_indices[MOVE] - 1)
	match _indices[VERTICAL]:
		1:
			intent.aim = FighterIntent.Aim.UP
		2:
			intent.aim = FighterIntent.Aim.DOWN

	var jump := _indices[JUMP] == 1
	intent.jump_held = jump
	if first:
		intent.jump_pressed = jump and (not _prev_jump or (fighter != null and fighter.is_on_floor()))
		_prev_jump = jump

	var block := _indices[BLOCK] == 1
	intent.block_held = block
	if first:
		intent.block_pressed = block and not _prev_block
		_prev_block = block

	if first:
		if _indices[SPECIAL] == 1:
			intent.special_pressed = true
			intent.aim = FighterIntent.Aim.UP
		elif _indices[ATTACK] > 0:
			intent.attack_pressed = true
			intent.aim = ATTACK_AIMS[_indices[ATTACK]]
		intent.throw_pressed = _indices[THROW] == 1
		intent.dash_pressed = _indices[DASH] == 1
	return intent

func _check(indices: PackedInt32Array) -> String:
	if indices.size() != BvsSchemaV2.BRANCHES.size():
		return "an action needs %d branches, got %d" % [BvsSchemaV2.BRANCHES.size(), indices.size()]
	for i in indices.size():
		var size: int = BvsSchemaV2.BRANCHES[i]["size"]
		if indices[i] < 0 or indices[i] >= size:
			return "branch %s index %d is outside 0..%d" % [BvsSchemaV2.BRANCHES[i]["name"], indices[i], size - 1]
	return ""
