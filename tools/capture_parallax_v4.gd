extends SceneTree

# Capture Parallax V4 backdrop scrolling for ~4 seconds.
#
# Instantiates the REAL backdrop_coordinator.tscn (children baked in) so the
# coordinator's _ready()/_populate() runs with its layer children present and
# actually spawns the planet, asteroids, and nebula. The earlier version
# hand-built the coordinator and added it to the tree before its children
# existed, so _populate() found nothing and only the self-spawning star/streak
# layers showed.
#
# Renders at the project's native 480×270 internal viewport (CanvasLayers
# render into the root viewport in that coordinate space); ffmpeg upscales the
# captured frames 4× with nearest-neighbour in the .ps1 wrapper.

const BackdropCoordinatorScene = preload("res://scenes/parallax/backdrop_coordinator.tscn")

const OUT_DIR := "res://captures/parallax_v4"
const FPS: int = 24
const DURATION: float = 4.0
const FRAME_TIME: float = 1.0 / float(FPS)

# Force a visible globe planet (5 = LandMasses) and a brisk drift so the
# planet + asteroids show clear motion within the short capture window.
const FORCED_PLANET_IDX: int = -1
const CAPTURE_DRIFT_SPEED: float = 50.0


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
	# Instantiate the real coordinator scene. Set exports BEFORE add_child so
	# _ready()/_populate() reads them (forced planet + brisk drift for capture).
	var backdrop := BackdropCoordinatorScene.instantiate()
	backdrop.set("forced_planet_idx", FORCED_PLANET_IDX)
	backdrop.set("drift_speed", CAPTURE_DRIFT_SPEED)
	root.add_child(backdrop)

	# Let _ready/_populate spawn everything + shaders compile.
	await create_timer(0.6).timeout

	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
		if f % 10 == 0:
			print("[parallax-v4] frame %d / %d" % [f, frame_count])

	print("[parallax-v4] captured %d frames" % frame_count)
	quit()
