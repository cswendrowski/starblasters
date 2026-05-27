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
const SlotTypes       = preload("res://scripts/weapons/SlotTypes.gd")
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

const BINARY_STAR_CHANCE     := 0.08          # 8% chance of a companion star
const BINARY_STAR_SIZE_RATIO := 0.55          # companion is 55% of primary size
const BINARY_STAR_OFFSET     := Vector2(-22.0, 7.0)  # companion center offset from primary

const EXOTIC_STAR_CHANCE_BASE       := 0.04   # 4% at 0 sectors cleared
const EXOTIC_STAR_CHANCE_PER_SECTOR := 0.012  # +1.2% per sector cleared
const EXOTIC_STAR_CHANCE_MAX        := 0.25   # cap at 25%
const EXOTIC_GLOW_COLORS := [
	Color(0.70, 0.22, 0.95, 1.0),  # purple
	Color(0.18, 0.90, 0.35, 1.0),  # green
	Color(1.00, 0.25, 0.65, 1.0),  # pink
]

const ROUTE_WIDTH := 8.0
# 0.70 × 0.8 = 0.56 — designer asked for -20% opacity on POI lines.
const ROUTE_COLOR := Color(0.30, 0.38, 0.55, 0.56)
const PROGRESS_COLOR := Color(0.40, 0.95, 0.40, 1.0)

# Background starfield palette — mirrors galaxy_backdrop_v3.STAR_COLORS but with
# -20% brightness applied at draw time per designer.
const BG_STAR_COLORS := [
	Color(0.95, 0.97, 1.00),
	Color(1.00, 0.97, 0.92),
	Color(1.00, 0.85, 0.60),
	Color(0.75, 0.85, 1.00),
	Color(1.00, 0.95, 0.80),
	Color(0.95, 0.70, 0.70),
	Color(0.80, 0.95, 0.95),
]
const BG_STAR_BRIGHTNESS_MUL := 0.8  # -20%

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
var _icon_outline_mat: ShaderMaterial = null
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
	# Single mid-run save point: every time the player lands on the sector
	# map (fresh run, post-combat, post-outpost, post-hazard), persist Run
	# state to disk so Resume Patrol from the main menu drops them back
	# here. Anything between map visits is "in a level" and not saved.
	if has_node("/root/Run"):
		var _run_ref = get_node("/root/Run")
		# Hull regen on sector map return — requires self_repair_mk upgrade.
		# +1 pip each visit, capped at max_hull (spec 2026-05-26).
		if int(_run_ref.self_repair_mk) > 0:
			_run_ref.current_hull = clampi(int(_run_ref.current_hull) + 1, 0, int(_run_ref.max_hull))
		_run_ref.save_to_disk()
	_build_bg_stars()
	_build_routes()
	_build_pois_from_cache()
	_build_bosses_from_cache()
	_build_stars()
	_build_labels()
	_show_post_combat_banner()


# Post-combat banner — Asteroid Miners + future events plant a message
# on Run via set_meta("post_combat_banner", text). We render it as a
# top-center label that lingers for a few seconds, then fades. Meta is
# cleared immediately so it never displays twice (no silent leak across
# returns to the map).
func _show_post_combat_banner() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if not run.has_meta("post_combat_banner"):
		return
	var text: String = String(run.get_meta("post_combat_banner", ""))
	run.remove_meta("post_combat_banner")
	if text == "":
		return
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var ls := LabelSettings.new()
	ls.font = FONT
	ls.font_size = 10
	ls.font_color = Color(1.0, 0.92, 0.55, 1.0)  # bounty-gold
	ls.outline_size = 2
	ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
	var lbl := Label.new()
	lbl.label_settings = ls
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.0
	lbl.anchor_right = 1.0
	lbl.offset_left = 8
	lbl.offset_right = -8
	lbl.offset_top = 16
	lbl.offset_bottom = 32
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(lbl)
	# Hold for 3s, then fade out over 0.6s.
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.tween_callback(layer.queue_free)


