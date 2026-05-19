extends SceneTree

# Capture a sequence of PNG frames of the shield_pips_demo scene. Run
# through ffmpeg afterward to produce a GIF.

const SCENE := "res://scenes/dev/shield_pips_demo.tscn"
const FRAME_DIR := "res://captures/frames_shield"
const FPS := 12
const DURATION := 12.0


func _initialize() -> void:
	var dir := ProjectSettings.globalize_path(FRAME_DIR)
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var d := DirAccess.open(FRAME_DIR)
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
	var ps: PackedScene = load(SCENE)
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await create_timer(0.2).timeout
	var frame_count: int = int(DURATION * FPS)
	var step: float = 1.0 / float(FPS)
	for i in frame_count:
		await create_timer(step).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		var path: String = "%s/frame_%04d.png" % [FRAME_DIR, i]
		img.save_png(ProjectSettings.globalize_path(path))
	print("[gif] captured %d frames at %d fps" % [frame_count, FPS])
	inst.queue_free()
	quit()
