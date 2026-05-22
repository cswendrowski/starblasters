extends Node2D

const FONT            = preload("res://graphics/fonts/PixelOperator.ttf")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const STAR_SCENE      = preload("res://Planets/Star/Star.tscn")
const PLANET_SCENES   := [
	"res://Planets/LavaWorld/LavaWorld.tscn",
	"res://Planets/DryTerran/DryTerran.tscn",
	"res://Planets/NoAtmosphere/NoAtmosphere.tscn",
	"res://Planets/LandMasses/LandMasses.tscn",
	"res://Planets/GasPlanet/GasPlanet.tscn",
	"res://Planets/IceWorld/IceWorld.tscn",
]
# Orbital zone preference per planet type (0=inner…1=outer).
# Pick types whose zone weight is highest for the current position fraction.
const PLANET_ZONE_PEAK := [0.10, 0.25, 0.30, 0.50, 0.70, 0.90]

const CELL  := 16
const COLS  := 30
const ROWS  := 16

const BG_COLOR    := Color(0.06, 0.07, 0.10, 1.0)
const GRID_MINOR  := Color(0.22, 0.27, 0.35, 0.55)
const GRID_MAJOR  := Color(0.35, 0.43, 0.58, 0.85)
const LABEL_COLOR := Color(0.32, 0.42, 0.58, 0.50)
const FONT_SIZE   := 5

const STAR_ANCHORS    := [Vector2(64, 64), Vector2(64, 128), Vector2(64, 192)]
# Labels start at cell [5, row] — one cell left of previous [6, row].
const LABEL_CELLS     := [Vector2(5, 2), Vector2(5, 7), Vector2(5, 11)]
const STAR_DISPLAY_PX := [64.0, 32.0, 24.0]   # min 24 per spec
const STAR_GLOW_COLORS := [
	Color(0.45, 0.65, 1.00, 1.0),
	Color(1.00, 0.72, 0.18, 1.0),
	Color(1.00, 0.26, 0.07, 1.0),
]
const STAR_GLOW_ALPHA := [0.65, 0.60, 0.55]
const STAR_PULSE_HZ   := [0.38, 0.52, 0.44]
const STAR_PHASE      := [0.00, 1.10, 2.30]
const STAR_COOL       := [true, false, false]

const ROUTE_MAX_X   := 448.0  # col-27/28 intersection
const ROUTE_MIN_LEN := 128.0
const ROUTE_MAX_LEN := 368.0
const ROUTE_WIDTH   := 8.0
const ROUTE_COLOR   := Color(0.30, 0.38, 0.55, 0.70)

# Planet placement on routes: starts at x=128 (col7/8 intersection).
const PLANET_START_X   := 128.0
const PLANET_MIN_PX    := 16.0
const PLANET_MAX_PX    := 32.0
const PLANET_STOP_PROB := 0.30  # per-planet chance to stop placing after ≥1

# Mashup naming: always "Greek Root[Suffix]" — root pool blends real and sci-fi.
const NAME_GREEK  := ["Alpha","Beta","Gamma","Delta","Epsilon","Zeta","Eta","Theta",
                       "Iota","Kappa","Lambda","Mu","Nu","Xi","Sigma","Tau",
                       "Upsilon","Phi","Chi","Psi","Omega","Proxima","Nova"]
const NAME_ROOTS  := ["Kyros","Novara","Centauri","Eridani","Cygni","Persei",
                       "Orionis","Leonis","Draconis","Lyrae","Tauri","Velorum",
                       "Carinae","Vega","Aquilae","Corvi","Hydrae","Lupi",
                       "Puppis","Ursae","Volantis","Piscium","Arietis","Hydrax",
                       "Noctis","Ferrum","Caeli","Fornax","Proxima","Solus"]
const NAME_SUFFIX := ["","","","","I","II","III","IV","Prime","Station",
                       "Relay","Colony","Outpost","Reach","Terminus","System"]

@export var map_seed: int = 12345

var _map_rng: RandomNumberGenerator
var _time:          float = 0.0
var _star_glows:    Array = []    # glow Node2D per star
var _system_names:  Array = []
var _route_lengths: Array = []
# All PixelPlanets Control nodes (stars + planets) — updated at 0.5× speed.
var _celestial_nodes: Array = []


