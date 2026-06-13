extends SceneTree

# Integrated nebula capture — boots the REAL combat backdrop (backdrop_coordinator) with a per-POI
# nebula band set, so the GIF shows the in-game look: tinted procedural cloud over the starfield/planet,
# parallax-scrolling AND swirling (the new TIME-driven warp). Alpha is boosted from the in-game default
# (0.1-0.2) to ~0.55 so the swirl reads in a short clip — note that in the live game it's far dimmer.
#   godot --headless -s res://tools/capture_nebula_live.gd

const OUT_DIR := "res://captures/nebula_live"
const FPS: int = 24
const DURATION: float = 6.0
const CAPTURE_ALPHA: float = 0.55   # boosted for review visibility (in game: 0.1-0.2)


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
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
	root.get_viewport().size = Vector2i(480, 270)
	var run = root.get_node_or_null("/root/Run")
	if run:
		run.new_run()
		run.current_stellar = {
			"planet_idx": 5, "planet_seed": 4242, "star_color": Color(0.80, 0.85, 1.0),
			"nebula_band": "nebula_magenta", "nebula_tint": Color(0.85, 0.58, 1.0),
		}
	var inst: Node = load("res://scenes/parallax/backdrop_coordinator.tscn").instantiate()
	root.add_child(inst)
	await create_timer(0.3).timeout
	# Boost the spawned nebula rects so the swirl is visible in a short clip.
	for rect in inst.find_children("Nebula", "", true, false):
		if rect is ColorRect and (rect as ColorRect).material is ShaderMaterial:
			((rect as ColorRect).material as ShaderMaterial).set_shader_parameter("max_alpha", CAPTURE_ALPHA)
	var frames: int = int(DURATION * float(FPS))
	for f in frames:
		await create_timer(1.0 / float(FPS)).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))
	print("[nebula_live] captured %d frames to %s" % [frames, OUT_DIR])
	quit()
