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

# Node dot strip + sector icons (same assets as sector_map_v2).
const NODE_STRIP       = preload("res://graphics/ui/sector_nodes.png")
const ICON_STRIP       = preload("res://graphics/ui/sector_icons.png")
const ICON_COUNT       := 6
# Icon frames by gameplay node type — reference sector_map_v2:
#   0=base(outpost) 1=start(origin) 2=battle(combat) 3=boss 4=hazard 5=signal
# Exclude 1(start/origin) and 3(boss) from regular POI icons.
const NODE_TYPE_ICONS  := [0, 4, 5, 2]  # outpost, hazard, signal, combat
const ICON_BOSS        := 3
# "Available node" green from sector_map_v2.
const COLOR_NODE_GREEN := Color(0.55, 1.0, 0.50, 1.0)
const COLOR_BOSS_RED   := Color(1.0, 0.30, 0.25, 1.0)
# Fixed boss hazard positions — at col28/row4, col28/row8, col28/row12 intersections.
const BOSS_POSITIONS   := [Vector2(448, 64), Vector2(448, 128), Vector2(448, 192)]
# Planet designation letters (real-world exoplanet convention).
const PLANET_LETTERS   := ["b", "c", "d", "e", "f", "g"]
# PixelPlanets scenes for non-planet route objects.
const ASTEROID_SCENE    = preload("res://Planets/Asteroids/Asteroid.tscn")
const NEBULA_SHADER     = preload("res://graphics/nebula2.gdshader")
const NEBULA_COLORSCHEME = preload("res://SpaceBG/Colorscheme.tres")
# Random hue tints for nebulae — cycle through distinct hues.
const NEBULA_TINTS := [
	Color(0.45, 0.55, 1.0, 1.0),   # blue
	Color(0.80, 0.45, 1.0, 1.0),   # purple
	Color(1.0,  0.45, 0.55, 1.0),  # red/pink
	Color(0.45, 1.0,  0.75, 1.0),  # teal
	Color(1.0,  0.75, 0.30, 1.0),  # amber
]
# Route object types: 0=planet 1=large_asteroid 2=asteroid_cluster
const OBJ_TYPE_COUNT    := 3
# Per-type advance in cells (placed object width + 2-cell gap).
# Planet advance is computed per-object from its size; others use these fixed values.
const OBJ_ADVANCE_CELLS := [0, 4, 6]  # planet=computed, ast=4, cluster=6

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
# Per-planet hover entries: {center, radius, label, icon}
var _planet_hovers: Array = []
# Asteroid rotation entries: {node, speed, phase} — driven in _process.
var _asteroid_rotators: Array = []
# Current system/node indices while building route objects — used by spawn helpers.
var _cur_sys_i:     int = 0
var _cur_node_type: int = 3  # 0=outpost 1=hazard 2=signal 3=combat
# Moon orbit data: {node, center, orbit_r, speed, phase, is_ctrl, ctrl_half?}
var _moon_data:     Array = []
# Lazy-created white circle textures keyed by radius_px.
var _moon_textures: Dictionary = {}
# POI ambient dressing: pulsing glows {spr, hz, phase, base_a} + combat glitter particles.
var _glow_pulses: Array = []
var _glitter:     Array = []  # {pos, vel, rect, brightness, hidden, timer}
# Non-deterministic RNG for runtime flicker — not seeded from map_seed.
var _fx_rng: RandomNumberGenerator


