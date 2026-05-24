extends SceneTree

# POI moon backdrop capture — instantiates galaxy_backdrop with a forced
# planet pick and a synthetic POI moon descriptor list, so we can verify
# the PlanetKit moons orbit correctly and inherit the planet's drift.

const OUT_DIR := "res://captures/poi_moons"
const FPS: int = 24
const DURATION: float = 4.0
const FRAME_TIME: float = 1.0 / float(FPS)
const BACKDROP_SCRIPT := preload("res://scripts/galaxy_backdrop.gd")


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var d := DirAccess.open(OUT_DIR)
	if d:
		d.list_dir_begin()
		while true:
			var fn := d.get_next()
			if fn == "":
				break
			if fn.ends_with(".png"):
				d.remove(fn)
		d.list_dir_end()
	_run.call_deferred()


# Build a synthetic moon descriptor list matching what
# sector_map_v3._derive_moon_descriptors would emit. planet_px=20 is a
# typical sector-map planet footprint.
func _make_moons() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var planet_px: float = 20.0
	var count: int = 6
	var out: Array = []
	for k in count:
		var base_r: float = planet_px * 0.5 + rng.randf_range(2.0, planet_px * 0.7)
		var rx: float = base_r
		var ry: float = base_r * rng.randf_range(0.45, 1.0)
		var spd: float = rng.randf_range(0.20, 0.70) * (1.0 if rng.randf() > 0.5 else -1.0)
		var phase: float = rng.randf_range(0.0, TAU)
		var base_tint := Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.6), 0.95, 1.0)
		var tint := Color(base_tint.r * 0.5, base_tint.g * 0.5, base_tint.b * 0.5, 1.0)
		var radius_px: int = 1 + rng.randi() % 3
		out.append({
			"radius": radius_px,
			"color":  tint,
			"phase":  phase,
			"rx":     rx,
			"ry":     ry,
			"speed":  spd,
		})
	return out


func _run() -> void:
	var vp_size: Vector2i = Vector2i(480, 270)
	root.get_viewport().size = vp_size
	# Seed Run.current_stellar so galaxy_backdrop._ready reads our forced
	# planet + moon descriptor list.
	var run = root.get_node_or_null("Run")
	if run != null:
		run.current_node_id = "capture_poi_moons"
		run.current_stellar = {
			"planet_idx": 5,           # LandMasses — green, easy to read against moons
			"moons":      _make_moons(),
			"star_color": Color(1, 1, 1, 1),
			"star_cool":  false,
		}
	# Instantiate the backdrop.
	var backdrop := Node2D.new()
	backdrop.set_script(BACKDROP_SCRIPT)
	root.add_child(backdrop)
	# Capture frames over DURATION seconds. The backdrop's _process drift
	# updates moon positions each frame.
	var frame_count: int = int(DURATION * float(FPS))
	for f in frame_count:
		await create_timer(FRAME_TIME).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		if img != null:
			var path := "%s/frame_%04d.png" % [OUT_DIR, f]
			img.save_png(ProjectSettings.globalize_path(path))
	print("[poi_moons] captured %d frames" % frame_count)
	quit()
