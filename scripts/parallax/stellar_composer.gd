# Random stellar composer (Roman 2026-06-17).
#
# The backdrop coordinator consumes a `current_stellar` dict that the SECTOR MAP authors per node
# (sector_map_v3._compute_poi_stellar + _compute_row_system). Any context WITHOUT sector-map data —
# the main menu, dev tools, the parallax tuner, signal events — previously fell through to a bare
# single white-washed planet over a fixed-seed starfield: no system staging, no asteroids, no nebula,
# no coloured star glow. That is the "sparse / same-every-time" regression.
#
# This is the RANDOM-GENERATION FALLBACK. compose() produces a faithful, varied stellar dict (same
# shape as the sector map) from a single rng, so those contexts get the full live composition styles.
#
# WIRED 2026-07-08 (WP3): backdrop_coordinator preloads this const and, when its
# `use_composer_fallback` export is ON and `current_stellar` is empty, calls compose(rng, opts) in
# _populate — driven by the coordinator's already-seeded rng so regenerate(seed) stays deterministic.
# `opts.kind` forces a composition (showcase picker: system/planet/asteroid/nebula). The flag ships
# OFF, so production menus keep the bare fallback until a later one-line flip. compose() also attaches
# a `palette` struct (see author_palette) and stamps the rolled `kind`.
#
# NOT class_name (preload-const referenced) to keep headless --script class-cache safety.

# Star glow palette — mirrors sector_map_v3.STAR_GLOW_COLORS (blue / amber / red) + the exotics.
const STAR_GLOW_COLORS := [
	Color(0.45, 0.65, 1.00), Color(1.00, 0.72, 0.18), Color(1.00, 0.26, 0.07),
]
const EXOTIC_GLOW_COLORS := [
	Color(0.70, 0.22, 0.95), Color(0.18, 0.90, 0.35), Color(1.00, 0.25, 0.65),
]
const NEBULA_BANDS := [
	{"name": "nebula_amber",   "tint": Color(0.95, 0.78, 0.50)},
	{"name": "nebula_cyan",    "tint": Color(0.55, 0.78, 1.00)},
	{"name": "nebula_magenta", "tint": Color(0.85, 0.58, 1.00)},
	{"name": "nebula_green",   "tint": Color(0.62, 0.95, 0.68)},
	{"name": "nebula_crimson", "tint": Color(1.00, 0.55, 0.58)},
]
const EXOTIC_CHANCE := 0.14
const NEBULA_OVERLAY_CHANCE := 0.30   # extra nebula on planet/system kinds, for variety
const ASTEROID_OVERLAY_CHANCE := 0.22 # sprinkle of drifting rocks on planet/system kinds

# Composition kinds + their unforced weights (sum 1.0). "system" dominates — the live look.
const KIND_WEIGHTS := {"system": 0.45, "planet": 0.25, "asteroid": 0.16, "nebula": 0.14}


# Compose a random stellar dict. `opts.kind` forces a composition ("system"/"planet"/"asteroid"/
# "nebula"); omit or "" for a weighted-random pick. All randomness comes from `rng` so callers
# control determinism / variation.
# Backdrop planet indices the composer may pick (layer_planet.PLANETS). Excludes 8 = Star; includes
# 9 = GasPlanetLayers (ringed) + 10 = Rivers so those appear in random/composed backdrops.
const PLANET_PICK := [0, 1, 2, 3, 4, 5, 6, 7, 9, 10]

