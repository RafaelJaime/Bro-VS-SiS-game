extends SceneTree
## The credits screen, windowed: the two names sit on the same row (same global y
## and height) and each is centered over its own column, shown over the shared
## menu background. Each illustration slides in from its own side, ends with its cut
## edge on the bottom of the screen and keeps it there.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const CREDITS_SCENE := "res://ui/credits/credits.tscn"

var s: RefCounted

func _initialize() -> void:
	_run()

func _run() -> void:
	s = Smoke.new(self)
	var scene_manager: Node = root.get_node("SceneManager")
	var holder := Node.new()
	root.add_child(holder)
	scene_manager.scene_container = holder
	scene_manager.change_scene(CREDITS_SCENE)
	await s.frames(2)
	var credits: Control = scene_manager.current_scene
	var r_art: TextureRect = credits.get_node("RafaelButton/Art")
	var m_art: TextureRect = credits.get_node("MatildeButton/Art")
	s.check("matilde's art starts off the left side (center outside the screen)", m_art.get_global_rect().get_center().x < 0.0, str(m_art.get_global_rect()))
	s.check("rafael's art starts off the right side (center outside the screen)", r_art.get_global_rect().get_center().x > 800.0, str(r_art.get_global_rect()))
	await create_timer(1.2).timeout
	var rafael: Label = credits.get_node("RafaelButton/VBoxContainer/RLabel")
	var matilde: Label = credits.get_node("MatildeButton/VBoxContainer/MLabel")
	var r_rect := rafael.get_global_rect()
	var m_rect := matilde.get_global_rect()
	s.check("both names are on the same row (same global y)", is_equal_approx(r_rect.position.y, m_rect.position.y), "%.1f vs %.1f" % [r_rect.position.y, m_rect.position.y])
	s.check("both name labels have the same height", is_equal_approx(r_rect.size.y, m_rect.size.y), "%.1f vs %.1f" % [r_rect.size.y, m_rect.size.y])
	s.check("the names sit at the top, below the title", r_rect.position.y > 40.0 and r_rect.end.y < 200.0, str(r_rect))
	s.check("each name is centered over its own column", is_equal_approx(m_rect.get_center().x, 200.0) and is_equal_approx(r_rect.get_center().x, 600.0), "%.1f / %.1f" % [m_rect.get_center().x, r_rect.get_center().x])
	s.check("matilde ends on the left half, rafael on the right half", m_art.get_global_rect().get_center().x < 400.0 and r_art.get_global_rect().get_center().x > 400.0)
	s.check("both illustrations end fully on screen", m_art.get_global_rect().position.x >= 0.0 and r_art.get_global_rect().end.x <= 800.0, "%s / %s" % [m_art.get_global_rect(), r_art.get_global_rect()])
	s.check("both illustrations have the same size", m_art.size.is_equal_approx(r_art.size), "%s vs %s" % [m_art.size, r_art.size])
	s.check("the names show at full size with no pop animation", is_equal_approx(rafael.scale.x, 1.0) and is_equal_approx(matilde.scale.x, 1.0))
	var bottom_ok := true
	var bottoms := PackedStringArray()
	for i in 8:
		var m_bottom := m_art.get_global_transform().origin.y + m_art.size.y * m_art.get_global_transform().get_scale().y
		var r_bottom := r_art.get_global_transform().origin.y + r_art.size.y * r_art.get_global_transform().get_scale().y
		bottoms.append("%.2f/%.2f" % [m_bottom, r_bottom])
		bottom_ok = bottom_ok and absf(m_bottom - 600.0) <= 1.0 and absf(r_bottom - 600.0) <= 1.0
		await create_timer(0.25).timeout
	s.check("each illustration's cut edge stays on the screen bottom", bottom_ok, ", ".join(bottoms))
	s.check("the art does not grow or breathe (scale stays 1.0)", is_equal_approx(m_art.scale.x, 1.0) and is_equal_approx(r_art.scale.x, 1.0), "%.3f / %.3f" % [m_art.scale.x, r_art.scale.x])
	s.check("no light-sweep material on the art", m_art.material == null and r_art.material == null)
	await s.screenshot("credits")
	s.check("the credits own no background of their own", credits.get_node_or_null("background") == null)
	s.finish()
