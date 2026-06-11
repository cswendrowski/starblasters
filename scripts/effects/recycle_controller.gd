extends RefCounted

# RecycleController — Pillar 2, step 2 (Roman worklist #33; spec
# docs/recycling_system_pillar2_2026-06-04.md). Preload-based, NOT class_name (a
# fresh global class_name didn't resolve in headless `-s` runs during Pillar 1).
#
# SCOPE LANDED HERE (deliberately conservative — Roman is away, and the spec flags
# the deep refactor as "only playtesting can clear it"):
#   * Single owner of the fly-back recycle TIMING + LOOK constants, loaded from the
#     RecycleTuner's JSON so Roman can dial recycle feel live.
#   * Defaults are BYTE-IDENTICAL to enemy_core._start_cycle's old magic numbers, so
#     with no tuner file present the roster behaves exactly as before — zero
#     regression surface to clear by playtest.
#
# DEFERRED for Roman's playtest pass (per the spec's "build in this order" + risk
# notes): generalizing edge-detection out of enemy_base, the NONE-mode opt-in path,
# enemy_base delegating its whole _offscreen_cleanup_check, and swapping the modulate
# ghost for MidDepthPresentation's shader tint. Those touch the whole roster and
# can't be headless-verified.

const CONFIG_PATH := "user://tuners/recycle.json"

# Defaults == the values enemy_core._start_cycle hardcoded before this controller.
const DEFAULTS := {
	"hold_min": 0.4,        # pre-cycle hold, randf_range low (s)
	"hold_max": 0.9,        # pre-cycle hold, randf_range high (s)
	"entry_inset": 22.0,    # px inset from the playfield band edges for re-entry x
	"fly_scale": 0.45,      # ghost-pass scale multiplier
	"fly_time": 1.8,        # fly-back tween duration (s)
	"fly_target_y": -20.0,  # tween destination y (px)
	# Ghost tint (faux-mid-depth). Stored as 4 floats so it round-trips through JSON.
	"tint_r": 0.75, "tint_g": 0.85, "tint_b": 1.0, "tint_a": 0.55,
}

# Cached so the hot recycle path doesn't hit disk every fly-back. Call
# invalidate() (the tuner does on save) to force a reload.
static var _cache: Dictionary = {}
static var _loaded: bool = false


# Returns the merged config (disk values over DEFAULTS). Missing/!malformed file →
# pure DEFAULTS. Cached after first read.
static func config() -> Dictionary:
	if _loaded:
		return _cache
	_cache = DEFAULTS.duplicate()
	if FileAccess.file_exists(CONFIG_PATH):
		var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				for k in DEFAULTS.keys():
					if parsed.has(k):
						_cache[k] = float(parsed[k])
	_loaded = true
	return _cache


static func invalidate() -> void:
	_loaded = false
	_cache = {}


# The ghost tint as a Color, assembled from the stored channels.
static func tint(cfg: Dictionary) -> Color:
	return Color(
		float(cfg.get("tint_r", DEFAULTS.tint_r)),
		float(cfg.get("tint_g", DEFAULTS.tint_g)),
		float(cfg.get("tint_b", DEFAULTS.tint_b)),
		float(cfg.get("tint_a", DEFAULTS.tint_a)))


# Persist a config dict to disk + invalidate the cache (used by the tuner).
static func save(cfg: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		return false
	var out := {}
	for k in DEFAULTS.keys():
		out[k] = float(cfg.get(k, DEFAULTS[k]))
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	invalidate()
	return true
