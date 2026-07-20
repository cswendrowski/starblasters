extends SceneTree

# Phase B1 combat-wiring check (Roman 2026-07-18): boot scenes/main.tscn with the REAL Run
# autoload seeded to a planet POI + forced_flyover meta, and assert backdrop_coordinator's new
# flyover branch fires. Two passes in one boot cycle:
#   Pass 1 (force + night): a FlyoverBackdrop node exists under the Backdrop coordinator, the
#     standard space stack is SKIPPED (LayerPlanet holds only its static CanvasModulate — no
#     spawned planet), and a visible "FlyoverNight" CanvasModulate is present.
#   Pass 2 (deny): the standard stack IS built (LayerPlanet gains a spawned planet child) and
#     NO FlyoverBackdrop exists.
# Uses root.get_node("Run") — headless -s DOES load autoloads; a fake node named "Run" gets
# auto-renamed and would silently miss (per the design's real-autoload note).
# Run: godot --path . --headless -s res://tools/test_flyover_combat.gd

const FlyoverBackdropScript = preload("res://scripts/parallax/flyover_backdrop.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var run: Node = root.get_node_or_null("Run")
	if run == null:
		printerr("[flyover-combat] Run autoload absent under -s — cannot test")
		quit(2)
		return

	var fails: Array = []

	# --- Pass 1: forced flyover + forced night ---
	_seed_run(run, "flyover_node_A")
	run.set_meta("forced_flyover", {"force": true, "night": true})
	var main1: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main1)
	for _i in 12:
		await process_frame

	var coord1: Node = main1.get_node_or_null("Backdrop")
	if coord1 == null:
		fails.append("pass1: Backdrop coordinator not found under main")
	else:
		var fb: Node = _find_flyover(coord1)
		if fb == null:
			fails.append("pass1: FlyoverBackdrop node absent under coordinator (flyover branch did not fire)")
		else:
			# (b) standard planet stack skipped: LayerPlanet keeps only its scene-static
			# CanvasModulate child (spawn_planet was never called).
			var lp: Node = coord1.get_node_or_null("LayerPlanet")
			if lp != null and lp.get_child_count() > 1:
				fails.append("pass1: standard planet layer populated (%d children) despite flyover" % lp.get_child_count())
			# (c) night CanvasModulate present + visible.
			var cm = fb.get_node_or_null("FlyoverNight")
			if cm == null or not (cm is CanvasModulate):
				fails.append("pass1: FlyoverNight CanvasModulate missing")
			elif not (cm as CanvasModulate).visible:
				fails.append("pass1: FlyoverNight present but not visible (night forced)")

	main1.queue_free()
	await process_frame

	# --- Pass 2: deny → standard space stack, no flyover ---
	_seed_run(run, "space_node_B")
	run.set_meta("forced_flyover", {"deny": true})
	var main2: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main2)
	for _i in 12:
		await process_frame

	var coord2: Node = main2.get_node_or_null("Backdrop")
	if coord2 == null:
		fails.append("pass2: Backdrop coordinator not found under main")
	else:
		if _find_flyover(coord2) != null:
			fails.append("pass2: FlyoverBackdrop present despite deny")
		var lp2: Node = coord2.get_node_or_null("LayerPlanet")
		if lp2 == null:
			fails.append("pass2: LayerPlanet missing")
		elif lp2.get_child_count() <= 1:
			fails.append("pass2: standard planet layer NOT populated (deny should keep the space stack)")

	main2.queue_free()
	await process_frame

	# --- Pass 3: non-combat host (allow_flyover default false) → always the space stack, even
	# with a planet POI + force meta still on Run. This is the raw coordinator scene as the main
	# menu (menu_backdrop) / signal_event / labs instantiate it — Roman 2026-07-18: the main
	# screen backdrop stays space parallax unconditionally.
	_seed_run(run, "flyover_node_A")
	run.set_meta("forced_flyover", {"force": true})
	var coord3: Node = load("res://scenes/parallax/backdrop_coordinator.tscn").instantiate()
	root.add_child(coord3)
	for _i in 8:
		await process_frame
	if _find_flyover(coord3) != null:
		fails.append("pass3: FlyoverBackdrop built by a default (allow_flyover=false) coordinator host")
	var lp3: Node = coord3.get_node_or_null("LayerPlanet")
	if lp3 == null or lp3.get_child_count() <= 1:
		fails.append("pass3: default coordinator host did not build the space stack")
	coord3.queue_free()
	await process_frame

	# Clean up the dev meta.
	if run.has_meta("forced_flyover"):
		run.remove_meta("forced_flyover")

	if fails.is_empty():
		print("VERDICT: PASS — flyover combat wiring: force builds FlyoverBackdrop + night & skips space stack; deny keeps space stack; non-combat hosts always space")
		quit(0)
	else:
		for fx in fails:
			print("FAIL: ", fx)
		print("VERDICT: FAIL")
		quit(1)


# Seed the real Run to a planet-POI combat node. current_stellar = DryTerran (planet_type 1 →
# Desert 2 preset); obj_kind 0 = planet POI. Fields set AFTER new_run() (which clears them).
func _seed_run(run: Node, node_id: String) -> void:
	if run.has_method("new_run"):
		run.new_run()
	run.run_seed = 12345
	run.current_node_id = node_id
	run.current_node_type = 0   # SectorNode.NodeType.COMBAT
	run.current_stellar = {"obj_kind": 0, "planet_type": 1, "planet_seed": 12345}


func _find_flyover(coord: Node) -> Node:
	for c in coord.get_children():
		if c.get_script() == FlyoverBackdropScript:
			return c
	return null