# Background star layer — modeled on galaxy_backdrop_v3._spawn_stars_layer
# but static (sector map doesn't scroll) and -20% brightness. Sits behind
# everything else via negative z_index. Only stars; no nebula / asteroids.
func _build_bg_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xB6500FF  # stable per-load
	var holder := Node2D.new()
	holder.name = "BgStars"
	holder.z_index = -100
	add_child(holder)
	var pinprick_count: int = rng.randi_range(140, 320)
	var pop_count: int = rng.randi_range(20, 70)
	for _i in pinprick_count:
		var dot := ColorRect.new()
		dot.size = Vector2(1, 1)
		dot.position = Vector2(floor(rng.randf() * 480.0), floor(rng.randf() * 270.0))
		var base: Color = BG_STAR_COLORS[rng.randi() % BG_STAR_COLORS.size()]
		var bright: float = (0.55 + rng.randf() * 0.45) * BG_STAR_BRIGHTNESS_MUL
		dot.color = Color(base.r * bright, base.g * bright, base.b * bright, 1.0)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(dot)
	for _i in pop_count:
		var big := ColorRect.new()
		big.size = Vector2(2, 2)
		big.position = Vector2(floor(rng.randf() * 478.0), floor(rng.randf() * 268.0))
		var c: Color = BG_STAR_COLORS[rng.randi() % BG_STAR_COLORS.size()]
		big.color = Color(c.r * BG_STAR_BRIGHTNESS_MUL, c.g * BG_STAR_BRIGHTNESS_MUL, c.b * BG_STAR_BRIGHTNESS_MUL, 1.0)
		big.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(big)


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
	# Designer: moons on the sector map orbit 70% slower than their descriptor
	# speed. Multiply at consumption so the descriptor remains the single
	# source of truth for combat backdrop derivation.
	const MOON_MAP_SPEED_MUL := 0.30
	for m in _moon_data:
		if not is_instance_valid(m.node):
			continue
		var angle: float = _time * m.speed * MOON_MAP_SPEED_MUL + m.phase
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
	# Hover fade. Each entry stores its own rest alphas — POI icons rest at
	# 0.0 (invisible until hover) per designer, bosses keep their old 0.2 so
	# the "BOSS" / "DEFEATED" label stays readable, completed POIs rest at 0.6.
	var mouse: Vector2 = get_local_mouse_position()
	for entry in _planet_hovers:
		var hovered: bool = mouse.distance_to(entry.center) <= entry.radius
		var lbl: Label    = entry.label
		var icon: Sprite2D = entry.icon
		var label_rest: float = float(entry.get("label_rest", 0.2))
		var icon_rest: float  = float(entry.get("icon_rest", 0.0))
		var hover_tint: Color = entry.get("hover_tint", COLOR_NODE_GREEN)
		var rest_tint: Color  = entry.get("rest_tint", Color.WHITE)
		lbl.modulate.a = lerpf(lbl.modulate.a, 1.0 if hovered else label_rest, delta * 8.0)
		var tgt: Color = hover_tint if hovered else rest_tint
		tgt.a = 0.9 if hovered else icon_rest
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
		# Designer: POI line alpha 0 at the star end, 1 at the boss end. Line2D
		# supports per-length gradient via the `gradient` property, so we keep a
		# single Line2D and tint via gradient stops (cheaper than splitting into
		# many _draw'd segments).
		var grad := Gradient.new()
		var c_star: Color = Color(ROUTE_COLOR.r, ROUTE_COLOR.g, ROUTE_COLOR.b, 0.0)
		var c_boss: Color = Color(ROUTE_COLOR.r, ROUTE_COLOR.g, ROUTE_COLOR.b, ROUTE_COLOR.a)
		grad.colors  = PackedColorArray([c_star, c_boss])
		grad.offsets = PackedFloat32Array([0.0, 1.0])
		line.gradient       = grad
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
			# Celestial bodies (planet/asteroid/cluster) are always drawn so
			# the map reads as a real star chart. The pulse glow and node
			# dressing are suppressed on completed POIs so the node reads
			# as "spent" at a glance. Advance planet_seq either way so the
			# next uncompleted POI keeps the planet-letter sequence stable.
			var draw_dressing: bool = not poi.completed
			match obj_kind:
				OBJ_PLANET:
					var px: float = PLANET_MIN_PX + float(deco_rng.randi() % 3) * 8.0
					var frac: float = (poi.pos.x - 128.0) / max(1.0, row_end_x - 128.0)
					var ptype: int  = _pick_planet_type(deco_rng, frac)
					_spawn_planet(poi.pos, px, ptype, r_idx, deco_rng, String(poi.id))
					planet_seq += 1
				OBJ_LARGE_AST:
					_spawn_large_asteroid(poi.pos, r_idx, deco_rng)
				OBJ_CLUSTER:
					_spawn_asteroid_cluster(poi.pos, r_idx, deco_rng)
			if draw_dressing:
				_add_node_dressing(poi.pos, int(poi.node_type), deco_rng)
			_add_hover_label_icon(poi.pos, 32.0, int(poi.node_type), poi.completed)
			_poi_hits.append({
				"id":     String(poi.id),
				"pos":    Vector2(poi.pos),
				# 14px — wide enough to cover the 16px icon footprint (32px
				# atlas at 0.5 scale) so the icon itself is clickable. Matches
				# the hover radius so reveal + click happen at the same range.
				"radius": 14.0,
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


# V3 planet type index -> galaxy_backdrop.PLANETS index. Keeps the planet
# the player saw on the map identical to the one they fly past in combat.
const V3_TO_BACKDROP_PLANET_IDX := {
	0: 0,  # LavaWorld    -> backdrop 0 LavaWorld
	1: 2,  # DryTerran    -> backdrop 2 DryTerran
	2: 4,  # NoAtmosphere -> backdrop 4 NoAtmosphere
	3: 5,  # LandMasses   -> backdrop 5 LandMasses
	4: 3,  # GasPlanet    -> backdrop 3 GasPlanet
	5: 1,  # IceWorld     -> backdrop 1 IceWorld
}


# Stable per-POI moon RNG. Salt the seed so moon derivation is decoupled
# from the planet's randomize_colors / set_seed consumption ordering — the
# combat backdrop can re-derive the same moon descriptors without having
# to replay the entire V3 spawn sequence.
func _make_moon_rng(poi_id: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = abs(hash(poi_id) ^ 0x9E3779B9)
	return r


# Deterministic exotic/binary state for a given row. Same result whether
# called from _build_stars() (map display) or _compute_poi/boss_stellar
# (combat backdrop) — keyed on run_seed + row so both see the same star.
func _get_star_variant(row_idx: int) -> Dictionary:
	var run = get_node("/root/Run")
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("star_variant:%d:%d" % [row_idx, run.run_seed]))
	# Base star class: randomize which of the 3 realistic types this row shows.
	var base_type_idx: int = rng.randi() % STAR_GLOW_COLORS.size()
	# Pixel seed: vary surface pattern per run.
	var pixel_seed: int = abs(rng.randi()) % 100000
	# Exotic color chance scales with sectors cleared.
	var exotic_chance: float = clampf(
		EXOTIC_STAR_CHANCE_BASE + EXOTIC_STAR_CHANCE_PER_SECTOR * run.sectors_cleared,
		0.0, EXOTIC_STAR_CHANCE_MAX)
	var exotic_idx: int = -1
	if rng.randf() < exotic_chance:
		exotic_idx = rng.randi() % EXOTIC_GLOW_COLORS.size()
	var has_binary: bool = rng.randf() < BINARY_STAR_CHANCE
	return {
		"base_type_idx": base_type_idx,
		"pixel_seed":    pixel_seed,
		"exotic_idx":    exotic_idx,
		"has_binary":    has_binary,
	}


# Flat descriptor for the combat backdrop. Deterministic per poi.id, no
# external state. obj_kind / planet_type mirror _build_pois_from_cache so
# the combat scene's planet matches what the player clicked on the map.
func _compute_poi_stellar(poi: Dictionary, row_idx: int) -> Dictionary:
	var run = get_node("/root/Run")
	var rows: Array = run.sector_map_cache.get("rows", [])
	var row_end_x: float = float(rows[row_idx].boss.pos.x) if row_idx < rows.size() else 416.0
	var deco_rng := RandomNumberGenerator.new()
	deco_rng.seed = abs(hash(poi.id))
	var obj_kind: int = deco_rng.randi() % 3
	var planet_idx: int = -1
	var planet_type: int = -1
	var moons: Array = []
	var has_asteroids: bool = false
	var asteroid_density: float = 0.0
	match obj_kind:
		OBJ_PLANET:
			var px: float = PLANET_MIN_PX + float(deco_rng.randi() % 3) * 8.0
			var frac: float = (poi.pos.x - 128.0) / max(1.0, row_end_x - 128.0)
			planet_type = _pick_planet_type(deco_rng, frac)
			planet_idx = int(V3_TO_BACKDROP_PLANET_IDX.get(planet_type, 0))
			moons = _derive_moon_descriptors(String(poi.id), px)
		OBJ_LARGE_AST:
			has_asteroids = true
			asteroid_density = 0.6
		OBJ_CLUSTER:
			has_asteroids = true
			asteroid_density = 1.2
	var sv: Dictionary = _get_star_variant(row_idx)
	var base_type: int  = sv.base_type_idx
	var star_color: Color = EXOTIC_GLOW_COLORS[sv.exotic_idx] if sv.exotic_idx >= 0 else STAR_GLOW_COLORS[base_type]
	return {
		"obj_kind":         obj_kind,
		"planet_idx":       planet_idx,
		"planet_type":      planet_type,
		"has_asteroids":    has_asteroids,
		"asteroid_density": asteroid_density,
		"moons":            moons,
		"star_color":       star_color,
		"star_cool":        STAR_COOL[base_type],
		"row_idx":          row_idx,
		"poi_id":           String(poi.id),
		"exotic_idx":       sv.exotic_idx,
		"has_binary":       sv.has_binary,
	}


# Deterministic moon list around a POI's planet. Same formula as the
# refactored _spawn_moons — uses the salted moon_rng. Each entry is a flat
# Dictionary the combat backdrop can spawn directly.
func _derive_moon_descriptors(poi_id: String, planet_px: float) -> Array:
	var moon_rng := _make_moon_rng(poi_id)
	var count: int = int(moon_rng.randf() * moon_rng.randf() * 13.0)
	var out: Array = []
	for _k in count:
		var base_r: float = planet_px * 0.5 + moon_rng.randf_range(2.0, planet_px * 0.7)
		var rx: float = base_r
		var ry: float = base_r * moon_rng.randf_range(0.45, 1.0)
		var spd: float = moon_rng.randf_range(0.20, 0.70) * (1.0 if moon_rng.randf() > 0.5 else -1.0)
		var phase: float = moon_rng.randf_range(0.0, TAU)
		var base_tint := Color.from_hsv(moon_rng.randf(), moon_rng.randf_range(0.2, 0.6), 0.95, 1.0)
		var tint := Color(base_tint.r * 0.5, base_tint.g * 0.5, base_tint.b * 0.5, 1.0)
		var radius_px: int = 1 + moon_rng.randi() % 3
		out.append({
			"radius": radius_px,
			"color":  tint,
			"phase":  phase,
			"rx":     rx,
			"ry":     ry,
			"speed":  spd,
		})
	return out


# Boss descriptor: bosses live at fixed row endpoints with no planet/asteroid
# decoration of their own. Tint the scene with the row's star color so the
# boss arena still feels "visited from" that line.
func _compute_boss_stellar(row_idx: int) -> Dictionary:
	var sv: Dictionary = _get_star_variant(row_idx)
	var base_type: int  = sv.base_type_idx
	var star_color: Color = EXOTIC_GLOW_COLORS[sv.exotic_idx] if sv.exotic_idx >= 0 else STAR_GLOW_COLORS[base_type]
	return {
		"obj_kind":         -1,
		"planet_idx":       -1,
		"planet_type":      -1,
		"has_asteroids":    false,
		"asteroid_density": 0.0,
		"moons":            [],
		"star_color":       star_color,
		"star_cool":        STAR_COOL[base_type],
		"row_idx":          row_idx,
		"poi_id":           "boss:%d" % row_idx,
		"exotic_idx":       sv.exotic_idx,
		"has_binary":       sv.has_binary,
	}


func _spawn_planet(center: Vector2, display_px: float, type_idx: int, row_idx: int, rng: RandomNumberGenerator, poi_id: String = "") -> void:
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
	_disable_celestial_mouse(p)
	_reset_planet_colorrects(p)
	if p.has_method("set_light"):
		p.set_light(Vector2(0.0, 0.5))
	# Mild star-color wash — use effective (randomized) star color for this row.
	var _psv: Dictionary = _get_star_variant(row_idx)
	var _p_star: Color = EXOTIC_GLOW_COLORS[_psv.exotic_idx] if _psv.exotic_idx >= 0 else STAR_GLOW_COLORS[_psv.base_type_idx]
	p.modulate = Color.WHITE.lerp(_p_star, 0.18)
	p.override_time = true
	_celestial_nodes.append(p)
	# Moons use a per-POI salted RNG so the descriptor produced by
	# _compute_poi_stellar matches what we draw here, regardless of how much
	# of `rng` got consumed by randomize_colors / set_seed above.
	var moon_rng: RandomNumberGenerator = _make_moon_rng(poi_id) if poi_id != "" else rng
	_spawn_moons(center, display_px, moon_rng)
	var planet_name_seed: int = abs(hash(poi_id)) if poi_id != "" else abs(hash(center))
	var planet_name: String = _generate_celestial_name("planet", planet_name_seed)
	_spawn_celestial_name_label(center, planet_name, display_px * 0.5 + 4.0, true)


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
	_disable_asteroid_outlines(ast)   # Change 3
	if ast.has_method("set_pixels"): ast.set_pixels(PX)
	if ast.has_method("set_seed"):   ast.set_seed(rng.randi())
	if ast.has_method("set_light"):  ast.set_light(Vector2(0.0, 0.5))
	add_child(ast)
	_disable_celestial_mouse(ast)
	_reset_planet_colorrects(ast)
	# Designer: asteroid surfaces were not picking up the row's randomized
	# tint — modulate-only ran into the muted gray-blue default palette and
	# came out muddy. Inject a 3-tone palette derived from the row star color
	# directly into the shader so the rocks actually read in the family color
	# the decoration pixels already use. Keep modulate at WHITE so we don't
	# double-tint.
	_apply_row_tint_to_asteroid(ast, row_idx)
	ast.modulate = Color.WHITE
	_asteroid_rotators.append({
		"node":  ast,
		"speed": rng.randf_range(0.008, 0.025),
		"phase": rng.randf_range(0.0, TAU),
	})
	_scatter_asteroid_band(center, rng)
	_scatter_pulse_pixels(center, PX, rng)
	var ast_name: String = _generate_celestial_name("asteroid", abs(hash(center)))
	_spawn_celestial_name_label(center, ast_name, PX * 0.5 + 4.0, true)


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
		_disable_asteroid_outlines(ast)   # Change 3
		if ast.has_method("set_pixels"): ast.set_pixels(px)
		if ast.has_method("set_seed"):   ast.set_seed(rng.randi())
		if ast.has_method("set_light"):  ast.set_light(Vector2(0.0, 0.5))
		add_child(ast)
		_disable_celestial_mouse(ast)
		_reset_planet_colorrects(ast)
		# Inject row tint into the asteroid shader's `colors` palette instead
		# of multiplying via modulate — modulate-on-gray reads muddy.
		_apply_row_tint_to_asteroid(ast, row_idx)
		ast.modulate = Color.WHITE
		_asteroid_rotators.append({
			"node":  ast,
			"speed": rng.randf_range(0.005, 0.020),
			"phase": rng.randf_range(0.0, TAU),
		})
		_scatter_pulse_pixels(Vector2(center.x + ox, center.y + oy), px, rng)
	_scatter_asteroid_band(center, rng)
	var cluster_name: String = _generate_celestial_name("cluster", abs(hash(center)) ^ 0xABCD)
	_spawn_celestial_name_label(center, cluster_name, 20.0, true)


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
		_disable_asteroid_outlines(ast)   # Change 3
		if ast.has_method("set_pixels"): ast.set_pixels(px)
		if ast.has_method("set_seed"):   ast.set_seed(rng.randi())
		if ast.has_method("set_light"):  ast.set_light(Vector2(0.0, 0.5))
		add_child(ast)
		_disable_celestial_mouse(ast)
		_reset_planet_colorrects(ast)
		# Same star-tint treatment as the parent asteroid spawners. _cur_row_idx
		# is the row this band is being scattered into. Inject palette into the
		# shader rather than relying on modulate (which read muddy on the gray
		# default colors).
		var band_tint_row: int = _cur_row_idx if _cur_row_idx < STAR_GLOW_COLORS.size() else 0
		_apply_row_tint_to_asteroid(ast, band_tint_row)
		ast.modulate = Color.WHITE
		_asteroid_rotators.append({
			"node":  ast,
			"speed": rng.randf_range(0.005, 0.018),
			"phase": rng.randf_range(0.0, TAU),
		})
		_scatter_pulse_pixels(Vector2(center.x + ox, center.y + oy), px, rng)


func _scatter_pulse_pixels(center: Vector2, ast_px: float, rng: RandomNumberGenerator) -> void:
	var count: int = 6 + rng.randi() % 7
	var radius: float = ast_px * 0.6 + 6.0
	# Source pixel color from the current row's star tint — this matches the
	# modulate the generated asteroids receive (lerp(WHITE, star, 0.18)) so
	# the decorative pixels read as the same family. Per-pixel brightness
	# variation kept (0.55-0.85) to preserve depth.
	var base_tint: Color = STAR_GLOW_COLORS[_cur_row_idx] if _cur_row_idx < STAR_GLOW_COLORS.size() else Color.WHITE
	# Pull the star tint toward white so we don't get a saturated red haze
	# around every asteroid — mirrors the 0.18 lerp on the asteroid modulate
	# but pushed further white (asteroid surface art is itself colored).
	base_tint = Color.WHITE.lerp(base_tint, 0.55)
	for _k in count:
		var ang: float = rng.randf() * TAU
		var dist: float = rng.randf_range(ast_px * 0.5 + 1.0, radius)
		var pos := Vector2(center.x + cos(ang) * dist, center.y + sin(ang) * dist)
		var size_px: int = 1 if rng.randf() < 0.75 else 2
		var shade: float = rng.randf_range(0.55, 0.85)
		_asteroid_pixels.append({
			"pos":   Vector2(floor(pos.x), floor(pos.y)),
			"size":  size_px,
			# 80% slower blink — old range 0.25-0.70 Hz / 5 = 0.05-0.14 Hz.
			"hz":    rng.randf_range(0.05, 0.14),
			"phase": rng.randf_range(0.0, TAU),
			"color": Color(base_tint.r * shade, base_tint.g * shade, base_tint.b * shade, 1.0),
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
		dot_spr.scale    = Vector2(0.5, 0.5)   # Change 1: half size
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
		icon_spr.scale    = Vector2(0.25, 0.25)
		icon_spr.z_index  = 5
		icon_spr.modulate = Color(1.0, 1.0, 1.0, 0.5)
		icon_spr.material = _get_icon_outline_mat()
		add_child(icon_spr)
		# Top label: BOSS / DEFEATED — same row/font as POI labels, red opaque.
		var ls := LabelSettings.new()
		ls.font = FONT; ls.font_size = 7
		ls.font_color    = Color(0.90, 0.30, 0.30, 1.0) if not defeated else Color(0.50, 1.0, 0.60, 1.0)
		ls.outline_size  = 1
		ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
		var lbl := Label.new()
		lbl.text                  = "DEFEATED" if defeated else "BOSS"
		lbl.label_settings        = ls
		lbl.custom_minimum_size.x = 40.0
		lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
		var row_above: int  = int((pos.y - 8.0) / CELL) - 1
		lbl.position  = Vector2(pos.x - 20.0, row_above * CELL + 2)
		lbl.z_index   = 10
		lbl.modulate.a = 1.0
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lbl)

		# Lock progress label "k/N" below the dot when not unlocked.
		if not unlocked and not defeated:
			var n_total: int = rows[r_idx].pois.size()
			var n_done: int  = 0
			for poi in rows[r_idx].pois:
				if poi.completed:
					n_done += 1
			var locks := LabelSettings.new()
			locks.font = FONT; locks.font_size = 4   # Change 1: halved from 8
			locks.font_color    = Color(1.0, 0.85, 0.30, 1.0)
			locks.outline_size  = 1
			locks.outline_color = Color(0.0, 0.0, 0.0, 1.0)
			var lock_lbl := Label.new()
			lock_lbl.text = "%d/%d" % [n_done, n_total]
			lock_lbl.label_settings = locks
			lock_lbl.position = Vector2(pos.x - 3, pos.y + 6)   # Change 1: -6→-3, +10→+6
			lock_lbl.z_index = 11
			lock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(lock_lbl)

		# Locked bosses must NOT hover green — designer feedback. Use dim red so
		# the player gets a clear "not yet" signal. Defeated bosses also avoid
		# green to keep "green = clickable" semantically tight.
		var boss_hover_tint: Color = COLOR_NODE_GREEN
		if not unlocked or defeated:
			boss_hover_tint = Color(COLOR_BOSS_RED.r, COLOR_BOSS_RED.g, COLOR_BOSS_RED.b, 1.0)
		_planet_hovers.append({
			"center":     pos,
			"radius":     8.0,    # Change 1: halved from 16
			"label":      lbl,
			"icon":       icon_spr,
			"label_rest": 1.0,   # boss label always fully visible
			"icon_rest":  0.0,
			"hover_tint": boss_hover_tint,
			"rest_tint":  Color.WHITE,
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
		var sv: Dictionary      = _get_star_variant(i)
		var base_type:  int     = sv.base_type_idx
		var seed_val:   int     = sv.pixel_seed
		var cool: bool          = STAR_COOL[base_type]
		var exotic_idx: int     = sv.exotic_idx
		var has_binary: bool    = sv.has_binary
		var glow_color: Color   = EXOTIC_GLOW_COLORS[exotic_idx] if exotic_idx >= 0 else STAR_GLOW_COLORS[base_type]

		_spawn_star_body(anchor, display_px, seed_val, cool, exotic_idx, i)

		# Glow halo.
		var glow_node := Node2D.new()
		glow_node.position = anchor
		add_child(glow_node)
		_star_glows.append(glow_node)
		_add_glow_sprite(glow_node, glow_color)

		# Binary companion — half-size, offset left of primary.
		if has_binary:
			var comp_px: float    = display_px * BINARY_STAR_SIZE_RATIO
			var comp_anchor: Vector2 = anchor + BINARY_STAR_OFFSET
			var comp_cool: bool   = not cool  # complement temperature for contrast
			var comp_seed: int    = (seed_val + 31337) % 100000
			_spawn_star_body(comp_anchor, comp_px, comp_seed, comp_cool, -1, i)
			var comp_glow_node := Node2D.new()
			comp_glow_node.position = comp_anchor
			add_child(comp_glow_node)
			_star_glows.append(comp_glow_node)
			var comp_gc: Color = STAR_GLOW_COLORS[0] if comp_cool else STAR_GLOW_COLORS[1]
			_add_glow_sprite(comp_glow_node, comp_gc)

		# Star name label — centered above the star body.
		var star_seed: int = abs(hash("star:%d" % i))
		if has_node("/root/Run"):
			star_seed = abs(hash("star:%d:%d" % [i, get_node("/root/Run").run_seed]))
		var star_name: String = _generate_celestial_name("star", star_seed)
		_spawn_celestial_name_label(anchor, star_name, display_px * 0.5 + 4.0, true)
	_process(0.0)


func _spawn_star_body(anchor: Vector2, display_px: float, seed_val: int, cool: bool, exotic_idx: int, row_i: int) -> void:
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
	_disable_celestial_mouse(star)
	_reset_star_colorrects(star)
	_apply_star_colors(star, cool, exotic_idx)
	star.override_time = true
	_celestial_nodes.append(star)


func _add_glow_sprite(parent: Node2D, gc: Color) -> void:
	var glow_spr := Sprite2D.new()
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
	parent.add_child(glow_spr)


func _build_labels() -> void:
	var ls := LabelSettings.new()
	ls.font         = FONT
	ls.font_size    = 9
	ls.font_color   = Color(0.85, 0.92, 1.0, 0.95)
	ls.outline_size  = 1
	ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
	# Sector header. "<Name> (Sector Patrol X/Y)" where X = current sector
	# (1-indexed) and Y = Run.TOTAL_SECTORS. Name is generated deterministically
	# from the sector seed and cached on sector_map_cache.sector_name; if a
	# stale cache from a prior run is missing the key, regenerate from the
	# cached seed so the header still reads correctly. No silent fallback to
	# "SECTOR N" — the name is required.
	var run = get_node("/root/Run")
	var current_sector: int = run.sectors_cleared + 1
	var total_sectors: int = int(run.TOTAL_SECTORS)
	var sector_name: String = String(run.sector_map_cache.get("sector_name", ""))
	if sector_name == "":
		var SectorNameGen = preload("res://scripts/sector_name_generator.gd")
		var seed_value: int = int(run.sector_map_cache.get("seed", run.run_seed + run.sectors_cleared))
		sector_name = SectorNameGen.generate(seed_value)
		run.sector_map_cache["sector_name"] = sector_name
	var hdr := Label.new()
	hdr.text = "%s (Sector Patrol %d/%d)" % [sector_name, current_sector, total_sectors]
	hdr.label_settings = ls
	hdr.position = Vector2(8, 2)
	hdr.z_index = 10
	hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hdr)
	# Live status row in the header — Hull/Shield/Bounty/Super/MG/2nd. Designer
	# (2026-05-24): "place Hull/Shield/Bounty from manage ship menu where
	# manage ship is, and put manage ship under it." Uses the same bits the
	# Manage Ship modal uses (_ms_build_status_bits) so the two read identically.
	var status_lbl := Label.new()
	status_lbl.text = _ms_build_status_bits_text(run)
	status_lbl.label_settings = ls
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Right-anchored so the status sits at the far-right where MANAGE SHIP used
	# to live. Width 200 covers all bits at font_size 9 without wrapping.
	status_lbl.position = Vector2(272, 2)
	status_lbl.size = Vector2(200, 10)
	status_lbl.z_index = 10
	status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_lbl)
	# Manage Ship button — opens an inspector modal (ship status, loadout,
	# upgrades, stored equipment). Sits on its own CanvasLayer so it isn't
	# eaten by the celestial _disable_celestial_mouse walks above. Moved
	# DOWN to y=14 to sit beneath the status row per designer.
	var btn_layer := CanvasLayer.new()
	btn_layer.name = "ManageShipBtnLayer"
	btn_layer.layer = 6
	add_child(btn_layer)
	var manage_btn := Button.new()
	manage_btn.text = "MANAGE SHIP"
	manage_btn.add_theme_font_override("font", FONT)
	manage_btn.add_theme_font_size_override("font_size", 9)
	manage_btn.custom_minimum_size = Vector2(76, 14)
	manage_btn.position = Vector2(396, 14)
	manage_btn.pressed.connect(_show_manage_ship_modal)
	btn_layer.add_child(manage_btn)


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


func _node_type_name(node_type: int) -> String:
	match node_type:
		int(SectorNode.NodeType.COMBAT):  return "COMBAT"
		int(SectorNode.NodeType.OUTPOST): return "OUTPOST"
		int(SectorNode.NodeType.SIGNAL):  return "SIGNAL"
		int(SectorNode.NodeType.HAZARD):  return "HAZARD"
	return ""


func _get_icon_outline_mat() -> ShaderMaterial:
	if _icon_outline_mat != null:
		return _icon_outline_mat
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tif (c.a < 0.1) {\n\t\tvec2 px = TEXTURE_PIXEL_SIZE;\n\t\tfloat a = texture(TEXTURE, UV + vec2(px.x, 0.0)).a\n\t\t\t+ texture(TEXTURE, UV - vec2(px.x, 0.0)).a\n\t\t\t+ texture(TEXTURE, UV + vec2(0.0, px.y)).a\n\t\t\t+ texture(TEXTURE, UV - vec2(0.0, px.y)).a;\n\t\tif (a > 0.0) { COLOR = vec4(0.0, 0.0, 0.0, 1.0); } else { COLOR = c; }\n\t} else { COLOR = c; }\n}"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_icon_outline_mat = mat
	return mat


func _icon_for_type(node_type: int) -> int:
	match node_type:
		int(SectorNode.NodeType.COMBAT):  return ICON_COMBAT
		int(SectorNode.NodeType.OUTPOST): return ICON_OUTPOST
		int(SectorNode.NodeType.SIGNAL):  return ICON_SIGNAL
		int(SectorNode.NodeType.HAZARD):  return ICON_HAZARD
		int(SectorNode.NodeType.BOSS):    return ICON_BOSS
	return ICON_COMBAT


func _add_hover_label_icon(pos: Vector2, display_px: float, node_type: int, completed: bool) -> void:
	# Node type label — appears directly below the icon on hover, green.
	var ls := LabelSettings.new()
	ls.font = FONT; ls.font_size = 7
	ls.font_color    = COLOR_NODE_GREEN
	ls.outline_size  = 1
	ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
	var lbl := Label.new()
	lbl.text                  = _node_type_name(node_type)
	lbl.label_settings        = ls
	lbl.custom_minimum_size.x = 48.0
	lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	# Icon half-size at scale 0.5 of 32px = 8px; sit label 2px below icon bottom.
	lbl.position       = Vector2(pos.x - 24.0, pos.y + 10.0)
	lbl.z_index        = 10
	lbl.modulate.a     = 0.0
	lbl.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var at := AtlasTexture.new()
	at.atlas  = ICON_STRIP
	at.region = Rect2(_icon_for_type(node_type) * 32, 0, 32, 32)
	var icon_spr := Sprite2D.new()
	icon_spr.texture  = at
	icon_spr.position = pos
	icon_spr.scale    = Vector2(0.5, 0.5)
	icon_spr.z_index  = 5
	icon_spr.material = _get_icon_outline_mat()
	# Designer: POI icons start 0% opacity and reveal on mouseover. Completed
	# POIs keep a soft green resting alpha (0.6) so the player can see what's
	# been done; uncompleted rest at 0.0.
	var icon_rest: float = 0.6 if completed else 0.0
	var rest_tint: Color = COLOR_NODE_GREEN if completed else Color.WHITE
	icon_spr.modulate = Color(rest_tint.r, rest_tint.g, rest_tint.b, icon_rest)
	add_child(icon_spr)
	# Hover radius matches the click radius (14) — slightly larger than the
	# previous display_px*0.5=16 baseline, but consistent with click-to-launch.
	_planet_hovers.append({
		"center":     pos,
		"radius":     14.0,
		"label":      lbl,
		"icon":       icon_spr,
		"label_rest": 0.0,
		"icon_rest":  icon_rest,
		"hover_tint": COLOR_NODE_GREEN,
		"rest_tint":  rest_tint,
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


func _apply_star_colors(root: Node, cool: bool, exotic_idx: int = -1) -> void:
	for child in root.get_children():
		if child is ColorRect and child.material is ShaderMaterial:
			child.material = (child.material as ShaderMaterial).duplicate()
			var mat: ShaderMaterial = child.material
			match String(child.name):
				"Star":
					mat.set_shader_parameter("colors", _star_surface_palette(cool, exotic_idx))
				"Blobs":
					mat.set_shader_parameter("colors", _star_blob_palette(cool, exotic_idx))
				"StarFlares":
					mat.set_shader_parameter("colors", _star_flare_palette(cool, exotic_idx))
		_apply_star_colors(child, cool, exotic_idx)


func _star_surface_palette(cool: bool, exotic_idx: int) -> PackedColorArray:
	match exotic_idx:
		0: return PackedColorArray([  # purple
			Color(0.90,0.80,1.00,1), Color(0.65,0.25,0.95,1),
			Color(0.38,0.08,0.65,1), Color(0.18,0.03,0.30,1)])
		1: return PackedColorArray([  # green
			Color(0.80,1.00,0.82,1), Color(0.25,0.88,0.40,1),
			Color(0.05,0.55,0.22,1), Color(0.02,0.25,0.12,1)])
		2: return PackedColorArray([  # pink
			Color(1.00,0.85,0.90,1), Color(1.00,0.35,0.60,1),
			Color(0.75,0.10,0.35,1), Color(0.40,0.04,0.18,1)])
	return PackedColorArray([
		Color(0.96,1.00,0.91,1), Color(0.47,0.84,0.76,1),
		Color(0.11,0.57,0.65,1), Color(0.01,0.24,0.37,1),
	]) if cool else PackedColorArray([
		Color(0.96,1.00,0.91,1), Color(1.00,0.85,0.20,1),
		Color(1.00,0.51,0.23,1), Color(0.49,0.10,0.10,1)])


func _star_blob_palette(cool: bool, exotic_idx: int) -> PackedColorArray:
	match exotic_idx:
		0: return PackedColorArray([Color(0.65,0.25,0.95,1)])
		1: return PackedColorArray([Color(0.25,0.88,0.40,1)])
		2: return PackedColorArray([Color(1.00,0.35,0.60,1)])
	return PackedColorArray([Color(0.47,0.84,0.76,1)]) if cool else \
		PackedColorArray([Color(1.00,0.85,0.20,1)])


func _star_flare_palette(cool: bool, exotic_idx: int) -> PackedColorArray:
	match exotic_idx:
		0: return PackedColorArray([Color(0.65,0.25,0.95,1), Color(0.90,0.80,1.00,1)])
		1: return PackedColorArray([Color(0.25,0.88,0.40,1), Color(0.80,1.00,0.82,1)])
		2: return PackedColorArray([Color(1.00,0.35,0.60,1), Color(1.00,0.85,0.90,1)])
	return PackedColorArray([
		Color(0.47,0.84,0.76,1), Color(0.96,1.00,0.91,1),
	]) if cool else PackedColorArray([
		Color(1.00,0.85,0.20,1), Color(0.96,1.00,0.91,1)])


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
# Change 4: Celestial name generator — seeded, deterministic per node
# ---------------------------------------------------------------------------

const _CN_GREEK := ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta",
					 "Eta", "Theta", "Iota", "Kappa", "Lambda", "Mu",
					 "Nu", "Xi", "Omicron", "Pi", "Rho", "Sigma",
					 "Tau", "Upsilon", "Phi", "Chi", "Psi", "Omega"]
const _CN_CONSTELLATIONS := ["Centauri", "Eridani", "Cephei", "Pavonis",
							 "Hydrae", "Draconis", "Cygni", "Orionis",
							 "Lyrae", "Aquilae", "Velorum", "Carinae",
							 "Lupi", "Scorpii", "Persei", "Tauri"]
const _CN_ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]
const _CN_SCI_FI_PREFIXES := ["Void", "Iron", "Cinder", "Pale", "Deep",
							  "Ashen", "Storm", "Null", "Ember", "Drift"]
const _CN_SCI_FI_NAMES := ["Station", "Reach", "Drift", "Crossing", "Terminus",
						   "Anchorage", "Bastion", "Hollow", "Shard", "Gate"]
const _CN_BELT_NAMES := ["Kappa", "Delta", "Zeta", "Rho", "Sigma", "Nu", "Tau", "Pi"]

# POI name word banks — one per node-type family.
const _PN_COMBAT_PREFIXES  := ["Contact", "Skirmish at", "Interdiction Zone", "Strike at",
								"Engagement", "Patrol", "Intercept", "Ambush at"]
const _PN_COMBAT_DESIGNATORS := ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot",
								  "Keth", "Vorn", "Ash", "Ryn", "Cael", "Dusk", "Haze"]
const _PN_COMBAT_SUFFIXES  := ["-1", "-2", "-3", "-4", "-5", "-7", "-9", "-12"]
const _PN_STATION_PREFIX   := ["Relay Station", "Waypoint", "Depot", "Anchorage", "Outpost",
								"Waystation", "Beacon", "Checkpoint"]
const _PN_STATION_SUFFIX   := ["Sigma", "Alpha", "Crest", "Veil", "Reach", "Ridge", "Spur", "Gate"]
const _PN_SIGNAL_PREFIX    := ["Anomaly", "Signal", "Ghost Trace", "Echo", "Pulse", "Drift Mark"]
const _PN_SIGNAL_SUFFIX    := ["Veil", "Wraith", "Null", "Shard", "Fade", "Quiet"]
const _PN_HAZARD_ASTEROID  := ["Debris Field", "Rock Field", "Scatter Zone", "Fragment Belt",
								"Dust Belt", "Shard Cloud"]
const _PN_HAZARD_MINE      := ["Mine Zone", "Exclusion Zone", "Mine Field", "Danger Zone",
								"Interdiction Field"]
const _PN_HAZARD_SUFFIX    := ["Kappa", "Alpha", "Delta", "Sigma", "Tau", "Mu", "Zeta"]

# Generate a deterministic celestial name seeded by the node's position hash.
# type: "star", "planet", "asteroid", "cluster"
func _generate_celestial_name(type: String, seed_val: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(seed_val) % 0x7FFFFFFF
	match type:
		"star":
			var style: int = rng.randi() % 3
			match style:
				0:
					return "HD-%d" % (rng.randi_range(1000, 9999))
				1:
					return "KIC-%d" % (rng.randi_range(1000, 9999))
				_:
					var g: String = _CN_GREEK[rng.randi() % _CN_GREEK.size()]
					var c: String = _CN_CONSTELLATIONS[rng.randi() % _CN_CONSTELLATIONS.size()]
					return "%s %s" % [g, c]
		"planet":
			var style: int = rng.randi() % 2
			match style:
				0:
					# "Proxima III" style — use a constellation fragment + roman numeral
					var c: String = _CN_CONSTELLATIONS[rng.randi() % _CN_CONSTELLATIONS.size()]
					# Strip trailing "i" for pronounceability (Centauri→Centaur is too far; just use as-is)
					var r: String = _CN_ROMAN[rng.randi() % mini(6, _CN_ROMAN.size())]
					return "%s %s" % [c, r]
				_:
					var p: String = _CN_SCI_FI_PREFIXES[rng.randi() % _CN_SCI_FI_PREFIXES.size()]
					var n: String = _CN_SCI_FI_NAMES[rng.randi() % _CN_SCI_FI_NAMES.size()]
					return "%s %s" % [p, n]
		"asteroid":
			var style: int = rng.randi() % 3
			match style:
				0:
					return "NGC-%d" % (rng.randi_range(100, 999))
				1:
					var belt: String = _CN_BELT_NAMES[rng.randi() % _CN_BELT_NAMES.size()]
					return "Rock %d-%s" % [rng.randi_range(1, 99), belt]
				_:
					return "Belt Shard %d" % rng.randi_range(1, 99)
		"cluster":
			var style: int = rng.randi() % 2
			match style:
				0:
					return "AST-%d" % (rng.randi_range(1000, 9999))
				_:
					var belt: String = _CN_BELT_NAMES[rng.randi() % _CN_BELT_NAMES.size()]
					return "Field %s-%d" % [belt, rng.randi_range(1, 9)]
	return "UNK-%d" % (abs(seed_val) % 9999)


# Generate a short deterministic name for a POI node.
# node_type matches SectorNode.NodeType ints. hazard_subtype is "" unless HAZARD.
func _generate_poi_name(node_type: int, seed_val: int, hazard_subtype: String = "") -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(seed_val) % 0x7FFFFFFF
	match node_type:
		int(SectorNode.NodeType.COMBAT):
			var style: int = rng.randi() % 3
			match style:
				0:
					# "Contact Keth-3" / "Contact Vorn-7"
					var p: String = _PN_COMBAT_PREFIXES[rng.randi() % _PN_COMBAT_PREFIXES.size()]
					var d: String = _PN_COMBAT_DESIGNATORS[rng.randi() % _PN_COMBAT_DESIGNATORS.size()]
					var s: String = _PN_COMBAT_SUFFIXES[rng.randi() % _PN_COMBAT_SUFFIXES.size()]
					return "%s %s%s" % [p, d, s]
				1:
					# "HD-827" style callsign
					return "HD-%d" % rng.randi_range(100, 999)
				_:
					# "Strike at Alpha-4"
					var p: String = _PN_COMBAT_PREFIXES[rng.randi() % _PN_COMBAT_PREFIXES.size()]
					var g: String = _CN_GREEK[rng.randi() % _CN_GREEK.size()]
					return "%s %s" % [p, g]
		int(SectorNode.NodeType.OUTPOST):
			var style: int = rng.randi() % 2
			match style:
				0:
					# "Relay Station 7" / "Depot Crest-4"
					var p: String = _PN_STATION_PREFIX[rng.randi() % _PN_STATION_PREFIX.size()]
					var n: int = rng.randi_range(1, 12)
					return "%s %d" % [p, n]
				_:
					# "Waypoint Sigma" / "Anchorage Veil"
					var p: String = _PN_STATION_PREFIX[rng.randi() % _PN_STATION_PREFIX.size()]
					var s: String = _PN_STATION_SUFFIX[rng.randi() % _PN_STATION_SUFFIX.size()]
					return "%s %s" % [p, s]
		int(SectorNode.NodeType.SIGNAL):
			var style: int = rng.randi() % 2
			match style:
				0:
					# "Anomaly 94-K" style
					var p: String = _PN_SIGNAL_PREFIX[rng.randi() % _PN_SIGNAL_PREFIX.size()]
					var n: int = rng.randi_range(1, 99)
					var g: String = _CN_GREEK[rng.randi() % _CN_GREEK.size()].left(1)
					return "%s %d-%s" % [p, n, g]
				_:
					# "Signal Veil" / "Ghost Trace Wraith"
					var p: String = _PN_SIGNAL_PREFIX[rng.randi() % _PN_SIGNAL_PREFIX.size()]
					var s: String = _PN_SIGNAL_SUFFIX[rng.randi() % _PN_SIGNAL_SUFFIX.size()]
					return "%s %s" % [p, s]
		int(SectorNode.NodeType.HAZARD):
			if hazard_subtype == "minefield":
				var p: String = _PN_HAZARD_MINE[rng.randi() % _PN_HAZARD_MINE.size()]
				var s: String = _PN_HAZARD_SUFFIX[rng.randi() % _PN_HAZARD_SUFFIX.size()]
				return "%s %s" % [p, s]
			else:
				# asteroid_field or generic
				var p: String = _PN_HAZARD_ASTEROID[rng.randi() % _PN_HAZARD_ASTEROID.size()]
				var s: String = _PN_HAZARD_SUFFIX[rng.randi() % _PN_HAZARD_SUFFIX.size()]
				return "%s %s" % [p, s]
	return ""


# Spawn a small name label near a celestial body. Low opacity so it reads as
# ambient chart data rather than UI chrome. font_size 7, alpha 0.35.
# center=true: horizontally centered above pos (for stars).
func _spawn_celestial_name_label(pos: Vector2, name_text: String, y_offset: float = 8.0, center: bool = false) -> void:
	var ls := LabelSettings.new()
	ls.font = FONT
	ls.font_size = 7
	ls.font_color = Color(0.75, 0.85, 1.0, 1.0)
	ls.outline_size = 1
	ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
	var lbl := Label.new()
	lbl.text = name_text
	lbl.label_settings = ls
	lbl.modulate.a = 0.35
	if center:
		lbl.custom_minimum_size.x = 64.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.position = Vector2(pos.x - 32.0, pos.y - y_offset - 8.0)
	else:
		lbl.position = Vector2(pos.x - 24.0, pos.y + y_offset)
	lbl.z_index = 8
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)


# Spawn a tiny POI name label below the POI icon position.
# Distinct from _spawn_celestial_name_label: slightly smaller (font_size 6)
# and uses a warmer tint so it reads as a designation rather than a star-chart
# annotation. Alpha kept at 0.45 — subtle but readable on hover.
func _spawn_poi_name_label(pos: Vector2, name_text: String) -> void:
	if name_text == "":
		return
	var ls := LabelSettings.new()
	ls.font = FONT
	ls.font_size = 6
	ls.font_color = Color(0.80, 0.90, 0.75, 1.0)
	ls.outline_size = 1
	ls.outline_color = Color(0.0, 0.0, 0.0, 0.8)
	var lbl := Label.new()
	lbl.text = name_text
	lbl.label_settings = ls
	lbl.modulate.a = 0.45
	# Sit the label 11px below centre — clears the 16px icon footprint (0.5
	# scale of 32px atlas = 16px half-height) without overlapping the
	# celestial-body name label that appears above it.
	lbl.position = Vector2(pos.x - 24.0, pos.y + 11.0)
	lbl.z_index = 8
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)


