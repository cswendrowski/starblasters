extends SceneTree

# Read-only guarantee test for the loading screen (Roman 2026-06-19). The screen spawns the REAL
# player as a visual copy, and the player's _ready()/start() can WRITE run state (super-charge refill,
# SidePods ammo). This forces the exact "would-refill" case (super_charges spent to 0) + a sentinel
# ammo, spawns the loading screen, and asserts Run's guarded fields + hull are untouched.
# Run: godot --headless -s res://tools/test_loading_readonly.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var run: Node = root.get_node_or_null("/root/Run")
	if run == null:
		printerr("[ro] Run autoload absent in -s mode — cannot test")
		quit(2)
		return
	if run.has_method("new_run"):
		run.new_run()
	await process_frame

	# Force the branch player.start() takes on a "fresh" spawn: super_charges spent to 0 (start()
	# refills run.super_charges here) + a sentinel ammo (SidePods writes run.ammo on apply()).
	if "super_charges" in run:
		run.super_charges = 0
	if "ammo" in run:
		run.ammo = 777
	var before := {}
	for f in ["super_charges", "max_super_charges", "ammo", "secondary_ammo", "current_hull", "max_hull"]:
		if f in run:
			before[f] = run.get(f)

	var ls: Node = load("res://scenes/loading_screen.tscn").instantiate()
	ls.manage_hd_scope = false   # skip the content-scale swap in the test
	root.add_child(ls)
	for _i in 8:
		await process_frame

	var ok := true
	for f in before:
		var now = run.get(f)
		if now != before[f]:
			printerr("[ro] FAIL: run.%s mutated %s -> %s" % [f, str(before[f]), str(now)])
			ok = false
	if ok:
		print("[ro] PASS: loading screen left Run untouched (super_charges=%s ammo=%s hull=%s/%s)" % [
			str(run.get("super_charges")), str(run.get("ammo")),
			str(run.get("current_hull")), str(run.get("max_hull"))])
	ls.queue_free()
	quit(0 if ok else 1)
