extends Node2D

# Sector Map V3 — LIVE gameplay version.
#
# Forked from scripts/dev/sector_map_v3.gd (commit b62eebb visual polish).
# Differences vs the dev tool:
#   - POI positions + types are sourced from Run.sector_map_cache (the
#     single source of truth for the current sector), not procgen.
#   - Decoration (planet/asteroid/cluster spawn + cosmetic randomness) is
#     seeded per-POI by hash(poi.id), so the same POI renders identically
#     across reloads without storing visual choices in the cache.
#   - Boss nodes are dim + show "0/N" progress label until their row's
#     POIs are 100% complete; only then are they clickable.
#   - POI / boss clicks transition to the right gameplay scene and set
#     Run.current_node_id / current_node_type / hazard_subtype.
#   - Dev affordances (Generate New, click-to-toggle-complete) are gone.

const FONT            = preload("res://graphics/fonts/PixelOperator.ttf")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const SectorNode      = preload("res://scripts/sector_node.gd")
const STAR_SCENE      = preload("res://Planets/Star/Star.tscn")
const PLANET_SCENES   := [
	"res://Planets/LavaWorld/LavaWorld.tscn",
	"res://Planets/DryTerran/DryTerran.tscn",
	"res://Planets/NoAtmosphere/NoAtmosphere.tscn",
	"res://Planets/LandMasses/LandMasses.tscn",
	"res://Planets/GasPlanet/GasPlanet.tscn",
	"res://Planets/IceWorld/IceWorld.tscn",
]
const PLANET_ZONE_PEAK := [0.10, 0.25, 0.30, 0.50, 0.70, 0.90]

const NODE_STRIP       = preload("res://graphics/ui/sector_nodes.png")
const ICON_STRIP       = preload("res://graphics/ui/sector_icons.png")
# Icon frames: 0=base(outpost) 1=start 2=battle(combat) 3=boss 4=hazard 5=signal
const ICON_OUTPOST     := 0
const ICON_COMBAT      := 2
const ICON_BOSS        := 3
const ICON_HAZARD      := 4
const ICON_SIGNAL      := 5
const COLOR_NODE_GREEN := Color(0.55, 1.0, 0.50, 1.0)
const COLOR_BOSS_RED   := Color(1.0, 0.30, 0.25, 1.0)
const PLANET_LETTERS   := ["b", "c", "d", "e", "f", "g"]
const ASTEROID_SCENE   = preload("res://Planets/Asteroids/Asteroid.tscn")

const CELL  := 16
const COLS  := 30
const ROWS  := 16

const BG_COLOR    := Color(0.06, 0.07, 0.10, 1.0)
const LABEL_COLOR := Color(0.32, 0.42, 0.58, 0.50)

# Row anchors must match Run.start_new_sector — three stars on the left.
const STAR_ANCHORS    := [Vector2(64, 64), Vector2(64, 128), Vector2(64, 192)]
const STAR_DISPLAY_PX := [64.0, 32.0, 24.0]
const STAR_GLOW_COLORS := [
	Color(0.45, 0.65, 1.00, 1.0),
	Color(1.00, 0.72, 0.18, 1.0),
	Color(1.00, 0.26, 0.07, 1.0),
]
const STAR_GLOW_ALPHA := [0.65, 0.60, 0.55]
const STAR_PULSE_HZ   := [0.38, 0.52, 0.44]
const STAR_PHASE      := [0.00, 1.10, 2.30]
const STAR_COOL       := [true, false, false]

const ROUTE_WIDTH := 8.0
const ROUTE_COLOR := Color(0.30, 0.38, 0.55, 0.70)
const PROGRESS_COLOR := Color(0.40, 0.95, 0.40, 1.0)

# Scene paths for click transitions. Combat/Boss/Hazard all share main.tscn;
# the distinction comes from current_node_type set on Run.
const COMBAT_SCENE  := "res://scenes/main.tscn"
const OUTPOST_SCENE := "res://scenes/outpost.tscn"
const SIGNAL_SCENE  := "res://scenes/signal_event.tscn"
const BOSS_SCENE    := "res://scenes/main.tscn"
const HAZARD_SCENE  := "res://scenes/main.tscn"

