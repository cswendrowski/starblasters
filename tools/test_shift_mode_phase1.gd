extends SceneTree

# Shift-Mode Phase 1 verification: the SHIFT_MODE slot + ModePart plumbing.
# - Default loadout equips Focus -> player.active_mode == FOCUS.
# - Equipping Phase / Hyper / Focus into SHIFT_MODE flips active_mode correctly.
# - The Mk-scaled getters match the spec (Phase duration/charges, Hyper fire/dmg).
# Boots the Hangar (spawns a player, no enemies — sidesteps unrelated WIP).

const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const ModePart = preload("res://scripts/parts/mode_part.gd")

const FOCUS := 0
const PHASE := 1
const HYPER := 2


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	change_scene_to_file("res://scenes/hangar.tscn")
	for i in range(5):
		await process_frame
	var hangar = current_scene
	var player = hangar._player
	var loadout = hangar._live_loadout()
	_assert(player != null, "player spawned")

	# Default: Focus equipped + active.
	var mode0 = loadout.get_part(SlotTypes.SlotType.SHIFT_MODE)
	_assert(mode0 != null and String(mode0.display_name) == "Focus", "default mode is Focus")
	_assert(int(player.active_mode) == FOCUS, "active_mode == FOCUS by default")

	# Equip Phase.
	_equip("_make_phase_shift", 1, loadout)
	_assert(int(player.active_mode) == PHASE, "active_mode == PHASE after equipping Phase")

	# Equip Hyper.
	_equip("_make_hyper_mode", 1, loadout)
	_assert(int(player.active_mode) == HYPER, "active_mode == HYPER after equipping Hyper")

	# Back to Focus.
	_equip("_make_focus_mode", 1, loadout)
	_assert(int(player.active_mode) == FOCUS, "active_mode == FOCUS after re-equipping Focus")

	# --- Mk-scaled getters match spec ---
	var phase = PartCatalog._make_by_name("_make_phase_shift", SlotTypes.SlotType.SHIFT_MODE)
	# base 3.0s / 2ch; Mk9 -> 7.0s / 6ch (even Mk +1s, odd Mk>1 +1 charge).
	_assert_eqf(phase.duration_at_mark(1), 3.0, "Phase dur Mk1 = 3.0")
	_assert_eqf(phase.duration_at_mark(2), 4.0, "Phase dur Mk2 = 4.0 (+1s)")
	_assert_eq(phase.charges_at_mark(3), 3, "Phase charges Mk3 = 3 (+1)")
	_assert_eqf(phase.duration_at_mark(9), 7.0, "Phase dur Mk9 = 7.0")
	_assert_eq(phase.charges_at_mark(9), 6, "Phase charges Mk9 = 6")

	var hyper = PartCatalog._make_by_name("_make_hyper_mode", SlotTypes.SlotType.SHIFT_MODE)
	# base +10% fire; odd Mk>1 +5% fire; even Mk +10% stacking damage.
	_assert_eqf(hyper.fire_bonus_at_mark(1), 0.10, "Hyper fire Mk1 = +10%")
	_assert_eqf(hyper.fire_bonus_at_mark(3), 0.15, "Hyper fire Mk3 = +15%")
	_assert_eqf(hyper.fire_bonus_at_mark(9), 0.30, "Hyper fire Mk9 = +30%")
	_assert_eqf(hyper.damage_mult_at_mark(1), 1.0, "Hyper dmg Mk1 = x1.0")
	_assert_eqf(hyper.damage_mult_at_mark(2), 1.10, "Hyper dmg Mk2 = x1.10")
	_assert_eqf(hyper.damage_mult_at_mark(8), 1.40, "Hyper dmg Mk8 = x1.40")

	# Slot type + supers: modes are SHIFT_MODE, not DEVICE_BAY_1 (super) anymore.
	_assert_eq(int(phase.slot_type), int(SlotTypes.SlotType.SHIFT_MODE), "Phase slot == SHIFT_MODE")
	_assert_eq(int(hyper.slot_type), int(SlotTypes.SlotType.SHIFT_MODE), "Hyper slot == SHIFT_MODE")
	var smartbomb_in_dev1 := false
	for entry in PartCatalog._all_pool():
		if int(entry["slot"]) == SlotTypes.SlotType.DEVICE_BAY_1:
			var p = PartCatalog._make_by_name(String(entry["factory"]), SlotTypes.SlotType.DEVICE_BAY_1)
			if p != null and String(p.display_name) == "Smart Bomb":
				smartbomb_in_dev1 = true
			_assert(p == null or String(p.display_name) == "Smart Bomb", "only Smart Bomb in DEVICE_BAY_1 pool (got %s)" % (String(p.display_name) if p else "null"))
	_assert(smartbomb_in_dev1, "Smart Bomb still the lone DEVICE_BAY_1 super")

	print("[test] ALL PASS")
	quit()


func _equip(factory: String, mk: int, loadout) -> void:
	var part = PartCatalog._make_by_name(factory, SlotTypes.SlotType.SHIFT_MODE)
	part.mark = mk
	root.get_node("/root/Run").equip_part(part)
	loadout.equip(SlotTypes.SlotType.SHIFT_MODE, part)


func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)

func _assert_eq(a: int, b: int, msg: String) -> void:
	_assert(a == b, "%s (got %d)" % [msg, a])

func _assert_eqf(a: float, b: float, msg: String) -> void:
	_assert(abs(a - b) < 0.001, "%s (got %.3f)" % [msg, a])
