extends SceneTree

# Planet Flyover loading-screen test (Roman 2026-07-18, Phase B2). Verifies the loading screen
# swaps the space starfield for a Planet Flyover backdrop when the fly-to lands on a planet POI,
# and stays on the starfield otherwise. Uses the REAL Run autoload (a fake node named "Run" gets
# auto-renamed under -s) for the forced_flyover meta the planner reads.
# Run: godot --headless -s res://tools/test_loading_flyover.gd

const LOADING_SCENE := "res://scenes/loading_screen.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var run: Node = root.get_node_or_null("/root/Run")
	if run == null:
		printerr("[fo] Run autoload absent under -s — cannot test")
		quit(2)
		return
	if run.has_method("new_run"):
		run.new_run()
	await process_frame

	var ok := true

	# --- 1) Flyover path: planet stellar override + forced roll + forced night. ---
	run.set_meta("forced_flyover", {"force": true})
	var ls: Node = load(LOADING_SCENE).instantiate()
	ls.manage_hd_scope = false
	ls.stellar_override = {"obj_kind": 0, "planet_type": 3, "planet_seed": 20260718}
	ls.night_override = 1
	root.add_child(ls)
	for _i in 12:
		await process_frame

	var layer = ls._flyover_layer
	var bd = ls._flyover
	if layer == null or not (layer is CanvasLayer):
		printerr("[fo] FAIL: flyover CanvasLayer not built"); ok = false
	if bd == null or not is_instance_valid(bd):
		printerr("[fo] FAIL: FlyoverBackdrop not built"); ok = false
	if ls._stars != null:
		printerr("[fo] FAIL: star layer was built on a flyover level"); ok = false
	if ls._streaks != null:
		printerr("[fo] FAIL: warp streaks were built on a flyover level"); ok = false
	# Night CanvasModulate must live INSIDE the flyover CanvasLayer (ship + title stay lit).
	var night_mod = null
	if bd != null and is_instance_valid(bd):
		night_mod = bd.get_node_or_null("FlyoverNight")
	if night_mod == null or not (night_mod is CanvasModulate) or not (night_mod as CanvasModulate).visible:
		printerr("[fo] FAIL: forced-night CanvasModulate missing/invisible inside flyover layer"); ok = false
	elif not layer.is_ancestor_of(night_mod):
		printerr("[fo] FAIL: night CanvasModulate not inside the flyover CanvasLayer"); ok = false
	ls.queue_free()
	await process_frame

	# --- 2) Space path: deny meta + empty override → normal starfield, no flyover. ---
	run.remove_meta("forced_flyover")
	run.set_meta("forced_flyover", {"deny": true})
	var ls2: Node = load(LOADING_SCENE).instantiate()
	ls2.manage_hd_scope = false
	ls2.stellar_override = {}
	root.add_child(ls2)
	for _j in 12:
		await process_frame

	if ls2._stars == null:
		printerr("[fo] FAIL: star layer NOT built on the space path"); ok = false
	if ls2._flyover != null:
		printerr("[fo] FAIL: FlyoverBackdrop built on the space path"); ok = false
	run.remove_meta("forced_flyover")
	ls2.queue_free()

	if ok:
		print("[fo] PASS: flyover backdrop + night on planet POI, starfield on space (deny)")
	quit(0 if ok else 1)
