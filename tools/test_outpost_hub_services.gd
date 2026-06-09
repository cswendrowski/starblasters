extends SceneTree

# Outpost-hub Phase 2: stock persists across visits + re-rolls only on boss refresh;
# repair is charge-limited (consumes a charge, blocked at 0).

const OutpostScene = preload("res://scenes/outpost.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var run = root.get_node("/root/Run")
	run.new_run()
	_assert(run.outpost_weapon_offers.is_empty(), "stock empty before first visit")

	# First visit rolls + persists stock.
	var op = OutpostScene.instantiate()
	root.add_child(op)
	await process_frame
	await process_frame
	_assert(not run.outpost_weapon_offers.is_empty(), "first visit rolled + persisted weapon offers")
	# Sentinel: mark the first offer sold; a re-roll would reset it.
	run.outpost_weapon_offers[0]["sold"] = true

	# Repair charge gating.
	run.max_hull = 3
	run.current_hull = 1
	run.bounty = 9999
	run.repair_charges = 2
	op._on_repair(null)
	_assert(run.current_hull == 2 and run.repair_charges == 1, "repair: hull+1, charge-1 (hull %d, chg %d)" % [run.current_hull, run.repair_charges])
	op._on_repair(null)
	_assert(run.repair_charges == 0, "second repair consumes last charge")
	run.current_hull = 1
	op._on_repair(null)
	_assert(run.current_hull == 1, "repair BLOCKED at 0 charges (hull stays 1)")
	op.free()
	await process_frame

	# Persistence across visits (no boss): sentinel survives -> not re-rolled.
	var op2 = OutpostScene.instantiate()
	root.add_child(op2)
	await process_frame
	await process_frame
	_assert(run.outpost_weapon_offers[0].get("sold", false), "stock persists across visit (sentinel intact, no re-roll)")
	op2.free()
	await process_frame

	# Boss refresh: flag set -> next visit re-rolls (sentinel cleared).
	run.on_boss_defeated()
	_assert(run.outpost_needs_refresh, "boss set the refresh flag")
	var op3 = OutpostScene.instantiate()
	root.add_child(op3)
	await process_frame
	await process_frame
	_assert(not run.outpost_needs_refresh, "refresh flag cleared after re-roll on visit")
	_assert(not run.outpost_weapon_offers[0].get("sold", false), "stock RE-ROLLED after boss (sentinel gone)")

	print("[test] ALL PASS")
	quit()


func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)
