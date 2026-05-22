extends SceneTree

# Captures the Sector Map V3 scene:
# Grid background + 3 breathing/pulsing stars (B-type, G-type, M-type)

const OUT_DIR := "res://captures/sector_map_v3"
const FPS: int = 24
const DURATION: float = 4.0
const FRAME_TIME: float = 1.0 / float(FPS)
const SECTOR_MAP_V3_SCENE := preload("res://scenes/dev/sector_map_v3.tscn")


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
	# Load the sector map scene — it handles its own rendering
	var scene: Node2D = SECTOR_MAP_V3_SCENE.instantiate()
	root.add_child(scene)

	# Wait a frame for initialization
	await create_timer(0.05).timeout

	# Capture frames at 24fps for 4 seconds = 96 frames
	var total: int = int(DURATION * float(FPS))
	for f in total:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))

	print("[sector-map-v3] captured %d frames" % total)
	quit()
