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
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const SectorNode      = preload("res://scripts/systems/sector_node.gd")
const SlotTypes       = preload("res://scripts/weapons/SlotTypes.gd")
const STAR_SCENE      = preload("res://Planets/Star/Star.tscn")
const PLANET_SCENES   := [
	"res://Planets/LavaWorld/LavaWorld.tscn",
	"res://Planets/DryTerran/DryTerran.tscn",
	"res://Planets/NoAtmosphere/NoAtmosphere.tscn",
	"res://Planets/LandMasses/LandMasses.tscn",
	"res://Planets/GasPlanet/GasPlanet.tscn",
	"res://Planets/IceWorld/IceWorld.tscn",
	"res://Planets/GasPlanetLayers/GasPlanetLayers.tscn",
	"res://Planets/Rivers/Rivers.tscn",
]
const PLANET_ZONE_PEAK := [0.10, 0.25, 0.30, 0.50, 0.70, 0.90, 0.75, 0.45]

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
# Faction tints for per-combat-node glitter (Roman 2026-06-11). corpo = #5b6ee1.
const DECO_FACTION_COLORS := {
	"zealot": Color("a85cc5"), "privateer": Color("4b692f"),
	"supremacy": Color("ac3232"), "corpo": Color("5b6ee1"),
}

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

# Asteroid surface palette — realistic astronomical types (85%) + exotic variants (15%).
const ASTEROID_REALISTIC_COLORS: Array[Color] = [
	Color(0.25, 0.24, 0.23),  # C-type dark carbon
	Color(0.48, 0.44, 0.40),  # C-type medium grey
	Color(0.52, 0.42, 0.35),  # S-type grey-brown
	Color(0.55, 0.38, 0.28),  # S-type warm brown
	Color(0.44, 0.30, 0.20),  # D-type reddish-brown
	Color(0.62, 0.60, 0.58),  # M-type silvery
	Color(0.42, 0.50, 0.62),  # icy blue-grey
	Color(0.35, 0.40, 0.52),  # dark icy/shadowed
]
const ASTEROID_EXOTIC_COLORS: Array[Color] = [
	Color(0.72, 0.35, 0.20),  # iron-oxide rusty red
	Color(0.45, 0.62, 0.35),  # olivine green
	Color(0.70, 0.65, 0.20),  # sulfurous yellow
	Color(0.55, 0.30, 0.60),  # iridescent purple
]

const ROUTE_WIDTH := 8.0
# 0.70 × 0.8 = 0.56 — designer asked for -20% opacity on POI lines.
const ROUTE_COLOR := Color(0.30, 0.38, 0.55, 0.56)
const PROGRESS_COLOR := Color(0.55, 1.0, 0.50, 1.0)

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
var _asteroid_rotators: Array = []
var _moon_data:     Array = []
var _moon_textures: Dictionary = {}
var _glow_pulses:   Array = []
var _glitter:       Array = []
var _asteroid_pixels: Array = []
var _fx_rng: RandomNumberGenerator

# Per-POI click hit-region entry: {id, pos, radius, on_press: Callable}
# Embedded mode: the HD host (sector_map_hd.gd) instances this map into a
# SubViewport and owns ALL the chrome — buttons, input, scene transitions — in
# a 1920×1080 overlay. When embedded we skip building our own bottom buttons,
# skip the global clear-color tint (the host's SubViewport owns its bg), and
# skip _unhandled_input transitions (the host drives selection via the public
# _on_poi_selected / _on_boss_selected / _on_depart_pressed API). The host sets
# this true after instantiate() but BEFORE add_child(), so _ready sees it.
var _embedded: bool = false

var _selected_node_id: String = ""
var _selected_is_boss: bool = false
var _selected_node_lbl: Label = null
var _depart_btn: Button = null

var _poi_hits: Array = []
# Per-boss entry: {id, pos, row_idx, label, icon, dot_spr}
var _boss_entries: Array = []
# Dedicated child Node2D that draws the boss progress rings ABOVE the poi
# route lines (Roman: "boss circle and progress bar should sort above the poi
# bar"). The root Node2D's own _draw paints an opaque BG fill, so the ring can't
# live there and still beat the route Line2D children — it gets its own node
# with z_index high enough to sit over both routes (z 0) and the boss dot (z 3).
var _boss_ring_node: Node2D = null
# Per-row endpoint cache for green progress overlay: {anchor, end_x}
var _route_segments: Array = []
# Tracks the visual decorator currently being placed (for hover-color logic).
var _cur_row_idx: int = 0


func _ready() -> void:
	# When embedded in the HD host's SubViewport, our _draw() already paints an
	# opaque BG_COLOR rect over the whole 480×270 surface, so we must NOT touch
	# the global clear color (that would tint the entire 1920×1080 window).
	if not _embedded:
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
		var _run_ref := get_node("/root/Run")
		# self_repair_mk RETIRED 2026-06-13 — between-node hull regen is superseded by the
		# Repair Nanites MODULE (in-combat regen). No upgrade heal on map return anymore;
		# the field stays in run_state for save compat.
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
	var run := get_node("/root/Run")
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
	ls.font_color = UiTheme.COLOR_BOUNTY  # bounty-gold
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
	var run := get_node("/root/Run")
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
	var run := get_node("/root/Run")
	if run.is_sector_complete():
		run.sectors_cleared += 1
		run.combats_in_sector = 0
		# Deterministic per-sector seed (matches _ensure_sector_cache:291) so a
		# regen of the same sector reproduces the same layout + boss picks, and
		# run_seed stays stable for the whole run. Was `run_seed = randi()`, which
		# clobbered the seed mid-run AND disagreed with the _ensure formula — a
		# regen then picked DIFFERENT bosses, which got appended to used_boss_scenes
		# too, double-consuming the boss pool (toward forced cross-sector repeats).
		# With a consistent seed the same-sector re-roll yields the same bosses, so
		# start_new_sector's dedup append (:494) is a no-op. (Endless-mode pool
		# depletion is handled separately in _pick_row_bosses.)
		var seed_value: int = run.run_seed + run.sectors_cleared
		run.start_new_sector(run.sectors_cleared + 1, seed_value)


func _process(delta: float) -> void:
	_time += delta
	for node in _celestial_nodes:
		if is_instance_valid(node) and node.has_method("update_time"):
			node.update_time(_time * 0.5)
	for i in mini(_star_glows.size(), STAR_PULSE_HZ.size()):
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
		var lbl: Label     = entry.label
		var icon: Sprite2D = entry.icon
		var icon_rest: float  = float(entry.get("icon_rest",  0.0))
		var hover_tint: Color = entry.get("hover_tint", COLOR_NODE_GREEN)
		var rest_tint: Color  = entry.get("rest_tint",  Color.WHITE)
		if lbl != null:
			var label_rest: float = float(entry.get("label_rest", 0.0))
			lbl.modulate.a = lerpf(lbl.modulate.a, 1.0 if hovered else label_rest, delta * 8.0)
		if icon != null:
			var tgt: Color = hover_tint if hovered else rest_tint
			tgt.a = 0.9 if hovered else icon_rest
			icon.modulate = icon.modulate.lerp(tgt, delta * 8.0)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

