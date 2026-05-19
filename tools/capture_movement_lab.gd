extends SceneTree

const SCENE := "res://scenes/dev/movement_lab.tscn"
const OUT_DIR := "res://captures/movement_lab"


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	_run.call_deferred()


func _run() -> void:
	var ps: PackedScene = load(SCENE)
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	# Capture a few frames spaced out so movement is visible across them.
	for i in 4:
		await create_timer(0.8).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var p := "%s/frame_%d.png" % [OUT_DIR, i]
			img.save_png(ProjectSettings.globalize_path(p))
			print("[movelab] wrote %s" % p)
	inst.queue_free()
	quit()
