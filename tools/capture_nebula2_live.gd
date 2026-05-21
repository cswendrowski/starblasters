extends SceneTree

# Capture the live combat backdrop with the nebula2 near-pass active.
# Roman's call: see it under real conditions (alongside planets / asteroids /
# foreground), not in isolation. Loads main.tscn, waits for the backdrop to
# settle, then captures ~5s of frames.

const OUT_DIR := "res://captures/nebula2_live"
const FPS: int = 20
const DURATION: float = 6.0
const FRAME_TIME: float = 1.0 / float(FPS)


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
	# Lock the seed so the celestial pick is stable and the nebula band
	# stays consistent run-to-run. Seed chosen by trial — picks a layout
	# with a visible mid-frame planet, gives the nebula room to read.
	if root.has_node("/root/Run"):
		var run = root.get_node("/root/Run")
		if "run_seed" in run:
			run.run_seed = 31337
	var ps: PackedScene = load("res://scenes/main.tscn")
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	# Give the backdrop a beat to compose and the wave director to start.
	await create_timer(0.6).timeout
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
	print("[nebula2-live] captured %d frames" % frame_count)
	quit()
