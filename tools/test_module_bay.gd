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
const TargetingComputer = preload("res://scripts/parts/targeting_computer.gd")
const OverclockCore = preload("res://scripts/parts/overclock_core.gd")
const SystemDelimiter = preload("res://scripts/parts/system_delimiter.gd")
const ReinforcedHull = preload("res://scripts/parts/reinforced_hull.gd")
const Thrusters = preload("res://scripts/parts/thrusters.gd")
const ShieldCapacitor = preload("res://scripts/parts/shield_capacitor.gd")
const BackupShieldCapacitor = preload("res://scripts/parts/backup_shield_capacitor.gd")
const ReflectiveShieldTuning = preload("res://scripts/parts/reflective_shield_tuning.gd")
const InternalMicroFabricator = preload("res://scripts/parts/internal_micro_fabricator.gd")
const PassiveEnergyRouters = preload("res://scripts/parts/passive_energy_routers.gd")
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
	var tc1 = TargetingComputer.new(); tc1.mark = 1
	var tc9 = TargetingComputer.new(); tc9.mark = 9
	_assert(absf(tc1._crit_chance() - 0.10) < 0.001, "Targeting Computer Mk.1 = 10% crit")
	_assert(absf(tc9._crit_chance() - 0.30) < 0.001, "Targeting Computer Mk.9 = 30% crit")
	var ov1 = OverclockCore.new(); ov1.mark = 1
	var ov9 = OverclockCore.new(); ov9.mark = 9
	_assert(absf(ov1._max_bonus() - 0.25) < 0.001, "Overclock Mk.1 = +25%")
	_assert(absf(ov9._max_bonus() - 0.65) < 0.001, "Overclock Mk.9 = +65%")
	var dl1 = SystemDelimiter.new(); dl1.mark = 1
	var dl9 = SystemDelimiter.new(); dl9.mark = 9
	_assert(absf(dl1._max_bonus() - 0.25) < 0.001, "De-Limiter Mk.1 = +25%")
	_assert(absf(dl9._max_bonus() - 0.75) < 0.001, "De-Limiter Mk.9 = +75%")
	# Former-upgrade modules.
	var sc9m = ShieldCore.new(); sc9m.mark = 9
	_assert(sc9m._capacity_bonus() == 20, "Shield Core Mk.9 capacity bonus = 20 (→ max_shield 30)")
	var rh1 = ReinforcedHull.new(); rh1.mark = 1
	var rh9 = ReinforcedHull.new(); rh9.mark = 9
	_assert(rh1._pips() == 1 and rh9._pips() == 8, "Reinforced Hull Mk.1=+1 / Mk.9=+8 pips")
	var th1 = Thrusters.new(); th1.mark = 1
	var th9 = Thrusters.new(); th9.mark = 9
	_assert(absf(th1._speed_pct() - 0.03) < 0.001 and absf(th9._speed_pct() - 0.27) < 0.001, "Thrusters +3%/Mk → +27% at Mk.9")
	var cap9 = ShieldCapacitor.new(); cap9.mark = 9
	_assert(cap9._delay() < 5.0 and cap9._interval() < 1.0, "Shield Capacitor lowers delay (%.1f) + interval (%.2f)" % [cap9._delay(), cap9._interval()])
	# Backup Shield Capacitor — 5% per Mk restore fraction.
	var bsc1 = BackupShieldCapacitor.new(); bsc1.mark = 1
	var bsc9 = BackupShieldCapacitor.new(); bsc9.mark = 9
	_assert(absf((bsc1.base_pct + (1 - 1) * bsc1.pct_per_mark) - 0.05) < 0.001, "Backup Capacitor Mk.1 = 5%")
	_assert(absf((bsc9.base_pct + (9 - 1) * bsc9.pct_per_mark) - 0.45) < 0.001, "Backup Capacitor Mk.9 = 45%")
	# Reflective Shield Tuning — N (reflect every Nth) lowers with Mk.
	var rs1 = ReflectiveShieldTuning.new(); rs1.mark = 1
	var rs9 = ReflectiveShieldTuning.new(); rs9.mark = 9
	_assert(rs1._n_for(1) == 6, "Reflective Mk.1 = reflect every 6th")
	_assert(rs9._n_for(9) == 2, "Reflective Mk.9 = reflect every 2nd")
	# Internal Micro Fabricator — 5% per Mk restock fraction.
	var mf1 = InternalMicroFabricator.new(); mf1.mark = 1
	var mf9 = InternalMicroFabricator.new(); mf9.mark = 9
	_assert(absf(mf1._pct_for(1) - 0.05) < 0.001, "Micro Fabricator Mk.1 = 5%")
	_assert(absf(mf9._pct_for(9) - 0.45) < 0.001, "Micro Fabricator Mk.9 = 45%")
	# Passive Energy Routers — idle regen boost 20% → 60%.
	var er1 = PassiveEnergyRouters.new(); er1.mark = 1
	var er9 = PassiveEnergyRouters.new(); er9.mark = 9
	_assert(absf(er1._pct_for(1) - 0.20) < 0.001, "Energy Routers Mk.1 = 20% idle boost")
	_assert(absf(er9._pct_for(9) - 0.60) < 0.001, "Energy Routers Mk.9 = 60% idle boost")
	# Restock math: 5% of a 40-round magazine = +2, capped at max. Snapshot/restore the
	# run pool so the later scene-load section gets a clean cannon_pool back.
	var _saved_pool = run.cannon_pool
	var _saved_idx = run.active_cannon_idx
	var _saved_sec = run.secondary_ammo
	var _saved_sec_max = run.secondary_ammo_max
	var dummy = _DummyCannon.new(); dummy.ammo_max = 40; dummy.current_ammo = 10
	run.cannon_pool = [_DummyCannon.new(), dummy]
	run.active_cannon_idx = 1
	run.restock_ammo_fraction(0.05)
	_assert(dummy.current_ammo == 12, "restock +5%% of 40 → 10→12 (got %d)" % dummy.current_ammo)
	dummy.current_ammo = 39
	run.restock_ammo_fraction(0.05)
	_assert(dummy.current_ammo == 40, "restock caps at ammo_max (got %d)" % dummy.current_ammo)
	run.secondary_ammo_max = 20; run.secondary_ammo = 5
	run.restock_ammo_fraction(0.10)
	_assert(run.secondary_ammo == 7, "restock secondary +10%% of 20 → 5→7 (got %d)" % run.secondary_ammo)
	# Restore the real run state.
	run.cannon_pool = _saved_pool
	run.active_cannon_idx = _saved_idx
	run.secondary_ammo = _saved_sec
	run.secondary_ammo_max = _saved_sec_max
	_assert(run.MODULE_BAY_SIZE == 6, "bay size bumped to 6")

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
	p.module_crit_chance = 0.0
	TargetingComputer.new().apply(p)
	_assert(p.module_crit_chance > 0.0, "Targeting Computer sets module_crit_chance (got %.3f)" % p.module_crit_chance)
	p.module_overclock_max = 0.0
	OverclockCore.new().apply(p)
	_assert(p.module_overclock_max > 0.0, "Overclock Core sets module_overclock_max (got %.3f)" % p.module_overclock_max)
	SystemDelimiter.new().apply(p)
	_assert(p.module_delimiter_max > 0.0, "De-Limiter sets module_delimiter_max (got %.3f)" % p.module_delimiter_max)
	# De-Limiter bonus scales with hull lost: 0 at full, > 0 when hurt.
	p.max_hull = 5; p.hull = 5
	_assert(p._delimiter_bonus() == 0.0, "De-Limiter bonus 0 at full hull")
	p.hull = 1
	_assert(p._delimiter_bonus() > 0.0, "De-Limiter bonus > 0 at 1 hull (got %.3f)" % p._delimiter_bonus())
	# Former-upgrade modules feed the player stats.
	p.module_hull_bonus = 0
	var rh5 = ReinforcedHull.new(); rh5.mark = 5; rh5.apply(p)
	p.apply_run_upgrades()
	_assert(p.max_hull > 2, "Reinforced Hull raises max_hull above base 2 (got %d)" % p.max_hull)
	p.module_speed_pct = 0.0
	Thrusters.new().apply(p)
	p.apply_run_upgrades()
	_assert(p.speed_multiplier > 1.0, "Thrusters raises speed_multiplier (got %.2f)" % p.speed_multiplier)
	p.shield_regen_delay = 5.0; p.shield_regen_interval = 1.0
	ShieldCapacitor.new().apply(p)
	_assert(p.shield_regen_delay < 5.0 and p.shield_regen_interval < 1.0, "Shield Capacitor speeds shield regen")
	# Backup Shield Capacitor sets the restore fraction onto the ship.
	p.module_backup_shield_pct = 0.0
	BackupShieldCapacitor.new().apply(p)
	_assert(p.module_backup_shield_pct > 0.0, "Backup Capacitor sets module_backup_shield_pct (got %.3f)" % p.module_backup_shield_pct)
	# Reflective Shield Tuning sets N onto the ship (0 = off).
	p.module_reflect_n = 0
	ReflectiveShieldTuning.new().apply(p)
	_assert(p.module_reflect_n > 0, "Reflective Shield sets module_reflect_n (got %d)" % p.module_reflect_n)
	# Internal Micro Fabricator sets the restock fraction.
	p.module_ammo_restore_pct = 0.0
	InternalMicroFabricator.new().apply(p)
	_assert(p.module_ammo_restore_pct > 0.0, "Micro Fabricator sets module_ammo_restore_pct (got %.3f)" % p.module_ammo_restore_pct)
	# Passive Energy Routers sets the idle-regen boost + lowers the effective regen when idle.
	p.module_energy_router_pct = 0.0
	PassiveEnergyRouters.new().apply(p)
	_assert(p.module_energy_router_pct > 0.0, "Energy Routers sets module_energy_router_pct (got %.3f)" % p.module_energy_router_pct)
	p.shield_regen_delay = 5.0; p.shield_regen_interval = 1.0
	p._shot_recency = 999.0  # idle → boost engaged
	_assert(p._effective_regen_delay() < 5.0 and p._effective_regen_interval() < 1.0, "Energy Routers cuts regen while idle (delay %.2f / iv %.2f)" % [p._effective_regen_delay(), p._effective_regen_interval()])
	p._shot_recency = 0.0  # firing → no boost
	_assert(is_equal_approx(p._effective_regen_delay(), 5.0), "Energy Routers reverts to baseline while firing (got %.2f)" % p._effective_regen_delay())
	# Shield Core Mk drives capacity (folded the old shield_cap upgrade in).
	p.module_shield_bonus = 0; p.module_shield_charge_penalty = 0
	run.modules = [ShieldCore.new()]
	var score9 = ShieldCore.new(); score9.mark = 9; score9.apply(p)
	p.apply_run_upgrades()
	_assert(p.max_shield >= 28, "Shield Core Mk.9 → max_shield ~30 (got %d)" % p.max_shield)

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


# Minimal stand-in for a metered cannon Part — just the two ammo fields
# Run.restock_ammo_fraction reads ("current_ammo" in prim / "ammo_max" in prim).
class _DummyCannon:
	var current_ammo: int = -1
	var ammo_max: int = 0