# Override the asteroid shader's `colors` palette with a 3-tone derived from
# the row's star color (dark / mid / light). PlanetKit's Asteroid shader uses
# a fixed gray-blue palette by default; modulate-tinting that palette reads
# muddy because gray × red = brown. Setting the shader uniform directly makes
# the rocks render in the family color the surrounding decoration pixels use.
# Caller is expected to have called _duplicate_materials(root) first so this
# write is per-instance, not shared.
func _apply_row_tint_to_asteroid(root: Node, row_idx: int) -> void:
	var idx: int = clampi(row_idx, 0, STAR_GLOW_COLORS.size() - 1)
	# Use the per-run randomized star color so asteroid tints match the star on display.
	var sv: Dictionary = _get_star_variant(idx)
	var star: Color = EXOTIC_GLOW_COLORS[sv.exotic_idx] if sv.exotic_idx >= 0 else STAR_GLOW_COLORS[sv.base_type_idx]
	# Pull the base color partway toward white so the lit face still reads as
	# a rock surface (not a flat saturated blob). The mid tone is the star
	# color itself, dark for shadow, light for highlight.
	var c_light: Color = Color.WHITE.lerp(star, 0.45)
	var c_mid: Color   = Color.WHITE.lerp(star, 0.75).darkened(0.10)
	var c_dark: Color  = star.darkened(0.55)
	c_light.a = 1.0; c_mid.a = 1.0; c_dark.a = 1.0
	_set_asteroid_palette(root, PackedColorArray([c_light, c_mid, c_dark]))


