extends SceneTree
## The credits screen, windowed: the two names sit on the same row (same global y
## and height) and each is centered over its own column, shown over the shared
## menu background.

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
	await s.frames(5)
	var credits: Control = scene_manager.current_scene
	var rafael: Label = credits.get_node("RafaelButton/VBoxContainer/RLabel")
	var matilde: Label = credits.get_node("MatildeButton/VBoxContainer/MLabel")
	var r_rect := rafael.get_global_rect()
	var m_rect := matilde.get_global_rect()
	s.check("both names are on the same row (same global y)", is_equal_approx(r_rect.position.y, m_rect.position.y), "%.1f vs %.1f" % [r_rect.position.y, m_rect.position.y])
	s.check("both name labels have the same height", is_equal_approx(r_rect.size.y, m_rect.size.y), "%.1f vs %.1f" % [r_rect.size.y, m_rect.size.y])
	s.check("the names sit at the top, below the title", r_rect.position.y > 40.0 and r_rect.end.y < 200.0, str(r_rect))
	s.check("each name is centered over its own column", is_equal_approx(m_rect.get_center().x, 200.0) and is_equal_approx(r_rect.get_center().x, 600.0), "%.1f / %.1f" % [m_rect.get_center().x, r_rect.get_center().x])
	var r_art: TextureRect = credits.get_node("RafaelButton/VBoxContainer/TextureRect")
	var m_art: TextureRect = credits.get_node("MatildeButton/VBoxContainer/TextureRect")
	s.check("both illustrations start right under their name, at the same y", is_equal_approx(r_art.get_global_rect().position.y, m_art.get_global_rect().position.y))
	s.check("the credits own no background of their own", credits.get_node_or_null("background") == null)
	await s.screenshot("credits")
	s.finish()
