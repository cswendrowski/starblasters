# Gameplay stellar authoring — extracted VERBATIM from sector_map_v3 (WP11, 2026-07-08).
#
# The sector map authors a per-node `current_stellar` dict + an `asteroid_base_color` that the combat
# backdrop (backdrop_coordinator) reads so the flown level visually echoes the node the player clicked.
# That authoring used to live inline in sector_map_v3 (_compute_poi_stellar / _compute_boss_stellar /
# _compute_row_system / _get_asteroid_color + helpers). It is now a static module so the Parallax
# Showcase lab can roll THE SORTS OF BACKGROUNDS PLAY PRODUCES through the exact same code path — one
# implementation, so the showcase stays true as the map evolves.
#
# This is a REFACTOR, not a redesign: every rng salt string + consumption order is byte-identical to
# the old sector_map_v3 code, so `compute_poi_stellar` / `compute_boss_stellar` / `asteroid_color_for_row`
# return the same dict for the same {run_seed, node} they did before the extraction. The map's methods
# are now thin wrappers that build a plain descriptor (data, not poi object references) and delegate here.
#
# The ONE sanctioned behavior change (WP11 item 4, Roman: "keep the new star scaling"): the row star's
# intrinsic scale was always BODY_SCALE_MAX (1.0) staged by distance, so a node beside its star always
# showed a full-ceiling star (clamped by star_fx) with no size variety across systems. `_build_row_system`
# now rolls a per-ROW continuous intrinsic scale (the composer's small-biased curve) on an isolated rng
# and multiplies it into the star's staged scale — gameplay stars gain the composer's 10-119px spread.
# The roll consumes NO deco_rng, so planet picks stay byte-identical; only the star's `scale` field moves.
#
# NOT class_name (preload-const referenced) to keep headless --script class-cache safety — mirrors
# stellar_composer.gd.

# ── Star / asteroid / planet palettes (verbatim from sector_map_v3) ──────────
const STAR_GLOW_COLORS := [
	Color(0.45, 0.65, 1.00, 1.0),
	Color(1.00, 0.72, 0.18, 1.0),
	Color(1.00, 0.26, 0.07, 1.0),
]
const STAR_COOL := [true, false, false]

const BINARY_STAR_CHANCE := 0.08          # 8% chance of a companion star

const EXOTIC_STAR_CHANCE_BASE       := 0.04   # 4% at 0 sectors cleared
const EXOTIC_STAR_CHANCE_PER_SECTOR := 0.012  # +1.2% per sector cleared
const EXOTIC_STAR_CHANCE_MAX        := 0.25   # cap at 25%
const EXOTIC_GLOW_COLORS := [
	Color(0.70, 0.22, 0.95, 1.0),  # purple
	Color(0.18, 0.90, 0.35, 1.0),  # green
	Color(1.00, 0.25, 0.65, 1.0),  # pink
]

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

const PLANET_ZONE_PEAK := [0.10, 0.25, 0.30, 0.50, 0.70, 0.90, 0.75, 0.45]

# V3 planet type index -> galaxy_backdrop.PLANETS index.
const V3_TO_BACKDROP_PLANET_IDX := {
	0: 0,  # LavaWorld       -> backdrop 0 LavaWorld
	1: 2,  # DryTerran       -> backdrop 2 DryTerran
	2: 4,  # NoAtmosphere    -> backdrop 4 NoAtmosphere
	3: 5,  # LandMasses      -> backdrop 5 LandMasses
	4: 3,  # GasPlanet       -> backdrop 3 GasPlanet
	5: 1,  # IceWorld        -> backdrop 1 IceWorld
	6: 9,  # GasPlanetLayers -> backdrop 9 GasPlanetLayers (ringed)
	7: 10, # Rivers          -> backdrop 10 Rivers
}

const OBJ_PLANET    := 0
const PLANET_MIN_PX := 16.0

# Per-POI decorative nebula — a minority of nodes carry a procedural nebula.
const NEBULA_NODE_CHANCE := 0.4
const NEBULA_BANDS := [
	{"name": "nebula_amber",   "tint": Color(0.95, 0.78, 0.50)},
	{"name": "nebula_cyan",    "tint": Color(0.55, 0.78, 1.00)},
	{"name": "nebula_magenta", "tint": Color(0.85, 0.58, 1.00)},
	{"name": "nebula_green",   "tint": Color(0.62, 0.95, 0.68)},
	{"name": "nebula_crimson", "tint": Color(1.00, 0.55, 0.58)},
]

