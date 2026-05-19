extends SceneTree

# One-shot: boot main.tscn, force the wave label to a representative
# string, then screenshot the playfield. Output: captures/hd_wave_label/*.png
#
# Compare the new HD-density WaveLabel (top-right gutter, font_size=16 in
# 960×540 SubViewport) against any in-game text to gauge whether 2× UI
# density looks clean or clashes with the 4× chunky-pixel game art.

const OUT_DIR := "user://hd_wave_label"


func _init() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	# Wait a few frames so _ready + _install_playfield_frame complete.
	for _i in range(20):
		await process_frame
	var ui = current_scene.find_child("UI", true, false) if current_scene else null
	if ui and ui.has_method("update_wave"):
		ui.update_wave(2, 7)
	# update_wave leaves the label hidden in production (banner carries the
	# info). Force visible for the spike so Roman can eyeball 2× density.
	var label: Label = current_scene.find_child("WaveLabel", true, false) if current_scene else null
	if label:
		label.visible = true
		label.modulate = Color(1, 1, 1, 1)
	# Let one more frame land so the SubViewport repaints.
	for _i in range(5):
		await process_frame
	# Capture.
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var img := root.get_viewport().get_texture().get_image()
	var path := OUT_DIR + "/frame.png"
	img.save_png(path)
	print("saved: ", ProjectSettings.globalize_path(path))
	quit()