static func compose(rng: RandomNumberGenerator, opts: Dictionary = {}) -> Dictionary:
	var star_color: Color
	if rng.randf() < EXOTIC_CHANCE:
		star_color = EXOTIC_GLOW_COLORS[rng.randi() % EXOTIC_GLOW_COLORS.size()]
	else:
		star_color = STAR_GLOW_COLORS[rng.randi() % STAR_GLOW_COLORS.size()]

	var kind: String = String(opts.get("kind", ""))
	if kind == "":
		kind = _weighted_kind(rng)

	# Star SIZE roll (item 5, astral size variation — Roman 2026-07-08 round 2). SIZE-first,
	# mode-derived: the old mode-first roll was bimodal — distant 0.06-0.14 (20-46px) vs near
	# 0.75-1.2, which ALWAYS saturated the 120px clamp, so stars were either tiny or exactly
	# 120 with nothing between. One continuous small-biased roll now covers the whole band
	# (scale 0.03-0.36 ≈ 10-119px at the 330 ceiling — under the layer's star_clamp_max);
	# the mode label (planet sizing, depth weighting, lab status) derives from the result
	# (< ~48px reads "distant"). Glow boost is continuous too: the smaller the star, the
	# harder it over-boosts so a 10px point still blooms brilliant.
	var star_scale: float = lerpf(0.03, 0.36, pow(rng.randf(), 1.4))
	var star_mode: String = "distant_star" if star_scale < 0.145 else "near_star"

	var st := {
		"planet_idx": PLANET_PICK[rng.randi() % PLANET_PICK.size()],
		"planet_seed": rng.randi(),
		"star_color": star_color,
		"star_mode": star_mode,
		"star_scale": star_scale,
		"has_asteroids": false,
		"asteroid_density": 0.0,
		"nebula_band": "",
		"nebula_tint": Color.WHITE,
		"moons": [],
		"system": [],
	}

	match kind:
		"system":
			st["system"] = _build_system(rng, star_color, star_mode, star_scale)
		"planet":
			st["moons"] = _build_moons(rng)
			# Widen the single-planet size spread well past planet_size_variance (0.35). The
			# coordinator multiplies actual_size by this when present (sector-map path untouched).
			st["size_scale"] = rng.randf_range(0.55, 1.7)
		"asteroid":
			st["has_asteroids"] = true
			st["asteroid_density"] = rng.randf_range(1.4, 2.4)
			# An asteroid belt still wants a couple of distant bodies behind it.
			if rng.randf() < 0.6:
				st["system"] = _build_system(rng, star_color, star_mode, star_scale)
		"nebula":
			var nb: Dictionary = NEBULA_BANDS[rng.randi() % NEBULA_BANDS.size()]
			st["nebula_band"] = String(nb["name"])
			st["nebula_tint"] = nb["tint"]
			st["system"] = _build_system(rng, star_color, star_mode, star_scale)

	# Independent overlays, like real nodes layer a belt-edge or a nebula onto a planet view.
	if (kind == "system" or kind == "planet"):
		if st["nebula_band"] == "" and rng.randf() < NEBULA_OVERLAY_CHANCE:
			var nb2: Dictionary = NEBULA_BANDS[rng.randi() % NEBULA_BANDS.size()]
			st["nebula_band"] = String(nb2["name"])
			st["nebula_tint"] = nb2["tint"]
		if not st["has_asteroids"] and rng.randf() < ASTEROID_OVERLAY_CHANCE:
			st["has_asteroids"] = true
			st["asteroid_density"] = rng.randf_range(0.8, 1.6)

	# Stamp the rolled kind (status readout) + derive the palette FROM the composition.
	st["kind"] = kind
	st["palette"] = _palette_for(star_color, String(st["nebula_band"]), st["nebula_tint"])
	return st


# ── Palette struct (WP3) ─────────────────────────────────────────────────────
# Neutral rock-grey the asteroid/dust hue biases toward when there is no nebula band
# (mirrors layer_stellar's default asteroid_tint).
const DUST_NEUTRAL := Color(0.9, 0.88, 0.85)


# Derive a {key, dust, deep} palette FROM an already-composed OR sector-map stellar dict.
# Static so the coordinator can apply it to sector-map dicts that carry no palette key.
#   key  = star_color (the light-source tint).
#   dust = the nebula band tint when a band is present (they ARE the same hue by design),
#          else key pulled 60% toward the neutral rock-grey so the dust/asteroid hue reads
#          as a subdued, desaturated cousin of the star light — never a pure saturated wash.
#   deep = key desaturated 60% then scaled to ~0.1 luma — a dark background bias in the
#          star's hue family.
static func author_palette(stellar: Dictionary) -> Dictionary:
	var key: Color = stellar.get("star_color", Color.WHITE)
	var band: String = String(stellar.get("nebula_band", ""))
	var band_tint: Color = stellar.get("nebula_tint", Color.WHITE)
	return _palette_for(key, band, band_tint)


