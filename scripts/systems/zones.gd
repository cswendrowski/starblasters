class_name Zones
extends Object

# Combat Y-bands for firing readability (bridge §1.8-1.9). Y grows downward in the
# 270-tall playfield. Enemies hold fire in the ENTRY band (just spawned, near the
# top), fire in the ENGAGEMENT band, and cease fire in the DEPARTURE band (low /
# committed to leaving) — which keeps them from plinking the player at point-blank.
# Pure static geometry; pairs with the bottom safe-zone in lane_system_spec §1.9.

const ENTRY_END: float = 40.0          # at/above this Y = entry band (hold fire)
const DEPARTURE_START: float = 195.0   # at/below this Y = departure band (cease fire)


static func in_engagement(y: float) -> bool:
	return y >= ENTRY_END and y < DEPARTURE_START


# Normalized progress through the engagement band: 0.0 at the entry edge (top),
# 1.0 at the departure edge (bottom), clamped. Path-phase firing (enemy_core
# fire_path_phases) fires when this crosses configured fractions, so a descending
# enemy shoots at fixed points in its pass instead of on a random timer.
static func band_progress(y: float) -> float:
	return clampf((y - ENTRY_END) / (DEPARTURE_START - ENTRY_END), 0.0, 1.0)


# --- Named depth bands (locomotion refactor 2026-06-19) ---
# WHERE a depth-aware pattern acts within the engagement band, as band_progress (0 = top/shallow,
# 1 = bottom/deep): where loiter/drift HOLD, where hook/curve/cut TURN OFF, where the crosser
# CROSSES. The NAME is editor/codex sugar; the fraction is the source of truth. "high" = shallow
# (acts near the top, e.g. loiter hover_y~50), "low" = deep (near the bottom). Tunable in the
# Enemy Bench; behaviour-preserving migration emits exact per-enemy fractions, not preset names.
const DEPTH_BANDS := {
	"high": 0.065,   # shallow — near the top (Y~50, the old loiter/drift_high hold)
	"mid": 0.323,    # Y~90 (old *_mid)
	"low": 0.58,     # deep — near the bottom (Y~130, old *_low)
}


# Screen Y for a band_progress fraction (inverse of band_progress()).
static func y_for_progress(bp: float) -> float:
	return ENTRY_END + clampf(bp, 0.0, 1.0) * (DEPARTURE_START - ENTRY_END)


# Resolve a depth spec — a preset name ("high"/"mid"/"low"), a numeric band_progress (String or
# number), or "" — to a band_progress. Returns `fallback` when empty/unrecognized.
static func depth_to_bp(spec, fallback: float) -> float:
	if spec is String:
		var s: String = String(spec)
		if DEPTH_BANDS.has(s):
			return float(DEPTH_BANDS[s])
		if s != "" and s.is_valid_float():
			return clampf(float(s), 0.0, 1.0)
		return fallback
	if spec is float or spec is int:
		return clampf(float(spec), 0.0, 1.0)
	return fallback


# "name (≈bp)" label for a band_progress, naming the nearest preset.
static func depth_label(bp: float) -> String:
	var best: String = ""
	var best_d: float = 1e9
	for k in DEPTH_BANDS:
		var d: float = absf(float(DEPTH_BANDS[k]) - bp)
		if d < best_d:
			best_d = d
			best = String(k)
	return "%s (≈%.2f)" % [best, bp]