func _ready() -> void:
	RenderingServer.set_default_clear_color(BG_COLOR)
	_fx_rng = RandomNumberGenerator.new()
	_fx_rng.seed = randi()
	_map_rng = RandomNumberGenerator.new()
	_map_rng.seed = map_seed
	_generate_names()
	_generate_route_lengths()
	_build_routes()          # Line2D — added first so it draws under everything
	_build_route_objects()   # planets/asteroids/nebulae — above routes, below stars
	_build_boss_nodes()      # boss hazard at route endpoints
	_build_stars()           # stars at anchors — above planets
	_build_labels()          # labels last — on top of stars
	_build_ui()              # Generate New button


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
	# Animate planet moons — elliptical orbits, always visible.
	for m in _moon_data:
		if not is_instance_valid(m.node):
			continue
		var angle: float = _time * m.speed + m.phase
		m.node.position = m.center + Vector2(cos(angle) * m.rx, sin(angle) * m.ry)
	# Rotate asteroids at their individual speeds.
	for entry in _asteroid_rotators:
		if is_instance_valid(entry.node) and entry.node.has_method("set_custom_time"):
			entry.node.set_custom_time(_time * entry.speed + entry.phase)
	# Pulse ambient glows — size breathes 1→8px, alpha 0.3→1.0.
	for g in _glow_pulses:
		if is_instance_valid(g.spr):
			var t: float = 0.5 + 0.5 * sin(_time * g.hz * TAU + g.phase)
			var sz: float = lerpf(1.0 / 64.0, 8.0 / 64.0, t)
			g.spr.scale     = Vector2(sz, sz)
			g.spr.modulate.a = lerpf(0.3, 1.0, t)
	# Update combat glitter particles.
	var needs_redraw := false
	for p in _glitter:
		p.pos += p.vel * delta
		if p.pos.x < p.rect.position.x or p.pos.x > p.rect.end.x:
			p.vel.x *= -1
		if p.pos.y < p.rect.position.y or p.pos.y > p.rect.end.y:
			p.vel.y *= -1
		p.timer -= delta
		if p.timer <= 0.0:
			p.hidden = not p.hidden
			p.timer = _fx_rng.randf_range(0.05, 0.5) if p.hidden else _fx_rng.randf_range(0.4, 2.5)
		var target_b: float = 0.0 if p.hidden else _fx_rng.randf_range(0.4, 1.0)
		p.brightness = lerpf(p.brightness, target_b, delta * 6.0)
		needs_redraw = true
	if needs_redraw:
		queue_redraw()
	# Hover: fade labels and icons in/out on mouse-over.
	var mouse: Vector2 = get_local_mouse_position()
	for entry in _planet_hovers:
		var hovered: bool = mouse.distance_to(entry.center) <= entry.radius
		var lbl: Label    = entry.label
		var icon: Sprite2D = entry.icon
		lbl.modulate.a = lerpf(lbl.modulate.a, 1.0 if hovered else 0.2, delta * 8.0)
		var tgt: Color = COLOR_NODE_GREEN if hovered else Color.WHITE
		tgt.a = 0.9 if hovered else 0.2
		icon.modulate = icon.modulate.lerp(tgt, delta * 8.0)


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
		var raw: float   = _map_rng.randf_range(ROUTE_MIN_LEN, ROUTE_MAX_LEN)
		var end_x: float = minf(STAR_ANCHORS[i].x + raw, ROUTE_MAX_X)
		# Snap endpoint to the nearest column intersection so it's a valid POI slot.
		end_x = float(int(end_x / CELL)) * CELL
		_route_lengths.append(end_x - STAR_ANCHORS[i].x)


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
# Route object placement — planets, asteroids, nebulae
# ---------------------------------------------------------------------------

func _build_route_objects() -> void:
	for i in STAR_ANCHORS.size():
		_cur_sys_i = i
		var anchor:    Vector2 = STAR_ANCHORS[i]
		var route_end: float   = anchor.x + _route_lengths[i]
		# Leave 3 cells before the boss node clear.
		var fill_limit: float  = route_end - 3.0 * CELL
		var cursor:     float  = PLANET_START_X
		var placed:     int    = 0
		var planet_idx: int    = 0

		while cursor <= fill_limit:
			var type_id:   int = _map_rng.randi() % OBJ_TYPE_COUNT
			var node_type: int = _pick_node_type()
			var advance: float = _spawn_route_obj(anchor.y, cursor, route_end, i, type_id, planet_idx, node_type)
			if type_id == 0:
				planet_idx += 1
			placed += 1
			cursor += advance
			if placed >= 1 and _map_rng.randf() < PLANET_STOP_PROB:
				break

		# Always place something at the route endpoint (column intersection).
		if route_end >= PLANET_START_X:
			var end_type_id:   int = _map_rng.randi() % OBJ_TYPE_COUNT
			var end_node_type: int = _pick_node_type()
			_spawn_route_obj(anchor.y, route_end, route_end, i, end_type_id, planet_idx, end_node_type)


