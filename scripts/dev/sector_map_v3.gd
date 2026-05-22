extends Node2D

const FONT            = preload("res://graphics/fonts/PixelOperator.ttf")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const STAR_SCENE      = preload("res://Planets/Star/Star.tscn")

const CELL  := 16
const COLS  := 30
const ROWS  := 16

const BG_COLOR    := Color(0.06, 0.07, 0.10, 1.0)
const GRID_MINOR  := Color(0.22, 0.27, 0.35, 0.55)
const GRID_MAJOR  := Color(0.35, 0.43, 0.58, 0.85)
const LABEL_COLOR := Color(0.32, 0.42, 0.58, 0.50)
const FONT_SIZE   := 5

# Grid intersection positions (col*CELL, row*CELL) for the star anchors.
const STAR_ANCHORS := [Vector2(64, 64), Vector2(64, 128), Vector2(64, 192)]

# Name label origins: top-left of cell [6, row].
const LABEL_CELLS := [Vector2(6, 2), Vector2(6, 7), Vector2(6, 11)]

# Star display sizes and glow palettes (seed is now driven by map_seed + index).
const STAR_DISPLAY_PX := [64.0, 32.0, 20.0]
const STAR_GLOW_COLORS := [
	Color(0.45, 0.65, 1.00, 1.0),   # B-type blue
	Color(1.00, 0.72, 0.18, 1.0),   # G-type yellow
	Color(1.00, 0.26, 0.07, 1.0),   # M-type red
]
const STAR_GLOW_ALPHA  := [0.65, 0.60, 0.55]
const STAR_PULSE_HZ    := [0.38, 0.52, 0.44]
const STAR_PHASE       := [0.00, 1.10, 2.30]
# B-type = odd seed (cool), G/M = even seed (warm). Applied per-star from map_seed.
const STAR_COOL        := [true, false, false]

# Route line: right from star anchor, randomised length, capped at col28 (x=448).
const ROUTE_MAX_X   := 448.0   # intersection of columns 27 and 28
const ROUTE_MIN_LEN := 128.0   # minimum pixels right of anchor
const ROUTE_MAX_LEN := 368.0   # maximum pixels right of anchor (anchor x=64 → 432)
const ROUTE_WIDTH   := 8.0
const ROUTE_COLOR   := Color(0.30, 0.38, 0.55, 0.70)

# Name generation pools — mix of real designation conventions and sci-fi tropes.
const NAME_GREEK   := ["Alpha","Beta","Gamma","Delta","Epsilon","Zeta","Eta","Theta",
                        "Iota","Kappa","Lambda","Mu","Nu","Xi","Omicron","Pi","Sigma",
                        "Tau","Upsilon","Phi","Chi","Psi","Omega"]
const NAME_ROOTS   := ["Kyros","Novara","Eridani","Centauri","Vega","Cygni","Persei",
                        "Orionis","Leonis","Draconis","Lyrae","Tauri","Ursae","Aquilae",
                        "Corvi","Hydrae","Lupi","Velorum","Carinae","Puppis"]
const NAME_CATALOG := ["HD","GJ","HIP","KIC","TYC","WISE","2MASS"]
const NAME_SUFFIX  := ["","","","I","II","III","IV","Prime","Station","Relay"]

# Seed that drives star seeds, system names, and route lengths.
# Change this to generate a different map layout.
@export var map_seed: int = 12345

var _map_rng: RandomNumberGenerator
var _time: float = 0.0
var _star_glows: Array = []
var _system_names: Array = []   # one string per star slot
var _route_lengths: Array = []  # one float per star slot


func _ready() -> void:
	RenderingServer.set_default_clear_color(BG_COLOR)
	_map_rng = RandomNumberGenerator.new()
	_map_rng.seed = map_seed
	_generate_names()
	_generate_route_lengths()
	_build_routes()   # add Line2D nodes BEFORE stars so they z-sort under
	_build_stars()
	_build_labels()


func _process(delta: float) -> void:
	_time += delta
	for i in _star_glows.size():
		var pulse: float = sin(_time * STAR_PULSE_HZ[i] * TAU + STAR_PHASE[i])
		var glow_spr: Sprite2D = _star_glows[i].get_child(0)
		var s: float = (STAR_DISPLAY_PX[i] * 2.2) / 64.0 * (1.0 + 0.06 * pulse)
		glow_spr.scale      = Vector2(s, s)
		glow_spr.modulate.a = STAR_GLOW_ALPHA[i] + 0.15 * pulse


# ---- Name generation -------------------------------------------------------

func _generate_names() -> void:
	_system_names.clear()
	for i in STAR_ANCHORS.size():
		_system_names.append(_make_name())

func _make_name() -> String:
	var roll: int = _map_rng.randi() % 3
	match roll:
		0:  # "Alpha Novara" style
			var g: String = NAME_GREEK[_map_rng.randi() % NAME_GREEK.size()]
			var r: String = NAME_ROOTS[_map_rng.randi() % NAME_ROOTS.size()]
			return g + " " + r
		1:  # "Novara II" or "Novara Prime" style
			var r: String = NAME_ROOTS[_map_rng.randi() % NAME_ROOTS.size()]
			var s: String = NAME_SUFFIX[_map_rng.randi() % NAME_SUFFIX.size()]
			return r + (" " + s if s != "" else "")
		_:  # "HD 29487" catalogue style
			var cat: String = NAME_CATALOG[_map_rng.randi() % NAME_CATALOG.size()]
			var num: int    = _map_rng.randi_range(1000, 99999)
			return cat + " " + str(num)


# ---- Route line lengths ----------------------------------------------------