func _build_routes() -> void:
	_route_segments.clear()
	var run := get_node("/root/Run")
	var rows: Array = run.sector_map_cache.get("rows", [])
	for i in rows.size():
		# Source anchor from star Marker2D so routes follow the scene editor.
		var anchor: Vector2 = STAR_ANCHORS[i]
		var star_marker_path: String = "star_%d" % (i + 1)
		if has_node(star_marker_path):
			anchor = (get_node(star_marker_path) as Marker2D).global_position
		var boss: Dictionary = rows[i].boss
		# Source boss end from its Marker2D so routes end at the marker position.
		var boss_marker_path: String = "star_%d/row_%d_boss_%d" % [i + 1, i + 1, i + 1]
		var end_x: float = boss.pos.x
		if has_node(boss_marker_path):
			end_x = (get_node(boss_marker_path) as Marker2D).global_position.x
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
	var run := get_node("/root/Run")
	var rows: Array = run.sector_map_cache.get("rows", [])
	for r_idx in rows.size():
		_cur_row_idx = r_idx
		# Boss end_x — prefer its Marker2D so route + frac stay consistent.
		var boss_marker_path_row: String = "star_%d/row_%d_boss_%d" % [r_idx + 1, r_idx + 1, r_idx + 1]
		var row_end_x: float = rows[r_idx].boss.pos.x
		if has_node(boss_marker_path_row):
			row_end_x = (get_node(boss_marker_path_row) as Marker2D).global_position.x
		# Write the resolved end_x back into the cache so the COMBAT backdrop's
		# frac math (_compute_poi_stellar / _compute_row_system, keyed off
		# boss.pos.x) uses the SAME row span the map renders with. Without this,
		# the map fracs off marker positions while combat fracs off the jittered
		# cache pos — different frac → _pick_planet_type returns a different planet,
		# so the level shows a planet/star that belongs to another node/row
		# (Roman 2026-06-02). Idempotent: re-resolving markers yields the same x.
		rows[r_idx].boss.pos = Vector2(row_end_x, rows[r_idx].boss.pos.y)
		var pois: Array = rows[r_idx].pois
		var planet_seq: int = 0
		for poi_idx in pois.size():
			var poi = pois[poi_idx]
			# Use the cache's already-randomized POI position (run_state._gen_row_pois
			# distributes POI X evenly with jitter into poi.pos). The old code
			# OVERRODE this with fixed scene Marker2D positions, mapping POI index i
			# -> marker i+1 and always filling markers 1..count from the LEFT, so a
			# 3-POI row clustered into the leftmost 3 of 5 markers (Roman, left-bias
			# bug). Reading poi.pos directly spreads them as generated AND keeps the
			# click Area2D / hover icon aligned (both derive from this same `pos`).
			# The cache already holds the randomized value, so no writeback is needed
			# and the combat frac (keyed off poi.pos) stays in lockstep with the map.
			var pos: Vector2 = poi.pos
			var deco_rng := RandomNumberGenerator.new()
			# Mix run_seed so the same grid-slot id varies decoration across runs
			# while staying stable WITHIN a run. Must match every combat-derive
			# site that re-seeds from poi.id (see _compute_poi_stellar :629,
			# _compute_row_system :772) and the moon RNG (:578) / planet appearance
			# (:684,:783,:889) — all xor run_seed identically.
			deco_rng.seed = abs(hash(poi.id) ^ run.run_seed)
			# Object kind: planet/large_ast/cluster. Distribution roughly
			# matches the dev v3 random pick (uniform across 3 types).
			var obj_kind: int = deco_rng.randi() % 3
			var hover_label: String = "" if poi.completed else "?"
			# Celestial bodies (planet/asteroid/cluster) are always drawn so
			# the map reads as a real star chart. The pulse glow and node
			# dressing are suppressed on completed POIs so the node reads
			# as "spent" at a glance. Advance planet_seq either way so the
			# next uncompleted POI keeps the planet-letter sequence stable.
			var draw_dressing: bool = not poi.completed
			match obj_kind:
				OBJ_PLANET:
					var px: float = PLANET_MIN_PX + float(deco_rng.randi() % 3) * 8.0
					var frac: float = (pos.x - 128.0) / max(1.0, row_end_x - 128.0)
					var ptype: int  = _pick_planet_type(deco_rng, frac)
					_spawn_planet(pos, px, ptype, r_idx, deco_rng, String(poi.id))
					if draw_dressing:
						hover_label = PLANET_LETTERS[mini(planet_seq, PLANET_LETTERS.size() - 1)]
					planet_seq += 1
				OBJ_LARGE_AST:
					_spawn_large_asteroid(pos, r_idx, deco_rng)
					if draw_dressing:
						hover_label = "Asteroid"
				OBJ_CLUSTER:
					_spawn_asteroid_cluster(pos, r_idx, deco_rng)
					if draw_dressing:
						hover_label = "Belt"
			if draw_dressing:
				_add_node_dressing(pos, int(poi.node_type), deco_rng, int(poi.get("faction", -1)))
				if int(poi.node_type) == int(SectorNode.NodeType.HAZARD) \
						and String(poi.get("hazard_subtype", "")) == "minefield":
					_add_minefield_indicators(pos, deco_rng)
			_add_hover_label_icon(pos, 32.0, hover_label, int(poi.node_type), poi.completed)
			# POI name label — skip completed nodes (spent) and BOSS type (handled separately).
			if not poi.completed and int(poi.node_type) != int(SectorNode.NodeType.BOSS):
				var poi_name_seed: int = abs(hash(poi.id)) ^ 0x3F7A1C2B
				# POI row shows the BODY name (planet, or asteroid for hazards). The event
				# prefix ("Skirmish at …") moves to the depart panel on selection.
				var poi_name: String = _poi_body_name(int(poi.node_type), poi_name_seed, String(poi.get("hazard_subtype", "")))
				# Anchor the name to the POI's randomized pos (not the fixed label
				# Marker2D) so it tracks the icon now that we no longer snap POIs to
				# scene markers (Fix 2). 14px below the icon, matching the old fallback.
				_make_label(poi_name, Vector2(pos.x, pos.y + 14.0), Color(0.75, 0.85, 1.0, 1.0))
			_poi_hits.append({
				"id":     String(poi.id),
				"pos":    pos,
				# 14px — wide enough to cover the 16px icon footprint (32px
				# atlas at 0.5 scale) so the icon itself is clickable. Matches
				# the hover radius so reveal + click happen at the same range.
				"radius": 14.0,
				"kind":   "poi",
			})


# NOTE (Roman 2026-06-11): the drifting decorative ships were pulled out in favor of
# per-combat-node faction glitter — the faction a node carries now tints its glitter
# zone (_add_glitter_zone), driven by the cache's per-POI `faction` field. See
# _faction_color + the combat branch of _add_node_dressing.


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
	0: 0,  # LavaWorld       -> backdrop 0 LavaWorld
	1: 2,  # DryTerran       -> backdrop 2 DryTerran
	2: 4,  # NoAtmosphere    -> backdrop 4 NoAtmosphere
	3: 5,  # LandMasses      -> backdrop 5 LandMasses
	4: 3,  # GasPlanet       -> backdrop 3 GasPlanet
	5: 1,  # IceWorld        -> backdrop 1 IceWorld
	6: 3,  # GasPlanetLayers -> backdrop 3 GasPlanet (closest match)
	7: 5,  # Rivers          -> backdrop 5 LandMasses (closest match)
}


# ── Row-system staging knobs (Roman to tune) ───────────────────────────────
# Each sector-map ROW is a star system: a star at the left edge (frac 0.0) and
# the row's planet POIs strung left→right by their `frac` (0=near star, 1=far
# right). When the player enters a node at `frac = C`, every body in the row is
# STAGED by its distance from C. The body coincident with the current node
# (distance 0) renders at BODY_SCALE_MAX (filling the screen); distant bodies
# fall off VERY FAST via a steep exponential curve so space reads as vast.
#
# Curve (Roman v2, 2026-05-30): scale = exp(-FALLOFF_K * d) where d = |C - frac|
# in [0,1]. This decays much faster than the old linear lerp:
#   d=0.0 -> 1.00 (full)   d=0.2 -> 0.37   d=0.4 -> 0.14
#   d=0.6 -> 0.05          d=0.8 -> 0.02   d=1.0 -> 0.007
# `scale` is a 0..1 multiplier; the coordinator turns it into px via
# planet_size (the size ceiling lives in backdrop_coordinator.planet_size /
# SYS_SIZE_CEILING and the 2px-dot threshold lives there too).
const BODY_SCALE_MAX := 1.0    # KNOB: scale of a body coincident with current node (full screen)
const FALLOFF_K      := 5.0    # KNOB: exponential falloff steepness; bigger = distant bodies vanish faster
# Cap on simultaneously-emitted PLANET bodies (the star is always included and
# does NOT count against this). Keeps a busy 5-POI row from cluttering the
# backdrop — we keep the planets NEAREST the current node (largest ones).
const SYSTEM_MAX_PLANETS := 3  # KNOB: max planet bodies emitted alongside the star
# Asteroid-belt amplification (Roman v2, 2026-05-30). When the current node IS
# an asteroid_field, or is ADJACENT (immediate row neighbor) to one, the
# decorative parallax asteroids get cranked across all 3 stellar layers so the
# player feels embedded in a vast belt. GATED behind SYSTEM_BACKDROP_ENABLED so
# the live combat path is unchanged until Roman flips the gate.
const BELT_DENSITY_SELF     := 2.4  # KNOB: asteroid_density when current node IS a belt
const BELT_DENSITY_ADJACENT := 1.6  # KNOB: asteroid_density when current node is NEXT TO a belt
# Master gate for the per-row star-system backdrop (Roman, enabled 2026-05-31
# for live testing). When false, current_stellar emits NO `system` array, the
# backdrop uses the original single-planet path, AND the belt-adjacency
# amplification is inert. Flip to false to fall back to the single-planet path.
const SYSTEM_BACKDROP_ENABLED := true


