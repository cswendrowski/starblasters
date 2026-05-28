extends SceneTree

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(480, 270))
	change_scene_to_file.call_deferred("res://scenes/dev/hud_mockup.tscn")