# Per-POI decoration object types: 0=planet, 1=large_asteroid, 2=asteroid_cluster
const OBJ_PLANET    := 0
const OBJ_LARGE_AST := 1
const OBJ_CLUSTER   := 2
const PLANET_MIN_PX := 16.0

var _time:          float = 0.0
var _star_glows:    Array = []
var _celestial_nodes: Array = []
var _planet_hovers: Array = []   # {center, radius, label, icon}
var _asteroid_rotators: Array = []
var _moon_data:     Array = []
var _moon_textures: Dictionary = {}
var _glow_pulses:   Array = []
var _glitter:       Array = []
var _asteroid_pixels: Array = []
var _fx_rng: RandomNumberGenerator

# Per-POI click hit-region entry: {id, pos, radius, on_press: Callable}
var _poi_hits: Array = []
# Per-boss entry: {id, pos, row_idx, label, icon, dot_spr}
var _boss_entries: Array = []
# Per-row endpoint cache for green progress overlay: {anchor, end_x}
var _route_segments: Array = []
# Tracks the visual decorator currently being placed (for hover-color logic).
var _cur_row_idx: int = 0


func _ready() -> void:
	RenderingServer.set_default_clear_color(BG_COLOR)
	_fx_rng = RandomNumberGenerator.new()
	_fx_rng.seed = randi()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("sector")
	_ensure_sector_cache()
	_advance_if_complete()
	_build_routes()
	_build_pois_from_cache()
	_build_bosses_from_cache()
	_build_stars()
	_build_labels()


# Pull cache; create one if missing OR if it's for a different sector.
func _ensure_sector_cache() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	var target_sector: int = run.sectors_cleared + 1
	var cache: Dictionary = run.sector_map_cache
	var needs_gen: bool = cache.is_empty() \
		or not cache.has("sector_idx") \
		or int(cache.get("sector_idx", -1)) != target_sector
	if needs_gen:
		var seed_value: int = run.run_seed + run.sectors_cleared
		run.start_new_sector(target_sector, seed_value)


# If returning to the map after the last boss died, bump sectors_cleared
# and roll the next sector immediately. This way the player never sees the
# empty post-sector cache — they see the new sector.
func _advance_if_complete() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if run.is_sector_complete():
		run.sectors_cleared += 1
		run.combats_in_sector = 0
		run.run_seed = randi()
		run.start_new_sector(run.sectors_cleared + 1, run.run_seed)


func _process(delta: float) -> void:
	_time += delta
	for node in _celestial_nodes:
		if is_instance_valid(node) and node.has_method("update_time"):
			node.update_time(_time * 0.5)
	for i in _star_glows.size():
		var pulse: float = sin(_time * STAR_PULSE_HZ[i] * TAU + STAR_PHASE[i])
		var glow_spr: Sprite2D = _star_glows[i].get_child(0)
		var s: float = (STAR_DISPLAY_PX[i] * 2.2) / 64.0 * (1.0 + 0.06 * pulse)
		glow_spr.scale      = Vector2(s, s)
		glow_spr.modulate.a = STAR_GLOW_ALPHA[i] + 0.15 * pulse
	for m in _moon_data:
		if not is_instance_valid(m.node):
			continue
		var angle: float = _time * m.speed + m.phase
		m.node.position = m.center + Vector2(cos(angle) * m.rx, sin(angle) * m.ry)
	for entry in _asteroid_rotators:
		if is_instance_valid(entry.node) and entry.node.has_method("set_custom_time"):
			entry.node.set_custom_time(_time * entry.speed + entry.phase)
	for g in _glow_pulses:
		if is_instance_valid(g.spr):
			var t: float = 0.5 + 0.5 * sin(_time * g.hz * TAU + g.phase)
			var sz: float = lerpf(0.8 / 64.0, 6.4 / 64.0, t)
			g.spr.scale     = Vector2(sz, sz)
			g.spr.modulate.a = lerpf(0.3, 1.0, t)
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
	if needs_redraw or not _asteroid_pixels.is_empty():
		queue_redraw()
	# Hover fade.
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
# Routes
# ---------------------------------------------------------------------------