func _ready() -> void:
	RenderingServer.set_default_clear_color(BG_COLOR)
	_map_rng = RandomNumberGenerator.new()
	_map_rng.seed = map_seed
	_generate_names()
	_generate_route_lengths()
	_build_routes()     # Line2D — added first so it draws under everything
	_build_planets()    # planets on routes — above routes, below stars
	_build_stars()      # stars at anchors — above planets
	_build_labels()     # labels last — on top of stars


func _process(delta: float) -> void:
	_time += delta
	# Drive all PixelPlanets nodes at half the planet's natural speed.
	for node in _celestial_nodes:
		if is_instance_valid(node) and node.has_method("update_time"):
			node.update_time(_time * 0.5)
	# Animate glow halos.
	for i in _star_glows.size():
		var pulse: float = sin(_time * STAR_PULSE_HZ[i] * TAU + STAR_PHASE[i])
		var glow_spr: Sprite2D = _star_glows[i].get_child(0)
		var s: float = (STAR_DISPLAY_PX[i] * 2.2) / 64.0 * (1.0 + 0.06 * pulse)
		glow_spr.scale      = Vector2(s, s)
		glow_spr.modulate.a = STAR_GLOW_ALPHA[i] + 0.15 * pulse


# ---------------------------------------------------------------------------
# Name generation — mashup of real-world designations and sci-fi tropes.
# Always produces: [Greek letter] [mixed root] [optional suffix].
# ---------------------------------------------------------------------------

func _generate_names() -> void:
	_system_names.clear()
	for _i in STAR_ANCHORS.size():
		var g: String = NAME_GREEK[_map_rng.randi() % NAME_GREEK.size()]
		var r: String = NAME_ROOTS[_map_rng.randi() % NAME_ROOTS.size()]
		var s: String = NAME_SUFFIX[_map_rng.randi() % NAME_SUFFIX.size()]
		_system_names.append(g + " " + r + (" " + s if s != "" else ""))


# ---------------------------------------------------------------------------
# Route generation
# ---------------------------------------------------------------------------

func _generate_route_lengths() -> void:
	_route_lengths.clear()
	for i in STAR_ANCHORS.size():
		var raw: float = _map_rng.randf_range(ROUTE_MIN_LEN, ROUTE_MAX_LEN)
		var end_x: float = STAR_ANCHORS[i].x + raw
		_route_lengths.append(minf(end_x, ROUTE_MAX_X) - STAR_ANCHORS[i].x)


func _build_routes() -> void:
	for i in STAR_ANCHORS.size():
		var anchor: Vector2 = STAR_ANCHORS[i]
		var line   := Line2D.new()
		line.default_color  = ROUTE_COLOR
		line.width          = ROUTE_WIDTH
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode   = Line2D.LINE_CAP_ROUND
		line.points = PackedVector2Array([
			anchor,
			Vector2(anchor.x + _route_lengths[i], anchor.y),
		])
		add_child(line)


# ---------------------------------------------------------------------------
# Planet placement along routes
# ---------------------------------------------------------------------------

func _build_planets() -> void:
	for i in STAR_ANCHORS.size():
		var anchor:    Vector2 = STAR_ANCHORS[i]
		var route_end: float   = anchor.x + _route_lengths[i]
		var cursor:    float   = PLANET_START_X
		var placed:    int     = 0

		while cursor <= route_end:
			# Pick display size (snap to 8px steps within 16–32 range).
			var steps: int = _map_rng.randi() % 3      # 0,1,2 → 16,24,32
			var px: float  = PLANET_MIN_PX + steps * 8.0
			# Check if planet fits (right edge must not exceed route end).
			if cursor + px * 0.5 > route_end:
				break
			# Pick orbital zone weight based on position fraction.
			var frac: float = (cursor - PLANET_START_X) / max(1.0, route_end - PLANET_START_X)
			var type_idx: int = _pick_planet_type(frac)
			_spawn_planet(anchor.y, cursor, px, type_idx)
			placed += 1
			# Advance: full planet width (rounded up to cell) + 2 cell gap.
			# Centers snap to grid intersections; 2-cell gap keeps planets from cramping.
			var advance: float = (ceili(px / CELL) + 2) * CELL
			cursor += advance
			# After first planet, randomly stop (routes shouldn't all be packed).
			if placed >= 1 and _map_rng.randf() < PLANET_STOP_PROB:
				break


