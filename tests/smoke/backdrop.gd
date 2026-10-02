extends SceneTree
## The kitchen backdrop, windowed (it reads rendered pixels): the world around the
## art is filled with the art's own wall texture (not a gradient) with no visible
## seam at the join, and the window shows a blue sky whose clouds drift over time
## behind the wall layer. Screenshots of every edge are saved for review.

const Smoke := preload("res://tests/smoke/smoke_util.gd")
const ART_X := -158.0
## World pixels per screen pixel is 1 at zoom 1 (the window is 800x600).
const SCREEN := Vector2(800.0, 600.0)

var s: RefCounted
var game: Node2D
var cam: Camera2D

func _initialize() -> void:
	_run()

# ------------------------------------------------------------------ helpers

func _look(center: Vector2, zoom: float) -> Image:
	cam.position = center
	cam.zoom = Vector2(zoom, zoom)
	cam.force_update_scroll()
	await s.frames(3)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _save(image: Image, shot_name: String) -> void:
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("user://")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(shot_name + ".png")
	image.save_png(path)
	print("SHOT %s" % path)

func _luma(color: Color) -> float:
	return 0.299 * color.r + 0.587 * color.g + 0.114 * color.b

## Mean luminance of the pixels in `area` (screen pixels).
func _mean(image: Image, area: Rect2i) -> float:
	var sum := 0.0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			sum += _luma(image.get_pixel(x, y))
	return sum / float(area.size.x * area.size.y)

## Mean absolute luminance step between neighbouring pixels (the fine texture),
## along x or along y.
func _energy(image: Image, area: Rect2i, along_x: bool) -> float:
	var sum := 0.0
	var count := 0
	for y in range(area.position.y, area.end.y - (0 if along_x else 1)):
		for x in range(area.position.x, area.end.x - (1 if along_x else 0)):
			var here := _luma(image.get_pixel(x, y))
			var next := _luma(image.get_pixel(x + 1, y)) if along_x else _luma(image.get_pixel(x, y + 1))
			sum += absf(next - here)
			count += 1
	return sum / float(count)

## Pixels of the sky (blue clearly above red; the orange wall has red above blue).
func _sky_pixels(image: Image, area: Rect2i) -> int:
	var count := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := image.get_pixel(x, y)
			if c.b > c.r + 0.08:
				count += 1
	return count

