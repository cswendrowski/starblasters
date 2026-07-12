extends SceneTree

# Sector Conditions — ECONOMY + GRANTS effect-site test (WP §4e/§4f/§5/§8).
# Covers the Run-side award choke points (award_bounty / award_combat_materials
# math, incl. the boon-only floor), record_kill's awarded return, the new
# mine_bonus_bounty field (new_run reset + save-surface membership), the
# cruiser-encounter mult reading the new cruiser.encounter_mult key, and that the
# catalog still validates 0 problems after the repair-entry edits.
# Run: godot --headless --script res://tools/test_conditions_economy.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var lines: Array = []
	var fails := 0
	var run = root.get_node("/root/Run")

	# 0. Catalog still clean after the complex/cheap/easy repair-entry edits.
	var problems: Array = Conditions.validate()
	lines.append("validate() problems: %d %s" % [problems.size(), str(problems)])
	if problems.size() != 0:
		lines.append("FAIL validate() reported problems"); fails += 1

	# 1. award_bounty — mult applied, bounty + stat advance by the AWARDED amount,
	#    and the return equals the delta. heavy_ordnance T=4 → 1 + 0.08*4 = 1.32.
	run.new_run()
	run.active_conditions = ["heavy_ordnance"]
	var b0: int = int(run.bounty)
	var s0: int = int(run.run_stats.get("bounty_gained", 0))
	var awarded: int = run.award_bounty(100)
	# Reward coupling CUT 2026-07-09 (K_BOUNTY = 0.0): award is the FLAT amount (was 132 at T4).
	var expected: int = 100
	lines.append("award_bounty(100)|T4 => awarded=%d bountyΔ=%d statΔ=%d (expect %d)"
		% [awarded, int(run.bounty) - b0, int(run.run_stats.get("bounty_gained", 0)) - s0, expected])
	if awarded != expected:
		lines.append("FAIL award_bounty return"); fails += 1
	if int(run.bounty) - b0 != expected:
		lines.append("FAIL award_bounty bounty delta"); fails += 1
	if int(run.run_stats.get("bounty_gained", 0)) - s0 != expected:
		lines.append("FAIL award_bounty stat delta"); fails += 1

	# 1b. record_kill routes through award_bounty and returns the awarded amount.
	var kb0: int = int(run.bounty)
	var kills0: int = int(run.enemies_killed)
	var kawarded: int = run.record_kill(100)
	lines.append("record_kill(100)|T4 => %d (killsΔ=%d)" % [kawarded, int(run.enemies_killed) - kills0])
	if kawarded != expected:
		lines.append("FAIL record_kill return"); fails += 1
	if int(run.bounty) - kb0 != expected:
		lines.append("FAIL record_kill bounty delta"); fails += 1
	if int(run.enemies_killed) - kills0 != 1:
		lines.append("FAIL record_kill did not tally a kill"); fails += 1

	# 1c. Boon-only list floors the multiplier at 1.0 (net-negative Threat) → no scaling.
	run.new_run()
	run.active_conditions = ["better_weapons"]  # T = -2
	var bb0: int = int(run.bounty)
	var boon_awarded: int = run.award_bounty(100)
	lines.append("award_bounty(100)|boon-only => %d (floored, expect 100)" % boon_awarded)
	if boon_awarded != 100 or int(run.bounty) - bb0 != 100:
		lines.append("FAIL boon-only award should floor at raw amount"); fails += 1

	# 1d. Empty active_conditions is a strict no-op (mult 1.0), works at run start.
	run.new_run()
	var empty_awarded: int = run.award_bounty(50)
	if empty_awarded != 50:
		lines.append("FAIL empty-conditions award should be identity (%d)" % empty_awarded); fails += 1

	# 2. award_combat_materials — mult applied via add_materials; return = awarded.
	#    heavy_ordnance materials_mult = 1 + 0.06*4 = 1.24 → round(100*1.24)=124.
	run.new_run()
	run.active_conditions = ["heavy_ordnance"]
	var m0: int = int(run.materials)
	var mg0: int = int(run.run_stats.get("materials_gained", 0))
	var mat_awarded: int = run.award_combat_materials(100)
	# Reward coupling CUT 2026-07-09 (K_MATERIALS = 0.0): award is the FLAT amount (was 124 at T4).
	var mat_expected: int = 100
	lines.append("award_combat_materials(100)|T4 => awarded=%d matΔ=%d statΔ=%d (expect %d)"
		% [mat_awarded, int(run.materials) - m0, int(run.run_stats.get("materials_gained", 0)) - mg0, mat_expected])
	if mat_awarded != mat_expected:
		lines.append("FAIL award_combat_materials return"); fails += 1
	if int(run.materials) - m0 != mat_expected:
		lines.append("FAIL award_combat_materials materials delta"); fails += 1
	if int(run.run_stats.get("materials_gained", 0)) - mg0 != mat_expected:
		lines.append("FAIL award_combat_materials stat delta"); fails += 1

	# 3. mine_bonus_bounty — resets in new_run() and is in the save whitelist,
	#    with a matching @export on RunSave (save-surface lockstep).
	run.mine_bonus_bounty = 5
	run.new_run()
	lines.append("mine_bonus_bounty after new_run = %d" % int(run.mine_bonus_bounty))
	if int(run.mine_bonus_bounty) != 0:
		lines.append("FAIL new_run did not reset mine_bonus_bounty"); fails += 1
	if not run._SAVE_FIELDS.has("mine_bonus_bounty"):
		lines.append("FAIL mine_bonus_bounty missing from _SAVE_FIELDS"); fails += 1
	var rs = load("res://scripts/game/run_save.gd").new()
	var has_export := false
	for prop in rs.get_property_list():
		if (int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and String(prop.name) == "mine_bonus_bounty":
			has_export = true
	if not has_export:
		lines.append("FAIL RunSave has no mine_bonus_bounty @export (save-surface drift)"); fails += 1

	# 4. cruiser_encounter_chance_mult reads the new cruiser.encounter_mult key.
	run.new_run()
	if not is_equal_approx(run.cruiser_encounter_chance_mult(), 1.0):
		lines.append("FAIL cruiser mult should be 1.0 with no conditions (%s)" % str(run.cruiser_encounter_chance_mult())); fails += 1
	run.active_conditions = ["heavy_escort"]
	var cm: float = run.cruiser_encounter_chance_mult()
	lines.append("cruiser mult|heavy_escort = %s" % str(cm))
	if not is_equal_approx(cm, 2.75):
		lines.append("FAIL cruiser mult should read cruiser.encounter_mult (2.75)"); fails += 1

	# 5. Grant sums resolve through the generic aggregator (mine/asteroid bounty).
	run.active_conditions = ["ordnance_disposal", "mining_contract"]
	if int(run.cond_sum("grant.mine_bounty")) != 5:
		lines.append("FAIL grant.mine_bounty sum"); fails += 1
	if int(run.cond_sum("grant.asteroid_bounty")) != 5:
		lines.append("FAIL grant.asteroid_bounty sum"); fails += 1

	# 6. Repair cost model (design §8, Roman 2026-07-11) — baseline is now bounty + 1
	#    material, and all four repair conditions share ONE mutex group. Outpost cost
	#    funcs need a live scene, so assert at the CATALOG + Run-cond surface the outpost
	#    reads. Baseline mats = REPAIR_BASE_MATERIALS(1) + cond_sum(repair_mat_delta),
	#    zeroed by the repair_no_mats flag.
	const REPAIR_BASE_MATERIALS := 1
	for rid in ["complex_repairs", "cheap_repairs", "costly_repairs", "easy_repairs"]:
		if String(Conditions.group_of(rid)) != "econ_repair":
			lines.append("FAIL %s not in merged 'econ_repair' group (got '%s')" % [rid, Conditions.group_of(rid)]); fails += 1
	# cheap_repairs: mat_delta now 1 (baseline 1 + 1 = 2 total), no bounty.
	if int(Conditions.CATALOG["cheap_repairs"]["mods"]["econ.repair_mat_delta"]) != 1:
		lines.append("FAIL cheap_repairs mat_delta should be 1 (baseline+1=2 total)"); fails += 1
	if not bool(Conditions.CATALOG["cheap_repairs"]["mods"].get("econ.repair_no_bounty", false)):
		lines.append("FAIL cheap_repairs should zero bounty"); fails += 1
	# Run-cond surface the outpost reads for each active repair condition.
	run.new_run()  # no conditions → baseline mats = 1, full bounty.
	var base_mats: int = REPAIR_BASE_MATERIALS + (0 if run.cond_flag("econ.repair_no_mats") else int(run.cond_sum("econ.repair_mat_delta")))
	if base_mats != 1:
		lines.append("FAIL baseline repair mats should be 1, got %d" % base_mats); fails += 1
	run.active_conditions = ["cheap_repairs"]  # no bounty, 2 mats
	var cheap_mats: int = REPAIR_BASE_MATERIALS + int(run.cond_sum("econ.repair_mat_delta"))
	if not run.cond_flag("econ.repair_no_bounty") or cheap_mats != 2:
		lines.append("FAIL cheap_repairs run surface (no_bounty=%s mats=%d)" % [str(run.cond_flag("econ.repair_no_bounty")), cheap_mats]); fails += 1
	run.active_conditions = ["complex_repairs"]  # bounty + 2 mats
	if REPAIR_BASE_MATERIALS + int(run.cond_sum("econ.repair_mat_delta")) != 2:
		lines.append("FAIL complex_repairs should total 2 mats"); fails += 1
	run.active_conditions = ["costly_repairs"]  # bounty ×1.5 + baseline 1 mat
	if not is_equal_approx(run.cond_scalar("econ.repair_cost_mult"), 1.5) or REPAIR_BASE_MATERIALS + int(run.cond_sum("econ.repair_mat_delta")) != 1:
		lines.append("FAIL costly_repairs should be 1.5x bounty + 1 mat"); fails += 1
	run.active_conditions = ["easy_repairs"]  # bounty only, no mats
	if not run.cond_flag("econ.repair_no_mats"):
		lines.append("FAIL easy_repairs should strip materials (repair_no_mats)"); fails += 1
	lines.append("repair model: baseline 1 mat; cheap=2/no-bounty, complex=2, costly=1.5x+1, easy=0-mat")

	run.new_run()  # leave Run clean
	lines.append("CONDITIONS_ECONOMY: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	for l in lines:
		print("[test] " + l)
	quit()