# Stable per-POI moon RNG. Salt the seed so moon derivation is decoupled
# from the planet's randomize_colors / set_seed consumption ordering — the
# combat backdrop can re-derive the same moon descriptors without having
# to replay the entire V3 spawn sequence.
func _make_moon_rng(poi_id: String) -> RandomNumberGenerator:
	var run := get_node("/root/Run")
	var r := RandomNumberGenerator.new()
	# Mix run_seed for cross-run variety (same id, same run -> same moons).
	r.seed = abs((hash(poi_id) ^ 0x9E3779B9) ^ run.run_seed)
	return r


# Deterministic exotic/binary state for a given row. Same result whether
# called from _build_stars() (map display) or _compute_poi/boss_stellar
# (combat backdrop) — keyed on run_seed + row so both see the same star.
func _get_star_variant(row_idx: int) -> Dictionary:
	var run := get_node("/root/Run")
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


# Deterministic asteroid surface color for a given row. 85% realistic
# (gray/brown/silvery), 15% exotic. Seeded from row_idx + run_seed so the
# same row always gets the same color within a run, independent of star color.
func _get_asteroid_color(row_idx: int) -> Color:
	var run := get_node("/root/Run")
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("asteroid_color:%d:%d" % [row_idx, run.run_seed]))
	if rng.randf() < 0.15:
		return ASTEROID_EXOTIC_COLORS[rng.randi() % ASTEROID_EXOTIC_COLORS.size()]
	return ASTEROID_REALISTIC_COLORS[rng.randi() % ASTEROID_REALISTIC_COLORS.size()]


# Flat descriptor for the combat backdrop. Deterministic per poi.id, no
# external state. obj_kind / planet_type mirror _build_pois_from_cache so
# the combat scene's planet matches what the player clicked on the map.
# Per-POI decorative nebula (Roman 2026-06-12). A minority of nodes carry a procedural nebula in the
# combat backdrop; the band picks a palette tint. Rolled on a SEPARATE salted rng so it never perturbs
# the planet/asteroid draw order (determinism with the sector-map render).
const NEBULA_NODE_CHANCE := 0.4
const NEBULA_BANDS := [
	{"name": "nebula_amber",   "tint": Color(0.95, 0.78, 0.50)},
	{"name": "nebula_cyan",    "tint": Color(0.55, 0.78, 1.00)},
	{"name": "nebula_magenta", "tint": Color(0.85, 0.58, 1.00)},
	{"name": "nebula_green",   "tint": Color(0.62, 0.95, 0.68)},
	{"name": "nebula_crimson", "tint": Color(1.00, 0.55, 0.58)},
]


func _compute_poi_stellar(poi: Dictionary, row_idx: int) -> Dictionary:
	var run := get_node("/root/Run")
	var rows: Array = run.sector_map_cache.get("rows", [])
	var row_end_x: float = float(rows[row_idx].boss.pos.x) if row_idx < rows.size() else 416.0
	var deco_rng := RandomNumberGenerator.new()
	# Mix run_seed — MUST match the map-render seed in _build_pois_from_cache
	# (:451) so obj_kind/px/planet_type combat-derive in lockstep with the map.
	deco_rng.seed = abs(hash(poi.id) ^ run.run_seed)
	var obj_kind: int = deco_rng.randi() % 3
	var planet_idx: int = -1
	var planet_type: int = -1
	var moons: Array = []
	var has_asteroids: bool = false
	var asteroid_density: float = 0.0
	# Decorative parallax asteroids in COMBAT must appear ONLY when the node the
	# player entered is an asteroid-field hazard (Roman 2026-05-30). The old code
	# keyed has_asteroids off `obj_kind` (a purely-decorative random pick shared
	# with the sector-map icon), which sprinkled background asteroids onto ~2/3 of
	# ALL levels. We now gate purely on hazard_subtype. NOTE: this only governs the
	# DECORATIVE backdrop — real gameplay asteroids are spawned by main.gd /
	# Levels.asteroid_field_level keyed off Run.current_hazard_subtype, untouched.
	var is_asteroid_field: bool = String(poi.get("hazard_subtype", "")) == "asteroid_field"
	# Belt adjacency (GATED): when the current node is next to a belt, we still
	# want a planet backdrop here but with amped decorative asteroids drifting in
	# from the neighboring field. Only consulted when SYSTEM_BACKDROP_ENABLED so
	# the live path keeps today's behavior (no asteroids on non-field nodes).
	var belt_adjacent: bool = SYSTEM_BACKDROP_ENABLED and _is_belt_adjacent(poi, row_idx)
	if is_asteroid_field:
		has_asteroids = true
		# Cluster-grade density for a real field; the old OBJ_CLUSTER used 1.2.
		# When the system backdrop is enabled, crank it to BELT_DENSITY_SELF so the
		# field reads as a vast belt across all 3 stellar layers.
		asteroid_density = BELT_DENSITY_SELF if SYSTEM_BACKDROP_ENABLED else 1.2
		# An asteroid field has no planet of its own — asteroids ARE the backdrop.
	elif belt_adjacent:
		# Adjacent to a belt: keep this node's planet backdrop AND sprinkle dense
		# drifting asteroids so the belt's edge is visible from here.
		has_asteroids = true
		asteroid_density = BELT_DENSITY_ADJACENT
		var px_adj: float = PLANET_MIN_PX + float(deco_rng.randi() % 3) * 8.0
		var frac_adj: float = (poi.pos.x - 128.0) / max(1.0, row_end_x - 128.0)
		planet_type = _pick_planet_type(deco_rng, frac_adj)
		planet_idx = int(V3_TO_BACKDROP_PLANET_IDX.get(planet_type, 0))
		moons = _derive_moon_descriptors(String(poi.id), px_adj)
	else:
		# Every non-asteroid-field node gets a real planet backdrop. Previously
		# the OBJ_LARGE_AST / OBJ_CLUSTER arms left planet_idx = -1 (the combat
		# coordinator then fell back to DryTerran), so forcing the planet path
		# here gives a deliberate planet instead of a fallback and avoids leaving
		# the now-asteroid-less nodes as bare starfields.
		var px: float = PLANET_MIN_PX + float(deco_rng.randi() % 3) * 8.0
		var frac: float = (poi.pos.x - 128.0) / max(1.0, row_end_x - 128.0)
		planet_type = _pick_planet_type(deco_rng, frac)
		planet_idx = int(V3_TO_BACKDROP_PLANET_IDX.get(planet_type, 0))
		moons = _derive_moon_descriptors(String(poi.id), px)
	var sv: Dictionary = _get_star_variant(row_idx)
	var base_type: int  = sv.base_type_idx
	var star_color: Color = EXOTIC_GLOW_COLORS[sv.exotic_idx] if sv.exotic_idx >= 0 else STAR_GLOW_COLORS[base_type]
	# Decorative nebula roll — separate salted rng so it doesn't shift the deco_rng sequence.
	var neb_rng := RandomNumberGenerator.new()
	neb_rng.seed = abs(hash(poi.id) ^ run.run_seed ^ 0x4E42)
	var nebula_band: String = ""
	var nebula_tint: Color = Color.WHITE
	if neb_rng.randf() < NEBULA_NODE_CHANCE:
		var nb: Dictionary = NEBULA_BANDS[neb_rng.randi() % NEBULA_BANDS.size()]
		nebula_band = String(nb["name"])
		nebula_tint = nb["tint"]
	return {
		"obj_kind":         obj_kind,
		"planet_idx":       planet_idx,
		"planet_type":      planet_type,
		# Planet PIXEL appearance seed. MUST equal _spawn_planet's psd (:889) so
		# the map planet and the combat planet look identical. Mixed with run_seed
		# in lockstep with psd.
		"planet_seed":      abs(hash(poi.id) ^ run.run_seed),
		"has_asteroids":    has_asteroids,
		"asteroid_density": asteroid_density,
		"nebula_band":      nebula_band,
		"nebula_tint":      nebula_tint,
		"moons":            moons,
		"star_color":       star_color,
		"star_cool":        STAR_COOL[base_type],
		"row_idx":          row_idx,
		"poi_id":           String(poi.id),
		"exotic_idx":       sv.exotic_idx,
		"has_binary":       sv.has_binary,
		# Row-system staging array (star + nearest planet POIs) for the combat
		# backdrop. See _compute_row_system. Single planet_idx/seed keys above
		# remain authoritative for tint + asteroid gating + fallback.
		"system":           _compute_row_system(poi, row_idx),
	}


