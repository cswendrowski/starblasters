extends SceneTree
# One-shot: generate placeholder PNGs for the multi-part cruiser prototype (core + destructible
# parts). Run: E:\tools\Godot_v4.6.3\Godot_v4.6.3-stable_win64.exe --headless --script tools/gen_cruiser_placeholders.gd
# Distinct flat-colored chamfered blocks so the cruiser reads as a multi-part structure in play.
# Swap each for real art later — one PNG per part type, same name/size keeps the .tscn wiring.

func _init() -> void:
	var dir_res := "res://graphics/enemies/placeholder/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_res))
	_make(dir_res + "cruiser_core.png",   60, 76, Color(0.20, 0.27, 0.40), Color(0.46, 0.60, 0.80), 6)  # steel hull
	_make(dir_res + "cruiser_gun.png",    22, 22, Color(0.52, 0.16, 0.16), Color(0.88, 0.36, 0.30), 3)  # red gun pod
	_make(dir_res + "cruiser_engine.png", 20, 28, Color(0.50, 0.30, 0.10), Color(0.92, 0.62, 0.20), 3)  # amber engine
	_make(dir_res + "cruiser_bridge.png", 28, 18, Color(0.12, 0.40, 0.46), Color(0.34, 0.72, 0.80), 3)  # teal bridge
	print("CRUISER PLACEHOLDERS DONE")
	quit()


# A flat fill + 2px border, with the four corners chamfered (skipped) for a slightly beveled block.
func _make(path: String, w: int, h: int, fill: Color, border: Color, chamfer: int) -> void:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			var cx: int = min(x, w - 1 - x)
			var cy: int = min(y, h - 1 - y)
			if cx + cy < chamfer:
				continue                       # chamfer the corner
			img.set_pixel(x, y, border if (cx < 2 or cy < 2) else fill)
	img.save_png(ProjectSettings.globalize_path(path))
	print("  wrote ", path, " (", w, "x", h, ")")
