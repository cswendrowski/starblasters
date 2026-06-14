extends SceneTree

# Capture vanilla combat (main.tscn) showing the 216×270 playfield band
# centred in the 480×270 viewport. Adds a top-layer light-blue band outline
# so the gutters are clearly visible in the capture (the in-game outline
# currently lives behind the backdrop and doesn't show through).

const _PreloadPlayfield = preload("res://scripts/systems/playfield.gd")

const OUT_DIR := "res://captures/playfield_band"
const FPS: int = 24
const DURATION: float = 7.0
const FRAME_TIME: float = 1.0 / float(FPS)
const MAIN_SCENE := "res://scenes/main.tscn"


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var d := DirAccess.open(OUT_DIR)
	if d:
		d.list_dir_begin()
		while true:
			var fn := d.get_next()
			if fn == "":
				break
			if fn.ends_with(".png"):
				d.remove(fn)
		d.list_dir_end()
	_run.call_deferred()


func _add_overlay_frame() -> void:
	# A foreground CanvasLayer that renders ABOVE the gameplay, so the band
	# outline + gutter shading reads in the capture even though the in-game
	# frame is currently at layer -1 behind the backdrop.
	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.name = "CaptureOverlay"
	root.add_child(layer)
	# Tinted gutter rectangles (left + right) — very subtle so the
	# underlying parallax still reads.
	var left := ColorRect.new()
	left.color = Color(0.35, 0.65, 1.0, 0.10)
	left.position = Vector2(0, 0)
	left.size = Vector2(Playfield.X_MIN, Playfield.H)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(left)
	var right := ColorRect.new()
	right.color = Color(0.35, 0.65, 1.0, 0.10)
	right.position = Vector2(Playfield.X_MAX, 0)
	right.size = Vector2(480.0 - Playfield.X_MAX, Playfield.H)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(right)
	# Outline panel around the play band.
	var frame := Panel.new()
	frame.position = Vector2(Playfield.X_MIN, Playfield.Y_MIN)
	frame.size = Vector2(Playfield.W, Playfield.H)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(0.45, 0.75, 1.0, 0.85)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	frame.add_theme_stylebox_override("panel", sb)
	layer.add_child(frame)


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(480, 270))
	var run_node := root.get_node_or_null("/root/Run")
	if run_node and run_node.has_method("new_run"):
		run_node.new_run()
	var err := change_scene_to_file(MAIN_SCENE)
	if err != OK:
		print("[playfield-band] change_scene failed: ", err)
		quit()
		return
	await create_timer(0.8).timeout
	DisplayServer.window_set_size(Vector2i(480, 270))
	_add_overlay_frame()
	await create_timer(0.2).timeout
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			if img.get_width() != 480 or img.get_height() != 270:
				img.resize(480, 270, Image.INTERPOLATE_NEAREST)
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
	print("[playfield-band] captured %d frames" % frame_count)
	quit()
