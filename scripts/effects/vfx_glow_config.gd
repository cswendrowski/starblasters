class_name VfxGlowConfig
extends RefCounted

# Per-category HDR-bright modulate multipliers — how hard each VFX class blooms through the
# WorldEnvironment (Roman 2026-06-21). Tuned in the Shader Lab "Glow" tab + the Combat VFX Lab,
# exported via Copy GDScript, then wired into production.
#
# Model: a multiplier M for a category means `node.modulate = Color(M, M, M)` — a uniform HDR
# brightness boost (the sprite keeps its own hue). M above the combat env `glow_hdr_threshold`
# (1.5) makes the node bloom; M = 1.0 is neutral (no bloom). The current values live in a static
# dict shared across the labs in a session, and persist to user://tuners/vfx_glow.json.

const CATEGORIES := ["bullets", "engines", "lasers", "explosions", "particles"]
# Canonical shipped values — Roman's 2026-06-23 tune. Production reads these (prod_hdr), the dev
# labs tune a separate `_current` copy for live preview. (Backdrop star/planet glow is NOT here —
# it's a per-LAYER CanvasModulate multiplier, see layer_base.glow_mult + the Parallax Tuner.)
const DEFAULTS := {
	"bullets": 1.75,
	"engines": 2.30,
	"lasers": 2.30,
	"explosions": 2.00,
	"particles": 2.30,
}
const SAVE_PATH := "user://tuners/vfx_glow.json"
const SLIDER_MIN := 1.0
const SLIDER_MAX := 3.0

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
				for c in CATEGORIES:
					if (d as Dictionary).has(c):
						_current[c] = float(d[c])


static func get_mult(cat: String) -> float:
	ensure_loaded()
	return float(_current.get(cat, 1.0))


static func set_mult(cat: String, m: float) -> void:
	ensure_loaded()
	_current[cat] = m


# Convenience: the uniform HDR modulate Color for a category (tuner-live value).
static func hdr(cat: String) -> Color:
	var m := get_mult(cat)
	return Color(m, m, m, 1.0)


# PRODUCTION accessor — reads the canonical DEFAULTS only (stable shipped values), independent of
# the dev tuner's _current / user://json. This is what gameplay VFX use.
static func prod_mult(cat: String) -> float:
	return float(DEFAULTS.get(cat, 1.0))

static func prod_hdr(cat: String) -> Color:
	var m := prod_mult(cat)
	return Color(m, m, m, 1.0)


static func values() -> Dictionary:
	ensure_loaded()
	return _current.duplicate()


static func save() -> void:
	ensure_loaded()
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_current, "\t"))
		f.close()


# Paste-ready export (the tuner contract).
static func snippet() -> String:
	ensure_loaded()
	var t := "# VFX glow — per-category HDR-bright modulate multipliers (Shader Lab / Combat VFX Lab).\n"
	t += "# Apply as: node.modulate = Color(M, M, M) so the WorldEnvironment bloom lights it.\n"
	t += "const VFX_GLOW := {\n"
	for c in CATEGORIES:
		t += "\t\"%s\": %.2f,\n" % [c, get_mult(c)]
	t += "}\n"
	return t
