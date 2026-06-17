# Random stellar composer (Roman 2026-06-17).
#
# The backdrop coordinator consumes a `current_stellar` dict that the SECTOR MAP authors per node
# (sector_map_v3._compute_poi_stellar + _compute_row_system). Any context WITHOUT sector-map data —
# the main menu, dev tools, the parallax tuner, signal events — previously fell through to a bare
# single white-washed planet over a fixed-seed starfield: no system staging, no asteroids, no nebula,
# no coloured star glow. That is the "sparse / same-every-time" regression.
#
# This is the missing RANDOM-GENERATION FALLBACK: compose() produces a faithful, varied stellar dict
# (same shape + palettes as the sector map) from a single rng, so those contexts get the full live
# composition styles. The coordinator calls it when current_stellar is empty; the tuner calls it
# directly with a forced `kind` so its picker can preview each style.
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
static func compose(rng: RandomNumberGenerator, opts: Dictionary = {}) -> Dictionary:
	var star_color: Color
	if rng.randf() < EXOTIC_CHANCE:
		star_color = EXOTIC_GLOW_COLORS[rng.randi() % EXOTIC_GLOW_COLORS.size()]
	else:
		star_color = STAR_GLOW_COLORS[rng.randi() % STAR_GLOW_COLORS.size()]

	var kind: String = String(opts.get("kind", ""))
	if kind == "":
		kind = _weighted_kind(rng)

	var st := {
		"planet_idx": rng.randi() % 8,
		"planet_seed": rng.randi(),
		"star_color": star_color,
		"has_asteroids": false,
		"asteroid_density": 0.0,
		"nebula_band": "",
		"nebula_tint": Color.WHITE,
		"moons": [],
		"system": [],
	}

	match kind:
		"system":
			st["system"] = _build_system(rng, star_color)
		"planet":
			st["moons"] = _build_moons(rng)
		"asteroid":
			st["has_asteroids"] = true
			st["asteroid_density"] = rng.randf_range(1.4, 2.4)
			# An asteroid belt still wants a couple of distant bodies behind it.
			if rng.randf() < 0.6:
				st["system"] = _build_system(rng, star_color)
		"nebula":
			var nb: Dictionary = NEBULA_BANDS[rng.randi() % NEBULA_BANDS.size()]
			st["nebula_band"] = String(nb["name"])
			st["nebula_tint"] = nb["tint"]
			st["system"] = _build_system(rng, star_color)

	# Independent overlays, like real nodes layer a belt-edge or a nebula onto a planet view.
	if (kind == "system" or kind == "planet"):
		if st["nebula_band"] == "" and rng.randf() < NEBULA_OVERLAY_CHANCE:
			var nb2: Dictionary = NEBULA_BANDS[rng.randi() % NEBULA_BANDS.size()]
			st["nebula_band"] = String(nb2["name"])
			st["nebula_tint"] = nb2["tint"]
		if not st["has_asteroids"] and rng.randf() < ASTEROID_OVERLAY_CHANCE:
			st["has_asteroids"] = true
			st["asteroid_density"] = rng.randf_range(0.8, 1.6)
	return st


static func _weighted_kind(rng: RandomNumberGenerator) -> String:
	var r: float = rng.randf()
	var acc: float = 0.0
	for k in KIND_WEIGHTS:
		acc += float(KIND_WEIGHTS[k])
		if r <= acc:
			return String(k)
	return "system"


# A staged star-system: a star (planet_idx 8) at frac 0 plus 2–4 planets spread across the band,
# with ONE "hero" body large (fills the upper screen) and the rest small/distant. Matches the entry
# shape _spawn_system reads (kind/planet_idx/planet_seed/frac/scale/star_color).
static func _build_system(rng: RandomNumberGenerator, star_color: Color) -> Array:
	var n: int = rng.randi_range(3, 5)
	var hero: int = rng.randi_range(0, n - 1)   # the big foreground body
	var sys: Array = []
	for i in n:
		var is_star: bool = i == 0
		var scale_f: float
		if i == hero:
			scale_f = rng.randf_range(0.68, 0.95)
		else:
			scale_f = rng.randf_range(0.08, 0.40)
		sys.append({
			"kind": "star" if is_star else "planet",
			"planet_idx": 8 if is_star else (rng.randi() % 8),
			"planet_seed": rng.randi(),
			"frac": float(i) / float(maxi(1, n - 1)),
			"scale": scale_f,
			"star_color": star_color,
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
