extends SceneTree

# Diagnostic: load the actual Parallax Tuner scene and capture frames, to see
# whether its SubViewport-rendered backdrop animates (twinkle/scroll/drift) and
# matches the live V4 backdrop. Run: godot --path . -s tools/capture_tuner.gd

const TUNER_SCENE := "res://scenes/dev/parallax_tuner.tscn"
const OUT_DIR := "res://captures/tuner"
const FPS: int = 24
const DURATION: float = 4.0
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
	var ps := load(TUNER_SCENE) as PackedScene
	var tuner := ps.instantiate()
	root.add_child(tuner)
	await create_timer(0.8).timeout
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/frame_%04d.png" % [OUT_DIR, f]))
		if f % 10 == 0:
			print("[tuner] frame %d / %d" % [f, frame_count])
	print("[tuner] done")
	quit()
