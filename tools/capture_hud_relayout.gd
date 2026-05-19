extends SceneTree

# Capture vanilla combat (main.tscn) at native 480x270 to show the HUD
# relayout: health bar + shield pips centred over the 216-wide playfield
# band; bounty + ammo in the right gutter.

const OUT_DIR := "res://captures/hud_relayout"
const FPS: int = 24
const DURATION: float = 6.0
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


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(480, 270))
	var run_node := root.get_node_or_null("/root/Run")
	if run_node and run_node.has_method("new_run"):
		run_node.new_run()
	var err := change_scene_to_file(MAIN_SCENE)
	if err != OK:
		print("[hud-relayout] change_scene failed: ", err)
		quit()
		return
	await create_timer(0.8).timeout
	DisplayServer.window_set_size(Vector2i(480, 270))
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
	print("[hud-relayout] captured %d frames" % frame_count)
	quit()
