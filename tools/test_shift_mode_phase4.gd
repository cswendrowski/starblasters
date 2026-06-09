extends SceneTree

# Shift-Mode Phase 4 economy wiring: modes are buyable at outposts.
# - The outpost weapons column weights include SHIFT_MODE.
# - roll_for_slot(SHIFT_MODE) yields Phase/Hyper (never Focus — default-only —
#   never null), priced like a weapon by the outpost's offer builder.
# - Equipping a rolled mode routes to the SHIFT_MODE slot.

const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const Outpost = preload("res://scripts/outpost.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# SHIFT_MODE is on the shop shelf.
	var has_mode := false
	for s in Outpost.WEAPON_SLOT_WEIGHTS:
		if int(s) == int(SlotTypes.SlotType.SHIFT_MODE):
			has_mode = true
	_assert(has_mode, "SHIFT_MODE is in the outpost WEAPON_SLOT_WEIGHTS")

	# roll_for_slot(SHIFT_MODE) only ever yields Phase/Hyper.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var seen := {}
	for i in range(40):
		var p = PartCatalog.roll_for_slot(rng, SlotTypes.SlotType.SHIFT_MODE, 1 + (i % 3))
		_assert(p != null, "roll_for_slot(SHIFT_MODE) never null")
		var dn := String(p.display_name)
		seen[dn] = true
		_assert(dn == "Phase" or dn == "Hyper Mode", "rolled a mode (Phase/Hyper), got '%s'" % dn)
		_assert(dn != "Focus", "never rolls Focus (default-only)")
		_assert(int(p.slot_type) == int(SlotTypes.SlotType.SHIFT_MODE), "rolled part is SHIFT_MODE")
	print("[test] rolled modes over 40 picks: %s" % str(seen.keys()))

	# Equip routing: a rolled mode lands in the SHIFT_MODE snapshot slot.
	var run = root.get_node("/root/Run")
	var hyper = PartCatalog.roll_for_slot(rng, SlotTypes.SlotType.SHIFT_MODE, 1)
	while String(hyper.display_name) != "Hyper Mode":
		hyper = PartCatalog.roll_for_slot(rng, SlotTypes.SlotType.SHIFT_MODE, 1)
	run.equip_part(hyper)
	var snap = run.loadout_snapshot.get(SlotTypes.SlotType.SHIFT_MODE, null)
	_assert(snap != null and String(snap.display_name) == "Hyper Mode", "bought mode routes to SHIFT_MODE snapshot")

	print("[test] ALL PASS")
	quit()


func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)