# Master gate for the per-row star-system backdrop + belt-adjacency amplification.
const SYSTEM_BACKDROP_ENABLED := true
const BELT_DENSITY_SELF     := 2.4  # asteroid_density when current node IS a belt
const BELT_DENSITY_ADJACENT := 1.6  # asteroid_density when current node is NEXT TO a belt

# Row-system staging.
const BODY_SCALE_MAX     := 1.0     # scale of a body coincident with the current node
const FALLOFF_K          := 5.0     # exponential falloff steepness
const SYSTEM_MAX_PLANETS := 3       # max planet bodies emitted alongside the star


# ── Public API ───────────────────────────────────────────────────────────────
# Flat combat-backdrop descriptor for a POI. `desc` carries the raw grid data the authoring reads
# (data, NOT poi object references):
#   id: String            — poi.id (rng salt + planet appearance seed)
#   row: int              — poi's row index (star variant + row-system keying)
#   pos_x: float          — poi.pos.x (frac along the row)
#   row_end_x: float      — row.boss.pos.x (416.0 fallback) — the frac span denominator
#   hazard_subtype: String
#   belt_adjacent: bool   — precomputed by the caller (map: SYSTEM_BACKDROP_ENABLED and _is_belt_adjacent)
#   sectors_cleared: int  — exotic-star chance scales with this
#   run_seed: int
#   row_pois: Array       — [{id: String, pos_x: float}, …] for the whole row (row-system staging)
static func compute_poi_stellar(desc: Dictionary) -> Dictionary:
	var id: String = String(desc.get("id", ""))
	var row_idx: int = int(desc.get("row", 0))
	var pos_x: float = float(desc.get("pos_x", 0.0))
	var run_seed: int = int(desc.get("run_seed", 0))
	var sectors_cleared: int = int(desc.get("sectors_cleared", 0))
	var row_end_x: float = float(desc.get("row_end_x", 416.0))
	var deco_rng := RandomNumberGenerator.new()
	# Mix run_seed — MUST match the map-render seed in _build_pois_from_cache so
	# obj_kind/px/planet_type combat-derive in lockstep with the map.
	deco_rng.seed = abs(hash(id) ^ run_seed)
	var obj_kind: int = deco_rng.randi() % 3
	var planet_idx: int = -1
	var planet_type: int = -1
	var moons: Array = []
	var has_asteroids: bool = false
	var asteroid_density: float = 0.0
	var is_asteroid_field: bool = String(desc.get("hazard_subtype", "")) == "asteroid_field"
	# Belt adjacency (GATED): the caller precomputes it (map applies the SYSTEM_BACKDROP_ENABLED gate).
	var belt_adjacent: bool = bool(desc.get("belt_adjacent", false))
	if is_asteroid_field:
		has_asteroids = true
		asteroid_density = BELT_DENSITY_SELF if SYSTEM_BACKDROP_ENABLED else 1.2
	elif belt_adjacent:
		has_asteroids = true
		asteroid_density = BELT_DENSITY_ADJACENT
		var px_adj: float = PLANET_MIN_PX + float(deco_rng.randi() % 3) * 8.0
		var frac_adj: float = (pos_x - 128.0) / max(1.0, row_end_x - 128.0)
		planet_type = _pick_planet_type(deco_rng, frac_adj)
		planet_idx = int(V3_TO_BACKDROP_PLANET_IDX.get(planet_type, 0))
		moons = _derive_moon_descriptors(id, px_adj, run_seed)
	else:
		var px: float = PLANET_MIN_PX + float(deco_rng.randi() % 3) * 8.0
		var frac: float = (pos_x - 128.0) / max(1.0, row_end_x - 128.0)
		planet_type = _pick_planet_type(deco_rng, frac)
		planet_idx = int(V3_TO_BACKDROP_PLANET_IDX.get(planet_type, 0))
		moons = _derive_moon_descriptors(id, px, run_seed)
	var sv: Dictionary = _get_star_variant(row_idx, run_seed, sectors_cleared)
	var base_type: int  = sv.base_type_idx
	var star_color: Color = EXOTIC_GLOW_COLORS[sv.exotic_idx] if sv.exotic_idx >= 0 else STAR_GLOW_COLORS[base_type]
	# Decorative nebula roll — separate salted rng so it doesn't shift the deco_rng sequence.
	var neb_rng := RandomNumberGenerator.new()
	neb_rng.seed = abs(hash(id) ^ run_seed ^ 0x4E42)
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
		# Planet PIXEL appearance seed — MUST equal _spawn_planet's psd, mixed with run_seed in lockstep.
		"planet_seed":      abs(hash(id) ^ run_seed),
		"has_asteroids":    has_asteroids,
		"asteroid_density": asteroid_density,
		"nebula_band":      nebula_band,
		"nebula_tint":      nebula_tint,
		"moons":            moons,
		"star_color":       star_color,
		"star_cool":        STAR_COOL[base_type],
		"row_idx":          row_idx,
		"poi_id":           id,
		"exotic_idx":       sv.exotic_idx,
		"has_binary":       sv.has_binary,
		"system":           _build_row_system(desc),
	}