func _build_routes() -> void:
	_route_segments.clear()
	var run = get_node("/root/Run")
	var rows: Array = run.sector_map_cache.get("rows", [])
	for i in rows.size():
		var anchor: Vector2 = STAR_ANCHORS[i]
		var boss: Dictionary = rows[i].boss
		var end_x: float = boss.pos.x
		var line := Line2D.new()
		line.default_color  = ROUTE_COLOR
		line.width          = ROUTE_WIDTH
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode   = Line2D.LINE_CAP_ROUND
		line.points = PackedVector2Array([anchor, Vector2(end_x, anchor.y)])
		add_child(line)
		_route_segments.append({"anchor": anchor, "end_x": end_x})


# ---------------------------------------------------------------------------
# POIs from cache — decoration is per-POI deterministic via hash(poi.id)
# ---------------------------------------------------------------------------

func _build_pois_from_cache() -> void:
	var run = get_node("/root/Run")
	var rows: Array = run.sector_map_cache.get("rows", [])
	for r_idx in rows.size():
		_cur_row_idx = r_idx
		var anchor: Vector2 = STAR_ANCHORS[r_idx]
		var row_end_x: float = rows[r_idx].boss.pos.x
		var pois: Array = rows[r_idx].pois
		var planet_seq: int = 0
		for poi in pois:
			var deco_rng := RandomNumberGenerator.new()
			deco_rng.seed = abs(hash(poi.id))
			# Object kind: planet/large_ast/cluster. Distribution roughly
			# matches the dev v3 random pick (uniform across 3 types).
			var obj_kind: int = deco_rng.randi() % 3
			var hover_label: String = "?"
			match obj_kind:
				OBJ_PLANET:
					var px: float = PLANET_MIN_PX + float(deco_rng.randi() % 3) * 8.0
					var frac: float = (poi.pos.x - 128.0) / max(1.0, row_end_x - 128.0)
					var ptype: int  = _pick_planet_type(deco_rng, frac)
					_spawn_planet(poi.pos, px, ptype, r_idx, deco_rng)
					hover_label = PLANET_LETTERS[mini(planet_seq, PLANET_LETTERS.size() - 1)]
					planet_seq += 1
				OBJ_LARGE_AST:
					_spawn_large_asteroid(poi.pos, r_idx, deco_rng)
					hover_label = "Asteroid"
				OBJ_CLUSTER:
					_spawn_asteroid_cluster(poi.pos, r_idx, deco_rng)
					hover_label = "Belt"
			_add_node_dressing(poi.pos, int(poi.node_type), deco_rng)
			_add_hover_label_icon(poi.pos, 32.0, hover_label, int(poi.node_type), poi.completed)
			_poi_hits.append({
				"id":     String(poi.id),
				"pos":    Vector2(poi.pos),
				"radius": 10.0,
				"kind":   "poi",
			})


func _pick_planet_type(rng: RandomNumberGenerator, frac: float) -> int:
	var weights: PackedFloat32Array
	weights.resize(PLANET_ZONE_PEAK.size())
	var total: float = 0.0
	for j in PLANET_ZONE_PEAK.size():
		var w: float = 1.0 - absf(PLANET_ZONE_PEAK[j] - frac) * 3.0
		weights[j] = maxf(0.05, w)
		total += weights[j]
	var roll: float = rng.randf() * total
	for j in weights.size():
		roll -= weights[j]
		if roll <= 0.0:
			return j
	return PLANET_ZONE_PEAK.size() - 1


