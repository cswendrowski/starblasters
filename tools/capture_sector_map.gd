extends SceneTree

const OUT_PATH := "res://captures/sector_map_label_review.png"
const SCENE := "res://scenes/sector_map_v3.tscn"


func _initialize() -> void:
	print("[sector_map] _initialize called")
	_run.call_deferred()


func _run() -> void:
	print("[sector_map] _run called")
	
	# Initialize Run if it exists
	if root.has_node("Run"):
		print("[sector_map] Run autoload found, calling new_run()")
		var run = root.get_node("Run")
		if run.has_method("new_run"):
			run.new_run()
	
	print("[sector_map] Changing scene to: %s" % SCENE)
	var err := change_scene_to_file(SCENE)
	if err != OK:
		print("[sector_map] change_scene failed: ", err)
		quit()
		return
	
	print("[sector_map] Waiting for scene to render...")
	await create_timer(2.0).timeout
	
	print("[sector_map] Capturing viewport...")
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		print("[sector_map] Image captured, size: %dx%d" % [img.get_width(), img.get_height()])
		img.save_png(ProjectSettings.globalize_path(OUT_PATH))
		print("[sector_map] saved %s" % OUT_PATH)
	else:
		print("[sector_map] ERROR - failed to get viewport image")
	
	quit()