# Boss descriptor: bosses live at fixed row endpoints with no planet/asteroid decoration of their
# own. `desc` carries {row, run_seed, sectors_cleared}.
static func compute_boss_stellar(desc: Dictionary) -> Dictionary:
	var row_idx: int = int(desc.get("row", 0))
	var run_seed: int = int(desc.get("run_seed", 0))
	var sectors_cleared: int = int(desc.get("sectors_cleared", 0))
	var sv: Dictionary = _get_star_variant(row_idx, run_seed, sectors_cleared)
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
		# Boss sits at the row's far-right endpoint (frac 1.0), so it views the star at maximum
		# distance -> small/distant. Star-only system; bosses have no planet of their own. The
		# per-row intrinsic star scale (item 4) multiplies in — a visual no-op here (the boss star
		# is already below the coordinator's dot threshold, rendered as a fixed 2px dot either way).
		"system":           ([{
			"kind":        "star",
			"planet_idx":  8,
			"planet_seed": abs(hash("star:%d:%d" % [row_idx, run_seed])),
			"frac":        0.0,
			"scale":       _row_star_scale(row_idx, run_seed) * _stage_scale(1.0, 0.0),
			"star_color":  star_color,
		}] if SYSTEM_BACKDROP_ENABLED else []),
	}


# Deterministic asteroid surface color for a given row. 85% realistic, 15% exotic. Seeded from
# row_idx + run_seed so the same row always gets the same color within a run.
static func asteroid_color_for_row(row_idx: int, run_seed: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("asteroid_color:%d:%d" % [row_idx, run_seed]))
	if rng.randf() < 0.15:
		return ASTEROID_EXOTIC_COLORS[rng.randi() % ASTEROID_EXOTIC_COLORS.size()]
	return ASTEROID_REALISTIC_COLORS[rng.randi() % ASTEROID_REALISTIC_COLORS.size()]


# ── Internals (verbatim moves of the map's private helpers) ──────────────────