func _spawn_planet(center: Vector2, display_px: float, type_idx: int, row_idx: int, rng: RandomNumberGenerator) -> void:
	var ps = load(PLANET_SCENES[type_idx])
	if ps == null:
		return
	var p = ps.instantiate()
	var sf: float = display_px / 100.0
	if p is Control:
		p.anchor_left = 0.0; p.anchor_top = 0.0
		p.anchor_right = 0.0; p.anchor_bottom = 0.0
		p.offset_right = 100.0; p.offset_bottom = 100.0
		p.size = Vector2(100.0, 100.0)
		p.custom_minimum_size = Vector2(100.0, 100.0)
		p.pivot_offset = Vector2.ZERO
	p.scale    = Vector2(sf, sf)
	p.position = Vector2(center.x - 50.0 * sf, center.y - 50.0 * sf)
	_duplicate_materials(p)
	if p.has_method("set_pixels"):  p.set_pixels(display_px)
	if p.has_method("set_seed"):    p.set_seed(rng.randi() % 100000)
	seed(rng.randi())
	if p.has_method("randomize_colors"): p.randomize_colors()
	if p.has_method("set_rotates"): p.set_rotates(true)
	add_child(p)
	_reset_planet_colorrects(p)
	if p.has_method("set_light"):
		p.set_light(Vector2(0.0, 0.5))
	p.modulate = Color.WHITE.lerp(STAR_GLOW_COLORS[row_idx], 0.18)
	p.override_time = true
	_celestial_nodes.append(p)
	_spawn_moons(center, display_px, rng)


func _spawn_large_asteroid(center: Vector2, row_idx: int, rng: RandomNumberGenerator) -> void:
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
	ast.position = Vector2(center.x - 50.0 * sf, center.y - 50.0 * sf)
	_duplicate_materials(ast)
	if ast.has_method("set_pixels"): ast.set_pixels(PX)
	if ast.has_method("set_seed"):   ast.set_seed(rng.randi())
	if ast.has_method("set_light"):  ast.set_light(Vector2(0.0, 0.5))
	add_child(ast)
	_reset_planet_colorrects(ast)
	ast.modulate = Color.WHITE.lerp(STAR_GLOW_COLORS[row_idx], 0.18)
	_asteroid_rotators.append({
		"node":  ast,
		"speed": rng.randf_range(0.008, 0.025),
		"phase": rng.randf_range(0.0, TAU),
	})
	_scatter_asteroid_band(center, rng)
	_scatter_pulse_pixels(center, PX, rng)


func _spawn_asteroid_cluster(center: Vector2, row_idx: int, rng: RandomNumberGenerator) -> void:
	var count: int = 3 + rng.randi() % 3
	for _k in count:
		var px: float  = 8.0 + float(rng.randi() % 3) * 4.0
		var sf: float  = px / 100.0
		var ox: float  = rng.randf_range(-20.0, 20.0)
		var oy: float  = rng.randf_range(-16.0, 16.0)
		var ast = ASTEROID_SCENE.instantiate()
		if ast is Control:
			ast.anchor_left = 0.0; ast.anchor_top = 0.0
			ast.anchor_right = 0.0; ast.anchor_bottom = 0.0
			ast.offset_right = 100.0; ast.offset_bottom = 100.0
			ast.size = Vector2(100.0, 100.0)
			ast.custom_minimum_size = Vector2(100.0, 100.0)
			ast.pivot_offset = Vector2.ZERO
		ast.scale    = Vector2(sf, sf)
		ast.position = Vector2(center.x + ox - 50.0 * sf, center.y + oy - 50.0 * sf)
		_duplicate_materials(ast)
		if ast.has_method("set_pixels"): ast.set_pixels(px)
		if ast.has_method("set_seed"):   ast.set_seed(rng.randi())
		if ast.has_method("set_light"):  ast.set_light(Vector2(0.0, 0.5))
		add_child(ast)
		_reset_planet_colorrects(ast)
		ast.modulate = Color.WHITE.lerp(STAR_GLOW_COLORS[row_idx], 0.18)
		_asteroid_rotators.append({
			"node":  ast,
			"speed": rng.randf_range(0.005, 0.020),
			"phase": rng.randf_range(0.0, TAU),
		})
		_scatter_pulse_pixels(Vector2(center.x + ox, center.y + oy), px, rng)
	_scatter_asteroid_band(center, rng)


