class_name FighterIntent
extends RefCounted

## What a fighter wants to do this physics frame. Produced by a
## FighterController (human input, scripted CPU or RL policy) and consumed by
## the state machine through `Fighter.intent`. States never read input
## devices or AI controllers directly.
##
## Every field defaults to neutral, so `FighterIntent.new()` means "do nothing".
## Fields marked S5 are declared now but stay inert until the smash-moves slice.

enum Aim { NEUTRAL, UP, DOWN, SIDE }

var move_x: float = 0.0 # -1..1
var jump_pressed := false # Edge (the Policy adapter guards this, see PolicyController).
var jump_held := false
var attack_pressed := false
var attack_held := false # S5 charge. Policy and scripted controllers keep it false.
var attack_released := false # S5.
var throw_pressed := false # Pick up or throw food (the "shoot" action).
var block_pressed := false
var block_held := false
var dash_pressed := false # Human: double-tap. Direction comes from move_x (or facing).
var aim: Aim = Aim.NEUTRAL # S5.
var special_pressed := false # S5 recovery request.
