extends SceneTree

# Standalone V3 capture — bypasses the parallax tuner entirely.
# Just instantiates galaxy_backdrop_v3 at native 480×270 in a fresh
# root viewport. Used to isolate whether V3 itself renders correctly,
# or whether the flat-color symptom is something the tuner's render
# pipeline introduces.

const V3_SCRIPT = preload("res://scripts/parallax/galaxy_backdrop_v3.gd")
const OUT := "res://captures/v3_standalone.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var win := root.get_window()
	if win:
		win.size = Vector2i(1920, 1080)
	# Single root viewport, V3 mounted directly with scale 4× so the
	# native 480×270 backdrop fills the window. No SubViewport, no
	# CanvasLayer transform — the simplest possible render path.
	var holder := Node2D.new()
	holder.name = "Backdrop"
	holder.scale = Vector2(4, 4)
	holder.set_script(V3_SCRIPT)
	if root.has_node("/root/Run"):
		var run = root.get_node("/root/Run")
		if "run_seed" in run:
			run.run_seed = 13579
		if "visited_nodes" in run:
			run.visited_nodes.clear()
	root.add_child(holder)
	await create_timer(1.6).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path(OUT))
		print("[v3-standalone] wrote %s" % OUT)
	# Dump the layer shape for the post.
	print("[v3-standalone] backdrop children:")
	for c in holder.get_children():
		var extra := ""
		if c is ColorRect:
			extra = "  color=%s a=%.2f" % [str(c.color), float(c.color.a)]
		print("  - %s (%s)%s" % [c.name, c.get_class(), extra])
		# Inside content layers: dump CanvasGroup presence + tint.
		if c is Parallax2D:
			for cc in c.get_children():
				if cc is CanvasGroup:
					var m: ShaderMaterial = cc.material
					var t = m.get_shader_parameter("tint") if m else "n/a"
					print("    └─ Content CanvasGroup, tint=%s, children=%d" % [str(t), cc.get_child_count()])
	quit()
