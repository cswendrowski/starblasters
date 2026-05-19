extends SceneTree

# Boot main.tscn, deal damage to the player so HULL COMPROMISED appears,
# also force the wave label visible. Screenshot the combat HUD with all
# HD-migrated widgets in their natural state.

const OUT_DIR := "user://hd_hud"


func _init() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for _i in range(30):
		await process_frame
	if current_scene:
		var ui = current_scene.find_child("UI", true, false)
		var player = current_scene.find_child("Player", true, false)
		# Hit the hull below 50% to trigger HULL COMPROMISED.
		if ui and ui.has_method("update_hull") and player and "max_hull" in player:
			ui.update_hull(player.max_hull, int(player.max_hull * 0.3))
		# Force WaveLabel visible.
		var wl = current_scene.find_child("WaveLabel", true, false)
		if wl and wl is Label:
			wl.visible = true
			wl.modulate = Color(1, 1, 1, 1)
			wl.text = "WAVE 3 / 7"
		# Force BossLabel visible to demo HD migration.
		var bl = current_scene.find_child("BossLabel", true, false)
		if bl and bl is Label:
			bl.visible = true
			bl.text = "SECTOR COMMANDER"
	for _i in range(8):
		await process_frame
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/frame.png")
	print("saved: ", ProjectSettings.globalize_path(OUT_DIR + "/frame.png"))
	quit()
