extends SceneTree

# Captures the HD sector map. The SubViewportContainer shows the 1920x1080
# content stretched to fill the 480x270 game window — capture from main
# viewport (same approach as capture_blaster_muzzle.gd).

const OUT_DIR := "res://captures/sector_map_hd"
const RunStateScript = preload("res://scripts/run_state.gd")
const SECTOR_MAP_SCENE := preload("res://scenes/sector_map_hd.tscn")


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
	# Real Run node using actual run_state.gd so property access works.
	var run := Node.new()
	run.set_script(RunStateScript)
	run.name = "Run"
	root.add_child(run)
	run.new_run()
	run.run_seed = 54321
	await create_timer(0.1).timeout

	var sector_map: Node = SECTOR_MAP_SCENE.instantiate()
	root.add_child(sector_map)

	# Wait long enough for the SubViewport to render its first frame.
	await create_timer(1.0).timeout

	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png(ProjectSettings.globalize_path("%s/frame_0000.png" % OUT_DIR))
		print("[sector-map-hd] saved %dx%d" % [img.get_width(), img.get_height()])
	else:
		print("[sector-map-hd] ERROR: no image")
	quit()
