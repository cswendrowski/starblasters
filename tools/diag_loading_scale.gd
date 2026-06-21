extends SceneTree

# Diagnostic: reproduce the LIVE entry into the loading screen (change_scene from a prior HD scene,
# like the sector map) and print the actual content-scale + subviewport sizes, to pin down why the
# live loading screen renders blurry/small. Expected when correct: content_scale 1920x1080,
# PlayContainer 1920x1080, PlayViewport 480x270. Run: godot --headless -s res://tools/diag_loading_scale.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	# Stand in for the sector map: an HD scene that owns an HdViewportScope.
	var prior := Control.new()
	prior.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(prior)
	current_scene = prior
	HdViewportScope.attach(prior, Vector2i(1920, 1080))
	await process_frame
	print("[diag] prior HD content_scale_size = ", root.content_scale_size)

	# Transition into the loading screen exactly like LevelLauncher does.
	change_scene_to_file("res://scenes/loading_screen.tscn")
	for _i in 14:
		await process_frame

	var ls: Node = current_scene
	print("[diag] current_scene = ", ls.scene_file_path if ls else "<null>")
	print("[diag] window content_scale_size = ", root.content_scale_size, "   (want 1920, 1080)")
	if ls is Control:
		print("[diag] loading_screen.size = ", (ls as Control).size, "   (want 1920, 1080)")
	var view: Node = ls.get_node_or_null("WorldView") if ls else null
	var vp: Node = ls.get_node_or_null("WorldViewport") if ls else null
	if view is Control:
		print("[diag] WorldView (TextureRect).size = ", (view as Control).size, "   (want 1920, 1080)")
	if vp is SubViewport:
		print("[diag] WorldViewport.size = ", (vp as SubViewport).size, "   (want 480, 270)")
	else:
		print("[diag] WorldViewport NOT FOUND")
	quit(0)