func _scatter_asteroid_band(center: Vector2, rng: RandomNumberGenerator) -> void:
	var count: int = 2 + rng.randi() % 3
	for _k in count:
		var px: float = 4.0 + float(rng.randi() % 3) * 2.0
		var sf: float = px / 100.0
		var ox: float = rng.randf_range(-36.0, 36.0)
		var oy: float = rng.randf_range(-12.0, 12.0)
		var ast = ASTEROID_SCENE.instantiate()
		if ast is Control:
			ast.anchor_left = 0.0; ast.anchor_top = 0.0
			ast.anchor_right = 0.0; ast.anchor_bottom = 0.0
			ast.offset_right = 100.0; ast.offset_bottom = 100.0
			ast.size = Vector2(100.0, 100.0)
			ast.custom_minimum_size = Vector2(100.0, 100.0)
			ast.pivot_offset = Vector2.ZERO
		ast.scale    = Vector2(sf, sf)
		ast.position = Vector2(center.x + ox - 50.0 * sf, center.y + oy - 50.0 * sf)
		_duplicate_materials(ast)
		if ast.has_method("set_pixels"): ast.set_pixels(px)
		if ast.has_method("set_seed"):   ast.set_seed(rng.randi())
		if ast.has_method("set_light"):  ast.set_light(Vector2(0.0, 0.5))
		add_child(ast)
		_reset_planet_colorrects(ast)
		_asteroid_rotators.append({
			"node":  ast,
			"speed": rng.randf_range(0.005, 0.018),
			"phase": rng.randf_range(0.0, TAU),
		})
		_scatter_pulse_pixels(Vector2(center.x + ox, center.y + oy), px, rng)


func _scatter_pulse_pixels(center: Vector2, ast_px: float, rng: RandomNumberGenerator) -> void:
	var count: int = 6 + rng.randi() % 7
	var radius: float = ast_px * 0.6 + 6.0
	for _k in count:
		var ang: float = rng.randf() * TAU
		var dist: float = rng.randf_range(ast_px * 0.5 + 1.0, radius)
		var pos := Vector2(center.x + cos(ang) * dist, center.y + sin(ang) * dist)
		var size_px: int = 1 if rng.randf() < 0.75 else 2
		var shade: float = rng.randf_range(0.55, 0.85)
		_asteroid_pixels.append({
			"pos":   Vector2(floor(pos.x), floor(pos.y)),
			"size":  size_px,
			"hz":    rng.randf_range(0.25, 0.70),
			"phase": rng.randf_range(0.0, TAU),
			"color": Color(shade, shade, shade, 1.0),
		})


# ---------------------------------------------------------------------------
# Bosses from cache — lock visual + clickability gate
# ---------------------------------------------------------------------------

func _build_bosses_from_cache() -> void:
	var run = get_node("/root/Run")
	var rows: Array = run.sector_map_cache.get("rows", [])
	for r_idx in rows.size():
		var boss: Dictionary = rows[r_idx].boss
		var pos: Vector2 = boss.pos
		var unlocked: bool = run.is_row_pois_complete(r_idx)
		var defeated: bool = boss.completed

		# Dot frame 0 (boss dot, red).
		var dot_at := AtlasTexture.new()
		dot_at.atlas  = NODE_STRIP
		dot_at.region = Rect2(0, 0, 32, 32)
		var dot_spr := Sprite2D.new()
		dot_spr.texture  = dot_at
		dot_spr.position = pos
		# Locked: dim 50% alpha. Unlocked: full strength. Defeated: dim green.
		if defeated:
			dot_spr.modulate = Color(COLOR_NODE_GREEN.r, COLOR_NODE_GREEN.g, COLOR_NODE_GREEN.b, 0.4)
		elif unlocked:
			dot_spr.modulate = Color(COLOR_BOSS_RED.r, COLOR_BOSS_RED.g, COLOR_BOSS_RED.b, 1.0)
		else:
			dot_spr.modulate = Color(COLOR_BOSS_RED.r, COLOR_BOSS_RED.g, COLOR_BOSS_RED.b, 0.5)
		dot_spr.z_index = 3
		add_child(dot_spr)
		# Boss icon overlay.
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
		# Top label: BOSS / DEFEATED.
		var ls := LabelSettings.new()
		ls.font = FONT; ls.font_size = 9
		ls.font_color    = Color(1.0, 0.65, 0.60, 0.95) if not defeated else Color(0.50, 1.0, 0.60, 0.95)
		ls.outline_size  = 1
		ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
		var lbl := Label.new()
		lbl.text           = "DEFEATED" if defeated else "BOSS"
		lbl.label_settings = ls
		var row_above: int  = int((pos.y - 16.0) / CELL) - 1
		lbl.position  = Vector2(pos.x - 14, row_above * CELL + 2)
		lbl.z_index   = 10
		lbl.modulate.a = 0.2
		add_child(lbl)

		# Lock progress label "k/N" below the dot when not unlocked.
		if not unlocked and not defeated:
			var n_total: int = rows[r_idx].pois.size()
			var n_done: int  = 0
			for poi in rows[r_idx].pois:
				if poi.completed:
					n_done += 1
			var locks := LabelSettings.new()
			locks.font = FONT; locks.font_size = 8
			locks.font_color    = Color(1.0, 0.85, 0.30, 1.0)
			locks.outline_size  = 1
			locks.outline_color = Color(0.0, 0.0, 0.0, 1.0)
			var lock_lbl := Label.new()
			lock_lbl.text = "%d/%d" % [n_done, n_total]
			lock_lbl.label_settings = locks
			lock_lbl.position = Vector2(pos.x - 6, pos.y + 10)
			lock_lbl.z_index = 11
			add_child(lock_lbl)

		_planet_hovers.append({
			"center": pos,
			"radius": 16.0,
			"label":  lbl,
			"icon":   icon_spr,
		})
		_boss_entries.append({
			"id":       String(boss.id),
			"pos":      Vector2(pos),
			"row_idx":  r_idx,
			"unlocked": unlocked,
			"defeated": defeated,
		})


