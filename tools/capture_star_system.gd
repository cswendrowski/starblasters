extends Node2D

# Capture the row-system combat backdrop (Roman v2 aggressive staging) from
# several node positions along the SAME row, plus a dense-belt case.
#
# Proves:
#   - NEAREST body FILLS the screen (scale 1.0 -> SYS_SIZE_CEILING px).
#   - AGGRESSIVE exponential falloff: a couple nodes away is already small.
#   - EXTREME-DISTANCE bodies collapse to ~2px glowing dots in their main color.
#   - BELT case: current node adjacent-to/at an asteroid_field -> dense
#     decorative asteroids across all 3 stellar layers.
#
# This tool builds `current_stellar` DIRECTLY (it does NOT read SYSTEM_BACKDROP_
# ENABLED), so it renders regardless of the gate. Curve constants below MIRROR
# sector_map_v3._stage_scale (BODY_SCALE_MAX, FALLOFF_K) — keep them in sync.
#
# NOT headless: run with the real GPU renderer or PixelPlanets shaders + the
# viewport texture come back null/black.

const COORD_SCENE := "res://scenes/parallax/backdrop_coordinator.tscn"
const OUT_DIR     := "res://captures/"

# MUST mirror sector_map_v3.gd staging curve knobs.
const BODY_SCALE_MAX := 1.0
const FALLOFF_K      := 5.0

# Synthetic row: a star plus three planet POIs at fracs 0.20, 0.50, 0.80.
# planet_idx values are representative globe types (1 Ice, 0 Lava, 3 Gas).
const ROW_BODIES := [
	{"kind": "star",   "planet_idx": 8, "planet_seed": 11111, "frac": 0.00},
	{"kind": "planet", "planet_idx": 1, "planet_seed": 22222, "frac": 0.20},
	{"kind": "planet", "planet_idx": 0, "planet_seed": 33333, "frac": 0.50},
	{"kind": "planet", "planet_idx": 3, "planet_seed": 44444, "frac": 0.80},
]
# A SEPARATE clustered row so the `far` viewpoint can put EVERY body at extreme
# distance (d > 0.85) and prove the 2px-glowing-dot path. On a normal spread row
# the current node is always within 0.2 of some body, so something is always a
# big sphere — that's covered by near_planet/two_away. Here all four cluster near
# frac 0 and we view from C=1.0, so all four collapse to dots.
const FAR_ROW_BODIES := [
	{"kind": "star",   "planet_idx": 8, "planet_seed": 11111, "frac": 0.00},
	{"kind": "planet", "planet_idx": 1, "planet_seed": 22222, "frac": 0.05},
	{"kind": "planet", "planet_idx": 0, "planet_seed": 33333, "frac": 0.10},
	{"kind": "planet", "planet_idx": 3, "planet_seed": 44444, "frac": 0.15},
]

# Viewpoints chosen to exercise the full range:
#   near_planet: C=0.50 -> the mid planet FILLS the screen, others fall off fast.
#   two_away:    C=0.20 -> near the ice planet, mid is smaller, far bodies tiny.
#   far:         clustered row viewed from C=1.0 -> ALL bodies become 2px dots.
#   belt:        C=0.50 -> a planet fills the frame + dense drifting asteroids.
# `settle` is the post-spawn wait (s); the belt frame needs several seconds so
# the amped asteroid field (which drifts in from above at drift_speed) populates
# the visible band before the snapshot.
const VIEWPOINTS := [
	{"name": "near_planet", "C": 0.50, "belt": false, "row": "spread", "settle": 0.6},
	{"name": "two_away",    "C": 0.20, "belt": false, "row": "spread", "settle": 0.6},
	{"name": "far",         "C": 1.00, "belt": false, "row": "far",    "settle": 0.6},
	# Belt: reuse the FAR clustered row (planets bunched near frac 0) viewed from
	# C=1.0 so every body is a distant dot — the dense asteroid field then OWNS
	# the frame instead of being occluded by a foreground planet. Density mirrors
	# BELT_DENSITY_SELF, the value this frame demonstrates.
	{"name": "belt",        "C": 1.00, "belt": true,  "row": "far",    "settle": 4.5},
]
const STAR_COLOR := Color(1.00, 0.88, 0.55, 1.0)
# Mirror sector_map_v3.BELT_DENSITY_SELF (the IS-a-belt case). The adjacent case
# uses BELT_DENSITY_ADJACENT=1.6; this frame demonstrates SELF.
const BELT_DENSITY := 2.4

var _coord: Node = null


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(480, 270))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_run_all()


func _run_all() -> void:
	for vp in VIEWPOINTS:
		await _capture_viewpoint(vp)
	print("[star_system] done")
	get_tree().quit()


# Mirror of sector_map_v3._stage_scale (exponential falloff, NOT floored).
func _stage_scale(c: float, body_frac: float) -> float:
	var d: float = clampf(absf(c - body_frac), 0.0, 1.0)
	return BODY_SCALE_MAX * exp(-FALLOFF_K * d)


func _build_system(c: float, row_kind: String) -> Array:
	var bodies: Array = FAR_ROW_BODIES if row_kind == "far" else ROW_BODIES
	var out: Array = []
	var dot_ct: int = 0
	for b in bodies:
		var sc: float = _stage_scale(c, float(b.frac))
		# Mirror backdrop_coordinator's dot decision for a verification count:
		# raw_px = SYS_SIZE_CEILING(330) * scale; dot if < SYS_DOT_THRESHOLD_PX(6).
		if 330.0 * sc < 6.0:
			dot_ct += 1
		out.append({
			"kind":        b.kind,
			"planet_idx":  b.planet_idx,
			"planet_seed": b.planet_seed,
			"frac":        b.frac,
			"scale":       sc,
			"star_color":  STAR_COLOR,
		})
	print("[star_system]   bodies=%d expected_dots=%d (row=%s C=%.2f)" % [bodies.size(), dot_ct, row_kind, c])
	return out


func _capture_viewpoint(vp: Dictionary) -> void:
	# Inject synthetic Run.current_stellar so the coordinator's _populate reads
	# the system array exactly as in gameplay.
	var run := get_node_or_null("/root/Run")
	var is_belt: bool = bool(vp.get("belt", false))
	var row_kind: String = String(vp.get("row", "spread"))
	if run != null:
		run.current_stellar = {
			"planet_idx":       ROW_BODIES[2].planet_idx,  # back-compat / tint source
			"planet_seed":      ROW_BODIES[2].planet_seed,
			"star_color":       STAR_COLOR,
			"has_asteroids":    is_belt,
			"asteroid_density": BELT_DENSITY if is_belt else 0.0,
			"moons":            [],
			"system":           _build_system(float(vp.C), row_kind),
		}

	# Free any prior coordinator, then instantiate fresh — _ready -> _populate
	# reads the freshly-set current_stellar.
	if _coord != null and is_instance_valid(_coord):
		_coord.queue_free()
		await get_tree().process_frame
	_coord = load(COORD_SCENE).instantiate()
	add_child(_coord)

	# Let layout + PixelPlanets shaders settle before grabbing the frame. The
	# belt frame waits longer so the amped asteroid field drifts into the band.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(float(vp.get("settle", 0.6))).timeout

	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR + "star_system_%s.png" % String(vp.name))
	img.save_png(path)
	print("[star_system] saved ", path)