# Build the "star system" body list for the row containing `current_poi`, viewed
# from the current node's position `C` (its frac along the row). Bodies = the
# star (frac 0.0) + each POI whose obj_kind == PLANET, each tagged with the same
# planet_idx/seed it would render with on the map. Every body's `scale` is its
# staging size by distance |C - frac|.
#
# CRITICAL — map/backdrop agreement: the per-POI deco_rng MUST be consumed in
# the EXACT order _build_pois_from_cache uses, or planet_type diverges from the
# map even with a matching seed:
#   1. randi() % 3          -> obj_kind            (matches :423)
#   2. (only if PLANET) randi() % 3  -> the `px` draw (matches :433)
#   3. _pick_planet_type(rng, frac)  -> planet_type (matches :435)
# True when an immediate row-neighbor of `current_poi` is an asteroid_field.
# Row POIs are generated left→right with monotonically increasing pos.x and
# stored in that order (run_state._gen_row_pois), so the neighbors are simply
# the entries at index±1. The current node itself being a field is handled by
# the caller (is_asteroid_field) — this only reports NEIGHBORS.
func _is_belt_adjacent(current_poi: Dictionary, row_idx: int) -> bool:
	var run := get_node("/root/Run")
	var rows: Array = run.sector_map_cache.get("rows", [])
	if row_idx < 0 or row_idx >= rows.size():
		return false
	var pois: Array = rows[row_idx].get("pois", [])
	var cur_id: String = String(current_poi.get("id", ""))
	var idx: int = -1
	for i in pois.size():
		if String(pois[i].get("id", "")) == cur_id:
			idx = i
			break
	if idx < 0:
		return false
	for n in [idx - 1, idx + 1]:
		if n >= 0 and n < pois.size():
			if String(pois[n].get("hazard_subtype", "")) == "asteroid_field":
				return true
	return false


func _compute_row_system(current_poi: Dictionary, row_idx: int) -> Array:
	if not SYSTEM_BACKDROP_ENABLED:
		return []
	var run := get_node("/root/Run")
	var rows: Array = run.sector_map_cache.get("rows", [])
	if row_idx < 0 or row_idx >= rows.size():
		return []
	var row: Dictionary = rows[row_idx]
	var pois: Array = row.get("pois", [])
	var row_end_x: float = float(row.boss.pos.x)
	var span: float = max(1.0, row_end_x - 128.0)
	# Current node's position metric C.
	var current_frac: float = (float(current_poi.pos.x) - 128.0) / span

	var sv: Dictionary = _get_star_variant(row_idx)
	var base_type: int = sv.base_type_idx
	var star_color: Color = EXOTIC_GLOW_COLORS[sv.exotic_idx] if sv.exotic_idx >= 0 else STAR_GLOW_COLORS[base_type]

	var system: Array = []
	# Star body — anchored at the left edge of the row (frac 0.0).
	system.append({
		"kind":        "star",
		"planet_idx":  8,                # layer_planet PLANETS[8] = Star
		"planet_seed": abs(hash("star:%d:%d" % [row_idx, run.run_seed])),
		"frac":        0.0,
		"scale":       _stage_scale(current_frac, 0.0),
		"star_color":  star_color,
	})

	# Collect candidate planet bodies (reproducing the map's obj_kind/type).
	var planets: Array = []
	for p in pois:
		var deco_rng := RandomNumberGenerator.new()
		# Mix run_seed — same form as the map-render seed (:451) so the staged
		# row-system planets match the map's per-POI planet_type.
		deco_rng.seed = abs(hash(p.id) ^ run.run_seed)
		var obj_kind: int = deco_rng.randi() % 3          # step 1 (matches map :423)
		if obj_kind != OBJ_PLANET:
			continue
		var _px_draw: int = deco_rng.randi() % 3           # step 2 (matches map :433)
		var p_frac: float = (float(p.pos.x) - 128.0) / span
		var ptype: int = _pick_planet_type(deco_rng, p_frac)  # step 3 (matches map :435)
		var p_idx: int = int(V3_TO_BACKDROP_PLANET_IDX.get(ptype, 0))
		planets.append({
			"kind":        "planet",
			"planet_idx":  p_idx,
			# Pixel appearance seed — must match _spawn_planet psd (:889), xor run_seed.
			"planet_seed": abs(hash(p.id) ^ run.run_seed),
			"frac":        p_frac,
			"scale":       _stage_scale(current_frac, p_frac),
			"star_color":  star_color,
		})

	# Cap to the SYSTEM_MAX_PLANETS planets NEAREST the current node (largest,
	# most-present bodies). Sort by distance |C - frac| ascending.
	planets.sort_custom(func(a, b):
		return absf(current_frac - float(a.frac)) < absf(current_frac - float(b.frac)))
	for i in mini(planets.size(), SYSTEM_MAX_PLANETS):
		system.append(planets[i])
	return system


# Staging scale for a body at `body_frac` viewed from current node `c`.
# Coincident (d=0) -> BODY_SCALE_MAX; falls off on a STEEP exponential curve so
# distant bodies shrink fast (sells the vastness of space). The returned scale
# is intentionally NOT floored — the coordinator decides dot-vs-sprite from the
# resulting raw px, so the far end must be allowed to approach ~0.
func _stage_scale(c: float, body_frac: float) -> float:
	var d: float = clampf(absf(c - body_frac), 0.0, 1.0)
	return BODY_SCALE_MAX * exp(-FALLOFF_K * d)


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
	var run := get_node("/root/Run")
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
		# Boss sits at the row's far-right endpoint (frac 1.0), so it views the
		# star at maximum distance -> small/distant (consistent with the staging
		# model). Star-only system; bosses have no planet of their own.
		"system":           ([{
			"kind":        "star",
			"planet_idx":  8,
			"planet_seed": abs(hash("star:%d:%d" % [row_idx, run.run_seed])),
			"frac":        0.0,
			"scale":       _stage_scale(1.0, 0.0),
			"star_color":  star_color,
		}] if SYSTEM_BACKDROP_ENABLED else []),
	}


# PixelPlanets/Control parity setup shared by every celestial spawn. PlanetKit scenes are
# Control-rooted; their ColorRect cells only line up to viewport pixels if the root is forced
# to a fixed 100x100 box with zero pivot BEFORE scaling. Extracted from 5 verbatim copies
# (health audit 2026-06-15).
func _setup_celestial_control(node, sf: float, pos: Vector2) -> void:
	if node is Control:
		node.anchor_left = 0.0; node.anchor_top = 0.0
		node.anchor_right = 0.0; node.anchor_bottom = 0.0
		node.offset_right = 100.0; node.offset_bottom = 100.0
		node.size = Vector2(100.0, 100.0)
		node.custom_minimum_size = Vector2(100.0, 100.0)
		node.pivot_offset = Vector2.ZERO
	node.scale = Vector2(sf, sf)
	node.position = pos


