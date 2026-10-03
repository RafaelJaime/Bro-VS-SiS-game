extends SceneTree
## Fighter visibility: the sprite is only ever hidden by the invulnerability blink
## and always comes back. Regression for fighters that stayed invisible for a
## long time: a non-blinking grant (ledge grab, climb) killed the blink tween
## while it was in its hidden half, leaving the sprite hidden for the whole grab.

const Smoke := preload("res://tests/smoke/smoke_util.gd")

func _initialize() -> void:
	_run()

# Longest invulnerability any source can grant, in seconds.
func _max_grant(p: FighterProfile) -> float:
	return maxf(maxf(p.respawn_invulnerability, p.post_hit_invulnerability), maxf(p.ledge_invuln_first, p.ledge_climb_invulnerability))

func _opaque(f: Fighter) -> bool:
	return f.animated_sprite_2d.visible and is_equal_approx(f.animated_sprite_2d.modulate.a, 1.0) and is_equal_approx(f.animated_sprite_2d.self_modulate.a, 1.0)

# Runs `frames` physics frames and returns the first frame index at which the
# fighter was vulnerable yet not fully visible (-1 when never), plus the longest
# invulnerable stretch in seconds.
func _watch(s: RefCounted, f: Fighter, frames: int) -> Dictionary:
	var bad := -1
	var longest := 0.0
	var run := 0
	for i in frames:
		await physics_frame
		if not f.is_invulnerable and not _opaque(f) and bad < 0:
			bad = i
		run = run + 1 if f.is_invulnerable else 0
		longest = maxf(longest, float(run) / float(Engine.physics_ticks_per_second))
	return {"bad": bad, "longest": longest}

# Frames until the blink hides the sprite (-1 when it never does).
func _until_hidden(f: Fighter, limit: int = 30) -> int:
	for i in limit:
		await physics_frame
		if not f.animated_sprite_2d.visible:
			return i
	return -1

func _run() -> void:
	var s := Smoke.new(self)
	var game: Node2D = s.spawn_game()
	var controllers: Array = s.attach_controllers(game)
	await s.frames(60)
	var f1: Fighter = game.get_node("Fighter1")
	var f2: Fighter = game.get_node("Fighter2")
	var p := f1.profile
	var max_grant := _max_grant(p)

	# --- a blinking grant followed by a non-blinking one (ledge after a hit/respawn) ---
	f1.grant_invulnerability(1.5)
	var hidden := await _until_hidden(f1)
	s.check("the respawn blink hides the sprite at some point", hidden >= 0, "frames=%d" % hidden)
	f1.grant_invulnerability(1.0, false)
	await s.frames(1)
	s.check("a non-blinking grant never leaves the sprite hidden", f1.animated_sprite_2d.visible)
	var watched: Dictionary = await _watch(s, f1, 120)
	s.check("the sprite stays visible for the whole non-blinking grant", watched["bad"] < 0 and f1.animated_sprite_2d.visible, "bad=%d" % watched["bad"])
	await s.frames(120)

	# --- the same through the real ledge path: hit, blink, grab the table leg ---
	var ledge: Dictionary = game.get_ledges()[0]
	f1.grant_invulnerability(p.post_hit_invulnerability)
	await _until_hidden(f1)
	f1.position = Vector2(ledge["x"] - p.ledge_hang_offset, ledge["top"] + 40.0)
	f1.velocity = Vector2(0.0, 100.0)
	f1.state_machine._change_state("Fall")
	await s.frames(4)
	s.check("the fighter grabbed the leg during the blink", s.state_of(f1) == "LedgeHang", "state=%s" % s.state_of(f1))
	s.check("a ledge grab made in the hidden half of the blink shows the sprite", f1.animated_sprite_2d.visible)
	f1.state_machine._change_state("Fall")
	await s.frames(200)

	# --- a long mixed run: respawn, hits during invulnerability, hit-stop, charge ---
	f1.block_ledge_grab(0.0)
	f1.position = Vector2(500.0, 300.0)
	f1.velocity = Vector2.ZERO
	f1.state_machine._change_state("Fall")
	f1.damage_percent = 0.0
	f1._respawn()
	var longest := 0.0
	var bad := -1
	var stamp := 0
	for round_index in 6:
		controllers[0].attack_held_level = (round_index % 2 == 0)
		controllers[0].press_punch()
		Combat.apply_hit(f2, f1, 5.0, Vector2(120.0, -60.0))
		Combat.cancel_hit_stop()
		Combat._trigger_hit_stop(0.08, 0.05)
		var w: Dictionary = await _watch(s, f1, 70)
		if bad < 0 and w["bad"] >= 0:
			bad = stamp + int(w["bad"])
		longest = maxf(longest, w["longest"])
		stamp += 70
	controllers[0].attack_held_level = false
	await s.frames(30)
	s.check("whenever a fighter is vulnerable it is fully visible and opaque", bad < 0, "first bad frame=%d" % bad)
	s.check("no invulnerability lasts longer than the longest configured grant", longest <= max_grant + 0.1, "longest=%.2fs max=%.2fs" % [longest, max_grant])
	s.check("the fighter ends the run vulnerable, visible and opaque", not f1.is_invulnerable and _opaque(f1))

	# --- leftovers are wiped when the invulnerability ends or is cancelled ---
	f1.grant_invulnerability(2.0)
	await _until_hidden(f1)
	f1.reset_player()
	await s.frames(1)
	s.check("cancelling the invulnerability shows the sprite", not f1.is_invulnerable and _opaque(f1))
	s.finish()
