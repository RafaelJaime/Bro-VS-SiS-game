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

@export_group("Directional punches")
## Smash-style variants (neutral is the Punch group above). Each uses the same
## punch frame and timing; they differ in damage, angle and hitbox.
@export var attack_side: AttackProfile = AttackProfile.make(10.0, Vector2(320.0, -90.0), Vector2(90.0, -10.0), Vector2(120.0, 44.0), &"side")
## Almost straight up, hits what is above (and a close grounded target).
@export var attack_up: AttackProfile = AttackProfile.make(8.0, Vector2(30.0, -380.0), Vector2(30.0, -70.0), Vector2(120.0, 80.0), &"up")
## Low sweep on the ground: a short, low launch.
@export var attack_down_ground: AttackProfile = AttackProfile.make(7.0, Vector2(150.0, -230.0), Vector2(65.0, 55.0), Vector2(130.0, 50.0), &"down")
## Down in the air is the spike: it sends the target straight down.
@export var attack_down_air: AttackProfile = AttackProfile.make(9.0, Vector2(40.0, 420.0), Vector2(0.0, 80.0), Vector2(110.0, 70.0), &"down")

@export_group("Charge")
## Holding punch on the ground charges a smash. A release before the tap
## threshold is an ordinary punch; the charge grows to 1.0 at max_charge_time and
## stays there however long the key is held.
@export var tap_threshold: float = 0.15
@export var max_charge_time: float = 1.0
## Damage and knockback multipliers at full charge (1.0 at no charge).
@export var charge_damage_max: float = 1.6
@export var charge_knockback_max: float = 1.5
## Charge look (Smash style): the fighter keeps its colors and flashes bright, and
## a small additive glow sits at the fist. All values go from the start to the end
## of the charge. Glow sprite scale (the texture is 512 px) and alpha:
@export var charge_glow_scale: Vector2 = Vector2(0.1, 0.28)
@export var charge_glow_alpha: Vector2 = Vector2(0.45, 0.9)
## Flash rate in Hz, how much brighter the sprite gets on a flash frame (added to
## 1.0 per channel) and the sprite shake in pixels.
@export var charge_flash_hz: Vector2 = Vector2(10.0, 15.0)
@export var charge_flash_boost: Vector2 = Vector2(0.35, 0.9)
@export var charge_shake: Vector2 = Vector2(0.0, 1.5)
## Glow position in front of the fist (x is mirrored by the facing).
@export var charge_glow_offset: Vector2 = Vector2(50.0, 2.0)

@export_group("Recovery")
## Up-recovery: one upward burst per airtime (up + punch in the air). The fighter
## is helpless afterwards until it lands, grabs a ledge or is hit.
@export var recovery_velocity: float = -950.0
@export var recovery_drift: float = 250.0
## Fraction of the air acceleration available during the burst and while helpless.
@export var recovery_air_control: float = 0.5
@export var helpless_air_control: float = 0.5

@export_group("Fast fall")
## Holding down while falling snaps the fall speed up to fast_fall_start_speed and
## raises the speed limit to fast_fall_speed until the fighter lands.
@export var fast_fall_start_speed: float = 700.0
@export var fast_fall_speed: float = 1300.0

@export_group("Ledge")
## Table legs at the ends of the table are grab zones (Smash ledge). The fighter
## hangs `ledge_hang_offset` outside the table end, never above `ledge_hang_depth`
## below the tabletop.
@export var ledge_hang_offset: float = 34.0
@export var ledge_hang_depth: float = 100.0
## Horizontal reach to the hang point, and how far above the hang depth a falling
## fighter may be grabbed (it then snaps down to the hang depth).
@export var ledge_reach_x: float = 70.0
@export var ledge_snap_up: float = 90.0
## A rising fighter faster than this cannot grab.
@export var ledge_max_rise: float = 50.0
## Invulnerability on the first grab, reduced by `ledge_invuln_decay` for every
## further grab without touching the ground or being hit (never below 0).
@export var ledge_invuln_first: float = 1.0
@export var ledge_invuln_decay: float = 0.3
## Longest hang before the fighter drops, and the delay before an option is read.
@export var ledge_max_hang: float = 4.0
@export var ledge_min_hang: float = 0.15
## After letting go (or being trumped) the same legs cannot be grabbed for this long.
@export var ledge_regrab_lockout: float = 0.6
@export var ledge_climb_time: float = 0.45
@export var ledge_attack_climb_time: float = 0.6
@export var ledge_climb_invulnerability: float = 0.5
## Where a climb ends: this far in from the table end.
@export var ledge_climb_land_x: float = 46.0
## Ledge jump: horizontal speed toward the table and the jump speed (a ground jump
## that is strong enough to clear the table edge from the hang depth).
@export var ledge_jump_drift: float = 160.0
@export var ledge_jump_velocity: float = -1000.0
## Climb attack (punch from the ledge).
@export var ledge_attack_damage: float = 10.0
@export var ledge_attack_knockback: Vector2 = Vector2(260.0, -180.0)
@export var ledge_attack_reach: float = 130.0

@export_group("Shield")
## Shield meter (see ShieldMeter): holding drains it, a blocked hit drains it and
## it breaks into a punishable dizzy state at zero. Times are game seconds; the
## runtime converts them to physics ticks.
@export var shield_max: float = 100.0
## A continuous hold from full breaks the shield after this long.
@export var shield_break_time: float = 5.0
@export var shield_regen_delay: float = 0.5
## Empty to full.
@export var shield_regen_time: float = 6.0
## Meter damage of a blocked hit = hit damage * this (unless the hit sets one).
@export var shield_damage_scale: float = 1.5
## Fraction of a blocked hit's damage that still lands (strictly between 0 and 1).
@export_range(0.01, 0.99) var shield_chip_fraction: float = 0.25
## Fraction of the knockback a blocked hit still applies.
@export var shield_knockback_fraction: float = 0.3
## Meter ratio the fighter wakes up with after a dizzy.
@export var shield_break_recovery: float = 0.5
@export var dizzy_duration: float = 2.0
## Upward pop at the moment the shield breaks (negative is up).
@export var shield_break_pop_velocity: float = -450.0

@export_group("Air dodge")
## In the air the block key dodges instead of shielding: intangible for
## `air_dodge_invuln`, then helpless for `air_dodge_endlag`. One per airtime, and
## a new one cannot start until `air_dodge_cooldown` (from the dodge start) is over.
@export var air_dodge_invuln: float = 0.3
@export var air_dodge_endlag: float = 0.15
@export var air_dodge_cooldown: float = 0.6
## Multipliers on the horizontal speed and on gravity during the dodge.
@export var air_dodge_drift: float = 0.5
@export var air_dodge_gravity_scale: float = 0.5

@export_group("Pickup")
## Food is picked up inside a rectangle `2 * pickup_reach_x` wide and
## `pickup_reach_height` tall whose bottom sits at the fighter's feet.
@export var pickup_reach_x: float = 105.0
@export var pickup_reach_height: float = 100.0

@export_group("Moveset")
@export var can_double_jump: bool = true
@export var can_dash: bool = true
@export var can_air_punch: bool = true
@export var can_charge: bool = true
@export var can_recover: bool = true
@export var can_fast_fall: bool = true
@export var can_ledge_grab: bool = true