# One decorative asteroid: instantiate -> parity setup -> palette/seed/light -> add -> row
# tint -> register for rotation. Extracted from the 3 verbatim copies (large / cluster / band).
# Callers pass the asteroid CENTER (already offset), pixel size, the row-tint index, and the
# per-variant spin range. RNG order (set_seed, then speed, then phase) is preserved exactly so
# the combat backdrop still reproduces the map. (Health audit 2026-06-15.)
func _spawn_one_asteroid(pos_center: Vector2, px: float, row_tint_idx: int, speed_lo: float, speed_hi: float, rng: RandomNumberGenerator) -> void:
	var sf: float = px / 100.0
	var ast = ASTEROID_SCENE.instantiate()
	_setup_celestial_control(ast, sf, Vector2(pos_center.x - 50.0 * sf, pos_center.y - 50.0 * sf))
	_duplicate_materials(ast)
	_disable_asteroid_outlines(ast)   # Change 3
	if ast.has_method("set_pixels"): ast.set_pixels(px)
	if ast.has_method("set_seed"):   ast.set_seed(rng.randi())
	if ast.has_method("set_light"):  ast.set_light(Vector2(0.0, 0.5))
	add_child(ast)
	_disable_celestial_mouse(ast)
	_reset_planet_colorrects(ast)
	_apply_row_tint_to_asteroid(ast, row_tint_idx)
	ast.modulate = Color.WHITE
	_asteroid_rotators.append({
		"node":  ast,
		"speed": rng.randf_range(speed_lo, speed_hi),
		"phase": rng.randf_range(0.0, TAU),
	})


func _spawn_planet(center: Vector2, display_px: float, type_idx: int, row_idx: int, rng: RandomNumberGenerator, poi_id: String = "") -> void:
	var ps := load(PLANET_SCENES[type_idx])
	if ps == null:
		return
	var p = ps.instantiate()
	var sf: float = display_px / 100.0
	_setup_celestial_control(p, sf, Vector2(center.x - 50.0 * sf, center.y - 50.0 * sf))
	_duplicate_materials(p)
	if p.has_method("set_pixels"):  p.set_pixels(display_px)
	# Deterministic per-node appearance so the combat backdrop can reproduce
	# this exact planet from the stored planet_seed in current_stellar. Mix
	# run_seed in lockstep with the planet_seed returned by _compute_poi_stellar
	# (:684) / _compute_row_system (:783) so map and combat planets match.
	var psd: int = abs(hash(poi_id) ^ get_node("/root/Run").run_seed) if poi_id != "" else rng.randi()
	if p.has_method("set_seed"):    p.set_seed(psd % 100000)
	seed(psd)
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


func _spawn_large_asteroid(center: Vector2, row_idx: int, rng: RandomNumberGenerator) -> void:
	const PX: float = 32.0
	_spawn_one_asteroid(center, PX, row_idx, 0.008, 0.025, rng)
	_scatter_asteroid_band(center, rng)
	_scatter_pulse_pixels(center, PX, rng)

func _spawn_asteroid_cluster(center: Vector2, row_idx: int, rng: RandomNumberGenerator) -> void:
	var count: int = 3 + rng.randi() % 3
	for _k in count:
		var px: float  = 8.0 + float(rng.randi() % 3) * 4.0
		var ox: float  = rng.randf_range(-20.0, 20.0)
		var oy: float  = rng.randf_range(-16.0, 16.0)
		_spawn_one_asteroid(Vector2(center.x + ox, center.y + oy), px, row_idx, 0.005, 0.020, rng)
		_scatter_pulse_pixels(Vector2(center.x + ox, center.y + oy), px, rng)
	_scatter_asteroid_band(center, rng)

func _scatter_asteroid_band(center: Vector2, rng: RandomNumberGenerator) -> void:
	var count: int = 2 + rng.randi() % 3
	for _k in count:
		var px: float = 4.0 + float(rng.randi() % 3) * 2.0
		var ox: float = rng.randf_range(-36.0, 36.0)
		var oy: float = rng.randf_range(-12.0, 12.0)
		_spawn_one_asteroid(Vector2(center.x + ox, center.y + oy), px, _cur_row_idx, 0.005, 0.018, rng)
		_scatter_pulse_pixels(Vector2(center.x + ox, center.y + oy), px, rng)


func _scatter_pulse_pixels(center: Vector2, ast_px: float, rng: RandomNumberGenerator) -> void:
	var count: int = 6 + rng.randi() % 7
	var radius: float = ast_px * 0.6 + 6.0
	# Source pixel color from the asteroid palette so scatter pixels match the
	# rock body tint set by _apply_row_tint_to_asteroid — not the star color.
	# Mid-tone: lerp base toward white by ~55%, matching the c_mid derivation.
	var base_tint: Color = Color.WHITE.lerp(_get_asteroid_color(_cur_row_idx), 0.55)
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


# Scatter 6-8 blinking red 1×1 pixel indicators around a minefield node.
# Uses the same _asteroid_pixels array + _draw() loop as decorative asteroid
# pixels — per-pixel blink hz and phase so they desync naturally. Color is
# saturated red to read distinctly from the amber/blue asteroid decoration.
# Only called when draw_dressing is true (i.e. node not yet completed), so
# clearing happens automatically — the map rebuilds from cache on every entry.
func _add_minefield_indicators(center: Vector2, rng: RandomNumberGenerator) -> void:
	const MINE_COLOR := Color(1.0, 0.10, 0.10, 1.0)
	const SCATTER_RADIUS: float = 30.0
	var count: int = 6 + rng.randi() % 3   # 6-8 pixels
	for _k in count:
		var ang: float  = rng.randf() * TAU
		var dist: float = rng.randf_range(8.0, SCATTER_RADIUS)
		var pos := Vector2(
			floor(center.x + cos(ang) * dist),
			floor(center.y + sin(ang) * dist))
		_asteroid_pixels.append({
			"pos":   pos,
			"size":  1,
			# Blink rate 0.25-0.80 Hz — visibly faster than the subdued asteroid
			# debris pixels (0.05-0.14 Hz) so mines read as urgent/active.
			"hz":    rng.randf_range(0.25, 0.80),
			"phase": rng.randf_range(0.0, TAU),
			"color": MINE_COLOR,
		})


# ---------------------------------------------------------------------------
# Bosses from cache — lock visual + clickability gate
# ---------------------------------------------------------------------------

