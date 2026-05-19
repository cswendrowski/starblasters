extends SceneTree

# Iterating the drop-shadow POC. Two side-by-side receivers — a clean
# solid-tan disc (proves the mechanism unambiguously) and the actual
# NoAtmosphere moon (proves it works in production context). Player
# slides across both.

const OUT_DIR := "res://captures/shadow_iter"
const FPS: int = 24
const DURATION: float = 6.0
const FRAME_TIME: float = 1.0 / float(FPS)
const SHADER := preload("res://graphics/masked_shadow.gdshader")
const MOON_SCENE := preload("res://Planets/NoAtmosphere/NoAtmosphere.tscn")
const PLAYER_TEX := preload("res://graphics/player/blue-fighter-sheet.png")

# Tunable knobs.
const LIGHT_OFFSET := Vector2(14, 22)
const SHADOW_SCALE := Vector2(2.0, 2.0)
const SHADOW_ALPHA := 0.4   # Roman spec
const RECEIVER_DISC_SIZE := Vector2(140, 140)


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var d := DirAccess.open(OUT_DIR)
	if d:
		d.list_dir_begin()
		while true:
			var fn := d.get_next()
			if fn == "":
				break
			if fn.ends_with(".png"):
				d.remove(fn)
		d.list_dir_end()
	_run.call_deferred()


func _run() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.z_index = -10
	root.add_child(bg)
	# Receiver A: clean tan disc Sprite2D on the LEFT side of the playfield.
	var disc_tex := _bake_solid_disc(140, 140, Color(0.78, 0.60, 0.36, 1.0))
	var disc := Sprite2D.new()
	disc.texture = disc_tex
	disc.position = Vector2(80, 160)
	disc.centered = true
	root.add_child(disc)
	var disc_origin := Vector2(80 - 70, 160 - 70)
	var disc_size := Vector2(140, 140)
	var disc_mask := _bake_hard_disc_mask(140, 140)
	# Receiver B: actual moon on the RIGHT. The Planet scene ships with
	# anchors_preset=15 (full rect) — Godot's layout pass overrides our
	# `size = 100×100` for the first few frames after add_child, making
	# `size * scale` return a wrong value to the shader's receiver_size_world.
	# That's why the shadow didn't render until ~frame 11: the layout
	# eventually settled and the bounds finally matched my mask. Force
	# anchors to TOP_LEFT so `size` is authoritative from frame 1.
	# (Roman 2026-05-18 — pointed at the tan-vs-blue delta as the clue.)
	var moon = MOON_SCENE.instantiate()
	if moon is Control:
		var ctrl := moon as Control
		ctrl.set_anchors_preset(Control.PRESET_TOP_LEFT)
		ctrl.offset_left = 0
		ctrl.offset_top = 0
		ctrl.offset_right = 100
		ctrl.offset_bottom = 100
		ctrl.position = Vector2(170, 90)
		ctrl.scale = Vector2(1.4, 1.4)
		ctrl.size = Vector2(100, 100)
		ctrl.custom_minimum_size = Vector2(100, 100)
		ctrl.pivot_offset = Vector2.ZERO
	root.add_child(moon)
	if moon.has_method("set_pixels"):
		moon.set_pixels(150.0)
	if "override_time" in moon:
		moon.override_time = true
	if moon.has_method("set_seed"):
		moon.set_seed(7)
	if moon.has_method("randomize_colors"):
		moon.randomize_colors()
	var moon_origin: Vector2 = (moon as Control).global_position
	var moon_size: Vector2 = (moon as Control).size * (moon as Control).scale
	var moon_mask := _bake_hard_disc_mask(140, 140)
	# Player.
	var player := Sprite2D.new()
	player.texture = PLAYER_TEX
	player.hframes = 3
	player.frame = 1
	player.scale = Vector2(3, 3)
	player.z_index = 10
	root.add_child(player)
	# Two shadow sprites — one per receiver, only the one whose receiver
	# the ray endpoint hits is set active. Avoids the need to swap
	# materials each frame.
	var shadow_a := _make_shadow_sprite(disc_mask, disc_origin, disc_size)
	root.add_child(shadow_a)
	var shadow_b := _make_shadow_sprite(moon_mask, moon_origin, moon_size)
	root.add_child(shadow_b)
	# Capture loop.
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		var t: float = float(f) / float(FPS)
		# Slide left-to-right across both receivers; gentle vertical wave.
		var x: float = 30.0 + 250.0 * (sin(t * TAU * 0.18) * 0.5 + 0.5)
		var y: float = 170.0 + 14.0 * sin(t * TAU * 0.5)
		player.position = Vector2(x, y)
		var endpoint: Vector2 = player.position + LIGHT_OFFSET
		_update_shadow(shadow_a, endpoint, disc_origin, disc_size)
		_update_shadow(shadow_b, endpoint, moon_origin, moon_size)
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))
	print("[shadow-iter] done")
	quit()


func _make_shadow_sprite(mask: Texture2D, recv_origin: Vector2, recv_size: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _bake_frame_texture(PLAYER_TEX, 1, 3, 1)
	s.scale = SHADOW_SCALE
	s.z_index = 5
	s.visible = false
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("mask_tex", mask)
	mat.set_shader_parameter("mask_active", false)
	mat.set_shader_parameter("shadow_color", Color(0, 0, 0, SHADOW_ALPHA))
	mat.set_shader_parameter("shadow_size_world", s.texture.get_size() * s.scale)
	mat.set_shader_parameter("receiver_world_origin", recv_origin)
	mat.set_shader_parameter("receiver_size_world", recv_size)
	s.material = mat
	return s


func _update_shadow(shadow: Sprite2D, endpoint: Vector2, recv_origin: Vector2, recv_size: Vector2) -> void:
	var rect := Rect2(recv_origin, recv_size)
	var over: bool = rect.has_point(endpoint)
	shadow.visible = over
	if not over:
		return
	shadow.global_position = endpoint
	var mat: ShaderMaterial = shadow.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("mask_active", true)
		var shadow_size_world: Vector2 = shadow.texture.get_size() * shadow.scale
		mat.set_shader_parameter("shadow_world_origin", endpoint - shadow_size_world * 0.5)


func _bake_solid_disc(w: int, h: int, color: Color) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx: float = float(w) * 0.5
	var cy: float = float(h) * 0.5
	var r: float = min(cx, cy) - 1.0
	for y in h:
		for x in w:
			var dx: float = float(x) - cx + 0.5
			var dy: float = float(y) - cy + 0.5
			var d: float = sqrt(dx * dx + dy * dy)
			if d < r:
				img.set_pixel(x, y, color)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _bake_hard_disc_mask(w: int, h: int) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx: float = float(w) * 0.5
	var cy: float = float(h) * 0.5
	var r: float = min(cx, cy)
	for y in h:
		for x in w:
			var dx: float = float(x) - cx + 0.5
			var dy: float = float(y) - cy + 0.5
			var d: float = sqrt(dx * dx + dy * dy)
			var a: float = 1.0 if d < r else 0.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _bake_frame_texture(tex: Texture2D, frame_idx: int, hframes: int, vframes: int) -> Texture2D:
	var src: Image = tex.get_image()
	var fw: int = int(src.get_width() / hframes)
	var fh: int = int(src.get_height() / vframes)
	var col: int = frame_idx % hframes
	var row: int = int(frame_idx / hframes)
	var rect := Rect2i(col * fw, row * fh, fw, fh)
	var sub := Image.create(fw, fh, false, src.get_format())
	sub.blit_rect(src, rect, Vector2i.ZERO)
	return ImageTexture.create_from_image(sub)