# Change 3: disable the 1-px black outline baked into the Asteroid shader.
# Walk the subtree and set draw_outline=false on every ShaderMaterial that
# exposes it. Must be called after _duplicate_materials so we don't pollute
# the shared shader instance.
func _disable_asteroid_outlines(root: Node) -> void:
	for child in root.get_children():
		if child is ColorRect and child.material is ShaderMaterial:
			var mat: ShaderMaterial = child.material
			if mat.shader != null and mat.get_shader_parameter("draw_outline") != null:
				mat.set_shader_parameter("draw_outline", false)
		_disable_asteroid_outlines(child)


func _set_asteroid_palette(root: Node, palette: PackedColorArray) -> void:
	for child in root.get_children():
		if child is ColorRect and child.material is ShaderMaterial:
			var mat: ShaderMaterial = child.material
			# Only touch shaders that actually expose `colors` — guard so a
			# future child ColorRect with an unrelated shader doesn't crash.
			if mat.shader != null and mat.get_shader_parameter("colors") != null:
				mat.set_shader_parameter("colors", palette)
		_set_asteroid_palette(child, palette)


# Recursively ignore mouse on every Control in a celestial subtree. Planets,
# stars, and asteroids are Control-rooted scenes — their default mouse_filter
# is STOP, which silently eats clicks on POI/boss hot-spots and explains why
# POI launches "don't work." Walk the tree and force IGNORE so our
# _unhandled_input click handler actually receives the event.
func _disable_celestial_mouse(root: Node) -> void:
	if root is Control:
		(root as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in root.get_children():
		_disable_celestial_mouse(child)


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
	# Designer: line-progress overlay removed; boss radial ring replaces it.
	# For each boss, draw a segmented clockwise arc — total segments = POI
	# count in that row, filled count = completed POIs. Starts at 12 o'clock
	# (-PI/2), progresses clockwise.
	var run = get_node("/root/Run")
	var rows: Array = run.sector_map_cache.get("rows", [])
	const RING_RADIUS: float       = 13.0   # halved from 26 (Change 1)
	const RING_WIDTH: float        = 1.0    # halved from 2 (Change 1)
	const RING_ARC_STEPS: int      = 32     # smooth arc steps for full circle
	var ring_filled: Color   = PROGRESS_COLOR
	var ring_unfilled: Color = Color(0.3, 0.3, 0.3, 0.5)
	for i in _boss_entries.size():
		if i >= rows.size():
			continue
		var b: Dictionary = _boss_entries[i]
		var center: Vector2 = b.pos
		var pois: Array = rows[i].pois
		var total: int = pois.size()
		if total <= 0:
			continue
		var done: int = 0
		for poi in pois:
			if poi.completed:
				done += 1
		# Change 2: smooth continuous arc instead of per-POI segments.
		# Filled arc from 12-o'clock to done/total fraction, then unfilled remainder.
		var fill_frac: float = float(done) / float(total)
		var start_angle: float = -PI * 0.5
		var fill_end: float = start_angle + fill_frac * TAU
		var filled_steps: int = maxi(1, int(RING_ARC_STEPS * fill_frac))
		var unfilled_steps: int = maxi(1, int(RING_ARC_STEPS * (1.0 - fill_frac)))
		if done > 0:
			draw_arc(center, RING_RADIUS, start_angle, fill_end, filled_steps, ring_filled, RING_WIDTH)
		if done < total:
			draw_arc(center, RING_RADIUS, fill_end, start_angle + TAU, unfilled_steps, ring_unfilled, RING_WIDTH)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# Manage-Ship modal takes priority on Esc — close it without opening
		# the options overlay. Falls through to options when modal absent.
		if get_node_or_null(_MS_MODAL_NAME) != null:
			_close_manage_ship_modal()
			get_viewport().set_input_as_handled()
			return
		# Esc opens the options overlay; never ends the run.
		var OptionsOverlay = load("res://scripts/ui/options_overlay.gd")
		if OptionsOverlay:
			OptionsOverlay.open(self)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Block POI/boss clicks when the Manage Ship modal is open. The modal's
		# dim ColorRect already absorbs the event via MOUSE_FILTER_STOP, but
		# Node2D._unhandled_input can still fire if the Control tree doesn't
		# consume it first — belt-and-suspenders so a buried POI never fires.
		if get_node_or_null(_MS_MODAL_NAME) != null:
			return
		var mp: Vector2 = get_local_mouse_position()
		# Try POIs first (smaller hit-radius, more numerous).
		for hit in _poi_hits:
			if mp.distance_to(hit.pos) <= hit.radius:
				_on_poi_clicked(String(hit.id))
				return
		# Then bosses.
		for b in _boss_entries:
			if mp.distance_to(b.pos) <= 8.0:   # Change 1: halved from 16
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
	# Copy per-POI modifiers into Run.sector_modifiers so director.gd /
	# player.gd pick them up at combat start. Empty array == no modifier.
	run.sector_modifiers = (poi.get("modifiers", []) as Array).duplicate()
	# Find this POI's row so the descriptor inherits the right star color.
	var rows: Array = run.sector_map_cache.get("rows", [])
	var poi_row_idx: int = 0
	for r_idx in rows.size():
		for p in rows[r_idx].pois:
			if String(p.id) == node_id:
				poi_row_idx = r_idx
				break
	# Stellar descriptor — combat/outpost/signal/hazard backdrops read this so
	# the scene visually echoes the POI the player clicked.
	run.current_stellar = _compute_poi_stellar(poi, poi_row_idx)
	match int(poi.node_type):
		int(SectorNode.NodeType.COMBAT):
			SceneTransition.change_scene(get_tree(), COMBAT_SCENE)
		int(SectorNode.NodeType.OUTPOST):
			# Designer ask (Cody 2026-05-24): block outpost entry with 0
			# bounty — show a Yes/Cancel modal so the player doesn't burn
			# the node by accident. Visiting is still allowed (refill
			# services can be free), so we don't hard-stop the launch.
			if int(run.bounty) <= 0:
				_show_no_bounty_modal()
			else:
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
	# Bosses currently carry no modifiers (boss entry's "modifiers" is []),
	# but copy through for forward-compat with future boss-modifier wiring.
	run.sector_modifiers = (boss.get("modifiers", []) as Array).duplicate()
	# Boss arenas don't have a planet/asteroid of their own — just tint with
	# the row's star color so the fight still feels rooted on the chosen line.
	run.current_stellar = _compute_boss_stellar(row_idx)
	run.forced_boss_scene = String(boss.get("boss_scene", ""))
	SceneTransition.change_scene(get_tree(), BOSS_SCENE)


# ---------------------------------------------------------------------------
# Zero-bounty outpost guard modal (Cody 2026-05-24)
# ---------------------------------------------------------------------------
# Renders an inline confirmation panel on a dedicated CanvasLayer so it sits
# above the parallax content. "Yes" enters the outpost (refills can be free).
# "Cancel" tears the modal down and returns the player to the map.

const _NB_MODAL_NAME := "NoBountyModal"

func _show_no_bounty_modal() -> void:
	if get_node_or_null(_NB_MODAL_NAME) != null:
		return  # already open
	var cl := CanvasLayer.new()
	cl.name = _NB_MODAL_NAME
	cl.layer = 50
	add_child(cl)
	# Dim backdrop blocks clicks on POIs underneath.
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	cl.add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(120, 92)
	panel.custom_minimum_size = Vector2(240, 86)
	cl.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "NO BOUNTY"
	var title_ls := LabelSettings.new()
	title_ls.font = FONT
	title_ls.font_size = 11
	title_ls.font_color = Color(1.0, 0.85, 0.30, 1.0)
	title_ls.outline_size = 1
	title_ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
	title.label_settings = title_ls
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var body := Label.new()
	body.text = "You have no bounty to spend.\nVisit the outpost anyway?"
	var body_ls := LabelSettings.new()
	body_ls.font = FONT
	body_ls.font_size = 9
	body_ls.font_color = Color(0.85, 0.92, 1.0, 1.0)
	body_ls.outline_size = 1
	body_ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
	body.label_settings = body_ls
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	var yes_btn := Button.new()
	yes_btn.text = "Yes"
	yes_btn.custom_minimum_size = Vector2(64, 16)
	yes_btn.pressed.connect(func():
		# current_node_id / current_node_type were set in _on_poi_clicked
		# before this modal opened — just transition.
		_close_no_bounty_modal()
		SceneTransition.change_scene(get_tree(), OUTPOST_SCENE)
	)
	row.add_child(yes_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(64, 16)
	cancel_btn.pressed.connect(func():
		# Roll back the run.current_node_* writes so the player can retry
		# the click cleanly (or pick a different node).
		var run = get_node("/root/Run")
		run.current_node_id = ""
		run.current_node_type = -1
		run.current_hazard_subtype = ""
		_close_no_bounty_modal()
	)
	row.add_child(cancel_btn)


func _close_no_bounty_modal() -> void:
	var m := get_node_or_null(_NB_MODAL_NAME)
	if m != null:
		m.queue_free()


# ---------------------------------------------------------------------------
# Manage Ship modal — full loadout inspector + equip-swap UI
# ---------------------------------------------------------------------------
# Reads Run state (loadout_snapshot, weapon_storage, inventory, hull/shield/
# super/ammo balances, mk levels) and renders a centered modal on a high
# CanvasLayer. Equip buttons reuse Run.equip_part so the displacement rules
# match the outpost path exactly. Modal stays open across multiple swaps;
# only Close (or Esc) tears it down. Dim ColorRect blocks underlying POI
# clicks; _unhandled_input has an additional guard for Node2D ordering.

const _MS_MODAL_NAME := "ManageShipModal"
const _MS_PANEL_SIZE := Vector2(420.0, 220.0)
const _MS_PANEL_ORIGIN := Vector2((480.0 - 420.0) * 0.5, (270.0 - 220.0) * 0.5)

# Slot ordering for the "Equipped Loadout" section. Only the four
# player-swappable slots are listed — wings / tail / engine / shield are
# fixed by the chassis and never swap mid-run.
const _MS_LOADOUT_SLOTS := [
	{"slot": SlotTypes.SlotType.CANNON,         "label": "PRIMARY"},
	{"slot": SlotTypes.SlotType.HARDPOINT_WING, "label": "SECONDARY"},
	{"slot": SlotTypes.SlotType.DEVICE_BAY_1,   "label": "SUPER"},
]

const _MS_UPGRADE_KEYS := [
	{"key": "hull_mk",            "name": "Hull"},
	{"key": "armor_mk",           "name": "Armor"},
	{"key": "thrusters_mk",       "name": "Thrusters"},
	{"key": "self_repair_mk",     "name": "Self-Repair"},
	{"key": "shield_cap_mk",      "name": "Shield Cap"},
	{"key": "shield_recharge_mk", "name": "Shield Regen"},
]


func _show_manage_ship_modal() -> void:
	if get_node_or_null(_MS_MODAL_NAME) != null:
		return
	var cl := CanvasLayer.new()
	cl.name = _MS_MODAL_NAME
	cl.layer = 50
	add_child(cl)
	# Dim backdrop — blocks POI clicks underneath via MOUSE_FILTER_STOP.
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	cl.add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = _MS_PANEL_ORIGIN
	panel.custom_minimum_size = _MS_PANEL_SIZE
	panel.size = _MS_PANEL_SIZE
	# Increase panel opacity by 15% over the Godot default (~0.70 → 0.85).
	var ms_sb := StyleBoxFlat.new()
	ms_sb.bg_color = Color(0.12, 0.12, 0.16, 0.85)
	ms_sb.corner_radius_top_left = 3
	ms_sb.corner_radius_top_right = 3
	ms_sb.corner_radius_bottom_left = 3
	ms_sb.corner_radius_bottom_right = 3
	ms_sb.content_margin_left = 6
	ms_sb.content_margin_right = 6
	ms_sb.content_margin_top = 4
	ms_sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", ms_sb)
	cl.add_child(panel)
	_render_manage_ship_contents(panel)


func _close_manage_ship_modal() -> void:
	var m := get_node_or_null(_MS_MODAL_NAME)
	if m != null:
		m.queue_free()


# Rebuilds the modal panel contents from scratch — called after every
# equip-swap so loadout + storage stay in sync with Run.
func _render_manage_ship_contents(panel: PanelContainer) -> void:
	for child in panel.get_children():
		child.queue_free()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)
	# Title row.
	var title := Label.new()
	title.text = "MANAGE SHIP"
	title.label_settings = _ms_label_settings(11, Color(0.95, 0.92, 0.55, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	if not has_node("/root/Run"):
		var err := Label.new()
		err.text = "Run state unavailable."
		err.label_settings = _ms_label_settings(9, Color(1.0, 0.5, 0.5, 1.0))
		vbox.add_child(err)
		return
	var run = get_node("/root/Run")
	_ms_add_status_section(vbox, run)
	_ms_add_separator(vbox)
	_ms_add_loadout_section(vbox, run, panel)
	_ms_add_separator(vbox)
	_ms_add_upgrades_section(vbox, run)
	_ms_add_separator(vbox)
	_ms_add_storage_section(vbox, run, panel)
	_ms_add_separator(vbox)
	# Close.
	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(close_row)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.add_theme_font_override("font", FONT)
	close_btn.add_theme_font_size_override("font_size", 9)
	close_btn.custom_minimum_size = Vector2(72, 14)
	close_btn.pressed.connect(_close_manage_ship_modal)
	close_row.add_child(close_btn)


func _ms_label_settings(size: int, color: Color) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = FONT
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = 1
	ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
	return ls


func _ms_add_separator(vbox: VBoxContainer) -> void:
	var sep := ColorRect.new()
	sep.color = Color(0.30, 0.38, 0.55, 0.4)
	sep.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(sep)


func _ms_add_status_section(vbox: VBoxContainer, run) -> void:
	var lbl := Label.new()
	lbl.text = _ms_build_status_bits_text(run)
	lbl.label_settings = _ms_label_settings(9, Color(0.85, 0.92, 1.0, 1.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)


# Shared status string used by both the Manage Ship modal and the sector map
# header row, so the two never drift apart. Designer wants Hull/Shield/Bounty
# (+ Super + ammo when present) visible at a glance without opening the modal.
func _ms_build_status_bits_text(run) -> String:
	var bits: Array = []
	bits.append("Hull %d/%d" % [int(run.current_hull), int(run.max_hull)])
	bits.append("Shield %d/%d" % [int(run.current_shield), int(run.max_shield)])
	bits.append("Bounty %d" % int(run.bounty))
	bits.append("Super %d/%d" % [int(run.super_charges), int(run.max_super_charges)])
	if int(run.ammo) >= 0:
		bits.append("MG %d" % int(run.ammo))
	if int(run.secondary_ammo) >= 0 and int(run.secondary_ammo_max) > 0:
		bits.append("2nd %d/%d" % [int(run.secondary_ammo), int(run.secondary_ammo_max)])
	return "  ".join(bits)


func _ms_add_loadout_section(vbox: VBoxContainer, run, panel: PanelContainer) -> void:
	for entry in _MS_LOADOUT_SLOTS:
		var slot: int = int(entry["slot"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		vbox.add_child(row)
		var name_lbl := Label.new()
		name_lbl.text = String(entry["label"])
		name_lbl.label_settings = _ms_label_settings(9, Color(0.65, 0.78, 0.95, 1.0))
		name_lbl.custom_minimum_size = Vector2(70, 0)
		row.add_child(name_lbl)
		var equipped = run.loadout_snapshot.get(slot, null)
		# Name + description stacked so the player sees what the equipped part
		# actually does without leaving the modal. Description is dim/gray so the
		# name remains the dominant read.
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		row.add_child(info)
		var part_lbl := Label.new()
		if equipped == null:
			part_lbl.text = "— (empty)"
			part_lbl.label_settings = _ms_label_settings(9, Color(0.55, 0.60, 0.70, 1.0))
		else:
			part_lbl.text = _ms_part_name(equipped)
			part_lbl.label_settings = _ms_label_settings(9, Color(0.95, 0.97, 1.0, 1.0))
		info.add_child(part_lbl)
		var desc_text: String = _ms_part_description(equipped)
		if desc_text != "":
			var desc_lbl := Label.new()
			desc_lbl.text = desc_text
			desc_lbl.label_settings = _ms_label_settings(8, Color(0.65, 0.72, 0.82, 1.0))
			desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc_lbl.custom_minimum_size = Vector2(_MS_PANEL_SIZE.x - 100.0, 0)
			info.add_child(desc_lbl)


func _ms_part_name(part) -> String:
	if part == null:
		return "—"
	var nm: String = String(part.get("display_name")) if "display_name" in part else "Part"
	var mk: int = int(part.get("mark")) if "mark" in part else 0
	if mk > 0:
		return "Mk.%d %s" % [mk, nm]
	return nm


# Pull the part's description line for the modal sub-label. Returns "" when
# absent so the caller can skip the row entirely instead of rendering an
# empty Label.
func _ms_part_description(part) -> String:
	if part == null:
		return ""
	if "description" in part:
		return String(part.get("description"))
	return ""


func _ms_add_upgrades_section(vbox: VBoxContainer, run) -> void:
	var parts: Array = []
	for u in _MS_UPGRADE_KEYS:
		var key: String = String(u["key"])
		var lvl: int = int(run.get(key))
		if lvl > 0:
			parts.append("%s Mk %d" % [u["name"], lvl])
	var lbl := Label.new()
	if parts.is_empty():
		lbl.text = "Upgrades: none"
		lbl.label_settings = _ms_label_settings(9, Color(0.55, 0.60, 0.70, 1.0))
	else:
		lbl.text = "Upgrades: " + ", ".join(parts)
		lbl.label_settings = _ms_label_settings(9, Color(0.85, 0.92, 1.0, 1.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(_MS_PANEL_SIZE.x - 16.0, 0)
	vbox.add_child(lbl)


func _ms_add_storage_section(vbox: VBoxContainer, run, panel: PanelContainer) -> void:
	var hdr := Label.new()
	hdr.text = "STORED EQUIPMENT"
	hdr.label_settings = _ms_label_settings(9, Color(0.65, 0.78, 0.95, 1.0))
	vbox.add_child(hdr)
	# Both arrays are valid sources of swappable parts. weapon_storage holds
	# displaced weapons from outpost / modal swaps; inventory is Junk Trader
	# cargo. Keep them distinct in the model — we record which array each row
	# came from so equip removes from the right one.
	var rows_added: int = 0
	for i in range(run.weapon_storage.size()):
		_ms_add_storage_row(vbox, panel, run.weapon_storage[i], i, "weapon_storage")
		rows_added += 1
	for i in range(run.inventory.size()):
		_ms_add_storage_row(vbox, panel, run.inventory[i], i, "inventory")
		rows_added += 1
	if rows_added == 0:
		var empty := Label.new()
		empty.text = "  (no carried equipment)"
		empty.label_settings = _ms_label_settings(9, Color(0.55, 0.60, 0.70, 1.0))
		vbox.add_child(empty)


func _ms_add_storage_row(vbox: VBoxContainer, panel: PanelContainer, part, idx: int, source: String) -> void:
	if part == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vbox.add_child(row)
	# Stack name + description so the player can see what each stored part
	# does at a glance, mirroring the loadout section above.
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	info.custom_minimum_size = Vector2(180, 0)
	row.add_child(info)
	var name_lbl := Label.new()
	name_lbl.text = _ms_part_name(part)
	name_lbl.label_settings = _ms_label_settings(9, Color(0.95, 0.97, 1.0, 1.0))
	info.add_child(name_lbl)
	var desc_text: String = _ms_part_description(part)
	if desc_text != "":
		var desc_lbl := Label.new()
		desc_lbl.text = desc_text
		desc_lbl.label_settings = _ms_label_settings(8, Color(0.65, 0.72, 0.82, 1.0))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(180, 0)
		info.add_child(desc_lbl)
	var slot_lbl := Label.new()
	slot_lbl.text = SlotTypes.slot_name(int(part.slot_type))
	slot_lbl.label_settings = _ms_label_settings(8, Color(0.65, 0.78, 0.95, 1.0))
	slot_lbl.custom_minimum_size = Vector2(120, 0)
	row.add_child(slot_lbl)
	var equip_btn := Button.new()
	equip_btn.text = "Equip"
	equip_btn.add_theme_font_override("font", FONT)
	equip_btn.add_theme_font_size_override("font_size", 8)
	equip_btn.custom_minimum_size = Vector2(48, 14)
	equip_btn.pressed.connect(_ms_on_equip_stored.bind(idx, source, panel))
	row.add_child(equip_btn)


func _ms_on_equip_stored(idx: int, source: String, panel: PanelContainer) -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	var arr: Array
	match source:
		"weapon_storage": arr = run.weapon_storage
		"inventory":      arr = run.inventory
		_: return
	if idx < 0 or idx >= arr.size():
		return
	var picked = arr[idx]
	arr.remove_at(idx)
	# Run.equip_part displaces the currently-equipped same-slot part into
	# weapon_storage — do NOT manually push the previous part here.
	run.equip_part(picked)
	# Rebuild the modal so loadout + storage rows reflect the new state.
	_render_manage_ship_contents(panel)