func _build_bosses_from_cache() -> void:
	var run := get_node("/root/Run")
	var rows: Array = run.sector_map_cache.get("rows", [])
	# Dedicated ring layer — z_index 4 puts the boss circle + progress arc above
	# the poi route lines (z 0) and the boss dot (z 3). Rings are static (no
	# _time animation), so one redraw after build is enough.
	_boss_ring_node = Node2D.new()
	_boss_ring_node.name = "BossRings"
	_boss_ring_node.z_index = 4
	add_child(_boss_ring_node)
	_boss_ring_node.draw.connect(_draw_boss_rings)
	for r_idx in rows.size():
		var boss: Dictionary = rows[r_idx].boss
		# Resolve position from Marker2D so moving the marker repositions
		# both the boss visual and its click/hover region.
		var boss_body_marker_path: String = "star_%d/row_%d_boss_%d" % [r_idx + 1, r_idx + 1, r_idx + 1]
		var pos: Vector2 = boss.pos
		if has_node(boss_body_marker_path):
			pos = (get_node(boss_body_marker_path) as Marker2D).global_position
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
		# Locked: dim red 50% alpha. Unlocked (boss AVAILABLE): full green so the
		# player reads "ready to fight" at a glance — matches the ring's
		# PROGRESS_COLOR / COLOR_NODE_GREEN. Defeated: dim green.
		if defeated:
			dot_spr.modulate = Color(COLOR_NODE_GREEN.r, COLOR_NODE_GREEN.g, COLOR_NODE_GREEN.b, 0.4)
		elif unlocked:
			dot_spr.modulate = Color(COLOR_NODE_GREEN.r, COLOR_NODE_GREEN.g, COLOR_NODE_GREEN.b, 1.0)
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
		icon_spr.scale    = Vector2(0.25, 0.25)   # Change 1: half size (was 0.5)
		icon_spr.z_index  = 5
		# Boss icon is ALWAYS visible (unlike regular POI icons, which rest at
		# alpha 0 until hovered). When the boss is AVAILABLE it shows green;
		# otherwise it shows its normal white tint. _process keeps it pinned via
		# the icon_rest / rest_tint entries below.
		var boss_icon_rest_tint: Color = COLOR_NODE_GREEN if (unlocked and not defeated) else Color.WHITE
		icon_spr.modulate = Color(boss_icon_rest_tint.r, boss_icon_rest_tint.g, boss_icon_rest_tint.b, 1.0)
		add_child(icon_spr)
		# BOSS/DEFEATED label — positioned above boss dot
		var boss_label_text: String = "DEFEATED" if defeated else "BOSS"
		var boss_label_color: Color = COLOR_NODE_GREEN if defeated else Color(0.90, 0.30, 0.30, 1.0)
		# Use Marker2D position from the scene
		var boss_label_marker_path := "star_%d/row_%d_boss_%d/boss_label_%d" % [r_idx + 1, r_idx + 1, r_idx + 1, r_idx + 1]
		if has_node(boss_label_marker_path):
			var boss_marker: Marker2D = get_node(boss_label_marker_path)
			_make_label(boss_label_text, boss_marker.global_position, boss_label_color)
		else:
			_make_label(boss_label_text, Vector2(pos.x, pos.y - 20.0), boss_label_color)

		var boss_hover_tint: Color = COLOR_NODE_GREEN
		if not unlocked or defeated:
			boss_hover_tint = Color(COLOR_BOSS_RED.r, COLOR_BOSS_RED.g, COLOR_BOSS_RED.b, 1.0)
		_planet_hovers.append({
			"center":     pos,
			"radius":     16.0,
			"label":      null,
			"icon":       icon_spr,
			"label_rest": 1.0,
			# Boss icon always shows (rest alpha ~0.9) — Roman: "boss poi icon
			# should not be invisible, unlike other poi icons."
			"icon_rest":  0.9,
			"hover_tint": boss_hover_tint,
			# Rest tint matches the dot/ring: green when AVAILABLE, white otherwise.
			"rest_tint":  boss_icon_rest_tint,
		})
		_boss_entries.append({
			"id":       String(boss.id),
			"pos":      Vector2(pos),
			"row_idx":  r_idx,
			"unlocked": unlocked,
			"defeated": defeated,
		})
	if is_instance_valid(_boss_ring_node):
		_boss_ring_node.queue_redraw()


# Draws the boss progress rings on the dedicated _boss_ring_node (z_index 4) so
# they sort ABOVE the poi route lines. Connected to that node's `draw` signal,
# so `draw_arc` here targets the ring node's canvas item, not the root's.
func _draw_boss_rings() -> void:
	var run := get_node("/root/Run")
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
		for poi_idx in pois.size():
			var poi = pois[poi_idx]
			if poi.completed:
				done += 1
		# Smooth continuous arc: filled from 12-o'clock to done/total fraction,
		# then unfilled remainder.
		var fill_frac: float = float(done) / float(total)
		var start_angle: float = -PI * 0.5
		var fill_end: float = start_angle + fill_frac * TAU
		var filled_steps: int = maxi(1, int(RING_ARC_STEPS * fill_frac))
		var unfilled_steps: int = maxi(1, int(RING_ARC_STEPS * (1.0 - fill_frac)))
		if done > 0:
			_boss_ring_node.draw_arc(center, RING_RADIUS, start_angle, fill_end, filled_steps, ring_filled, RING_WIDTH)
		if done < total:
			_boss_ring_node.draw_arc(center, RING_RADIUS, fill_end, start_angle + TAU, unfilled_steps, ring_unfilled, RING_WIDTH)


# ---------------------------------------------------------------------------
# Stars + labels — identical to dev v3
# ---------------------------------------------------------------------------

func _build_stars() -> void:
	for i in STAR_ANCHORS.size():
		# Source anchor from scene Marker2D so moving star_N repositions
		# the star body, glow, and label together.
		var anchor: Vector2 = STAR_ANCHORS[i]
		var star_body_marker_path: String = "star_%d" % (i + 1)
		if has_node(star_body_marker_path):
			anchor = (get_node(star_body_marker_path) as Marker2D).global_position
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

		# Star name label — centered above star anchor
		var star_seed: int = abs(hash("star:%d" % i))
		if has_node("/root/Run"):
			star_seed = abs(hash("star:%d:%d" % [i, get_node("/root/Run").run_seed]))
		var star_name: String = _generate_celestial_name("star", star_seed)
		# Use Marker2D position from the scene
		var star_label_marker_path := "star_%d/star_label_%d" % [i + 1, i + 1]
		if has_node(star_label_marker_path):
			var star_marker: Marker2D = get_node(star_label_marker_path)
			_make_label(star_name, star_marker.global_position, Color(0.75, 0.85, 1.0, 1.0))
		else:
			_make_label(star_name, Vector2(anchor.x, anchor.y - 20.0), Color(0.75, 0.85, 1.0, 1.0))

	_process(0.0)


func _spawn_star_body(anchor: Vector2, display_px: float, seed_val: int, cool: bool, exotic_idx: int, row_i: int) -> void:
	var star = STAR_SCENE.instantiate()
	var sf: float = display_px / 100.0
	_setup_celestial_control(star, sf, Vector2(anchor.x - 50.0 * sf, anchor.y - 50.0 * sf))
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
	var run := get_node("/root/Run")
	var current_sector: int = run.sectors_cleared + 1
	var total_sectors: int = int(run.TOTAL_SECTORS)
	var sector_name: String = String(run.sector_map_cache.get("sector_name", ""))
	if sector_name == "":
		var SectorNameGen := preload("res://scripts/strings/sector_name_generator.gd")
		var seed_value: int = int(run.sector_map_cache.get("seed", run.run_seed + run.sectors_cleared))
		sector_name = SectorNameGen.generate(seed_value)
		run.sector_map_cache["sector_name"] = sector_name

# Sector header label — centered at top at (256, 16)
	var patrol_count: int = 0
	var rows: Array = run.sector_map_cache.get("rows", [])
	for row in rows:
		patrol_count += row.pois.size()
	var sector_header_text: String = "%s  —  %d Patrols" % [sector_name, patrol_count]
	# Use Marker2D position from the scene
	if has_node("sector_label"):
		var sector_marker: Marker2D = get_node("sector_label")
		_make_label(sector_header_text, sector_marker.global_position, Color(0.85, 0.92, 1.0, 1.0))
	else:
		_make_label(sector_header_text, Vector2(240.0, 8.0), Color(0.85, 0.92, 1.0, 1.0))

	# (Player status line removed 2026-06-08 — the same Hull/Shield/Bounty/Super/ammo
	# readout lives in the Manage Ship panel. The bottom-left slot is now free for the
	# Visit Outpost + Manage Ship buttons. _ms_build_status_bits_text is kept — it's
	# still used by manage_ship.gd.)

	# Selected node label — bottom center at (256, 232)
	var sel_ls := LabelSettings.new()
	sel_ls.font = FONT; sel_ls.font_size = 9
	sel_ls.font_color    = Color(0.75, 1.0, 0.75, 0.95)
	sel_ls.outline_size  = 1
	sel_ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
	_selected_node_lbl = Label.new()
	_selected_node_lbl.text = ""
	_selected_node_lbl.label_settings = sel_ls
	_selected_node_lbl.position = Vector2(130.0, 230.0)
	_selected_node_lbl.size = Vector2(220.0, 14.0)
	_selected_node_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selected_node_lbl.z_index = 10
	_selected_node_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selected_node_lbl.modulate.a = 0.0
	add_child(_selected_node_lbl)

	# Bottom buttons: skipped entirely when embedded — the HD host renders its
	# own crisp 1920×1080 buttons at the same marker anchors × 4.
	if _embedded:
		return

	# Bottom buttons on their own CanvasLayer so mouse events reach them
	var btn_layer := CanvasLayer.new()
	btn_layer.name = "BottomBtnLayer"
	btn_layer.layer = 6
	add_child(btn_layer)

	# (MANAGE SHIP fallback button retired 2026-06-14 — folded into the at-will outpost.)

	# Options button — bottom right at (448, 256)
	var options_btn := Button.new()
	options_btn.text = "OPTIONS"
	options_btn.add_theme_font_override("font", FONT)
	options_btn.add_theme_font_size_override("font_size", 9)
	options_btn.custom_minimum_size = Vector2(56, 14)
	options_btn.position = Vector2(420, 248)
	options_btn.pressed.connect(_open_options)
	btn_layer.add_child(options_btn)

	# Depart button — bottom center at (256, 256). Idle: faded + dim border.
	# Ready (node selected, player can depart): lit + green outline. Roman
	# 2026-06-02: the green outline reinforces the "you may depart" affordance
	# beyond the alpha lift alone.
	_depart_btn = Button.new()
	_depart_btn.text = "DEPART"
	_depart_btn.add_theme_font_override("font", FONT)
	_depart_btn.add_theme_font_size_override("font_size", 9)
	_depart_btn.custom_minimum_size = Vector2(56, 14)
	_depart_btn.position = Vector2(228, 248)
	_depart_btn.pressed.connect(_on_depart_pressed)
	btn_layer.add_child(_depart_btn)
	_set_depart_ready(false)