## Luminance of one row of `area` across x, to follow a cloud edge.
func _row_profile(image: Image, y: int, x0: int, x1: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for x in range(x0, x1):
		out.append(_luma(image.get_pixel(x, y)))
	return out

## The horizontal shift (pixels, to the left) that best maps `before` onto `after`.
func _best_shift(before: Image, after: Image, rows: Array, x0: int, x1: int, max_shift: int) -> int:
	var best := 0
	var best_error := INF
	for shift in range(0, max_shift + 1):
		var error := 0.0
		for y in rows:
			var a := _row_profile(before, y, x0 + shift, x1)
			var b := _row_profile(after, y, x0, x1 - shift)
			for i in a.size():
				error += absf(a[i] - b[i])
		if error < best_error:
			best_error = error
			best = shift
	return best

func _hide_gameplay() -> void:
	for node_name in ["Fighter1", "Fighter2", "TableStage"]:
		(game.get_node(node_name) as CanvasItem).visible = false
	(game.get_node("UI") as CanvasLayer).visible = false
	# No food drops into the shots.
	var spawner := game.get_node_or_null("FoodSpawner")
	if spawner != null:
		spawner.process_mode = Node.PROCESS_MODE_DISABLED
	for fighter_name in ["Fighter1", "Fighter2"]:
		(game.get_node(fighter_name).get_node("PlayerUI") as CanvasLayer).visible = false
	# The match camera's off-screen bubbles live in its own layers.
	var match_camera := game.get_node("Camera2D") as Camera2D
	match_camera.set_physics_process(false)
	for child in match_camera.get_children():
		if child is CanvasLayer:
			child.visible = false

# --------------------------------------------------------------------- run

func _run() -> void:
	s = Smoke.new(self)
	game = s.spawn_game()
	s.attach_controllers(game)
	await s.frames(2)
	_hide_gameplay()
	(game.get_node("Camera2D") as Camera2D).enabled = false
	cam = Camera2D.new()
	game.add_child(cam)
	cam.make_current()

	var backdrop := game.get_node("Backdrop") as Sprite2D
	var cocina := game.get_node_or_null("Cocina") as Sprite2D
	var clouds := game.get_node_or_null("Clouds") as Sprite2D
	var extension := game.get_node("BackdropExtension") as BackdropExtension

	# --- structure: the layered art, clouds behind the wall, the extension on the art
	s.check("backdrop: the wall layer (fondo_cocina) is the game backdrop, not the opaque merged picture", backdrop.texture.resource_path.ends_with("fondo_cocina.png"), backdrop.texture.resource_path)
	s.check("backdrop: the cabinets and fridge layer (cocina) sits on the wall at the same place", cocina != null and cocina.position == backdrop.position and cocina.scale == backdrop.scale and cocina.centered == backdrop.centered)
	s.check("backdrop: the cloud sky exists and sits behind the wall layer", clouds != null and clouds.get_index() < backdrop.get_index() and backdrop.get_index() < cocina.get_index() and cocina.get_index() < extension.get_index())
	s.check("backdrop: the layers are dimmed alike", clouds != null and clouds.modulate == backdrop.modulate and cocina.modulate == backdrop.modulate and extension.modulate == backdrop.modulate)
	s.check("backdrop: the art keeps its 1:1 world placement (x=-158)", backdrop.position == Vector2(ART_X, 0.0) and backdrop.scale == Vector2.ONE)
	var shader_material := extension.material as ShaderMaterial
	s.check("backdrop: the extension is drawn with the wall shader, no gradient strips", shader_material != null and shader_material.shader == BackdropExtension.WALL_SHADER)
	var patch: ImageTexture = shader_material.get_shader_parameter("patch") if shader_material != null else null
	var art := backdrop.texture.get_image()
	art.decompress()
	var art_pixel := art.get_pixelv(BackdropExtension.WALL_PATCH.position)
	s.check("backdrop: the tile is a region of the art itself", patch != null and patch.get_size() == Vector2(BackdropExtension.WALL_PATCH.size) and patch.get_image().get_pixel(0, 0).is_equal_approx(art_pixel))

	# --- the wall around the art, at zoom 1 (one screen pixel per world pixel)
	var left := await _look(Vector2(ART_X, 220.0), 1.0)
	_save(left, "fb_left_edge")
	# Join at screen x=400. Rows 60..400 are plain wall on both sides of it.
	var rows_y := 60 + 80
	var texture_area := Rect2i(400 - 120, rows_y, 100, 260)
	var art_area := Rect2i(400 + 8, rows_y, 55, 260)
	var ext_energy := _energy(left, texture_area, true)
	var art_energy := _energy(left, art_area, true)
	s.check("backdrop: the left fill has the art's fine texture, not a smooth gradient", ext_energy > 0.4 * art_energy and ext_energy > 0.004, "fill=%.4f art=%.4f" % [ext_energy, art_energy])
	var jump := absf(_mean(left, Rect2i(400 - 8, rows_y, 6, 260)) - _mean(left, Rect2i(400 + 3, rows_y, 6, 260)))
	s.check("backdrop: no visible seam where the left fill meets the art", jump < 0.025, "step=%.4f" % jump)
	var row_steps := 0.0
	for y in range(rows_y, rows_y + 260):
		row_steps += absf(_luma(left.get_pixel(400 - 2, y)) - _luma(left.get_pixel(400 + 2, y)))
	row_steps /= 260.0
	s.check("backdrop: pixels across the left join differ about as much as neighbours in the art", row_steps < maxf(art_energy * 6.0, 0.04), "across=%.4f art-step=%.4f" % [row_steps, art_energy])

	var top := await _look(Vector2(460.0, 0.0), 1.0)
	_save(top, "fb_top_edge")
	# The join is the picture's top line: world y=0 at screen y=300.
	var top_energy := _energy(top, Rect2i(150, 180, 500, 100), true)
	var top_art_energy := _energy(top, Rect2i(150, 303, 500, 17), true)
	s.check("backdrop: the top fill has the art's fine texture", top_energy > 0.4 * top_art_energy and top_energy > 0.004, "fill=%.4f art=%.4f" % [top_energy, top_art_energy])
	var top_jump := absf(_mean(top, Rect2i(150, 300 - 8, 500, 6)) - _mean(top, Rect2i(150, 300 + 3, 500, 6)))
	s.check("backdrop: no visible seam where the top fill meets the art", top_jump < 0.025, "step=%.4f" % top_jump)

	var right := await _look(Vector2(1018.0, 450.0), 1.0)
	_save(right, "fb_right_edge")
	var right_energy := _energy(right, Rect2i(400 + 20, 180, 100, 260), true)
	s.check("backdrop: the right fill has the art's fine texture", right_energy > 0.4 * art_energy and right_energy > 0.004, "fill=%.4f" % right_energy)
	var right_luma := _mean(right, Rect2i(400 + 20, 180, 100, 260))
	var wall_luma := _mean(left, art_area)
	s.check("backdrop: the right fill is as bright as the wall", absf(right_luma - wall_luma) < 0.15, "right=%.3f wall=%.3f" % [right_luma, wall_luma])

	var corner := await _look(Vector2(-60.0, -100.0), 0.58)
	_save(corner, "fb_corner_zoomed_out")
	await _look(Vector2(430.0, 300.0), 0.58)
	_save(root.get_texture().get_image(), "fb_world_zoomed_out")
	var far_right := await _look(Vector2(900.0, 100.0), 0.58)
	_save(far_right, "fb_top_right_zoomed_out")

	# --- the sky in the window moves, behind the wall
	var window_view := await _look(Vector2(ART_X + 620.0, 215.0), 1.0)
	_save(window_view, "fb_window_t0")
	# The window spans picture x 407..833, y 34..394: screen x 187..613, y 119..479.
	var window_area := Rect2i(190, 122, 420, 355)
	var sky_before := _sky_pixels(window_view, window_area)
	s.check("backdrop: the window shows the blue sky", sky_before > window_area.get_area() / 4, "sky pixels=%d of %d" % [sky_before, window_area.get_area()])
	var wall_only := _sky_pixels(window_view, Rect2i(40, 130, 100, 300))
	s.check("backdrop: the wall outside the window shows no sky", wall_only < 200, "sky pixels on the wall=%d" % wall_only)
	var offset_before := clouds.region_rect.position.x
	await s.sim(3.0)
	var window_later := await _look(Vector2(ART_X + 620.0, 215.0), 1.0)
	_save(window_later, "fb_window_t3")
	var moved := clouds.region_rect.position.x - offset_before
	s.check("backdrop: the clouds drift slowly (about 16 px per second)", moved > 40.0 and moved < 56.0, "moved=%.1f px in 3 s" % moved)
	var changed := 0.0
	for y in range(window_area.position.y, window_area.end.y, 3):
		for x in range(window_area.position.x, window_area.end.x, 3):
			changed += absf(_luma(window_view.get_pixel(x, y)) - _luma(window_later.get_pixel(x, y)))
	changed /= float(window_area.get_area() / 9)
	s.check("backdrop: the window pixels change as the clouds move", changed > 0.004, "mean change=%.4f" % changed)
	# Follow a cloud edge: the picture slides to the left by about the drift.
	var shift := _best_shift(window_view, window_later, [150, 170, 190, 210], 200, 330, 80)
	s.check("backdrop: the clouds slide to the left in world space", shift >= 38 and shift <= 58, "best shift=%d px" % shift)
	var sky_after := _sky_pixels(window_later, window_area)
	s.check("backdrop: the sky keeps filling the window while it drifts", absi(sky_after - sky_before) < window_area.get_area() / 10, "before=%d after=%d" % [sky_before, sky_after])

	s.finish()