# ---------------------------------------------------------------------------
# Stars + labels — identical to dev v3
# ---------------------------------------------------------------------------

func _build_stars() -> void:
	for i in STAR_ANCHORS.size():
		var anchor:     Vector2 = STAR_ANCHORS[i]
		var display_px: float   = STAR_DISPLAY_PX[i]
		var seed_val:   int     = (12345 + i * 7919) % 100000
		var cool: bool          = STAR_COOL[i]
		var star = STAR_SCENE.instantiate()
		var sf: float = display_px / 100.0
		if star is Control:
			star.anchor_left = 0.0; star.anchor_top = 0.0
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


func _build_labels() -> void:
	var ls := LabelSettings.new()
	ls.font         = FONT
	ls.font_size    = 9
	ls.font_color   = Color(0.85, 0.92, 1.0, 0.95)
	ls.outline_size  = 1
	ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
	# Sector header.
	var hdr := Label.new()
	hdr.text = "SECTOR %d" % (get_node("/root/Run").sectors_cleared + 1)
	hdr.label_settings = ls
	hdr.position = Vector2(8, 2)
	hdr.z_index = 10
	add_child(hdr)


# ---------------------------------------------------------------------------
# Hover/label/icon + node-type dressing (mirrors dev v3)
# ---------------------------------------------------------------------------

func _add_node_dressing(pos: Vector2, node_type: int, rng: RandomNumberGenerator) -> void:
	# Map enum int → dressing.
	#   COMBAT = 0, OUTPOST = 1, SIGNAL = 2, HAZARD = 5 (see sector_node.gd)
	match node_type:
		int(SectorNode.NodeType.OUTPOST): _add_pulse_glow(pos, Color(0.35, 0.65, 1.0), rng)
		int(SectorNode.NodeType.HAZARD):  _add_pulse_glow(pos, Color(1.0,  0.25, 0.20), rng)
		int(SectorNode.NodeType.SIGNAL):  _add_pulse_glow(pos, Color(1.0,  0.90, 0.15), rng)
		int(SectorNode.NodeType.COMBAT):  _add_glitter_zone(pos)


func _add_pulse_glow(pos: Vector2, color: Color, rng: RandomNumberGenerator) -> void:
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
		pos.x + rng.randf_range(-CELL * 0.3, CELL * 0.3),
		pos.y + rng.randf_range(-CELL * 0.3, CELL * 0.3))
	spr.scale = Vector2(6.4 / 64.0, 6.4 / 64.0)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spr.material = mat
	add_child(spr)
	_glow_pulses.append({
		"spr":   spr,
		"hz":    rng.randf_range(0.20, 0.50),
		"phase": rng.randf_range(0.0, TAU),
	})
	var dot := ColorRect.new()
	dot.color  = Color(color.r, color.g, color.b, 1.0)
	dot.position = Vector2(floor(spr.position.x), floor(spr.position.y))
	dot.size   = Vector2(1, 1)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)