# ---------------------------------------------------------------------------
# Hover/label/icon + node-type dressing (mirrors dev v3)
# ---------------------------------------------------------------------------

func _add_node_dressing(pos: Vector2, node_type: int, rng: RandomNumberGenerator, faction: int = -1) -> void:
	# Map enum int → dressing.
	#   COMBAT = 0, OUTPOST = 1, SIGNAL = 2, HAZARD = 5 (see sector_node.gd)
	match node_type:
		int(SectorNode.NodeType.OUTPOST): _add_pulse_glow(pos, Color(0.35, 0.65, 1.0), rng)
		int(SectorNode.NodeType.HAZARD):  _add_pulse_glow(pos, Color(1.0,  0.25, 0.20), rng)
		int(SectorNode.NodeType.SIGNAL):  _add_pulse_glow(pos, Color(1.0,  0.90, 0.15), rng)
		int(SectorNode.NodeType.COMBAT):  _add_glitter_zone(pos, faction)


# Faction int (Factions.Id: SUPREMACY 0 / PRIVATEER 1 / CORPORATE 2 / ZEALOT 3) →
# decoration color. -1 (no faction) falls back to the neutral whitish glitter.
func _faction_color(faction: int) -> Color:
	match faction:
		0: return DECO_FACTION_COLORS["supremacy"]
		1: return DECO_FACTION_COLORS["privateer"]
		2: return DECO_FACTION_COLORS["corpo"]
		3: return DECO_FACTION_COLORS["zealot"]
	return Color(0.78, 0.84, 0.92)


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


