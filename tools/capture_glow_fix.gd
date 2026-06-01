extends SceneTree

# Captures the enemy-bullet shader glow halo to prove the frame-strip ghosting
# fix (Roman, 2026-06-01). The enemy_bullet.tscn host is an AnimatedSprite2D
# whose 4 frames are AtlasTexture sub-regions of one 64x16 sheet; the buggy
# glow read ACROSS frame boundaries and bloomed the whole strip. We spawn ONE
# animating enemy bullet on a dark background, let the animation cycle, and zoom
# in so the ~16px bullet + its halo fill the frame. Must run WITHOUT --headless
# (dummy renderer returns null viewport textures + won't compile the shader).

const OUT_DIR := "res://captures/glow_fix"
const FPS: int = 30
const DURATION: float = 2.0
const FRAME_TIME: float = 1.0 / float(FPS)
const BULLET_SCENE := "res://scenes/projectiles/enemy_bullet.tscn"


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
	# Background on a CanvasLayer BEHIND everything (layer -1) so the glow halo
	# (z_index -1 in the default layer) is not painted over by the bg, and so a
	# Camera2D zoom does not move it.
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	root.add_child(bg_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0)
	bg.size = Vector2(960, 540)
	bg.position = Vector2(-240, -135)
	bg_layer.add_child(bg)

	# Logical 480x270 space; pin the bullet at center.
	var center: Vector2 = Vector2(240.0, 135.0)
	var scene: PackedScene = load(BULLET_SCENE)
	var bullet: Node = scene.instantiate()
	root.add_child(bullet)
	if bullet is Node2D:
		(bullet as Node2D).position = center
	if "speed" in bullet:
		bullet.set("speed", 0.0)
	# Freeze movement / lifetime (base_bullet._process advances + frees). The
	# child AnimatedSprite2D autoplays on its OWN timer, so the animation keeps
	# cycling even with the bullet Area2D's processing disabled.
	bullet.set_process(false)
	bullet.set_physics_process(false)
	if "_base_position" in bullet:
		bullet.set("_base_position", center)
	var notifier: Node = bullet.get_node_or_null("VisibleOnScreenNotifier2D")
	if notifier != null:
		notifier.queue_free()

	# Camera zoom magnifies the ~16px bullet so the halo detail is readable.
	var cam := Camera2D.new()
	cam.position = center
	cam.zoom = Vector2(14.0, 14.0)
	root.add_child(cam)
	cam.make_current()

	# Let _ready() run (glow attaches in _apply_visuals) + animation start.
	await create_timer(0.2).timeout

	# Ensure the animation is actually playing.
	var asp: AnimatedSprite2D = bullet.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if asp != null and not asp.is_playing():
		asp.play("default")

	print("[glow-fix] viewport=", root.get_viewport().size)
	var glow: Node = bullet.get_node_or_null("ShaderGlow")
	print("[glow-fix] glow node=", "yes" if glow != null else "NO", " class=", glow.get_class() if glow != null else "-")
	if glow != null and glow.material is ShaderMaterial:
		var c = (glow.material as ShaderMaterial).get_shader_parameter("glow_color")
		print("[glow-fix] glow_color=", c)

	var total: int = int(DURATION * float(FPS))
	for f in total:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))
	print("[glow-fix] captured %d frames" % total)
	quit()