func _pick_planet_type(frac: float) -> int:
	# Weighted pick: planet types with zone_peak closer to frac are more likely.
	var weights: PackedFloat32Array
	weights.resize(PLANET_ZONE_PEAK.size())
	var total: float = 0.0
	for j in PLANET_ZONE_PEAK.size():
		var w: float = 1.0 - absf(PLANET_ZONE_PEAK[j] - frac) * 3.0
		weights[j] = maxf(0.05, w)
		total += weights[j]
	var roll: float = _map_rng.randf() * total
	for j in weights.size():
		roll -= weights[j]
		if roll <= 0.0:
			return j
	return PLANET_ZONE_PEAK.size() - 1


func _spawn_planet(center_y: float, center_x: float, display_px: float, type_idx: int) -> void:
	var ps = load(PLANET_SCENES[type_idx])
	if ps == null:
		return
	var p = ps.instantiate()
	var sf: float = display_px / 100.0
	if p is Control:
		p.anchor_left = 0.0; p.anchor_top    = 0.0
		p.anchor_right = 0.0; p.anchor_bottom = 0.0
		p.offset_right = 100.0; p.offset_bottom = 100.0
		p.size = Vector2(100.0, 100.0)
		p.custom_minimum_size = Vector2(100.0, 100.0)
		p.pivot_offset = Vector2.ZERO
	p.scale    = Vector2(sf, sf)
	p.position = Vector2(center_x - 50.0 * sf, center_y - 50.0 * sf)
	if p.has_method("set_pixels"):     p.set_pixels(display_px)
	if p.has_method("set_seed"):       p.set_seed(_map_rng.randi() % 100000)
	if p.has_method("randomize_colors"): p.randomize_colors()
	if p.has_method("set_rotates"):    p.set_rotates(true)
	add_child(p)
	_reset_planet_colorrects(p)
	if p.has_method("set_light"):
		p.set_light(Vector2(0.0, 0.5))  # lit from the left
	p.override_time = true
	_celestial_nodes.append(p)


# ---------------------------------------------------------------------------
# Stars
# ---------------------------------------------------------------------------

func _build_stars() -> void:
	for i in STAR_ANCHORS.size():
		var anchor:     Vector2 = STAR_ANCHORS[i]
		var display_px: float   = STAR_DISPLAY_PX[i]
		var seed_val:   int     = (map_seed + i * 7919) % 100000
		var cool: bool          = STAR_COOL[i]

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
		star.override_time = true
		_celestial_nodes.append(star)

		# Glow halo.
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
		gt.gradient  = g; gt.width = 64; gt.height = 64
		gt.fill      = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5)
		glow_spr.texture = gt
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow_spr.material = mat
		glow_node.add_child(glow_spr)

	_process(0.0)


# ---------------------------------------------------------------------------
# Labels — added last so they render on top of everything
# ---------------------------------------------------------------------------

func _build_labels() -> void:
	var ls := LabelSettings.new()
	ls.font         = FONT
	ls.font_size    = 9       # 7 * 1.25 ≈ 9
	ls.font_color   = Color(0.85, 0.92, 1.0, 0.95)
	ls.outline_size  = 1
	ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)

	for i in LABEL_CELLS.size():
		var cell: Vector2 = LABEL_CELLS[i]
		var lbl := Label.new()
		lbl.text           = _system_names[i]
		lbl.label_settings = ls
		lbl.position = Vector2(cell.x * CELL + 2, cell.y * CELL + 1)
		lbl.z_index   = 10   # above stars (default 0)
		add_child(lbl)


# ---------------------------------------------------------------------------
# PixelPlanets helpers
# ---------------------------------------------------------------------------

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


func _reset_planet_colorrects(root: Node) -> void:
	for child in root.get_children():
		if child is ColorRect:
			(child as ColorRect).size     = Vector2(100.0, 100.0)
			(child as ColorRect).position = Vector2.ZERO
		_reset_planet_colorrects(child)


# ---------------------------------------------------------------------------
# Grid
# ---------------------------------------------------------------------------

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

