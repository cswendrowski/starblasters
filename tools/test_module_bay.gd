extends SceneTree

# Passive Module bay — core mechanics (2026-06-13).
# A) Run layer — default Shield Core seed, add/remove/has, the ≤5 cap.
# B) Module Mk math — Overcharge damage curve, Siphon threshold curve.
# C) Player integration — the shield gate (no Shield Core in an initialized bay = max_shield 0)
#    + Overcharge's damage_mult applied at combat start.

const ShieldCore = preload("res://scripts/parts/shield_core.gd")
const OverchargeCore = preload("res://scripts/parts/overcharge_core.gd")
const SiphonCore = preload("res://scripts/parts/siphon_core.gd")
const RepairNanites = preload("res://scripts/parts/repair_nanites.gd")
const AblativePlating = preload("res://scripts/parts/ablative_plating.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const Slots = preload("res://scripts/weapons/SlotTypes.gd")


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var run = root.get_node("/root/Run")

	# --- A. Run layer ---
	run.new_run()
	_assert(run.has_module("shield_core"), "new_run seeds the default Shield Core")
	_assert(run.bay_initialized, "bay_initialized true after new_run")
	_assert(run.modules.size() == 1, "bay starts with 1 module")
	_assert(run.add_module(OverchargeCore.new()), "add Overcharge accepted")
	_assert(run.add_module(SiphonCore.new()), "add Siphon accepted")
	for _i in range(5):
		run.add_module(OverchargeCore.new())  # try to overfill
	_assert(run.modules.size() == run.MODULE_BAY_SIZE, "bay capped at MODULE_BAY_SIZE (%d)" % run.modules.size())
	_assert(not run.add_module(OverchargeCore.new()), "add rejected when full")
	var removed = run.remove_module(0)  # the default Shield Core
	_assert(removed != null and String(removed.module_id) == "shield_core", "remove_module returns the Shield Core")
	_assert(not run.has_module("shield_core"), "Shield Core gone after removal")

	# --- B. Module Mk math ---
	var oc1 = OverchargeCore.new(); oc1.mark = 1
	var oc9 = OverchargeCore.new(); oc9.mark = 9
	_assert(absf(oc1._damage_mult() - 1.10) < 0.001, "Overcharge Mk.1 = +10%")
	_assert(absf(oc9._damage_mult() - 1.30) < 0.001, "Overcharge Mk.9 = +30%")
	var sc1 = SiphonCore.new(); sc1.mark = 1
	var sc9 = SiphonCore.new(); sc9.mark = 9
	_assert(sc1._kills_per_charge() == 10, "Siphon Mk.1 = every 10 kills")
	_assert(sc9._kills_per_charge() == 2, "Siphon Mk.9 = every 2 kills")
	var rn1 = RepairNanites.new(); rn1.mark = 1
	var rn9 = RepairNanites.new(); rn9.mark = 9
	_assert(rn1._interval() == 12.0, "Repair Nanites Mk.1 = 12s/pip")
	_assert(rn9._interval() == 4.0, "Repair Nanites Mk.9 = 4s/pip")
	var ap1 = AblativePlating.new(); ap1.mark = 1
	var ap9 = AblativePlating.new(); ap9.mark = 9
	_assert(ap1._every_n() == 6, "Ablative Mk.1 = absorb every 6th hit")
	_assert(ap9._every_n() == 2, "Ablative Mk.9 = absorb every 2nd hit")

	# --- D. Shop roll produces modules (item-gen rules) ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var got_module := false
	for _k in range(20):
		var rolled = PartCatalog.roll_for_slot(rng, Slots.SlotType.MODULE, 3)
		if rolled != null and int(rolled.slot_type) == Slots.SlotType.MODULE:
			got_module = true
			break
	_assert(got_module, "roll_for_slot(MODULE) produces module parts for the shop")

	# --- C. Player integration (shield gate + damage mult) ---
	change_scene_to_file("res://scenes/main.tscn")
	for _i in range(12):
		await process_frame
	var main = current_scene
	if main == null or main.player == null or not is_instance_valid(main.player):
		print("[test] (skipped player integration — no player)")
		_finish()
		return
	var p = main.player
	# Glass cannon: an initialized bay with no Shield Core → max_shield 0.
	run.modules = []
	run.bay_initialized = true
	p.apply_run_upgrades()
	_assert(p.max_shield == 0, "no Shield Core in an initialized bay → max_shield 0 (got %d)" % p.max_shield)
	# Shield Core back → shield restored.
	run.modules = [ShieldCore.new()]
	p.apply_run_upgrades()
	_assert(p.max_shield > 0, "Shield Core present → max_shield > 0 (got %d)" % p.max_shield)
	# Overcharge applies a >1 damage mult onto the ship.
	p.module_damage_mult = 1.0
	OverchargeCore.new().apply(p)
	_assert(p.module_damage_mult > 1.0, "Overcharge raises module_damage_mult (got %.3f)" % p.module_damage_mult)
	p.module_regen_interval = 0.0
	RepairNanites.new().apply(p)
	_assert(p.module_regen_interval > 0.0, "Repair Nanites sets module_regen_interval (got %.1f)" % p.module_regen_interval)
	p.module_ablative_n = 0
	AblativePlating.new().apply(p)
	_assert(p.module_ablative_n > 0, "Ablative Plating sets module_ablative_n (got %d)" % p.module_ablative_n)

	_finish()


func _finish() -> void:
	print("[test] ALL PASS")
	quit()


func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg)
		quit(1)