# Dispatches to the right spawn function; returns the advance step in px.
func _spawn_route_obj(cy: float, cx: float, route_end: float, _sys_i: int, type_id: int, planet_idx: int, node_type: int) -> float:
	_cur_node_type = node_type
	var advance: float = float(4 * CELL)
	match type_id:
		0:  # planet
			var steps: int = _map_rng.randi() % 3
			var px: float  = PLANET_MIN_PX + steps * 8.0
			var frac: float = (cx - PLANET_START_X) / max(1.0, route_end - PLANET_START_X)
			var ptype: int  = _pick_planet_type(frac)
			_spawn_planet(cy, cx, px, ptype, planet_idx)
			advance = float((ceili(px / CELL) + 2) * CELL)
		1:  # large asteroid
			_spawn_large_asteroid(cy, cx)
			advance = float(OBJ_ADVANCE_CELLS[1] * CELL)
		2:  # asteroid cluster
			_spawn_asteroid_cluster(cy, cx)
			advance = float(OBJ_ADVANCE_CELLS[2] * CELL)
	_add_node_dressing(cy, cx, node_type)
	return advance


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


func _spawn_planet(center_y: float, center_x: float, display_px: float, type_idx: int, planet_idx: int) -> void:
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
	_duplicate_materials(p)
	if p.has_method("set_pixels"):  p.set_pixels(display_px)
	if p.has_method("set_seed"):    p.set_seed(_map_rng.randi() % 100000)
	seed(_map_rng.randi())          # drive global RNG so randomize_colors is unique
	if p.has_method("randomize_colors"): p.randomize_colors()
	if p.has_method("set_rotates"): p.set_rotates(true)
	add_child(p)
	_reset_planet_colorrects(p)
	if p.has_method("set_light"):
		p.set_light(Vector2(0.0, 0.5))
	p.modulate = Color.WHITE.lerp(STAR_GLOW_COLORS[_cur_sys_i], 0.18)
	p.override_time = true
	_celestial_nodes.append(p)

	_spawn_moons(center_y, center_x, display_px)
	_add_hover_label_icon(center_y, center_x, display_px,
		PLANET_LETTERS[mini(planet_idx, PLANET_LETTERS.size() - 1)])


func _spawn_large_asteroid(center_y: float, center_x: float) -> void:
	const PX: float = 32.0
	var sf: float   = PX / 100.0
	var ast = ASTEROID_SCENE.instantiate()
	if ast is Control:
		ast.anchor_left = 0.0; ast.anchor_top = 0.0
		ast.anchor_right = 0.0; ast.anchor_bottom = 0.0
		ast.offset_right = 100.0; ast.offset_bottom = 100.0
		ast.size = Vector2(100.0, 100.0)
		ast.custom_minimum_size = Vector2(100.0, 100.0)
		ast.pivot_offset = Vector2.ZERO
	ast.scale    = Vector2(sf, sf)
	ast.position = Vector2(center_x - 50.0 * sf, center_y - 50.0 * sf)
	_duplicate_materials(ast)                        # own material per instance
	if ast.has_method("set_pixels"): ast.set_pixels(PX)
	if ast.has_method("set_seed"):   ast.set_seed(_map_rng.randi())
	if ast.has_method("set_light"):  ast.set_light(Vector2(0.0, 0.5))
	add_child(ast)
	_reset_planet_colorrects(ast)
	ast.modulate = Color.WHITE.lerp(STAR_GLOW_COLORS[_cur_sys_i], 0.18)
	_asteroid_rotators.append({
		"node":  ast,
		"speed": _map_rng.randf_range(0.008, 0.025),
		"phase": _map_rng.randf_range(0.0, TAU),
	})
	_scatter_asteroid_band(center_y, center_x)
	_add_hover_label_icon(center_y, center_x, PX, "Asteroid")


