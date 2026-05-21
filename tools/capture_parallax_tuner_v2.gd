extends SceneTree

# Capture the parallax tuner with V2 backdrop active so we can see what
# the "white screen" report actually shows.

const SCENE := "res://scenes/dev/parallax_tuner.tscn"
const OUT := "res://captures/parallax_tuner_v2_mode.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var win := root.get_window()
	if win:
		win.size = Vector2i(1920, 1080)
	var ps: PackedScene = load(SCENE)
	if ps == null:
		print("[parallax-tuner-v2] failed to load scene")
		quit()
		return
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await create_timer(0.4).timeout
	# Trigger the V2 swap programmatically.
	if inst.has_method("_on_swap_version"):
		inst.call("_on_swap_version")
	await create_timer(1.4).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path(OUT))
		print("[parallax-tuner-v2] wrote %s" % OUT)
	# Also dump V2 layer info so we can see what got built.
	var bd = inst.get("_backdrop") if "_backdrop" in inst else null
	if bd:
		print("[parallax-tuner-v2] backdrop class: %s" % bd.get_script().resource_path)
		print("[parallax-tuner-v2] children:")
		for c in bd.get_children():
			var mod := ""
			if c is CanvasItem:
				mod = " modulate=%s" % str((c as CanvasItem).modulate)
			print("  - %s (%s)%s" % [c.name, c.get_class(), mod])
	quit()
