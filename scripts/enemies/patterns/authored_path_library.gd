extends RefCounted
class_name AuthoredPathLibrary

# Registry of hand-authored flight paths (2026-07-06). Each entry is a path definition dict in the
# same NORMALIZED authoring shape the Path Editor (scripts/dev/path_editor.gd) emits with its
# "Copy GDScript" button. build(name) bakes one into a live AuthoredPath movement Resource.
#
# Path definition schema (authoring space — resolution-independent, survives playfield/lane changes):
#   {
#     "name":        String,             # unique key (also the movement key, "path_<name>")
#     "waypoints":   Array[[x, y], ...], # x = LANE units 0..6 (fractional; relative = offset from
#                                        #     spawn lane). y = BAND PROGRESS 0..1 (0 top, 1 bottom).
#     "speed_scale": float,              # × chassis move_speed, snapped to a Clarity rung at runtime
#     "relative":    bool,               # x are spawn-lane offsets (true) or absolute lanes (false)
#     "smoothing":   float,              # 0 = polyline; 0..1 = Catmull-Rom corner rounding
#     "mirror":      bool,               # author-time default L<->R flip (director overrides live)
#     "dwell":       Array[float],       # optional per-waypoint hold seconds (parallel to waypoints)
#   }
#
# WIRING into production: enemy_roster.make_movement resolves "path_" keys through is_path_key()/
# resolve_key() (hooked 2026-07-06, just before its match). The Path Editor previews by building
# AuthoredPath directly (dogfooding the runtime), so it needs no roster wiring.

const AuthoredPath := preload("res://scripts/enemies/patterns/authored_path.gd")

# Movement-key prefix. A key like "path_s_weave" resolves to DATA["s_weave"].
const KEY_PREFIX := "path_"

# User-override source (Path Editor Save, 2026-07-06). An edited copy of a path stored here SHADOWS
# the baked DATA entry of the same name at resolve time — lets Roman iterate a path in the editor and
# have it take effect in-game INSTANTLY without a code edit (Copy GDScript re-bakes it permanently).
const OVERRIDE_PATH := "user://tuners/enemy_paths.json"