func _spawn_asteroid_cluster(center_y: float, center_x: float) -> void:
	var count: int = 3 + _map_rng.randi() % 3  # 3-5 rocks
	for _k in count:
		var px: float  = 8.0 + float(_map_rng.randi() % 3) * 4.0  # 8,12,16px
		var sf: float  = px / 100.0
		var ox: float  = _map_rng.randf_range(-20.0, 20.0)
		var oy: float  = _map_rng.randf_range(-16.0, 16.0)
		var ast = ASTEROID_SCENE.instantiate()
		if ast is Control:
			ast.anchor_left = 0.0; ast.anchor_top = 0.0
			ast.anchor_right = 0.0; ast.anchor_bottom = 0.0
			ast.offset_right = 100.0; ast.offset_bottom = 100.0
			ast.size = Vector2(100.0, 100.0)
			ast.custom_minimum_size = Vector2(100.0, 100.0)
			ast.pivot_offset = Vector2.ZERO
		ast.scale    = Vector2(sf, sf)
		ast.position = Vector2(center_x + ox - 50.0 * sf, center_y + oy - 50.0 * sf)
		_duplicate_materials(ast)
		if ast.has_method("set_pixels"): ast.set_pixels(px)
		if ast.has_method("set_seed"):   ast.set_seed(_map_rng.randi())
		if ast.has_method("set_light"):  ast.set_light(Vector2(0.0, 0.5))
		add_child(ast)
		_reset_planet_colorrects(ast)
		ast.modulate = Color.WHITE.lerp(STAR_GLOW_COLORS[_cur_sys_i], 0.18)
		_asteroid_rotators.append({
			"node":  ast,
			"speed": _map_rng.randf_range(0.005, 0.020),
			"phase": _map_rng.randf_range(0.0, TAU),
		})
	_scatter_asteroid_band(center_y, center_x)
	# One hover label + icon representing the whole cluster.
	_add_hover_label_icon(center_y, center_x, 40.0, "Belt")


# Shared helper: label above object + sector icon at center + hover entry.
# Scatter 2-4 tiny filler asteroids around an asteroid POI to form a band.
func _scatter_asteroid_band(center_y: float, center_x: float) -> void:
	var count: int = 2 + _map_rng.randi() % 3  # 2-4 rocks
	for _k in count:
		var px: float = 4.0 + float(_map_rng.randi() % 3) * 2.0  # 4,6,8px
		var sf: float = px / 100.0
		var ox: float = _map_rng.randf_range(-36.0, 36.0)
		var oy: float = _map_rng.randf_range(-12.0, 12.0)
		var ast = ASTEROID_SCENE.instantiate()
		if ast is Control:
			ast.anchor_left = 0.0; ast.anchor_top = 0.0
			ast.anchor_right = 0.0; ast.anchor_bottom = 0.0
			ast.offset_right = 100.0; ast.offset_bottom = 100.0
			ast.size = Vector2(100.0, 100.0)
			ast.custom_minimum_size = Vector2(100.0, 100.0)
			ast.pivot_offset = Vector2.ZERO
		ast.scale    = Vector2(sf, sf)
		ast.position = Vector2(center_x + ox - 50.0 * sf, center_y + oy - 50.0 * sf)
		_duplicate_materials(ast)
		if ast.has_method("set_pixels"): ast.set_pixels(px)
		if ast.has_method("set_seed"):   ast.set_seed(_map_rng.randi())
		if ast.has_method("set_light"):  ast.set_light(Vector2(0.0, 0.5))
		add_child(ast)
		_reset_planet_colorrects(ast)
		_asteroid_rotators.append({
			"node":  ast,
			"speed": _map_rng.randf_range(0.005, 0.018),
			"phase": _map_rng.randf_range(0.0, TAU),
		})


# ---------------------------------------------------------------------------
# Boss hazard nodes — placed at the route endpoint for each system
# ---------------------------------------------------------------------------

