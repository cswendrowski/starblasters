extends SceneTree

# Composite capture proving the pixel-parity rule: show the same scene
# at several planet_size settings, side-by-side. Each panel should have
# planet cells the same viewport size (≈1 vp-px = 4 screen-px) regardless
# of the body's footprint — the whole point of the new rule.

const OUT_DIR := "res://captures/pixel_parity"
const SCENE := "res://scenes/main.tscn"

const RUNS := [
	{"name": "01_tiny_planet",   "size": 80.0,   "seed": 7777},
	{"name": "02_normal_planet", "size": 240.0,  "seed": 7777},
	{"name": "03_huge_planet",   "size": 600.0,  "seed": 7777},
	{"name": "04_giant_planet",  "size": 1000.0, "seed": 7777},
]


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	_run.call_deferred()


func _run() -> void:
	for r in RUNS:
		await _one(r)
	print("[pixel-parity] done")
	quit()


func _one(cfg: Dictionary) -> void:
	if root.has_node("/root/Run"):
		var run = root.get_node("/root/Run")
		if "run_seed" in run:
			run.run_seed = int(cfg.seed)
	var ps: PackedScene = load(SCENE)
	var inst: Node = ps.instantiate()
	var bd = _find_by_name(inst, "Backdrop")
	if bd:
		if "planet_size" in bd:
			bd.planet_size = float(cfg.size)
		# Reduce variance so each capture shows the requested size exactly.
		if "planet_size_variance" in bd:
			bd.planet_size_variance = 0.0
		# Force a planet variant with clean pixel-art reads (LavaWorld).
		if "forced_planet_idx" in bd:
			bd.forced_planet_idx = 0
	root.add_child(inst)
	await create_timer(1.2).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		var p := "%s/%s.png" % [OUT_DIR, cfg.name]
		img.save_png(ProjectSettings.globalize_path(p))
		print("[pixel-parity] wrote %s" % p)
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
