extends SceneTree

# Capture a single frame of the UI Designer dev page at native 480x270
# for review. Boots the tuner, waits long enough for layout to settle,
# saves one PNG.

const OUT_PATH := "res://captures/ui_designer.png"
const SCENE := "res://scenes/dev/ui_designer.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(480, 270))
	var err := change_scene_to_file(SCENE)
	if err != OK:
		print("[ui-designer] change_scene failed: ", err)
		quit()
		return
	await create_timer(0.5).timeout
	DisplayServer.window_set_size(Vector2i(480, 270))
	# Two more frames so the rail + HUD layout fully resolves.
	await create_timer(0.3).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		if img.get_width() != 480 or img.get_height() != 270:
			img.resize(480, 270, Image.INTERPOLATE_NEAREST)
		# Upscale 4x for review legibility.
		img.resize(1920, 1080, Image.INTERPOLATE_NEAREST)
		img.save_png(ProjectSettings.globalize_path(OUT_PATH))
		print("[ui-designer] saved %s" % OUT_PATH)
	else:
		print("[ui-designer] no image")
	quit()