# Deterministic exotic/binary state for a given row — keyed on run_seed + row.
static func _get_star_variant(row_idx: int, run_seed: int, sectors_cleared: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("star_variant:%d:%d" % [row_idx, run_seed]))
	var base_type_idx: int = rng.randi() % STAR_GLOW_COLORS.size()
	var pixel_seed: int = abs(rng.randi()) % 100000
	var exotic_chance: float = clampf(
		EXOTIC_STAR_CHANCE_BASE + EXOTIC_STAR_CHANCE_PER_SECTOR * sectors_cleared,
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


# Per-ROW intrinsic star size (WP11 item 4). Isolated rng (consumes no deco_rng) so planet picks
# stay byte-identical. Small-biased continuous curve — the same roll stellar_composer uses.
static func _row_star_scale(row_idx: int, run_seed: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash("star_scale:%d:%d" % [row_idx, run_seed]))
	return lerpf(0.03, 0.36, pow(rng.randf(), 1.4))


# Build the "star system" body list for the row containing the current node, viewed from the
# current node's frac. Bodies = the star (frac 0.0) + each POI whose obj_kind == PLANET, staged
# by distance |C - frac|. CRITICAL: the per-POI deco_rng MUST be consumed in the EXACT order the
# map render uses (randi()%3 obj_kind → randi()%3 px draw → _pick_planet_type) or planet_type
# diverges from the map even with a matching seed.
static func _build_row_system(desc: Dictionary) -> Array:
	if not SYSTEM_BACKDROP_ENABLED:
		return []
	var row_idx: int = int(desc.get("row", 0))
	var run_seed: int = int(desc.get("run_seed", 0))
	var sectors_cleared: int = int(desc.get("sectors_cleared", 0))
	var row_pois: Array = desc.get("row_pois", [])
	if row_pois.is_empty():
		return []
	var row_end_x: float = float(desc.get("row_end_x", 416.0))
	var span: float = max(1.0, row_end_x - 128.0)
	var current_frac: float = (float(desc.get("pos_x", 0.0)) - 128.0) / span

	var sv: Dictionary = _get_star_variant(row_idx, run_seed, sectors_cleared)
	var base_type: int = sv.base_type_idx
	var star_color: Color = EXOTIC_GLOW_COLORS[sv.exotic_idx] if sv.exotic_idx >= 0 else STAR_GLOW_COLORS[base_type]

	# Per-row intrinsic star scale (item 4) — multiplies the distance staging so gameplay stars get
	# the composer's size variety instead of always staging from the full BODY_SCALE_MAX ceiling.
	var intrinsic: float = _row_star_scale(row_idx, run_seed)

	var system: Array = []
	system.append({
		"kind":        "star",
		"planet_idx":  8,                # layer_planet PLANETS[8] = Star
		"planet_seed": abs(hash("star:%d:%d" % [row_idx, run_seed])),
		"frac":        0.0,
		"scale":       intrinsic * _stage_scale(current_frac, 0.0),
		"star_color":  star_color,
	})

	var planets: Array = []
	for p in row_pois:
		var p_id: String = String(p.get("id", ""))
		var deco_rng := RandomNumberGenerator.new()
		deco_rng.seed = abs(hash(p_id) ^ run_seed)
		var obj_kind: int = deco_rng.randi() % 3          # step 1 (matches map)
		if obj_kind != OBJ_PLANET:
			continue
		var _px_draw: int = deco_rng.randi() % 3           # step 2 (matches map)
		var p_frac: float = (float(p.get("pos_x", 0.0)) - 128.0) / span
		var ptype: int = _pick_planet_type(deco_rng, p_frac)  # step 3 (matches map)
		var p_idx: int = int(V3_TO_BACKDROP_PLANET_IDX.get(ptype, 0))
		planets.append({
			"kind":        "planet",
			"planet_idx":  p_idx,
			"planet_seed": abs(hash(p_id) ^ run_seed),
			"frac":        p_frac,
			"scale":       _stage_scale(current_frac, p_frac),
			"star_color":  star_color,
		})

	planets.sort_custom(func(a, b):
		return absf(current_frac - float(a.frac)) < absf(current_frac - float(b.frac)))
	for i in mini(planets.size(), SYSTEM_MAX_PLANETS):
		system.append(planets[i])
	return system


# Staging scale for a body at `body_frac` viewed from current node `c`.
static func _stage_scale(c: float, body_frac: float) -> float:
	var d: float = clampf(absf(c - body_frac), 0.0, 1.0)
	return BODY_SCALE_MAX * exp(-FALLOFF_K * d)


static func _pick_planet_type(rng: RandomNumberGenerator, frac: float) -> int:
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


# Stable per-POI moon RNG. Salt decoupled from the planet's randomize_colors / set_seed ordering.
static func _make_moon_rng(poi_id: String, run_seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = abs((hash(poi_id) ^ 0x9E3779B9) ^ run_seed)
	return r


# Deterministic moon list around a POI's planet — same formula as _spawn_moons.
static func _derive_moon_descriptors(poi_id: String, planet_px: float, run_seed: int) -> Array:
	var moon_rng := _make_moon_rng(poi_id, run_seed)
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
