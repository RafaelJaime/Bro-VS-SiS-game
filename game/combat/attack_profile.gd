class_name AttackProfile
extends Resource

## One punch variant: how much it hurts, where it sends the target and where the
## hitbox sits. Every directional punch (up, down, side) reuses the same punch
## frame and differs only by these numbers, which live in `FighterProfile` so a
## future per-character kit can swap them.

## Damage % dealt.
@export var damage: float = 8.0
## Knockback before damage scaling. `x` is the strength away from the attacker
## (the sign comes from who stands on which side), `y` is up when negative.
@export var knockback: Vector2 = Vector2(220.0, -120.0)
## Hitbox center relative to the fighter. `x` is mirrored by the facing.
@export var hitbox_offset: Vector2 = Vector2(75.0, -10.0)
@export var hitbox_size: Vector2 = Vector2(110.0, 40.0)
## Name written to `Fighter.last_attack_direction`.
@export var direction: StringName = &"neutral"
## Meter damage against a shield. Below 0 means "derive it from `damage`" (the
## fighter profile's shield_damage_scale).
@export var shield_damage: float = -1.0

@export_group("Frame data")
## Timing in physics ticks (60 per second). -1 means "derive it from the fighter's
## legacy punch fields" (see `resolved_frames`), so an attack that sets none of
## these behaves exactly like the original punch.
## Ticks before the first active tick.
@export var startup_ticks: int = -1
## Active ticks: the hitbox is live on ticks startup+1 .. startup+active.
@export var active_ticks: int = -1
## Ticks after the active window; the swing ends at startup+active+endlag.
@export var endlag_ticks: int = -1
## Lockout counted from the press (Fighter.attack_cooldown_ticks): -1 is the
## legacy punch cooldown, 0 means actionable when the swing ends.
@export var cooldown_ticks: int = -1
## Chain steps only: a neutral press advances the chain on ticks
## startup+active+1 .. startup+active+link_window. 0 means no next step (a finisher).
@export var link_window_ticks: int = 0
## Base hitstun in ticks; -1 means the global knockback formula.
@export var hitstun_ticks: int = -1
## Extra hitstun ticks per px/s of final knockback (only with hitstun_ticks >= 0).
@export var hitstun_kb_growth: float = 0.0
## Multiplies the hit-stop of a FULL hit (jabs freeze the game less).
@export var hitstop_scale: float = 1.0

static func make(attack_damage: float, attack_knockback: Vector2, offset: Vector2, size: Vector2, attack_direction: StringName, attack_shield_damage: float = -1.0) -> AttackProfile:
	var attack := AttackProfile.new()
	attack.damage = attack_damage
	attack.knockback = attack_knockback
	attack.hitbox_offset = offset
	attack.hitbox_size = size
	attack.direction = attack_direction
	attack.shield_damage = attack_shield_damage
	return attack

## Sets the frame data of `attack` (a code-built attack) and returns it.
static func frames(attack: AttackProfile, startup: int, active: int, endlag: int, link_window: int = 0, cooldown: int = 0, stun: int = -1, stun_kb_growth: float = 0.0, stop_scale: float = 1.0) -> AttackProfile:
	attack.startup_ticks = startup
	attack.active_ticks = active
	attack.endlag_ticks = endlag
	attack.link_window_ticks = link_window
	attack.cooldown_ticks = cooldown
	attack.hitstun_ticks = stun
	attack.hitstun_kb_growth = stun_kb_growth
	attack.hitstop_scale = stop_scale
	return attack

## Startup, active, endlag, cooldown and link window of this attack in ticks. A
## field left at -1 comes from the fighter's legacy punch numbers: with the default
## 0.3 s punch that is startup 3, active 9 (ticks 4..12), endlag 6 and a cooldown of
## 42 ticks from the press. `duration_override` and `cooldown_override` (seconds, <0
## for none) are the Punch node's own overrides of those legacy numbers.
func resolved_frames(fighter: FighterProfile, duration_override: float = -1.0, cooldown_override: float = -1.0) -> Dictionary:
	var duration := duration_override if duration_override >= 0.0 else fighter.punch_duration
	var cooldown := cooldown_override if cooldown_override >= 0.0 else fighter.punch_cooldown
	var total := CombatClock.ticks(duration)
	var first_active := ceili(total * fighter.punch_active_start - 0.0001)
	var last_active := ceili(total * fighter.punch_active_end - 0.0001)
	var startup := maxi(0, first_active - 1)
	var active := maxi(1, last_active - first_active)
	var endlag := maxi(0, total - startup - active)
	if startup_ticks >= 0:
		startup = startup_ticks
	if active_ticks >= 0:
		active = maxi(1, active_ticks)
	if endlag_ticks >= 0:
		endlag = endlag_ticks
	return {
		"startup": startup,
		"active": active,
		"endlag": endlag,
		"cooldown": cooldown_ticks if cooldown_ticks >= 0 else CombatClock.ticks(cooldown),
		"link_window": link_window_ticks,
	}