func _generate_route_lengths() -> void:
	_route_lengths.clear()
	for i in STAR_ANCHORS.size():
		var len: float = _map_rng.randf_range(ROUTE_MIN_LEN, ROUTE_MAX_LEN)
		var end_x: float = STAR_ANCHORS[i].x + len
		# Cap so the line never crosses into column 29.
		_route_lengths.append(minf(end_x, ROUTE_MAX_X) - STAR_ANCHORS[i].x)


# ---- Route lines -----------------------------------------------------------
# Added BEFORE star nodes so they render below them in draw order.

func _build_routes() -> void:
	for i in STAR_ANCHORS.size():
		var anchor: Vector2 = STAR_ANCHORS[i]
		var line := Line2D.new()
		line.default_color     = ROUTE_COLOR
		line.width             = ROUTE_WIDTH
		line.begin_cap_mode    = Line2D.LINE_CAP_ROUND
		line.end_cap_mode      = Line2D.LINE_CAP_ROUND
		line.z_index           = 0
		line.points = PackedVector2Array([
			anchor,
			Vector2(anchor.x + _route_lengths[i], anchor.y),
		])
		add_child(line)


# ---- Stars -----------------------------------------------------------------

func _build_stars() -> void:
	for i in STAR_ANCHORS.size():
		var anchor:     Vector2 = STAR_ANCHORS[i]
		var display_px: float   = STAR_DISPLAY_PX[i]
		# Derive a repeatable per-star seed from map_seed + index.
		var seed_val: int = (map_seed + i * 7919) % 100000
		var cool: bool    = STAR_COOL[i]

		var star = STAR_SCENE.instantiate()
		var sf: float = display_px / 100.0
		if star is Control:
			star.anchor_left = 0.0; star.anchor_top    = 0.0
			star.anchor_right = 0.0; star.anchor_bottom = 0.0
			star.offset_right = 100.0; star.offset_bottom = 100.0
			star.size = Vector2(100.0, 100.0)
			star.custom_minimum_size = Vector2(100.0, 100.0)
			star.pivot_offset = Vector2.ZERO
		star.scale    = Vector2(sf, sf)
		star.position = Vector2(anchor.x - 50.0 * sf, anchor.y - 50.0 * sf)
		if star.has_method("set_pixels"):  star.set_pixels(display_px)
		if star.has_method("set_seed"):    star.set_seed(seed_val)
		if star.has_method("set_rotates"): star.set_rotates(false)
		add_child(star)
		_reset_star_colorrects(star)
		_apply_star_colors(star, cool)

		# Additive glow halo.
		var glow_node := Node2D.new()
		glow_node.position = anchor
		add_child(glow_node)
		_star_glows.append(glow_node)

		var glow_spr := Sprite2D.new()
		var gc: Color = STAR_GLOW_COLORS[i]
		var g := Gradient.new()
		g.colors  = PackedColorArray([gc, Color(gc.r, gc.g, gc.b, 0.0)])
		g.offsets = PackedFloat32Array([0.0, 1.0])
		var gt := GradientTexture2D.new()
		gt.gradient  = g;  gt.width = 64;  gt.height = 64
		gt.fill      = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5);  gt.fill_to = Vector2(1.0, 0.5)
		glow_spr.texture = gt
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow_spr.material = mat
		glow_node.add_child(glow_spr)

	_process(0.0)


# ---- System name labels ----------------------------------------------------

func _build_labels() -> void:
	for i in LABEL_CELLS.size():
		var cell:  Vector2 = LABEL_CELLS[i]
		var px:    float   = cell.x * CELL + 2
		var py:    float   = cell.y * CELL + CELL - 2
		var lbl := Label.new()
		lbl.text = _system_names[i]
		lbl.position = Vector2(px, py - 9)
		lbl.add_theme_font_override("font", FONT)
		lbl.add_theme_font_size_override("font_size", 7)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.90))
		add_child(lbl)


# ---- Shader color helpers --------------------------------------------------

func _apply_star_colors(root: Node, cool: bool) -> void:
	for child in root.get_children():
		if child is ColorRect and child.material is ShaderMaterial:
			child.material = (child.material as ShaderMaterial).duplicate()
			var mat: ShaderMaterial = child.material
			match String(child.name):
				"Star":
					mat.set_shader_parameter("colors",
						PackedColorArray([
							Color(0.96,1.00,0.91,1), Color(0.47,0.84,0.76,1),
							Color(0.11,0.57,0.65,1), Color(0.01,0.24,0.37,1),
						]) if cool else PackedColorArray([
							Color(0.96,1.00,0.91,1), Color(1.00,0.85,0.20,1),
							Color(1.00,0.51,0.23,1), Color(0.49,0.10,0.10,1),
						]))
				"Blobs":
					mat.set_shader_parameter("colors",
						PackedColorArray([Color(0.47,0.84,0.76,1)]) if cool else
						PackedColorArray([Color(1.00,0.85,0.20,1)]))
				"StarFlares":
					mat.set_shader_parameter("colors",
						PackedColorArray([
							Color(0.47,0.84,0.76,1), Color(0.96,1.00,0.91,1),
						]) if cool else PackedColorArray([
							Color(1.00,0.85,0.20,1), Color(0.96,1.00,0.91,1),
						]))
		_apply_star_colors(child, cool)


func _reset_star_colorrects(root: Node) -> void:
	for child in root.get_children():
		if child is ColorRect:
			match String(child.name):
				"Blobs","StarFlares":
					(child as ColorRect).size     = Vector2(200.0, 200.0)
					(child as ColorRect).position = Vector2(-50.0, -50.0)
				_:
					(child as ColorRect).size     = Vector2(100.0, 100.0)
					(child as ColorRect).position = Vector2.ZERO
		_reset_star_colorrects(child)


# ---- Grid draw -------------------------------------------------------------

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
