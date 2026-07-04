extends SceneTree

# Hull-parity test (Roman 2026-06-19): the loading-screen ship must show the SAME damage combat will,
# not a stale snapshot. Reproduces the reported bug — Run.max_hull stale/divergent from the loadout
# max — and asserts the loading-screen player's (hull, max_hull) equals what a combat player computes.
# Run: godot --headless -s res://tools/test_loading_hull_parity.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var run: Node = root.get_node_or_null("/root/Run")
	if run == null:
		printerr("[hp] Run autoload absent — cannot test")
		quit(2)
		return
	run.new_run()
	await process_frame
	# Damaged + a DELIBERATELY stale max snapshot: the loadout-derived max is 2+module_bonus, NOT 9.
	# Old code used Run.max_hull=9 → 1-2/9=0.78 severity (heavy fake damage) while combat shows none.
	run.current_hull = 2
	run.max_hull = 9

	# 1) Loading-screen player.
	var ls: Node = load("res://scenes/loading_screen.tscn").instantiate()
	ls.manage_hd_scope = false
	root.add_child(ls)
	for _i in 8:
		await process_frame
	var lp: Node = _find_player(ls)
	if lp == null:
		printerr("[hp] loading-screen player not found")
		quit(1)
		return
	var l_hull := int(lp.hull)
	var l_max := int(lp.max_hull)

	# 2) Combat-style player: spawn (→ _ready/start sets loadout max) + main.gd's hull load. new_run
	# leaves ship_variant 0 = player.tscn (avoid the ShipCatalog class_name — unresolved in -s scope).
	var cp: Node = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(cp)
	await process_frame
	if int(run.current_hull) > 0:
		cp.hull = mini(int(run.current_hull), int(cp.max_hull))
	var c_hull := int(cp.hull)
	var c_max := int(cp.max_hull)

	print("[hp] loading=(%d/%d)  combat=(%d/%d)  stale Run.max_hull=%d" % [l_hull, l_max, c_hull, c_max, int(run.max_hull)])
	var ok := (l_hull == c_hull and l_max == c_max)
	if ok:
		print("[hp] PASS: loading screen matches combat (ignores stale Run.max_hull=%d)" % int(run.max_hull))
	else:
		printerr("[hp] FAIL: loading screen diverges from combat")
	quit(0 if ok else 1)


func _find_player(ls: Node) -> Node:
	var w: Node = ls.get_node_or_null("World")
	if w == null:
		return null
	for c in w.get_children():
		if "max_hull" in c and "hull" in c:
			return c
	return null
