extends SceneTree

# One-frame screenshot of the parallax tuner so the rewrite can be
# reviewed without booting the editor.

const SCENE := "res://scenes/dev/parallax_tuner.tscn"
const OUT := "res://captures/parallax_tuner_v2.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Resize the root window so the screenshot lands at HD resolution
	# (the tuner swaps content_scale_size to 1920×1080 but the rendered
	# texture is bounded by the actual window size).
	var win := root.get_window()
	if win:
		win.size = Vector2i(1920, 1080)
	var ps: PackedScene = load(SCENE)
	if ps == null:
		print("[parallax-tuner] failed to load scene")
		quit()
		return
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	# Wait for backdrop spawn + layer enumeration.
	await create_timer(1.4).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path(OUT))
		print("[parallax-tuner] wrote %s" % OUT)
	quit()
