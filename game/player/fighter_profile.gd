class_name FighterProfile
extends Resource

## Per-fighter tuning and moveset flags (the "kit" seam).
##
## Future per-character kits (Smash-style) supply a different FighterProfile
## to a Fighter; no state code may hardcode these values, it must read them
## from `owner.profile`. Defaults reproduce the pre-overhaul baseline exactly,
## and both characters currently share the same defaults.

@export_group("Movement")
@export var run_speed: float = 300.0
@export var acceleration: float = 1000.0
@export var jump_velocity: float = -600.0
@export var gravity: float = 500.0
@export var dash_speed: float = 600.0
@export var dash_duration: float = 0.3

@export_group("Weight")
## Multiplier applied on top of the damage-% knockback scaling. Above 1.0 the
## fighter is launched farther (lighter), below 1.0 it is heavier.
@export var knockback_scale: float = 1.0

@export_group("Punch")
@export var punch_damage: float = 8.0
@export var punch_knockback: Vector2 = Vector2(220, -120)
@export var punch_duration: float = 0.3
@export var punch_cooldown: float = 0.7
## Hitbox center, in front of the fighter (mirrored by facing), and its size.
## The fighter is never moved by a punch.
@export var punch_reach: float = 75.0
@export var punch_hitbox_size: Vector2 = Vector2(110.0, 40.0)
@export var punch_hitbox_y: float = -10.0
## The hitbox is live only between these two times, as fractions of
## punch_duration: startup before it, recovery after it (Smash-style frames).
@export_range(0.0, 1.0) var punch_active_start: float = 0.2
@export_range(0.0, 1.0) var punch_active_end: float = 0.7

@export_group("Moveset")
@export var can_double_jump: bool = true
@export var can_dash: bool = true
@export var can_air_punch: bool = true
@export var can_charge: bool = true
@export var can_recover: bool = true
