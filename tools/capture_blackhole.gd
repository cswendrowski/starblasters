extends SceneTree

# Force the backdrop to spawn the BlackHole planet (idx 6) and snap a frame
# so we can compare disc color vs halo color across multiple random seeds.

const SCENE := "res://scenes/main.tscn"
const OUT_DIR := "res://captures/blackhole"
const RUNS := 4


func _initialize() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	_run.call_deferred()


func _run() -> void:
	for i in RUNS:
		await _one(i)
	print("[bh] done — %d captures -> %s" % [RUNS, OUT_DIR])
	quit()


func _one(idx: int) -> void:
	var ps: PackedScene = load(SCENE)
	var inst: Node = ps.instantiate()
	# Force the backdrop seed before adding to tree so it picks idx 6.
	# Force the backdrop to roll a BlackHole BEFORE add_child so _ready
	# sees the override.
	var bd_pre := _find_by_name(inst, "Backdrop")
	if bd_pre and "forced_planet_idx" in bd_pre:
		bd_pre.forced_planet_idx = 6
	root.add_child(inst)
	await create_timer(1.4).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		var p := "%s/run_%d.png" % [OUT_DIR, idx]
		img.save_png(ProjectSettings.globalize_path(p))
		print("[bh] wrote %s" % p)
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