func _build_boss_nodes() -> void:
	for i in BOSS_POSITIONS.size():
		var pos: Vector2 = BOSS_POSITIONS[i]
		# Node dot — boss frame (0) from NODE_STRIP, 1× scale (32px).
		var dot_at := AtlasTexture.new()
		dot_at.atlas  = NODE_STRIP
		dot_at.region = Rect2(0, 0, 32, 32)   # frame 0 = boss
		var dot_spr := Sprite2D.new()
		dot_spr.texture  = dot_at
		dot_spr.position = pos
		dot_spr.modulate = Color(COLOR_BOSS_RED.r, COLOR_BOSS_RED.g, COLOR_BOSS_RED.b, 0.5)
		dot_spr.z_index  = 3
		add_child(dot_spr)
		# Boss icon on top of the dot.
		var icon_at := AtlasTexture.new()
		icon_at.atlas  = ICON_STRIP
		icon_at.region = Rect2(ICON_BOSS * 32, 0, 32, 32)
		var icon_spr := Sprite2D.new()
		icon_spr.texture  = icon_at
		icon_spr.position = pos
		icon_spr.scale    = Vector2(0.5, 0.5)
		icon_spr.z_index  = 5
		icon_spr.modulate = Color(1.0, 1.0, 1.0, 0.0)
		add_child(icon_spr)
		# Label above.
		var ls := LabelSettings.new()
		ls.font = FONT; ls.font_size = 9
		ls.font_color    = Color(1.0, 0.65, 0.60, 0.95)
		ls.outline_size  = 1
		ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
		var lbl := Label.new()
		lbl.text           = "BOSS"
		lbl.label_settings = ls
		var row_above: int  = int((pos.y - 16.0) / CELL) - 1
		lbl.position  = Vector2(pos.x - 12, row_above * CELL + 2)
		lbl.z_index   = 10
		lbl.modulate.a = 0.2
		add_child(lbl)
		_planet_hovers.append({
			"center": pos,
			"radius": 16.0,
			"label":  lbl,
			"icon":   icon_spr,
		})


# ---------------------------------------------------------------------------
# Moon system
# ---------------------------------------------------------------------------

