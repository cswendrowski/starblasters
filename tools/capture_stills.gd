extends SceneTree

const SCENE := "res://scenes/main.tscn"
const OUT_PATH := "res://captures/combat.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await create_timer(0.2).timeout
	var ps: PackedScene = load(SCENE)
	if ps == null:
		quit()
		return
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	# Long enough for intro flicker + first wave spawn.
	await create_timer(4.0).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_PATH))
	print("[stills] wrote %s" % OUT_PATH)
	inst.queue_free()
	quit()
