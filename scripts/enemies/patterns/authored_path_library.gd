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
# WIRING into production (make_movement): keys prefixed "path_" resolve here. Because
# scripts/levels/enemy_roster.gd is owned by another agent this pass, the one-line hook was NOT added
# to make_movement's match; instead resolve_key()/build() are the public entry points and the
# intended make_movement hook is documented at the bottom of this file. The Path Editor previews by
# building AuthoredPath directly (dogfooding the runtime), so it needs no roster wiring.

const AuthoredPath := preload("res://scripts/enemies/patterns/authored_path.gd")

# Movement-key prefix. A key like "path_s_weave" resolves to DATA["s_weave"].
const KEY_PREFIX := "path_"


# name -> path definition. Author these in the Path Editor and paste its Copy GDScript output here.
const DATA := {
	# S-weave descent — smooth sinusoidal side-to-side while descending. Lane-relative so it reads
	# the same from any spawn lane; smoothed into a flowing S.
	"s_weave": {
		"name": "s_weave",
		"relative": true,
		"speed_scale": 1.0,
		"smoothing": 1.0,
		"mirror": false,
		"waypoints": [[0.0, 0.0], [1.2, 0.25], [-1.2, 0.5], [1.2, 0.75], [0.0, 1.0]],
		"dwell": [],
	},
	# Corner-hook dive — spawn at the top-left, dive down the left lane, then hook hard across to the
	# right and exit low-right. Absolute lanes so the corners are fixed to the board.
	"corner_hook": {
		"name": "corner_hook",
		"relative": false,
		"speed_scale": 1.0,
		"smoothing": 0.6,
		"mirror": false,
		"waypoints": [[0.0, 0.0], [0.0, 0.45], [1.5, 0.62], [4.5, 0.72], [6.0, 0.9]],
		"dwell": [],
	},
	# Loop-and-exit flourish — descend to mid-band, carve a loop (rising back up on one side) then
	# resume the descent and exit. NON-MONOTONE y (rises mid-path) → fires on cadence, not path-phase.
	"loop_exit": {
		"name": "loop_exit",
		"relative": false,
		"speed_scale": 1.0,
		"smoothing": 1.0,
		"mirror": false,
		"waypoints": [[3.0, 0.0], [3.0, 0.4], [4.4, 0.5], [4.4, 0.32], [3.0, 0.32], [3.0, 0.6], [3.0, 1.0]],
		"dwell": [],
	},
	# Zigzag rush — fast, sharp alternating cuts down the band (polyline, no rounding). Lane-relative;
	# a touch above chassis speed for an aggressive strafe.
	"zigzag_rush": {
		"name": "zigzag_rush",
		"relative": true,
		"speed_scale": 1.0,
		"smoothing": 0.0,
		"mirror": false,
		"waypoints": [[0.0, 0.0], [1.5, 0.2], [-1.5, 0.4], [1.5, 0.6], [-1.5, 0.8], [0.0, 1.0]],
		"dwell": [],
	},
}


# All baked path names.
static func names() -> Array:
	return DATA.keys()


# All movement keys these paths register ("path_<name>").
static func movement_keys() -> Array:
	var out: Array = []
	for n in DATA.keys():
		out.append(KEY_PREFIX + String(n))
	return out


static func has_path(name: String) -> bool:
	return DATA.has(name)


# True if a movement key routes to an authored path.
static func is_path_key(key: String) -> bool:
	return key.begins_with(KEY_PREFIX) and DATA.has(key.substr(KEY_PREFIX.length()))


# Resolve a "path_<name>" movement key to a live AuthoredPath, or null if it isn't one of ours.
static func resolve_key(key: String) -> Resource:
	if not is_path_key(key):
		return null
	return build(key.substr(KEY_PREFIX.length()))


# Build a live AuthoredPath movement Resource from a baked definition (or a raw definition dict).
static func build(name: String) -> Resource:
	if not DATA.has(name):
		push_warning("AuthoredPathLibrary.build: no path named '%s'" % name)
		return null
	return build_from_def(DATA[name])


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
