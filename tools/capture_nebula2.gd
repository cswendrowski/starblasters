extends SceneTree

# Nebula 2 capture — drives scroll_offset over time to demonstrate
# the infinite-flight feel, with a pixel-art-preserving pixelation knob
# and a soft purple/pink palette. Captures a deep starfield base
# behind it so the nebula reads as a layer, not a flat fill.

const OUT_DIR := "res://captures/nebula2"
const FPS: int = 24
const DURATION: float = 6.0
const FRAME_TIME: float = 1.0 / float(FPS)
const SHADER := preload("res://graphics/nebula2.gdshader")


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


func _build_palette() -> GradientTexture1D:
	# Deep-space → ionized-pink palette. Low noise values land on near-black
	# void, mid values pick up indigo/magenta gas, peaks burst into hot pink
	# / hydrogen-emission white.
	var g := Gradient.new()
	g.colors = PackedColorArray([
		Color(0.04, 0.02, 0.10),   # near-black void
		Color(0.18, 0.08, 0.30),   # deep indigo
		Color(0.45, 0.18, 0.55),   # magenta gas
		Color(0.90, 0.40, 0.75),   # hot pink emission
		Color(1.00, 0.85, 0.95),   # core hydrogen highlight
	])
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.6, 0.85, 1.0])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 64
	return tex


func _starfield(parent: Node, w: int, h: int) -> void:
	# Cheap procedural star sprinkle on a dark base so the nebula reads
	# against something, not a void.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05)
	bg.size = Vector2(w, h)
	parent.add_child(bg)
	for i in range(220):
		var s := ColorRect.new()
		var x: float = rng.randf() * float(w)
		var y: float = rng.randf() * float(h)
		var bright: float = rng.randf()
		var sz: float = 1.0 if bright < 0.75 else 2.0
		s.color = Color(1, 1, 1, 0.3 + bright * 0.7)
		s.position = Vector2(x, y)
		s.size = Vector2(sz, sz)
		parent.add_child(s)


func _run() -> void:
	# Use the project's native viewport size so the capture matches the
	# in-game scale (480×270 internal viewport per project.godot).
	var vp_size: Vector2i = Vector2i(480, 270)
	root.get_viewport().size = vp_size
	_starfield(root, vp_size.x, vp_size.y)
	# Full-viewport ColorRect carrying the nebula material.
	var rect := ColorRect.new()
	rect.size = Vector2(vp_size)
	rect.color = Color(1, 1, 1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("colorscheme", _build_palette())
	mat.set_shader_parameter("scale", 2.2)
	mat.set_shader_parameter("octaves", 6)
	mat.set_shader_parameter("seed", 42.0)
	mat.set_shader_parameter("density", 1.05)
	mat.set_shader_parameter("edge_sharpness", 0.45)
	mat.set_shader_parameter("max_alpha", 0.85)
	mat.set_shader_parameter("opacity", 0.85)
	mat.set_shader_parameter("warp_strength", 1.6)
	mat.set_shader_parameter("warp_scale", 1.0)
	mat.set_shader_parameter("wisp_strength", 0.35)
	mat.set_shader_parameter("pixels", 200.0)
	mat.set_shader_parameter("drift_speed", 0.0)  # disable legacy drift, we drive scroll directly
	mat.set_shader_parameter("uv_correct", Vector2(float(vp_size.x) / float(vp_size.y), 1.0))
	rect.material = mat
	root.add_child(rect)

	# Drive scroll_offset to simulate the player flying "up" through an
	# infinite nebula field. Y component grows linearly with time; X has a
	# subtle sway so the motion reads as organic, not on rails.
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		var t: float = float(f) / float(FPS)
		var sx: float = 0.03 * sin(t * 0.6)
		var sy: float = -t * 0.08  # flying forward = noise scrolls toward viewer
		mat.set_shader_parameter("scroll_offset", Vector2(sx, sy))
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
	print("[nebula2] captured %d frames" % frame_count)
	quit()
