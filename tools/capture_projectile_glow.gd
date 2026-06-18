extends SceneTree

# Captures the new shader-based projectile glow (Roman, 2026-05-30). Spawns a
# row of representative projectiles on a dark background, freezes them, and
# zooms in so the subtle 2-3px auto-colored halo is visible. Must run WITHOUT
# --headless (dummy renderer returns null viewport textures + won't compile
# the glow shader).

const OUT_DIR := "res://captures/projectile_glow"
const FPS: int = 30
const DURATION: float = 1.0
const FRAME_TIME: float = 1.0 / float(FPS)

# Representative spread of colors/shapes to prove auto-derivation.
const SPECS := [
	"res://scenes/projectiles/bullet_blaster_heavy.tscn",  # cyan player bolt
	"res://scenes/projectiles/bullet_minigun.tscn",        # warm tracer
	"res://scenes/projectiles/bullet_wave_small.tscn",     # green wave
	"res://scenes/projectiles/enemy_bullet_wave.tscn",     # magenta orb
	"res://scenes/projectiles/enemy_bullet_diamond.tscn",  # purple diamond
	"res://scenes/projectiles/enemy_bullet_tracer.tscn",   # cyan tracer
]


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
	# Background on a CanvasLayer BEHIND everything (layer -1) so the glow
	# halo (z_index -1 in the default layer) is not painted over by the bg.
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	root.add_child(bg_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.02, 0.04)
	bg.size = Vector2(960, 540)
	bg.position = Vector2(-240, -135)
	bg_layer.add_child(bg)

	# The root viewport renders in the project's 480x270 logical space
	# (scaled up to the window). Position + size everything in THAT space,
	# matching the working capture scripts; reading get_texture() returns the
	# window-sized framebuffer of this logical content.
	var center: Vector2 = Vector2(240.0, 135.0)
	var n: int = SPECS.size()
	var spacing: float = 32.0
	var start_x: float = center.x - (float(n - 1) * spacing) * 0.5
	var made: Array = []
	for i in range(n):
		var scene: PackedScene = load(SPECS[i])
		if scene == null:
			continue
		var b: Node = scene.instantiate()
		root.add_child(b)
		var p: Vector2 = Vector2(start_x + float(i) * spacing, center.y)
		if b is Node2D:
			(b as Node2D).position = p
			# Native 1x scale — the window renders the 480-logical space at
			# ~5x, so the true 2-3px halo is magnified for inspection without
			# distorting its relative width (judge subtlety on this).
			(b as Node2D).scale = Vector2(1.0, 1.0)
		if "speed" in b:
			b.set("speed", 0.0)
		# Freeze: base_bullet._process advances position AND frees the bullet
		# when it leaves the 480x270 playfield bounds / hits max_lifetime.
		# Our capture viewport is far larger, so disable processing entirely
		# and pin the position.
		b.set_process(false)
		b.set_physics_process(false)
		if "_base_position" in b:
			b.set("_base_position", p)
		# Defang the offscreen-notifier auto-free for these frozen props.
		var notifier: Node = b.get_node_or_null("VisibleOnScreenNotifier2D")
		if notifier != null:
			notifier.queue_free()
		made.append(b)

	# Let _ready() run (glow attaches in _apply_visuals) + animations tick.
	await create_timer(0.2).timeout

	# --- diagnostics: confirm bullets alive + glow color derived ---
	print("[projectile-glow] viewport=", root.get_viewport().size)
	for b in made:
		if not is_instance_valid(b):
			print("  - (freed)")
			continue
		var glow: Node = b.get_node_or_null("ShaderGlow")
		var col: String = "none"
		if glow != null and glow.material is ShaderMaterial:
			var c = (glow.material as ShaderMaterial).get_shader_parameter("glow_color")
			col = str(c)
		var pos: Vector2 = (b as Node2D).global_position if b is Node2D else Vector2.ZERO
		print("  - %s pos=%s glow=%s color=%s" % [b.name, pos, "yes" if glow != null else "NO", col])

	var total: int = int(DURATION * float(FPS))
	for f in total:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))
	print("[projectile-glow] captured %d frames" % total)
	quit()
