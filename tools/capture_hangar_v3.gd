extends SceneTree

# Snapshot of the rebuilt hangar — native viewport (no HD swap, no
# SubViewport), live-game player + backdrop + dummy target.

const SCENE := "res://scenes/hangar.tscn"
const OUT := "res://captures/hangar_v3.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps: PackedScene = load(SCENE)
	if ps == null:
		print("[hangar-v3] failed to load scene")
		quit()
		return
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await create_timer(1.5).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path(OUT))
		print("[hangar-v3] wrote %s" % OUT)
	quit()
