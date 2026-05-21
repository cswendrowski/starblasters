extends SceneTree

# Snapshot of the parallax tuner with V3 active. Cycles past V2 to get
# there since the variant button rotates V1 → V2 → V3 → V1.

const SCENE := "res://scenes/dev/parallax_tuner.tscn"
const OUT := "res://captures/parallax_tuner_v3.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var win := root.get_window()
	if win:
		win.size = Vector2i(1920, 1080)
	var ps: PackedScene = load(SCENE)
	if ps == null:
		print("[parallax-tuner-v3] failed to load scene")
		quit()
		return
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await create_timer(0.4).timeout
	# Cycle twice to land on V3 (V1 → V2 → V3).
	if inst.has_method("_on_swap_version"):
		inst.call("_on_swap_version")
		await create_timer(0.4).timeout
		inst.call("_on_swap_version")
	await create_timer(1.6).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path(OUT))
		print("[parallax-tuner-v3] wrote %s" % OUT)
	# Dump the layer inventory so we can confirm V3's 5-layer shape.
	var bd = inst.get("_backdrop") if "_backdrop" in inst else null
	if bd:
		print("[parallax-tuner-v3] backdrop class: %s" % bd.get_script().resource_path)
		print("[parallax-tuner-v3] children:")
		for c in bd.get_children():
			print("  - %s (%s)" % [c.name, c.get_class()])
	quit()
