extends Control

const OUT_PATH  := "res://captures/hud_mockup.png"
const DOT_TEX   := "res://graphics/ui/hud_dot_light.png"
const ANN_TEX   := "res://graphics/ui/hud_annunciator_danger.png"
const SHIP_TEX  := "res://Mini Pixel Pack 3/Player ship/Player_ship (16 x 16).png"
const FONT_PATH := "res://graphics/fonts/PixelOperator.ttf"

var _dot_tex:  Texture2D
var _ann_tex:  Texture2D
var _ship_tex: Texture2D
var _font:     Font

const DOT_FW := 8
const DOT_FH := 8
const ANN_FW := 32
const ANN_FH := 32

const SHIELD_ON   := [10, 10, 4]
const SHIELD_ROWS := 3
const SHIELD_COLS := 10
const HULL_ON     := 7
const HULL_COLS   := 10

const COLOR_GOLD   := Color(1.00, 0.86, 0.42, 1.0)
const COLOR_GREEN  := Color(0.55, 1.00, 0.50, 1.0)
const COLOR_WHITE  := Color(1.00, 1.00, 1.00, 1.0)
const COLOR_SHIELD := Color(0.35, 0.65, 1.00, 1.0)
const COLOR_HULL   := Color(1.00, 0.30, 0.30, 1.0)


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(480, 270))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_dot_tex  = load(DOT_TEX)
	_ann_tex  = load(ANN_TEX)
	_ship_tex = load(SHIP_TEX)
	_font     = load(FONT_PATH)
	queue_redraw()

	# [pos, text, color]
	var entries: Array = [
		[Vector2(392, 16),  "BLASTER",      COLOR_WHITE],
		[Vector2(456, 16),  "ACTIVE",       COLOR_GREEN],
		[Vector2(392, 32),  "Laser Cannon", COLOR_GREEN],
		[Vector2(456, 32),  "120",          COLOR_GREEN],
		[Vector2(392, 48),  "Rocket Pod",   COLOR_GREEN],
		[Vector2(456, 48),  "6",            COLOR_GREEN],
		[Vector2(392, 64),  "Drone Swarm",  COLOR_GREEN],
		[Vector2(456, 64),  "|||",          COLOR_GREEN],
		[Vector2(392, 240), "BOUNTY",       COLOR_GOLD],
		[Vector2(448, 240), "4,250",        COLOR_GOLD],
	]
	for e in entries:
		var lbl := Label.new()
		lbl.text = e[1]
		lbl.add_theme_font_override("font", _font)
		lbl.add_theme_font_size_override("font_size", 7)
		lbl.add_theme_color_override("font_color", e[2])
		lbl.position = e[0]
		add_child(lbl)

	await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUT_PATH).get_base_dir())
	img.save_png(ProjectSettings.globalize_path(OUT_PATH))
	print("[hud_mockup] saved ", ProjectSettings.globalize_path(OUT_PATH))
	get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 270), Color(0.05, 0.05, 0.08))

	# Seeded star field for gameplay context
	var rng := RandomNumberGenerator.new()
	rng.seed = 99137
	for i in range(140):
		var x := rng.randf_range(0, 480)
		var y := rng.randf_range(0, 270)
		var b  := rng.randf_range(0.2, 0.9)
		draw_rect(Rect2(x, y, 1, 1), Color(b, b, b + 0.05, b))

	# Subtle playfield column guides
	draw_line(Vector2(132, 0), Vector2(132, 270), Color(0.25, 0.30, 0.45, 0.35), 1.0)
	draw_line(Vector2(348, 0), Vector2(348, 270), Color(0.25, 0.30, 0.45, 0.35), 1.0)

	# Player ship — centred in playfield at Y=190
	if _ship_tex != null:
		var sw := float(_ship_tex.get_width())
		var sh := float(_ship_tex.get_height())
		var scale := 3.0
		var dst := Rect2(240.0 - sw * scale * 0.5, 190.0 - sh * scale * 0.5,
						 sw * scale, sh * scale)
		draw_texture_rect(_ship_tex, dst, false)

	if _dot_tex == null or _ann_tex == null:
		return

	# Shield pips
	for row in range(SHIELD_ROWS):
		for col in range(SHIELD_COLS):
			var on: bool = col < SHIELD_ON[row]
			var src := Rect2(DOT_FW * (1 if on else 0), 0, DOT_FW, DOT_FH)
			var dst := Rect2(16 + col * (DOT_FW + 2), 16 + row * (DOT_FH + 2), DOT_FW, DOT_FH)
			draw_texture_rect_region(_dot_tex, dst, src, COLOR_SHIELD)

	# Hull pips
	for col in range(HULL_COLS):
		var on: bool = col < HULL_ON
		var src := Rect2(DOT_FW * (1 if on else 0), 0, DOT_FW, DOT_FH)
		var dst := Rect2(16 + col * (DOT_FW + 2), 72, DOT_FW, DOT_FH)
		draw_texture_rect_region(_dot_tex, dst, src, COLOR_HULL)

	# Annunciator — frame 1 = WARN
	draw_texture_rect_region(_ann_tex, Rect2(16, 88, ANN_FW, ANN_FH),
							 Rect2(ANN_FW, 0, ANN_FW, ANN_FH))