static func _palette_for(key: Color, band: String, band_tint: Color) -> Dictionary:
	var dust: Color
	if band != "":
		dust = Color(band_tint.r, band_tint.g, band_tint.b, 1.0)
	else:
		dust = key.lerp(DUST_NEUTRAL, 0.6)
	return {
		"key": Color(key.r, key.g, key.b, 1.0),
		"dust": dust,
		"deep": _derive_deep(key),
	}


static func _derive_deep(key: Color) -> Color:
	var lum: float = key.r * 0.299 + key.g * 0.587 + key.b * 0.114
	var desat: Color = key.lerp(Color(lum, lum, lum), 0.6)
	var cur: float = desat.r * 0.299 + desat.g * 0.587 + desat.b * 0.114
	var s: float = 0.1 / maxf(cur, 0.001)   # scale to ~0.1 target luma
	return Color(
		clampf(desat.r * s, 0.0, 1.0),
		clampf(desat.g * s, 0.0, 1.0),
		clampf(desat.b * s, 0.0, 1.0),
		1.0,
	)


static func _weighted_kind(rng: RandomNumberGenerator) -> String:
	var r: float = rng.randf()
	var acc: float = 0.0
	for k in KIND_WEIGHTS:
		acc += float(KIND_WEIGHTS[k])
		if r <= acc:
			return String(k)
	return "system"


# A staged star-system: a star (planet_idx 8) at frac 0 plus 2–4 planets spread across the band.
# The star's scale is the CONTINUOUS size rolled in compose() (star_scale, 0.03–0.36); its
# glow_boost scales inversely with size (small = brilliant point, big = today's glow). The
# mode label still sets the planet size band:
#   distant_star → hero planet large (0.70–0.95), rest 0.15–0.50.
#   near_star    → planets recede (0.05–0.45 — widened for mid-size coverage).
# The hero is chosen among the PLANETS (never the star) so the star always follows its roll.
# Matches the entry shape _spawn_system reads (kind/planet_idx/planet_seed/frac/scale/star_color/glow_boost).
static func _build_system(rng: RandomNumberGenerator, star_color: Color, star_mode: String = "distant_star", star_scale: float = 0.1) -> Array:
	var n: int = rng.randi_range(3, 5)
	var hero: int = rng.randi_range(1, n - 1)   # big foreground PLANET (never the star)
	var sys: Array = []
	for i in n:
		var is_star: bool = i == 0
		var scale_f: float
		var glow_boost: float = 1.0
		if is_star:
			scale_f = star_scale
			# Continuous brightness compensation: 10px point → ~1.9×, 119px → 1.0×.
			var t: float = clampf((star_scale - 0.03) / 0.33, 0.0, 1.0)
			glow_boost = lerpf(1.9, 1.0, t)
		elif star_mode == "distant_star":
			scale_f = rng.randf_range(0.70, 0.95) if i == hero else rng.randf_range(0.15, 0.50)
		else:
			scale_f = rng.randf_range(0.05, 0.45)   # near_star: planets recede
		sys.append({
			"kind": "star" if is_star else "planet",
			"planet_idx": 8 if is_star else PLANET_PICK[rng.randi() % PLANET_PICK.size()],
			"planet_seed": rng.randi(),
			"frac": float(i) / float(maxi(1, n - 1)),
			"scale": scale_f,
			"star_color": star_color,
			"glow_boost": glow_boost,
		})
	return sys


# Moon descriptors for the single-planet path (layer_planet.attach_moons). Count biased toward 0–2.
static func _build_moons(rng: RandomNumberGenerator) -> Array:
	var count: int = int(rng.randf() * rng.randf() * 4.0)
	var moons: Array = []
	for i in count:
		moons.append({
			"radius": rng.randi_range(2, 5),
			"color": Color(rng.randf_range(0.55, 0.9), rng.randf_range(0.55, 0.9), rng.randf_range(0.65, 1.0)),
			"phase": rng.randf() * TAU,
			"rx": rng.randf_range(22.0, 46.0),
			"ry": rng.randf_range(8.0, 20.0),
			"speed": rng.randf_range(0.2, 0.6),
		})
	return moons