# Combat-node glitter, colored by the node's faction (Roman 2026-06-11): the
# decorative pixel glitter on a combat node now reads as that faction's color,
# mirroring how minefield nodes scatter blinking red pixels. faction -1 → neutral.
func _add_glitter_zone(pos: Vector2, faction: int = -1) -> void:
	var rect: Rect2 = Rect2(pos.x - 32.0, pos.y - 32.0, 64.0, 64.0)
	var base_col: Color = _faction_color(faction)
	var neutral_col := Color(0.78, 0.84, 0.92)   # the default whitish glitter
	var priv_col: Color = DECO_FACTION_COLORS["privateer"]
	# Roman worklist (sector map): color ~50% of the motes the node's faction colour,
	# the rest neutral. Privateer is THE overlay faction: a non-privateer combat node
	# has a ~12% chance (mirrors Factions.PRIVATEER_OVERLAY_CHANCE) to host privateer
	# interlopers, in which case the split is 30% faction / 20% privateer / 50% neutral.
	# (corpo stays blue #5b6ee1; the worklist's corpo #ac3232 reads as a supremacy dup.)
	var has_interloper: bool = faction >= 0 and faction != 1 and _fx_rng.randf() < 0.12
	var count: int = 7 + _fx_rng.randi() % 5
	for _k in count:
		# Per-mote colour: neutral by default; faction (and, on interloper nodes,
		# privateer) tint a fraction of them per the split above.
		var col: Color = neutral_col
		if faction >= 0:
			var r: float = _fx_rng.randf()
			if has_interloper:
				if r < 0.30:
					col = base_col
				elif r < 0.50:
					col = priv_col
			elif r < 0.50:
				col = base_col
		_glitter.append({
			"pos":        Vector2(_fx_rng.randf_range(rect.position.x, rect.end.x),
								  _fx_rng.randf_range(rect.position.y, rect.end.y)),
			"vel":        Vector2(_fx_rng.randf_range(-10.0, 10.0),
								  _fx_rng.randf_range(-6.0,   6.0)),
			"rect":       rect,
			"brightness": _fx_rng.randf(),
			"hidden":     false,
			"timer":      _fx_rng.randf_range(0.3, 2.0),
			"color":      col,
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
	var at := AtlasTexture.new()
	at.atlas  = ICON_STRIP
	at.region = Rect2(_icon_for_type(node_type) * 32, 0, 32, 32)
	var icon_spr := Sprite2D.new()
	icon_spr.texture  = at
	icon_spr.position = pos
	icon_spr.scale    = Vector2(0.5, 0.5)
	icon_spr.z_index  = 5
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
		"label":      null,
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

# ---------------------------------------------------------------------------
# Label creation helper — standard style for all labels
# ---------------------------------------------------------------------------

func _make_label(text: String, pos: Vector2, color: Color) -> Label:
	var ls := LabelSettings.new()
	ls.font = FONT
	ls.font_size = 7
	ls.font_color = color
	ls.outline_size = 1
	ls.outline_color = Color(0.0, 0.0, 0.0, 1.0)
	var lbl := Label.new()
	lbl.text = text
	lbl.label_settings = ls
	lbl.custom_minimum_size.x = 64
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(pos.x - lbl.custom_minimum_size.x * 0.5, pos.y)
	lbl.z_index = 100
	lbl.modulate.a = 1.0
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	return lbl


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
# POI naming (reworked 2026-06-13): the sector-map POI ROW shows the BODY name — a
# realistic sci-fi PLANET name for most nodes, an ASTEROID-field name for hazards — and
# the depart panel adds the node EVENT prefix on selection (e.g. "Skirmish at Centauri
# III" / "Exclusion Zone NGC-417"). Body + prefix are seeded off the POI id, so they're
# stable per node and the row body matches the depart label.

# Body name shown on the POI row (planet, or asteroid for hazards).
func _poi_body_name(node_type: int, seed_val: int, _hazard_subtype: String = "") -> String:
	var t: String = "asteroid" if node_type == int(SectorNode.NodeType.HAZARD) else "planet"
	return _generate_celestial_name(t, seed_val)


# The node's EVENT prefix (what's happening there). Seeded independently of the body
# (xor offset) so both are stable but uncorrelated.
func _poi_event_prefix(node_type: int, seed_val: int, hazard_subtype: String = "") -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = (abs(seed_val) ^ 0x5151A3) % 0x7FFFFFFF
	match node_type:
		int(SectorNode.NodeType.COMBAT):
			return _PN_COMBAT_PREFIXES[rng.randi() % _PN_COMBAT_PREFIXES.size()]
		int(SectorNode.NodeType.OUTPOST):
			return _PN_STATION_PREFIX[rng.randi() % _PN_STATION_PREFIX.size()]
		int(SectorNode.NodeType.SIGNAL):
			return _PN_SIGNAL_PREFIX[rng.randi() % _PN_SIGNAL_PREFIX.size()]
		int(SectorNode.NodeType.HAZARD):
			if hazard_subtype == "minefield":
				return _PN_HAZARD_MINE[rng.randi() % _PN_HAZARD_MINE.size()]
			return _PN_HAZARD_ASTEROID[rng.randi() % _PN_HAZARD_ASTEROID.size()]
	return ""


# Full depart-panel label: event prefix + body name (same seed → body matches the row).
func _poi_event_label(node_type: int, seed_val: int, hazard_subtype: String = "") -> String:
	var body: String = _poi_body_name(node_type, seed_val, hazard_subtype)
	var prefix: String = _poi_event_prefix(node_type, seed_val, hazard_subtype)
	return ("%s %s" % [prefix, body]) if prefix != "" else body


# Override the asteroid shader's `colors` palette with a 3-tone derived from
# the row's star color (dark / mid / light). PlanetKit's Asteroid shader uses
# a fixed gray-blue palette by default; modulate-tinting that palette reads
# muddy because gray × red = brown. Setting the shader uniform directly makes
# the rocks render in the family color the surrounding decoration pixels use.
# Caller is expected to have called _duplicate_materials(root) first so this
# write is per-instance, not shared.
func _apply_row_tint_to_asteroid(root: Node, row_idx: int) -> void:
	# Use realistic asteroid colors (gray/brown/silvery, 15% exotic) rather than
	# the star color — rocks should look like rocks, not star-tinted blobs.
	var base: Color = _get_asteroid_color(row_idx)
	# 3-tone palette: light (highlight), mid (surface), dark (shadow).
	var c_light: Color = Color.WHITE.lerp(base, 0.45)
	var c_mid: Color   = Color.WHITE.lerp(base, 0.75).darkened(0.10)
	var c_dark: Color  = base.darkened(0.55)
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
	# Combat glitter — 1px dots, tinted by the node's faction (Roman 2026-06-11).
	for p in _glitter:
		if p.brightness > 0.04:
			var gc: Color = p.get("color", Color(0.78, 0.84, 0.92))
			draw_rect(Rect2(p.pos, Vector2(1, 1)),
				Color(gc.r, gc.g, gc.b, p.brightness))
	# Pulsing decorative pixels around asteroids.
	for px in _asteroid_pixels:
		var a: float = 0.5 + 0.5 * sin(_time * px.hz * TAU + px.phase)
		var c: Color = px.color
		c.a = a
		draw_rect(Rect2(px.pos, Vector2(px.size, px.size)), c)
	# Boss progress rings are NOT drawn here — they live in _boss_ring_node
	# (z_index 4) so they sort ABOVE the poi route lines instead of being
	# occluded by them. See _draw_boss_rings / _build_bosses_from_cache.


func _unhandled_input(event: InputEvent) -> void:
	# Embedded: the HD host owns all input (HD-native hit-testing + Esc) and
	# this map lives in a gui-disabled SubViewport that never sees clicks anyway.
	if _embedded:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# Esc opens the options overlay; never ends the run.
		var OptionsOverlay := load("res://scripts/ui/options_overlay.gd")
		if OptionsOverlay:
			OptionsOverlay.open(self)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp: Vector2 = get_local_mouse_position()
		# Try POIs first (smaller hit-radius, more numerous).
		for hit in _poi_hits:
			if mp.distance_to(hit.pos) <= hit.radius:
				_on_poi_selected(String(hit.id))
				return
		# Then bosses.
		for b in _boss_entries:
			if mp.distance_to(b.pos) <= 16.0:
				_on_boss_selected(String(b.id))
				return


func _on_poi_selected(node_id: String) -> void:
	var run := get_node("/root/Run")
	var poi = run.find_sector_node(node_id)
	if poi == null or poi.get("completed", false):
		return
	_selected_node_id = node_id
	_selected_is_boss = false
	# Depart panel shows the EVENT + the body name, e.g. "Skirmish at Centauri III" /
	# "Exclusion Zone NGC-417" (same seed → the body matches the POI row label).
	var poi_name_seed: int = abs(hash(node_id)) ^ 0x3F7A1C2B
	var poi_name: String = _poi_event_label(int(poi.node_type), poi_name_seed, String(poi.get("hazard_subtype", "")))
	if is_instance_valid(_selected_node_lbl):
		_selected_node_lbl.text = poi_name
		_selected_node_lbl.modulate.a = 1.0
	_set_depart_ready(true)


func _on_boss_selected(node_id: String) -> void:
	var run := get_node("/root/Run")
	var boss = run.find_sector_node(node_id)
	if boss == null or boss.get("completed", false):
		return
	var rows: Array = run.sector_map_cache.get("rows", [])
	var row_idx: int = -1
	for i in rows.size():
		if rows[i].boss.id == node_id:
			row_idx = i
			break
	if row_idx < 0 or not run.is_row_pois_complete(row_idx):
		return  # locked
	_selected_node_id = node_id
	_selected_is_boss = true
	if is_instance_valid(_selected_node_lbl):
		_selected_node_lbl.text = "BOSS ENCOUNTER"
		_selected_node_lbl.modulate.a = 1.0
	_set_depart_ready(true)


# Toggle the depart button between idle (faded, dim border) and ready (lit,
# green outline). "Ready" = a node is selected and the player can depart.
func _set_depart_ready(ready: bool) -> void:
	if not is_instance_valid(_depart_btn):
		return
	_depart_btn.modulate.a = 1.0 if ready else 0.3
	var border: Color = UiTheme.COLOR_GREEN if ready else Color(0.30, 0.36, 0.44, 1.0)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.11, 0.16, 0.85)
		sb.border_color = border
		sb.set_border_width_all(1)
		sb.corner_radius_top_left = 3
		sb.corner_radius_top_right = 3
		sb.corner_radius_bottom_left = 3
		sb.corner_radius_bottom_right = 3
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		_depart_btn.add_theme_stylebox_override(state, sb)


func _on_depart_pressed() -> void:
	if _selected_node_id == "":
		return
	if _selected_is_boss:
		_on_boss_clicked(_selected_node_id)
	else:
		_on_poi_clicked(_selected_node_id)


func _open_options() -> void:
	var OptionsOverlay := load("res://scripts/ui/options_overlay.gd")
	if OptionsOverlay:
		OptionsOverlay.open(self)


func _on_poi_clicked(node_id: String) -> void:
	var run := get_node("/root/Run")
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
	# Gated on the kill-switch (Roman 2026-06-10: modifiers pulled pending re-eval) so even a
	# stale cache/save that already carries modifiers can't apply them.
	run.sector_modifiers = (poi.get("modifiers", []) as Array).duplicate() if run.SECTOR_MODIFIERS_ENABLED else []
	# Find this POI's row so the descriptor inherits the right star color.
	var rows: Array = run.sector_map_cache.get("rows", [])
	var poi_row_idx: int = 0
	for r_idx in rows.size():
		var found_row := false
		for p in rows[r_idx].pois:
			if String(p.id) == node_id:
				poi_row_idx = r_idx
				found_row = true
				break
		if found_row:
			break
	# Stellar descriptor — combat/outpost/signal/hazard backdrops read this so
	# the scene visually echoes the POI the player clicked.
	run.current_stellar = _compute_poi_stellar(poi, poi_row_idx)
	# Store the row's asteroid color so galaxy_backdrop uses the same family
	# for all backdrop asteroids in this level. Falls back to random if absent.
	run.set_meta("asteroid_base_color", _get_asteroid_color(poi_row_idx))
	match int(poi.node_type):
		int(SectorNode.NodeType.COMBAT):
			SceneTransition.change_scene(get_tree(), COMBAT_SCENE)
		int(SectorNode.NodeType.OUTPOST):
			# Zero-bounty entry is no longer gated by a modal — the HD host
			# surfaces a "no bounty to spend" warning over the selected-node
			# label at selection time (visiting is allowed; refills can be free).
			SceneTransition.change_scene(get_tree(), OUTPOST_SCENE)
		int(SectorNode.NodeType.SIGNAL):
			SceneTransition.change_scene(get_tree(), SIGNAL_SCENE)
		int(SectorNode.NodeType.HAZARD):
			SceneTransition.change_scene(get_tree(), HAZARD_SCENE)


func _on_boss_clicked(node_id: String) -> void:
	var run := get_node("/root/Run")
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
	# Same kill-switch gate as the POI path (modifiers pulled pending re-eval).
	run.sector_modifiers = (boss.get("modifiers", []) as Array).duplicate() if run.SECTOR_MODIFIERS_ENABLED else []
	# Boss arenas don't have a planet/asteroid of their own — just tint with
	# the row's star color so the fight still feels rooted on the chosen line.
	run.current_stellar = _compute_boss_stellar(row_idx)
	# Store the row's asteroid color for the combat backdrop. Boss arenas
	# don't have asteroid decorations of their own, but the backdrop still
	# spawns parallax rocks — give them the same family color the sector used.
	run.set_meta("asteroid_base_color", _get_asteroid_color(row_idx))
	run.forced_boss_scene = String(boss.get("boss_scene", ""))
	SceneTransition.change_scene(get_tree(), BOSS_SCENE)


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
