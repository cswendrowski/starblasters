extends Node2D

const FONT            = preload("res://graphics/fonts/PixelOperator.ttf")
const SceneTransition = preload("res://scripts/scene_transition.gd")

const CELL  := 16
const COLS  := 30
const ROWS  := 16

const BG_COLOR    := Color(0.06, 0.07, 0.10, 1.0)
const GRID_MINOR  := Color(0.22, 0.27, 0.35, 0.55)
const GRID_MAJOR  := Color(0.35, 0.43, 0.58, 0.85)
const LABEL_COLOR := Color(0.32, 0.42, 0.58, 0.50)
const FONT_SIZE   := 5

# Stars at the major-line intersections requested by Roman.
# Position = pixel coords of the grid-line intersection.
# Stellar types scaled to 16–64 px visible diameter range:
#   B-type  blue-white  hot supergiant  — largest, brightest
#   G-type  yellow      main sequence   — mid (like our sun)
#   M-type  orange-red  cool dwarf      — smallest, dimmest
#
# Each row: [px, py, glow_px, core_px, core_color, glow_color, pulse_hz, pulse_phase]
const STAR_DATA := [
	# B-type — intersection col4/row4 → pixel (64, 64)
	[64.0, 64.0, 80.0, 28.0,
		Color(0.88, 0.94, 1.00, 1.0),   # blue-white core
		Color(0.45, 0.65, 1.00, 1.0),   # blue glow
		0.38, 0.00],
	# G-type — intersection col4/row8 → pixel (64, 128)
	[64.0, 128.0, 46.0, 16.0,
		Color(1.00, 0.91, 0.52, 1.0),   # warm yellow core
		Color(1.00, 0.72, 0.18, 1.0),   # orange-yellow glow
		0.52, 1.10],
	# M-type — intersection col4/row12 → pixel (64, 192)
	[64.0, 192.0, 30.0, 10.0,
		Color(1.00, 0.48, 0.22, 1.0),   # orange-red core
		Color(1.00, 0.26, 0.07, 1.0),   # deep red glow
		0.44, 2.30],
]

var _time: float = 0.0
# Parallel arrays: [glow_sprite, core_sprite] per star
var _star_glows: Array = []
var _star_cores: Array = []


func _ready() -> void:
	RenderingServer.set_default_clear_color(BG_COLOR)
	_build_stars()


func _process(delta: float) -> void:
	_time += delta
	for i in STAR_DATA.size():
		var d     := STAR_DATA[i]
		var glow_base: float = d[2]
		var core_base: float = d[3]
		var hz:    float     = d[6]
		var phase: float     = d[7]
		var pulse: float     = sin(_time * hz * TAU + phase)
		# Glow breathes ±6% in scale and ±15% in alpha.
		var glow_s: float = glow_base / 64.0 * (1.0 + 0.06 * pulse)
		_star_glows[i].scale   = Vector2(glow_s, glow_s)
		_star_glows[i].modulate.a = 0.60 + 0.15 * pulse
		# Core pulses ±4% — subtler than the glow.
		var core_s: float = core_base / 64.0 * (1.0 + 0.04 * pulse)
		_star_cores[i].scale = Vector2(core_s, core_s)


func _build_stars() -> void:
	for d in STAR_DATA:
		var pos        := Vector2(float(d[0]), float(d[1]))
		var core_color := d[4] as Color
		var glow_color := d[5] as Color

		var node := Node2D.new()
		node.position = pos
		add_child(node)

		# Glow layer — large radial gradient, additive blend so it blooms
		# into the dark background without muddying other colours.
		var glow := Sprite2D.new()
		glow.texture = _radial_gradient(glow_color, Color(glow_color.r, glow_color.g, glow_color.b, 0.0))
		glow.material = _additive_mat()
		glow.z_index = 1
		node.add_child(glow)
		_star_glows.append(glow)

		# Core layer — tight bright disc, white-hot centre fading to the
		# stellar colour at the edge, also additive.
		var core := Sprite2D.new()
		core.texture = _radial_gradient(Color(1.0, 1.0, 1.0, 1.0), Color(core_color.r, core_color.g, core_color.b, 0.0), 0.25)
		core.material = _additive_mat()
		core.z_index = 2
		node.add_child(core)
		_star_cores.append(core)

	# Trigger initial scale from _process.
	_process(0.0)


# Build a 64×64 radial gradient texture from centre_color to edge_color.
# `mid_stop` (0–1) places an optional hard colour midpoint for the core's
# white-hot centre effect; pass 0 to skip (two-stop gradient).
func _radial_gradient(centre: Color, edge: Color, mid_stop: float = 0.0) -> GradientTexture2D:
	var g := Gradient.new()
	if mid_stop > 0.0:
		g.colors  = PackedColorArray([Color(1,1,1,1), centre, edge])
		g.offsets = PackedFloat32Array([0.0, mid_stop, 1.0])
	else:
		g.colors  = PackedColorArray([centre, edge])
		g.offsets = PackedFloat32Array([0.0, 1.0])
	var t := GradientTexture2D.new()
	t.gradient  = g
	t.width     = 64
	t.height    = 64
	t.fill      = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to   = Vector2(1.0, 0.5)
	return t


func _additive_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 270), BG_COLOR)
	for col in range(COLS + 1):
		var x   := col * CELL
		var maj := col % 4 == 0
		draw_line(Vector2(x, 0), Vector2(x, 270),
			GRID_MAJOR if maj else GRID_MINOR, 1.0)
	for row in range(ROWS + 1):
		var y   := row * CELL
		var maj := row % 4 == 0
		draw_line(Vector2(0, y), Vector2(480, y),
			GRID_MAJOR if maj else GRID_MINOR, 1.0)
	for col in COLS:
		for row in ROWS:
			var pos := Vector2(col * CELL + 2, row * CELL + FONT_SIZE + 1)
			draw_string(FONT, pos, "%d,%d" % [col, row],
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LABEL_COLOR)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")