func _get_moon_texture(radius_px: int) -> ImageTexture:
	if _moon_textures.has(radius_px):
		return _moon_textures[radius_px]
	var size: int = radius_px * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for x in size:
		for y in size:
			var dx: float = x - radius_px + 0.5
			var dy: float = y - radius_px + 0.5
			if dx * dx + dy * dy <= float(radius_px * radius_px):
				img.set_pixel(x, y, Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	_moon_textures[radius_px] = tex
	return tex


func _spawn_moons(planet_cy: float, planet_cx: float, planet_px: float) -> void:
	var count: int = int(_map_rng.randf() * _map_rng.randf() * 13.0)  # 0-12, biased low
	if count == 0:
		return
	var center := Vector2(planet_cx, planet_cy)
	for _k in count:
		# Tight orbital radii: just outside the planet edge up to ~1.2× the planet radius.
		var base_r: float = planet_px * 0.5 + _map_rng.randf_range(2.0, planet_px * 0.7)
		# Elliptical: rx = base_r, ry = base_r * eccentricity (0.45–1.0).
		var rx: float = base_r
		var ry: float = base_r * _map_rng.randf_range(0.45, 1.0)
		var spd: float = _map_rng.randf_range(0.20, 0.70) * (1.0 if _map_rng.randf() > 0.5 else -1.0)
		var phase: float = _map_rng.randf_range(0.0, TAU)
		# Random soft pastel tint.
		var tint := Color.from_hsv(_map_rng.randf(), _map_rng.randf_range(0.2, 0.6), 0.95, 0.85)
		var radius_px: int = 1 + _map_rng.randi() % 6  # 1-6px
		var spr := Sprite2D.new()
		spr.texture  = _get_moon_texture(radius_px)
		spr.modulate = tint
		spr.z_index  = 1  # always in front — no z-flip
		add_child(spr)
		_moon_data.append({
			"node": spr, "center": center,
			"rx": rx, "ry": ry,
			"speed": spd, "phase": phase,
		})


# Node type for ambient dressing: 0=outpost 1=hazard 2=signal 3=combat
func _pick_node_type() -> int:
	var r: int = _map_rng.randi() % 9
	if r < 4: return 3  # combat  (4/9)
	if r < 6: return 0  # outpost (2/9)
	if r < 8: return 1  # hazard  (2/9)
	return 2             # signal  (1/9)


func _add_node_dressing(cy: float, cx: float, node_type: int) -> void:
	match node_type:
		0: _add_pulse_glow(cy, cx, Color(0.35, 0.65, 1.0),  0.35)  # outpost — blue
		1: _add_pulse_glow(cy, cx, Color(1.0,  0.25, 0.20), 0.40)  # hazard  — red
		2: _add_pulse_glow(cy, cx, Color(1.0,  0.90, 0.15), 0.35)  # signal  — yellow
		3: _add_glitter_zone(cy, cx)                                 # combat  — glitter


func _add_pulse_glow(cy: float, cx: float, color: Color, _unused: float) -> void:
	var g := Gradient.new()
	g.colors  = PackedColorArray([color, Color(color.r, color.g, color.b, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = g; gt.width = 64; gt.height = 64
	gt.fill      = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5)
	var spr := Sprite2D.new()
	spr.texture  = gt
	spr.position = Vector2(
		cx + _map_rng.randf_range(-CELL * 0.3, CELL * 0.3),
		cy + _map_rng.randf_range(-CELL * 0.3, CELL * 0.3))
	spr.scale = Vector2(8.0 / 64.0, 8.0 / 64.0)  # starts at 8px; pulses down to 1px
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spr.material = mat
	add_child(spr)
	_glow_pulses.append({
		"spr":   spr,
		"hz":    _map_rng.randf_range(0.20, 0.50),
		"phase": _map_rng.randf_range(0.0, TAU),
	})


func _add_glitter_zone(cy: float, cx: float) -> void:
	var rect: Rect2 = Rect2(cx - 32.0, cy - 32.0, 64.0, 64.0)
	var count: int = 7 + _fx_rng.randi() % 5  # 7-11 particles
	for _k in count:
		_glitter.append({
			"pos":        Vector2(_fx_rng.randf_range(rect.position.x, rect.end.x),
			                      _fx_rng.randf_range(rect.position.y, rect.end.y)),
			"vel":        Vector2(_fx_rng.randf_range(-10.0, 10.0),
			                      _fx_rng.randf_range(-6.0,   6.0)),
			"rect":       rect,
			"brightness": _fx_rng.randf(),
			"hidden":     false,
			"timer":      _fx_rng.randf_range(0.3, 2.0),
		})


func _add_hover_label_icon(center_y: float, center_x: float, display_px: float, label_text: String) -> void:
	var ls := LabelSettings.new()
	ls.font = FONT; ls.font_size = 9
	ls.font_color    = Color(0.85, 0.92, 1.0, 0.95)
	ls.outline_size  = 1
	ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
	var lbl := Label.new()
	lbl.text           = label_text
	lbl.label_settings = ls
	var obj_top: float = center_y - display_px * 0.5
	var row_above: int = int(obj_top / CELL) - 1
	lbl.position  = Vector2(center_x - 3, row_above * CELL + 2)
	lbl.z_index   = 10
	lbl.modulate.a = 0.2
	add_child(lbl)
	var icon_idx: int = NODE_TYPE_ICONS[_cur_node_type]
	var at := AtlasTexture.new()
	at.atlas  = ICON_STRIP
	at.region = Rect2(icon_idx * 32, 0, 32, 32)
	var icon_spr := Sprite2D.new()
	icon_spr.texture  = at
	icon_spr.position = Vector2(center_x, center_y)
	icon_spr.scale    = Vector2(0.5, 0.5)
	icon_spr.z_index  = 5
	icon_spr.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(icon_spr)
	_planet_hovers.append({
		"center": Vector2(center_x, center_y),
		"radius": display_px * 0.5,
		"label":  lbl,
		"icon":   icon_spr,
	})


func _spawn_nebula(center_y: float, center_x: float) -> void:
	var px: float = 32.0 + float(_map_rng.randi() % 3) * 16.0  # 32, 48, 64px
	var mat := ShaderMaterial.new()
	mat.shader = NEBULA_SHADER
	mat.set_shader_parameter("colorscheme", NEBULA_COLORSCHEME)
	mat.set_shader_parameter("scale",        2.0)
	mat.set_shader_parameter("octaves",      4)
	mat.set_shader_parameter("seed",         float(_map_rng.randi() % 900) / 100.0 + 1.0)
	mat.set_shader_parameter("pixels",       px)
	mat.set_shader_parameter("drift_speed",  0.004)
	mat.set_shader_parameter("max_alpha",    0.90)
	mat.set_shader_parameter("density",      1.2)
	mat.set_shader_parameter("edge_sharpness", 0.5)
	mat.set_shader_parameter("warp_strength", 1.0)
	mat.set_shader_parameter("warp_scale",   1.0)
	mat.set_shader_parameter("wisp_strength", 0.3)
	mat.set_shader_parameter("opacity",      1.0)
	mat.set_shader_parameter("uv_correct",   Vector2(1.0, 1.0))
	mat.set_shader_parameter("scroll_offset", Vector2.ZERO)
	var rect := ColorRect.new()
	rect.color        = Color(0.0, 0.0, 0.0, 0.0)
	rect.material     = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size         = Vector2(px, px)
	rect.position     = Vector2(center_x - px * 0.5, center_y - px * 0.5)
	rect.modulate     = NEBULA_TINTS[_map_rng.randi() % NEBULA_TINTS.size()]
	add_child(rect)
	# Circular mask: radial gradient from transparent-center to BG-edge,
	# painted on top to cut the square corners off the nebula.
	var mask_g := Gradient.new()
	mask_g.colors  = PackedColorArray([
		Color(BG_COLOR.r, BG_COLOR.g, BG_COLOR.b, 0.0),
		BG_COLOR,
	])
	mask_g.offsets = PackedFloat32Array([0.40, 0.75])
	var mask_gt := GradientTexture2D.new()
	mask_gt.gradient  = mask_g
	mask_gt.width     = 64; mask_gt.height = 64
	mask_gt.fill      = GradientTexture2D.FILL_RADIAL
	mask_gt.fill_from = Vector2(0.5, 0.5)
	mask_gt.fill_to   = Vector2(1.0, 0.5)
	var mask_spr := Sprite2D.new()
	mask_spr.texture  = mask_gt
	mask_spr.scale    = Vector2(px / 64.0, px / 64.0)
	mask_spr.position = Vector2(center_x, center_y)
	add_child(mask_spr)


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
		_duplicate_materials(star)
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

	for i in STAR_ANCHORS.size():
		var anchor: Vector2 = STAR_ANCHORS[i]
		var star_top: float  = anchor.y - STAR_DISPLAY_PX[i] * 0.5
		# Row just above the star's upper edge.
		var row_above: int   = int(star_top / CELL) - 1
		var lbl := Label.new()
		lbl.text           = _system_names[i]
		lbl.label_settings = ls
		lbl.position = Vector2(anchor.x - 2, row_above * CELL + 2)
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


# Duplicate every ShaderMaterial on ColorRect children so each instance
# gets its own parameter namespace (avoids shared-resource clobbering).
func _duplicate_materials(root: Node) -> void:
	for child in root.get_children():
		if child is ColorRect and child.material is ShaderMaterial:
			(child as ColorRect).material = (child.material as ShaderMaterial).duplicate()
		_duplicate_materials(child)


# ---------------------------------------------------------------------------
# Grid
# ---------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 270), BG_COLOR)
	# Combat glitter — 1px dots.
	for p in _glitter:
		if p.brightness > 0.04:
			draw_rect(Rect2(p.pos, Vector2(1, 1)),
				Color(0.78, 0.84, 0.92, p.brightness))
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


# ---------------------------------------------------------------------------
# Dev UI — "Generate New" button at cell [13,15]
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var btn := Button.new()
	btn.text     = "Generate New"
	btn.position = Vector2(13 * CELL, 15 * CELL)
	btn.size     = Vector2(80, 14)
	btn.pressed.connect(_rebuild)
	add_child(btn)


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_star_glows.clear()
	_system_names.clear()
	_route_lengths.clear()
	_celestial_nodes.clear()
	_planet_hovers.clear()
	_asteroid_rotators.clear()
	_glow_pulses.clear()
	_glitter.clear()
	_moon_data.clear()
	_moon_textures.clear()
	map_seed = _map_rng.randi()
	call_deferred("_deferred_build")


func _deferred_build() -> void:
	_map_rng.seed = map_seed
	_generate_names()
	_generate_route_lengths()
	_build_routes()
	_build_route_objects()
	_build_boss_nodes()
	_build_stars()
	_build_labels()
	_build_ui()