# name -> path definition. Author these in the Path Editor and paste its Copy GDScript output here.
# Baked from the Path Editor (user://tuners/enemy_paths.json) on 2026-07-06. Entries here are the
# PERMANENT production source; the four starters (s_weave/corner_hook/loop_exit/zigzag_rush) are
# Roman's edited replacements of the originals. Three scratch entries (default-named path_4/6/8,
# blank straight-down lines) were left out. Non-monotone paths (loops) fire on cadence, not path-phase.
const DATA := {
	# Stepped S-weave - lateral shifts held at fixed depths then a final drop. Absolute lanes, mirror-paired.
	"s_weave": {
		"name": "s_weave",
		"relative": false,
		"speed_scale": 1.0,
		"smoothing": 1.0,
		"mirror": true,
		"waypoints": [[0.0, 0.0], [0.0, 0.59], [3.0, 0.59], [3.0, 0.3], [6.0, 0.3], [6.0, 0.89]],
		"dwell": [],
	},
	# Corner-hook dive - down the near-left column, hook across, then climb back out top-right. Absolute lanes.
	"corner_hook": {
		"name": "corner_hook",
		"relative": false,
		"speed_scale": 1.0,
		"smoothing": 0.6,
		"mirror": false,
		"waypoints": [[0.47, 0.0], [0.49, 0.47], [1.5, 0.62], [4.92, 0.61], [5.55, 0.34], [5.53, 0.0]],
		"dwell": [],
	},
	# Loop-and-exit - carve a side loop mid-descent then resume and exit. NON-MONOTONE y (cadence fire).
	"loop_exit": {
		"name": "loop_exit",
		"relative": false,
		"speed_scale": 1.0,
		"smoothing": 1.0,
		"mirror": false,
		"waypoints": [[3.0, 0.0], [3.0, 0.59], [6.0, 0.59], [6.0, 0.3], [3.0, 0.3], [2.0, 0.59], [3.0, 1.0]],
		"dwell": [],
	},
	# Zigzag rush - sharp alternating cuts down the band (polyline, no rounding). Lane-relative.
	"zigzag_rush": {
		"name": "zigzag_rush",
		"relative": true,
		"speed_scale": 1.0,
		"smoothing": 0.0,
		"mirror": false,
		"waypoints": [[0.0, 0.0], [0.0, 0.15], [-1.0, 0.44], [1.0, 0.59], [0.0, 0.89], [0.0, 1.0]],
		"dwell": [],
	},
	# Diagonal dive - a clean relative slant across two lanes on the way down. Monotone (path-phase).
	"dive_diagonal": {
		"name": "dive_diagonal",
		"relative": true,
		"speed_scale": 1.0,
		"smoothing": 1.0,
		"mirror": false,
		"waypoints": [[3.0, 0.0], [2.0, 0.15], [-2.0, 0.74], [-3.0, 0.89], [-3.0, 1.0]],
		"dwell": [],
	},
	# Back-and-forth weave - gentle relative side-to-side, smoothed. Monotone descent (path-phase).
	"back_and_forth": {
		"name": "back_and_forth",
		"relative": true,
		"speed_scale": 1.0,
		"smoothing": 0.5,
		"mirror": false,
		"waypoints": [[0.0, 0.0], [0.0, 0.15], [1.0, 0.15], [1.0, 0.3], [-1.0, 0.3], [-1.0, 0.44], [1.0, 0.44], [1.0, 0.59], [-1.0, 0.59], [-1.0, 0.74], [0.0, 0.74], [0.0, 1.0]],
		"dwell": [],
	},
	# Wide back-and-forth - same weave, larger lateral throw. Monotone descent (path-phase).
	"back_and_forth_wide": {
		"name": "back_and_forth_wide",
		"relative": true,
		"speed_scale": 1.0,
		"smoothing": 0.5,
		"mirror": false,
		"waypoints": [[0.0, 0.0], [0.0, 0.15], [3.0, 0.15], [3.0, 0.3], [-3.0, 0.3], [-3.0, 0.44], [3.0, 0.44], [3.0, 0.59], [-3.0, 0.59], [-3.0, 0.74], [0.0, 0.74], [0.0, 1.0]],
		"dwell": [],
	},
	# Skirmish loop - descend then orbit a lane cluster (imported from the skirmish_loop pattern). NON-MONOTONE.
	"skirmish_loop": {
		"name": "skirmish_loop",
		"relative": false,
		"speed_scale": 1.0,
		"smoothing": 1.0,
		"mirror": false,
		"waypoints": [[3.0, 0.0], [3.0, 0.3], [3.0, 0.59], [5.0, 0.59], [5.0, 0.3], [3.0, 0.15], [1.0, 0.3], [1.0, 0.59], [3.0, 0.74], [3.0, 0.89], [3.0, 1.0]],
		"dwell": [],
	},
	# Skirmish figure-8 - twin looping orbit (imported from skirmish_figure8). NON-MONOTONE (cadence fire).
	"skirmish_figure8": {
		"name": "skirmish_figure8",
		"relative": false,
		"speed_scale": 1.0,
		"smoothing": 1.0,
		"mirror": false,
		"waypoints": [[3.0, 0.0], [3.01, 0.22], [4.0, 0.59], [6.0, 0.59], [6.0, 0.3], [4.0, 0.3], [2.0, 0.59], [0.0, 0.59], [0.0, 0.3], [2.0, 0.3], [3.0, 0.74], [3.0, 1.0]],
		"dwell": [],
	},
}


# --- User-override cache (lazy, one file read per session) -----------------------------------------
# resolve_key/build run at ENEMY SPAWN TIME, so the override JSON must NOT be re-read per spawn. It is
# loaded ONCE on first access and cached here (name -> def dict). `_overrides_loaded` guards the read
# so an ABSENT file (fresh install / headless / no tuners dir) is a cheap no-op, cached as "checked,
# empty". A dev tool can force a re-read with reload_overrides() (the Path Editor's "Reload
# overrides" button) after Saving; production never calls it.
static var _overrides: Dictionary = {}
static var _overrides_loaded: bool = false


