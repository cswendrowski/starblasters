class_name PlanetGlowConfig
extends RefCounted

# Per-PLANET-TYPE HDR glow multipliers (Roman 2026-06-23). Keeps the WorldEnvironment threshold at
# 1.5 and does NOT edit the planet kit — instead it scales each body's PALETTE through the kit's own
# get_colors()/set_colors() so that type's brightest colours clear 1.5 and bloom in their OWN hue.
#
# Why the palette and not modulate: the PixelPlanet shaders overwrite COLOR, so a CanvasItem modulate
# is ignored. set_colors() feeds the uniforms the shader actually reads. M = 1.0 is neutral (no boost).
#
# Tuned per-type in the Parallax Tuner's "Planet Glow" tab; production reads DEFAULTS (prod_mult).
# Keyed by the layer_planet.PLANETS index (0..10).

const NAMES := {
	0: "LavaWorld", 1: "IceWorld", 2: "DryTerran", 3: "GasPlanet", 4: "NoAtmosphere",
	5: "LandMasses", 6: "BlackHole", 7: "Galaxy", 8: "Star", 9: "GasPlanetLayers", 10: "Rivers",
}
# Canonical shipped values — Roman's 2026-06-23 tune (Parallax Tuner → Planet Glow tab). Production
# reads these (prod_mult); each is the palette multiplier that makes that planet bloom at threshold 1.5.
const DEFAULTS := {
	0: 1.50,   # LavaWorld
	1: 2.00,   # IceWorld
	2: 1.45,   # DryTerran
	3: 1.50,   # GasPlanet
	4: 2.00,   # NoAtmosphere
	5: 1.75,   # LandMasses
	6: 3.00,   # BlackHole
	7: 2.75,   # Galaxy
	8: 2.00,   # Star
	9: 1.80,   # GasPlanetLayers
	10: 2.00,  # Rivers
}
const SAVE_PATH := "user://tuners/planet_glow.json"
const SLIDER_MIN := 1.0
const SLIDER_MAX := 4.0

static var _current: Dictionary = {}


static func ensure_loaded() -> void:
	if not _current.is_empty():
		return
	_current = DEFAULTS.duplicate()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if d is Dictionary:
				for k in (d as Dictionary):
					_current[int(k)] = float(d[k])


static func get_mult(idx: int) -> float:
	ensure_loaded()
	return float(_current.get(idx, 1.0))


static func set_mult(idx: int, m: float) -> void:
	ensure_loaded()
	_current[idx] = m


# PRODUCTION accessor — canonical DEFAULTS only (stable shipped values), ignores the dev tuner's
# _current / json. This is what layer_planet applies at spawn.
static func prod_mult(idx: int) -> float:
	return float(DEFAULTS.get(idx, 1.0))


static func save() -> void:
	ensure_loaded()
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_current, "\t"))
		f.close()


# Paste-ready export — drop into PlanetGlowConfig.DEFAULTS.
static func snippet() -> String:
	ensure_loaded()
	var t := "# Per-planet HDR glow (palette x M -> blooms in own hue at threshold 1.5). Into PlanetGlowConfig.DEFAULTS.\n"
	t += "const PLANET_GLOW := {\n"
	for idx in range(NAMES.size()):
		t += "\t%d: %.2f,  # %s\n" % [idx, get_mult(idx), String(NAMES.get(idx, "?"))]
	t += "}\n"
	return t
