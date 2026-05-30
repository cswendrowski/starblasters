extends Control

const CAPTURE_FRAME_DIR := "res://captures/frames_light_patterns"

func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	get_window().size = Vector2i(480, 270)
	
	# Simple colored background
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	
	# Create output dir
	var dir_path := ProjectSettings.globalize_path(CAPTURE_FRAME_DIR)
	DirAccess.make_dir_recursive_absolute(dir_path)
	
	# Short delay then capture
	get_tree().create_timer(0.5).timeout.connect(func():
		_capture_test()
	)


func _capture_test() -> void:
	var viewport := get_viewport()
	var texture := viewport.get_texture()
	if texture == null:
		var f := FileAccess.open(ProjectSettings.globalize_path(CAPTURE_FRAME_DIR + "/debug.txt"), FileAccess.WRITE)
		if f:
			f.store_line("Texture is null!")
		get_tree().quit()
		return
	
	var img := texture.get_image()
	if img == null:
		var f := FileAccess.open(ProjectSettings.globalize_path(CAPTURE_FRAME_DIR + "/debug.txt"), FileAccess.WRITE)
		if f:
			f.store_line("Image is null!")
		get_tree().quit()
		return
	
	var frame_path := CAPTURE_FRAME_DIR + "/frame_0000.png"
	img.save_png(ProjectSettings.globalize_path(frame_path))
	
	var f := FileAccess.open(ProjectSettings.globalize_path(CAPTURE_FRAME_DIR + "/debug.txt"), FileAccess.WRITE)
	if f:
		f.store_line("Frame saved: %s" % frame_path)
	
	get_tree().quit()
