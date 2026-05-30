extends Node2D

# Capture the row-system combat backdrop staged from 3 node positions along the
# SAME row: near-star (C~0.1), mid (C~0.5), far-right (C~0.95). Proves the
# staging model — star big near star -> small far right; a mid-row planet large
# when entered at mid.
#
# NOT headless: run with the real GPU renderer or PixelPlanets shaders + the
# viewport texture come back null/black.

const COORD_SCENE := "res://scenes/parallax/backdrop_coordinator.tscn"
const OUT_DIR     := "res://captures/"

# Synthetic row: a star plus three planet POIs at fracs 0.20, 0.50, 0.80.
# planet_idx values are arbitrary representative globe types (1 Ice, 0 Lava,
# 3 Gas). star_color = warm yellow. We rebuild scale per viewpoint below using
# the same lerp(MAX,MIN,|C-frac|) model as sector_map_v3._stage_scale.
const BODY_SCALE_MAX := 1.0
const BODY_SCALE_MIN := 0.18

const ROW_BODIES := [
	{"kind": "star",   "planet_idx": 8, "planet_seed": 11111, "frac": 0.00},
	{"kind": "planet", "planet_idx": 1, "planet_seed": 22222, "frac": 0.20},
	{"kind": "planet", "planet_idx": 0, "planet_seed": 33333, "frac": 0.50},
	{"kind": "planet", "planet_idx": 3, "planet_seed": 44444, "frac": 0.80},
]
const VIEWPOINTS := [
	{"name": "near_star", "C": 0.10},
	{"name": "mid",       "C": 0.50},
	{"name": "far_right", "C": 0.95},
]
const STAR_COLOR := Color(1.00, 0.88, 0.55, 1.0)

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


func _stage_scale(c: float, body_frac: float) -> float:
	var d: float = clampf(absf(c - body_frac), 0.0, 1.0)
	return lerpf(BODY_SCALE_MAX, BODY_SCALE_MIN, d)


func _build_system(c: float) -> Array:
	var out: Array = []
	for b in ROW_BODIES:
		out.append({
			"kind":        b.kind,
			"planet_idx":  b.planet_idx,
			"planet_seed": b.planet_seed,
			"frac":        b.frac,
			"scale":       _stage_scale(c, float(b.frac)),
			"star_color":  STAR_COLOR,
		})
	return out


func _capture_viewpoint(vp: Dictionary) -> void:
	# Inject synthetic Run.current_stellar so the coordinator's _populate reads
	# the system array exactly as in gameplay.
	var run := get_node_or_null("/root/Run")
	if run != null:
		run.current_stellar = {
			"planet_idx":       ROW_BODIES[2].planet_idx,  # back-compat / tint source
			"planet_seed":      ROW_BODIES[2].planet_seed,
			"star_color":       STAR_COLOR,
			"has_asteroids":    false,
			"asteroid_density": 0.0,
			"moons":            [],
			"system":           _build_system(float(vp.C)),
		}

	# Free any prior coordinator, then instantiate fresh — _ready -> _populate
	# reads the freshly-set current_stellar.
	if _coord != null and is_instance_valid(_coord):
		_coord.queue_free()
		await get_tree().process_frame
	_coord = load(COORD_SCENE).instantiate()
	add_child(_coord)

	# Let layout + PixelPlanets shaders settle before grabbing the frame.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout

	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR + "star_system_%s.png" % String(vp.name))
	img.save_png(path)
	print("[star_system] saved ", path)
