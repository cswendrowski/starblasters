extends SceneTree

# Single-frame screenshot of the dev menu at native 480x270, upscaled
# 4x for review.

const OUT_PATH := "res://captures/dev_menu.png"
const SCENE := "res://scenes/dev_menu.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(480, 270))
	var err := change_scene_to_file(SCENE)
	if err != OK:
		print("[dev-menu] change_scene failed: ", err)
		quit()
		return
	await create_timer(0.5).timeout
	DisplayServer.window_set_size(Vector2i(480, 270))
	await create_timer(0.3).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		if img.get_width() != 480 or img.get_height() != 270:
			img.resize(480, 270, Image.INTERPOLATE_NEAREST)
		img.resize(1920, 1080, Image.INTERPOLATE_NEAREST)
		img.save_png(ProjectSettings.globalize_path(OUT_PATH))
		print("[dev-menu] saved %s" % OUT_PATH)
	quit()
