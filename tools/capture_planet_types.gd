extends SceneTree

# Diagnostic: force each planet index 0-8 through the coordinator and save one
# frame each, to confirm every planet type (including Star/BlackHole/Galaxy)
# actually renders. Run: godot --path . -s tools/capture_planet_types.gd

const BackdropCoordinatorScene = preload("res://scenes/parallax/backdrop_coordinator.tscn")
const OUT_DIR := "res://captures/planet_types"


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	_run.call_deferred()


func _run() -> void:
	for idx in 9:
		var backdrop := BackdropCoordinatorScene.instantiate()
		backdrop.set("forced_planet_idx", idx)
		backdrop.set("planet_size", 200.0)
		backdrop.set("planet_size_variance", 0.0)
		backdrop.set("drift_speed", 0.0)
		root.add_child(backdrop)
		await create_timer(0.5).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/planet_%d.png" % [OUT_DIR, idx]))
		print("[planet-types] idx %d captured" % idx)
		backdrop.queue_free()
		await create_timer(0.1).timeout
	print("[planet-types] done")
	quit()