# PRECEDENCE (resolve order for a given path name):
#   1. user://tuners/enemy_paths.json entry of that name   ← SHADOWS the baked DATA (edited copy)
#   2. baked DATA[name]                                     ← the committed default
# The user JSON is the Path Editor's save target; saving an edited copy of a baked path under the
# same name makes it win here until Copy GDScript re-bakes it into DATA (the permanent path).
static func _ensure_overrides() -> void:
	if _overrides_loaded:
		return
	_overrides_loaded = true
	_overrides = {}
	# DEV-ONLY: overrides are an iteration convenience for Roman's editor/debug builds. A release
	# export ignores the user JSON entirely — a player-writable file must never silently change enemy
	# behavior in a shipped build (baked DATA is the only production source).
	if not OS.is_debug_build():
		return
	# Safe headless / at-runtime when the file is absent — file_exists is false, we keep the empty map.
	if not FileAccess.file_exists(OVERRIDE_PATH):
		return
	var f := FileAccess.open(OVERRIDE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	# The editor persists an ARRAY of path-definition dicts; key them by name for O(1) shadow lookup.
	if parsed is Array:
		for entry in parsed:
			if entry is Dictionary and entry.has("name"):
				_overrides[String(entry["name"])] = entry


# Force a re-read of the override JSON (dev-only — the Path Editor calls this after Save).
static func reload_overrides() -> void:
	_overrides_loaded = false
	_overrides = {}
	_ensure_overrides()


# The definition dict for a name: user override if present, else the baked DATA entry, else {}.
static func _def_for(name: String) -> Dictionary:
	_ensure_overrides()
	if _overrides.has(name):
		return _overrides[name]
	if DATA.has(name):
		return DATA[name]
	return {}


# All path names (baked + user-override-only, deduped). Override names that don't shadow a baked path
# are still resolvable, so they belong in the roster/editor vocabulary too.
static func names() -> Array:
	_ensure_overrides()
	var out: Array = DATA.keys()
	for n in _overrides.keys():
		if not out.has(n):
			out.append(n)
	return out


# All movement keys these paths register ("path_<name>").
static func movement_keys() -> Array:
	var out: Array = []
	for n in names():
		out.append(KEY_PREFIX + String(n))
	return out


static func has_path(name: String) -> bool:
	_ensure_overrides()
	return DATA.has(name) or _overrides.has(name)


# True if a movement key routes to an authored path (baked OR user-override).
static func is_path_key(key: String) -> bool:
	return key.begins_with(KEY_PREFIX) and has_path(key.substr(KEY_PREFIX.length()))


# Resolve a "path_<name>" movement key to a live AuthoredPath, or null if it isn't one of ours.
static func resolve_key(key: String) -> Resource:
	if not is_path_key(key):
		return null
	return build(key.substr(KEY_PREFIX.length()))


# Build a live AuthoredPath movement Resource from a definition (user override shadows baked DATA).
static func build(name: String) -> Resource:
	var def: Dictionary = _def_for(name)
	if def.is_empty():
		push_warning("AuthoredPathLibrary.build: no path named '%s'" % name)
		return null
	return build_from_def(def)


# Build directly from a definition dict (the Path Editor uses this to preview un-baked paths).
static func build_from_def(def: Dictionary) -> Resource:
	var m := AuthoredPath.new()
	m.waypoints = _wps_to_v2(def.get("waypoints", []))
	m.speed_scale = float(def.get("speed_scale", 1.0))
	m.relative = bool(def.get("relative", false))
	m.smoothing = float(def.get("smoothing", 0.0))
	m.mirrored = bool(def.get("mirror", false))
	m.dwell = (def.get("dwell", []) as Array).duplicate()
	return m


# Normalize a waypoint array ([[x,y],...] or [Vector2,...]) to Array[Vector2].
static func _wps_to_v2(wps: Array) -> Array:
	var out: Array = []
	for wp in wps:
		if wp is Vector2:
			out.append(wp)
		elif wp is Array and (wp as Array).size() >= 2:
			out.append(Vector2(float(wp[0]), float(wp[1])))
	return out


# --- Intended make_movement hook (scripts/levels/enemy_roster.gd) ---------------------------------
# Add ONE guard at the top of make_movement(), after the key is resolved (right after the
# MOVEMENT_ALIASES collapse, before the `match key:`):
#
#     const AuthoredPathLibrary = preload("res://scripts/enemies/patterns/authored_path_library.gd")
#     ...
#     key = MOVEMENT_ALIASES.get(key, key)
#     if AuthoredPathLibrary.is_path_key(key):
#         return AuthoredPathLibrary.resolve_key(key)
#     match key:
#         ...
#
# That routes every "path_<name>" movement key (authorable in the Formation Builder / eligibility
# matrix / roster entries) through the baked library. director._apply_direction already mirrors the
# pattern via its `mirrored` field, so authored paths flip with a wave's direction_override for free.
