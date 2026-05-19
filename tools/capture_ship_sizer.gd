extends SceneTree

const OUT_PATH := "res://captures/ship_sizer.png"
const SCENE := "res://scenes/dev/ship_sizer.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(480, 270))
	var err := change_scene_to_file(SCENE)
	if err != OK:
		print("[ship-sizer] change_scene failed: ", err)
		quit()
		return
	await create_timer(0.6).timeout
	DisplayServer.window_set_size(Vector2i(480, 270))
	# Note: stepping the picker to an enemy in this -s capture context
	# fails because the standalone runtime can't resolve class_name
	# Playfield used inside enemy scripts (the global script class cache
	# only loads via the editor / packed game path). Live in-game flow
	# works fine — Roman can verify enemies in the live tuner.
	await create_timer(0.3).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		if img.get_width() != 480 or img.get_height() != 270:
			img.resize(480, 270, Image.INTERPOLATE_NEAREST)
		img.resize(1920, 1080, Image.INTERPOLATE_NEAREST)
		img.save_png(ProjectSettings.globalize_path(OUT_PATH))
		print("[ship-sizer] saved %s" % OUT_PATH)
	quit()
