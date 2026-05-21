extends SceneTree

const SCENE := "res://scenes/dev/parallax_tuner.tscn"
const OUT := "res://captures/parallax_tuner_v1.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var win := root.get_window()
	if win:
		win.size = Vector2i(1920, 1080)
	var ps: PackedScene = load(SCENE)
	if ps == null:
		quit()
		return
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await create_timer(2.0).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path(OUT))
		print("[parallax-tuner-v1] wrote %s" % OUT)
	quit()