func _add_glitter_zone(pos: Vector2) -> void:
	var rect: Rect2 = Rect2(pos.x - 32.0, pos.y - 32.0, 64.0, 64.0)
	var count: int = 7 + _fx_rng.randi() % 5
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


func _icon_for_type(node_type: int) -> int:
	match node_type:
		int(SectorNode.NodeType.COMBAT):  return ICON_COMBAT
		int(SectorNode.NodeType.OUTPOST): return ICON_OUTPOST
		int(SectorNode.NodeType.SIGNAL):  return ICON_SIGNAL
		int(SectorNode.NodeType.HAZARD):  return ICON_HAZARD
		int(SectorNode.NodeType.BOSS):    return ICON_BOSS
	return ICON_COMBAT


func _add_hover_label_icon(pos: Vector2, display_px: float, label_text: String, node_type: int, completed: bool) -> void:
	var ls := LabelSettings.new()
	ls.font = FONT; ls.font_size = 9
	ls.font_color    = Color(0.85, 0.92, 1.0, 0.95)
	ls.outline_size  = 1
	ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
	var lbl := Label.new()
	lbl.text           = label_text
	lbl.label_settings = ls
	var obj_top: float = pos.y - display_px * 0.5
	var row_above: int = int(obj_top / CELL) - 1
	lbl.position  = Vector2(pos.x - 3, row_above * CELL + 2)
	lbl.z_index   = 10
	lbl.modulate.a = 0.2
	add_child(lbl)
	var at := AtlasTexture.new()
	at.atlas  = ICON_STRIP
	at.region = Rect2(_icon_for_type(node_type) * 32, 0, 32, 32)
	var icon_spr := Sprite2D.new()
	icon_spr.texture  = at
	icon_spr.position = pos
	icon_spr.scale    = Vector2(0.5, 0.5)
	icon_spr.z_index  = 5
	# Completed POIs render in soft green; otherwise use the hover-fade default.
	if completed:
		icon_spr.modulate = Color(COLOR_NODE_GREEN.r, COLOR_NODE_GREEN.g, COLOR_NODE_GREEN.b, 0.6)
	else:
		icon_spr.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(icon_spr)
	_planet_hovers.append({
		"center": pos,
		"radius": display_px * 0.5,
		"label":  lbl,
		"icon":   icon_spr,
	})


# ---------------------------------------------------------------------------
# Moons + planet helpers (lifted from dev v3)
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


func _spawn_moons(center: Vector2, planet_px: float, rng: RandomNumberGenerator) -> void:
	var count: int = int(rng.randf() * rng.randf() * 13.0)
	if count == 0:
		return
	for _k in count:
		var base_r: float = planet_px * 0.5 + rng.randf_range(2.0, planet_px * 0.7)
		var rx: float = base_r
		var ry: float = base_r * rng.randf_range(0.45, 1.0)
		var spd: float = rng.randf_range(0.20, 0.70) * (1.0 if rng.randf() > 0.5 else -1.0)
		var phase: float = rng.randf_range(0.0, TAU)
		var base_tint := Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.6), 0.95, 1.0)
		var tint := Color(base_tint.r * 0.5, base_tint.g * 0.5, base_tint.b * 0.5, 1.0)
		var radius_px: int = 1 + rng.randi() % 3
		var spr := Sprite2D.new()
		spr.texture  = _get_moon_texture(radius_px)
		spr.modulate = tint
		spr.z_index  = 1
		add_child(spr)
		_moon_data.append({
			"node": spr, "center": center,
			"rx": rx, "ry": ry,
			"speed": spd, "phase": phase,
		})


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


func _duplicate_materials(root: Node) -> void:
	for child in root.get_children():
		if child is ColorRect and child.material is ShaderMaterial:
			(child as ColorRect).material = (child.material as ShaderMaterial).duplicate()
		_duplicate_materials(child)


