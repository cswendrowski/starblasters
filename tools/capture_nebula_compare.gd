extends SceneTree

# A/B captures of the nebula at different pixel densities. The linear
# scaling rule Roman proposed (0.468 × size) doesn't directly apply to a
# full-viewport nebula, but the spirit ("bigger thing benefits from more
# pixels") suggests bumping the default 200 to a higher value to see if
# detail improves. Capture both for comparison.

const SCENE := "res://scenes/main.tscn"
const OUT_DIR := "res://captures/nebula"

const RUNS := [
	{"name": "01_nebula_200_current", "px": 200.0},
	{"name": "02_nebula_400_linear",  "px": 400.0},
	{"name": "03_nebula_600_dense",   "px": 600.0},
]


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	_run.call_deferred()


func _run() -> void:
	for r in RUNS:
		await _one(r)
	print("[nebula] done")
	quit()


func _one(cfg: Dictionary) -> void:
	# Lock seed for palette stability and force a planet variant that
	# leaves room for the nebula to read (idx 4, NoAtmosphere — a small
	# rock with no halo competing).
	if root.has_node("/root/Run"):
		var run = root.get_node("/root/Run")
		if "run_seed" in run:
			run.run_seed = 9999
	var ps: PackedScene = load(SCENE)
	var inst: Node = ps.instantiate()
	var bd := _find_by_name(inst, "Backdrop")
	if bd:
		if "forced_planet_idx" in bd:
			bd.forced_planet_idx = 4
		if "nebula_pixels" in bd:
			bd.nebula_pixels = float(cfg.px)
		# Force a non-empty nebula band so the nebula renders strongly.
		if "use_nebula" in bd:
			bd.use_nebula = true
	root.add_child(inst)
	await create_timer(1.4).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		var p := "%s/%s.png" % [OUT_DIR, cfg.name]
		img.save_png(ProjectSettings.globalize_path(p))
		print("[nebula] wrote %s" % p)
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
