class_name FighterProfile
extends Resource

## Per-fighter tuning and moveset flags (the "kit" seam).
##
## Future per-character kits (Smash-style) supply a different FighterProfile
## to a Fighter; no state code may hardcode these values, it must read them
## from `owner.profile`. The defaults are the snappy Smash-like feel (S2); this
## resource is the single place to tune it, and both characters currently share
## the same defaults.

@export_group("Movement")
@export var run_speed: float = 300.0
@export var ground_acceleration: float = 2400.0
@export var air_acceleration: float = 1400.0
## Snappy Smash-like arc: strong gravity, faster fall, capped fall speed.
@export var gravity: float = 1800.0
@export var fall_gravity_multiplier: float = 1.2
@export var max_fall_speed: float = 1000.0
@export var dash_speed: float = 600.0
@export var dash_duration: float = 0.25
@export var air_dash_duration: float = 0.18
## Gravity is suspended during an air dash (0.0), 1.0 would be full gravity.
@export var air_dash_gravity_scale: float = 0.0

@export_group("Jump")
@export var jump_velocity: float = -850.0
@export var double_jump_velocity: float = -750.0
## Releasing jump while rising multiplies the upward speed by this (short hop).
@export var jump_cut_multiplier: float = 0.45
## A ground jump is still allowed this long after leaving a ledge.
@export var coyote_time: float = 0.10
## A jump pressed this long before landing fires on landing.
@export var jump_buffer: float = 0.10
@export var max_air_jumps: int = 1

@export_group("Weight")
## Multiplier applied on top of the damage-% knockback scaling. Above 1.0 the
## fighter is launched farther (lighter), below 1.0 it is heavier.
@export var knockback_scale: float = 1.0

@export_group("Hit reaction")
## hitstun = clamp(base + |knockback| * per_knockback, min, max) seconds.
@export var hitstun_base: float = 0.2
@export var hitstun_per_knockback: float = 0.0004
@export var hitstun_min: float = 0.3
@export var hitstun_max: float = 0.9
@export var hurt_gravity_scale: float = 0.6
## Invulnerability granted when hitstun ends, so a punch cannot stun-lock.
@export var post_hit_invulnerability: float = 0.5
@export var respawn_invulnerability: float = 1.5

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