# ---------------------------------------------------------------------------
# Draw + input
# ---------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 270), BG_COLOR)
	# Combat glitter — 1px dots.
	for p in _glitter:
		if p.brightness > 0.04:
			draw_rect(Rect2(p.pos, Vector2(1, 1)),
				Color(0.78, 0.84, 0.92, p.brightness))
	# Pulsing decorative pixels around asteroids.
	for px in _asteroid_pixels:
		var a: float = 0.5 + 0.5 * sin(_time * px.hz * TAU + px.phase)
		var c: Color = px.color
		c.a = a
		draw_rect(Rect2(px.pos, Vector2(px.size, px.size)), c)
	# Green progress overlay per row.
	var run = get_node("/root/Run")
	var rows: Array = run.sector_map_cache.get("rows", [])
	for i in _route_segments.size():
		var seg: Dictionary = _route_segments[i]
		var pois: Array = rows[i].pois
		if pois.is_empty():
			continue
		var sorted := pois.duplicate()
		sorted.sort_custom(func(a, b): return a.pos.x < b.pos.x)
		var farthest_x: float = -INF
		var all_done: bool = true
		for poi in sorted:
			if poi.completed:
				farthest_x = maxf(farthest_x, poi.pos.x)
			else:
				all_done = false
		# If row's POIs are all complete, extend through the boss endpoint.
		if all_done:
			farthest_x = seg.end_x
		if farthest_x > -INF:
			draw_line(seg.anchor, Vector2(farthest_x, seg.anchor.y),
				PROGRESS_COLOR, ROUTE_WIDTH)
		# Completed POI ring markers.
		for poi in pois:
			if poi.completed:
				draw_rect(Rect2(poi.pos.x - 4, poi.pos.y - 4, 8, 8),
					PROGRESS_COLOR, false, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# Esc opens the options overlay; never ends the run.
		var OptionsOverlay = load("res://scripts/ui/options_overlay.gd")
		if OptionsOverlay:
			OptionsOverlay.open(self)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp: Vector2 = get_local_mouse_position()
		# Try POIs first (smaller hit-radius, more numerous).
		for hit in _poi_hits:
			if mp.distance_to(hit.pos) <= hit.radius:
				_on_poi_clicked(String(hit.id))
				return
		# Then bosses.
		for b in _boss_entries:
			if mp.distance_to(b.pos) <= 16.0:
				_on_boss_clicked(String(b.id))
				return


func _on_poi_clicked(node_id: String) -> void:
	var run = get_node("/root/Run")
	var poi = run.find_sector_node(node_id)
	if poi == null:
		return
	if poi.get("completed", false):
		return  # already done — no-op (player can still see it on the map)
	run.current_node_id = node_id
	run.current_node_type = int(poi.node_type)
	run.current_hazard_subtype = String(poi.get("hazard_subtype", ""))
	# Stellar metadata is V2-only; clear it so combat backdrop doesn't read stale data.
	run.current_stellar = {}
	match int(poi.node_type):
		int(SectorNode.NodeType.COMBAT):
			SceneTransition.change_scene(get_tree(), COMBAT_SCENE)
		int(SectorNode.NodeType.OUTPOST):
			SceneTransition.change_scene(get_tree(), OUTPOST_SCENE)
		int(SectorNode.NodeType.SIGNAL):
			SceneTransition.change_scene(get_tree(), SIGNAL_SCENE)
		int(SectorNode.NodeType.HAZARD):
			SceneTransition.change_scene(get_tree(), HAZARD_SCENE)


func _on_boss_clicked(node_id: String) -> void:
	var run = get_node("/root/Run")
	var boss = run.find_sector_node(node_id)
	if boss == null:
		return
	if boss.get("completed", false):
		return
	# Find the row this boss lives on.
	var rows: Array = run.sector_map_cache.get("rows", [])
	var row_idx: int = -1
	for i in rows.size():
		if rows[i].boss.id == node_id:
			row_idx = i
			break
	if row_idx < 0 or not run.is_row_pois_complete(row_idx):
		return  # locked
	run.current_node_id = node_id
	run.current_node_type = int(SectorNode.NodeType.BOSS)
	run.current_hazard_subtype = ""
	run.current_stellar = {}
	run.forced_boss_scene = String(boss.get("boss_scene", ""))
	SceneTransition.change_scene(get_tree(), BOSS_SCENE)
