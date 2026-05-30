extends Control

const OUT_PATH  := "res://captures/hud_live.png"
const SHIP_TEX  := "res://Mini Pixel Pack 3/Player ship/Player_ship (16 x 16).png"

var _ship_tex: Texture2D
var _ui: Control = null

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(480, 270))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_ship_tex = load(SHIP_TEX)
	
	# Instantiate the live HUD
	_ui = load("res://scenes/ui.tscn").instantiate()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_ui)
	
	# Seed with test state
	if _ui.has_method("update_hull"):
		_ui.update_hull(10, 7)
	if _ui.has_method("update_shield"):
		_ui.update_shield(30, 24)
	if _ui.has_method("update_score"):
		_ui.update_score(4250)
	
	queue_redraw()
	
	# Wait for layout and one frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUT_PATH).get_base_dir())
	img.save_png(ProjectSettings.globalize_path(OUT_PATH))
	print("[hud_live] saved ", ProjectSettings.globalize_path(OUT_PATH))
	get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 270), Color(0.05, 0.05, 0.08))

	# Seeded star field
	var rng := RandomNumberGenerator.new()
	rng.seed = 99137
	for i in range(140):
		var x := rng.randf_range(0, 480)
		var y := rng.randf_range(0, 270)
		var b  := rng.randf_range(0.2, 0.9)
		draw_rect(Rect2(x, y, 1, 1), Color(b, b, b + 0.05, b))

	# Playfield column guides
	draw_line(Vector2(132, 0), Vector2(132, 270), Color(0.25, 0.30, 0.45, 0.35), 1.0)
	draw_line(Vector2(348, 0), Vector2(348, 270), Color(0.25, 0.30, 0.45, 0.35), 1.0)

	# Player ship centred in playfield
	if _ship_tex != null:
		var sw := float(_ship_tex.get_width())
		var sh := float(_ship_tex.get_height())
		var s  := 3.0
		draw_texture_rect(_ship_tex, Rect2(240.0 - sw*s*0.5, 190.0 - sh*s*0.5, sw*s, sh*s), false)
