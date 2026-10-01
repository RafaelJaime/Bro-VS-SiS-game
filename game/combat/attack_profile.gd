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

static func make(attack_damage: float, attack_knockback: Vector2, offset: Vector2, size: Vector2, attack_direction: StringName) -> AttackProfile:
	var attack := AttackProfile.new()
	attack.damage = attack_damage
	attack.knockback = attack_knockback
	attack.hitbox_offset = offset
	attack.hitbox_size = size
	attack.direction = attack_direction
	return attack
