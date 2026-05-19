extends SceneTree

# A/B captures of two planet kinds (BlackHole + LavaWorld), under both the
# OLD pixels-per-size = 0.5 / ceiling 600 settings and the NEW 0.468 / 800
# settings. Same forced planet idx + same backdrop construction, so the
# only varying axis is the scaling rule.

const SCENE := "res://scenes/main.tscn"
const OUT_DIR := "res://captures/scaling"

const RUNS := [
	{"name": "01_blackhole_OLD",  "idx": 6, "pps": 0.5,   "ceil": 600.0, "seed": 42},
	{"name": "02_blackhole_NEW",  "idx": 6, "pps": 0.468, "ceil": 800.0, "seed": 42},
	{"name": "03_lavaworld_OLD",  "idx": 0, "pps": 0.5,   "ceil": 600.0, "seed": 1337},
	{"name": "04_lavaworld_NEW",  "idx": 0, "pps": 0.468, "ceil": 800.0, "seed": 1337},
]


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	_run.call_deferred()


func _run() -> void:
	for r in RUNS:
		await _one(r)
	print("[scaling] done")
	quit()


func _one(cfg: Dictionary) -> void:
	# Lock the run seed BEFORE building the scene so the backdrop rolls the
	# same palette + position across the OLD/NEW pairs. Only the pixel
	# density should vary.
	if root.has_node("/root/Run"):
		var run = root.get_node("/root/Run")
		if "run_seed" in run:
			run.run_seed = int(cfg.seed)
	var ps: PackedScene = load(SCENE)
	var inst: Node = ps.instantiate()
	var bd := _find_by_name(inst, "Backdrop")
	if bd:
		if "forced_planet_idx" in bd:
			bd.forced_planet_idx = int(cfg.idx)
		if "pixels_per_size" in bd:
			bd.pixels_per_size = float(cfg.pps)
		if "pixels_ceiling" in bd:
			bd.pixels_ceiling = float(cfg.ceil)
	root.add_child(inst)
	await create_timer(1.4).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		var p := "%s/%s.png" % [OUT_DIR, cfg.name]
		img.save_png(ProjectSettings.globalize_path(p))
		print("[scaling] wrote %s" % p)
	inst.queue_free()
	await create_timer(0.2).timeout


func _find_by_name(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var hit := _find_by_name(c, nm)
		if hit:
			return hit
	return null
