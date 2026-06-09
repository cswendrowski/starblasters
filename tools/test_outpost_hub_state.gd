extends SceneTree

# Outpost-hub Run foundation: new_run seeds 2d6 repair + 2d6 ammo charges; a boss
# defeat bumps bosses_defeated, adds 1d6 to each pool, and flags a stock refresh.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var run = root.get_node("/root/Run")
	run.new_run()
	_assert(run.repair_charges >= 2 and run.repair_charges <= 12, "repair_charges 2d6 (%d)" % run.repair_charges)
	_assert(run.ammo_restock_charges >= 2 and run.ammo_restock_charges <= 12, "ammo charges 2d6 (%d)" % run.ammo_restock_charges)
	_assert(not run.outpost_needs_refresh, "no refresh flag at run start")

	var rep0: int = run.repair_charges
	var ammo0: int = run.ammo_restock_charges
	var bosses0: int = run.bosses_defeated
	run.on_boss_defeated()
	_assert(run.bosses_defeated == bosses0 + 1, "boss defeat bumps count")
	_assert(run.repair_charges >= rep0 + 1 and run.repair_charges <= rep0 + 6, "repair +1d6 (%d->%d)" % [rep0, run.repair_charges])
	_assert(run.ammo_restock_charges >= ammo0 + 1 and run.ammo_restock_charges <= ammo0 + 6, "ammo +1d6 (%d->%d)" % [ammo0, run.ammo_restock_charges])
	_assert(run.outpost_needs_refresh, "refresh flag set after boss")

	print("[test] ALL PASS")
	quit()

func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)
