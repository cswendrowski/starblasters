extends SceneTree

# Key architecture test: does a parallax LAYER's CanvasModulate (post-shader composite multiply)
# bloom the shader-driven planet where node.modulate failed? If yes, per-layer CanvasModulate glow
# can replace the palette hack and work UNIFORMLY across all layers (planets, star dots, streaks).

var _lab: Node = null

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/_diag"))
	_run.call_deferred()

func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/_diag/%s.png" % name))
	print("[diag] saved ", name)

func _settle(n: int) -> void:
	for _i in n:
		await create_timer(0.02).timeout

func _set_layer_cm(layer_name: String, m: float) -> void:
	var ln = _lab._backdrop.get_node_or_null(layer_name)
	if ln == null:
		print("[diag] no layer ", layer_name); return
	var cm = ln.get_node_or_null("CanvasModulate")
	if cm == null:
		print("[diag] layer ", layer_name, " has NO CanvasModulate"); return
	cm.color = Color(m, m, m, 1.0)
	print("[diag] set ", layer_name, " CanvasModulate=", m)

func _run() -> void:
	_lab = load("res://scenes/dev/parallax_tuner.tscn").instantiate()
	root.add_child(_lab)
	await create_timer(0.6).timeout
	_lab._forced_planet = 5
	_lab._on_gradient_glows_toggled(false)
	_lab._set_worldenv(true)
	_lab._rebuild_backdrop()
	await _settle(40)
	_set_layer_cm("LayerPlanet", 1.0)
	await _settle(12)
	await _grab("cm_m1")
	_set_layer_cm("LayerPlanet", 2.5)
	await _settle(12)
	await _grab("cm_m25")
	quit()
