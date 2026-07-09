extends SceneTree

# Sector Conditions — PLAYER-KIT + LOADOUT effect-site test (WP §4b/§4c/§4d).
# Headless-testable surfaces only (no Player scene): the part_catalog No-X / hull-module
# pool filters, the run_state More-Ammo cap seam, and the starting-kit skips. The
# player-scene effects (weapon damage / fire rate / shields / modes) are verified by parse +
# code-reading, NOT by instantiating the player.
# Run: godot --headless --script res://tools/test_conditions_player.gd

const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const PartFactory = preload("res://scripts/parts/part_factory.gd")
const Slots = preload("res://scripts/weapons/SlotTypes.gd")


# Minimal loadout stand-in — records what default_starting_loadout equips.
class StubLoadout:
	var equips: Dictionary = {}
	func equip(slot, part) -> void:
		equips[slot] = part


# Minimal ship stand-in for a secondary Part's _apply_visuals — exposes the fields the
# secondary_weapon/bullet_secondary chain touches and records the (current, cap) pair the
# part writes via set_secondary_ammo. Must be in the tree so has_node("/root/Run") resolves.
class StubShip extends Node:
	var secondary_bullet_scene = null
	var secondary_mode: int = 0
	var secondary_homing: bool = false
	var secondary_pod_count: int = 1
	var last_ammo: int = -999
	var last_cap: int = -999
	func set_secondary_ammo(value: int, maximum: int = -1) -> void:
		last_ammo = value
		last_cap = maximum


func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var lines: Array = []
	var fails := 0
	var run = root.get_node("/root/Run")

	# ── (a) part_catalog pool filters ────────────────────────────────────────
	# No Primaries blocks every CANNON entry: roll_for_slot(CANNON) returns null across seeds.
	run.new_run()
	run.active_conditions = ["no_primaries"]
	var cannon_leaks := 0
	for s in range(60):
		var rng := RandomNumberGenerator.new()
		rng.seed = 4000 + s * 17
		var p = PartCatalog.roll_for_slot(rng, Slots.SlotType.CANNON, 1)
		if p != null:
			cannon_leaks += 1
	lines.append("no_primaries: roll_for_slot(CANNON) non-null across 60 seeds = %d (expect 0)" % cannon_leaks)
	if cannon_leaks != 0:
		lines.append("FAIL roll_for_slot leaked a CANNON under No Primaries"); fails += 1

	# roll_random_part never yields a CANNON-slot part under No Primaries.
	var rr_cannon := 0
	var rr_total := 0
	for s in range(200):
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 9000 + s * 13
		var part = PartCatalog.roll_random_part(rng2)
		if part == null:
			continue
		rr_total += 1
		if "slot_type" in part and int(part.slot_type) == Slots.SlotType.CANNON:
			rr_cannon += 1
	lines.append("no_primaries: roll_random_part CANNON slots = %d / %d rolls" % [rr_cannon, rr_total])
	if rr_cannon != 0:
		lines.append("FAIL roll_random_part returned a CANNON under No Primaries"); fails += 1
	if rr_total == 0:
		lines.append("FAIL roll_random_part produced nothing at all"); fails += 1

	# No Secondaries / No Modules block their slots too (HARDPOINT_WING / MODULE / SHIFT_MODE).
	run.active_conditions = ["no_secondaries", "no_modules"]
	var bad_slots := 0
	for s in range(200):
		var rng3 := RandomNumberGenerator.new()
		rng3.seed = 11000 + s * 7
		var part2 = PartCatalog.roll_random_part(rng3)
		if part2 == null or not ("slot_type" in part2):
			continue
		var st: int = int(part2.slot_type)
		if st == Slots.SlotType.HARDPOINT_WING or st == Slots.SlotType.MODULE or st == Slots.SlotType.SHIFT_MODE:
			bad_slots += 1
	lines.append("no_secondaries+no_modules: blocked-slot leaks = %d (expect 0)" % bad_slots)
	if bad_slots != 0:
		lines.append("FAIL roll_random_part leaked a blocked slot"); fails += 1

	# Glass Patrol pulls the hull/ablative modules from the pool.
	run.active_conditions = ["glass_patrol"]
	var hull_mod_leaks := 0
	for s in range(300):
		var rng4 := RandomNumberGenerator.new()
		rng4.seed = 13000 + s * 5
		var part3 = PartCatalog.roll_random_part(rng4)
		if part3 == null or not ("display_name" in part3):
			continue
		var dn := String(part3.display_name)
		# Reinforced Hull + Ablative Plating are the two blocked hull modules.
		if dn == "Reinforced Hull" or dn == "Ablative Plating":
			hull_mod_leaks += 1
	lines.append("glass_patrol: hull-module leaks across 300 rolls = %d (expect 0)" % hull_mod_leaks)
	if hull_mod_leaks != 0:
		lines.append("FAIL Glass Patrol did not pull hull modules"); fails += 1

	# Codex index is NOT filtered — _build_display_index shows everything regardless of Conditions.
	PartCatalog._display_to_factory = {}
	run.active_conditions = []
	PartCatalog._build_display_index()
	var full_index: int = PartCatalog._display_to_factory.size()
	PartCatalog._display_to_factory = {}
	run.active_conditions = ["no_primaries", "no_secondaries", "no_modules", "glass_patrol"]
	PartCatalog._build_display_index()
	var blocked_index: int = PartCatalog._display_to_factory.size()
	PartCatalog._display_to_factory = {}  # reset the static cache for anyone downstream
	lines.append("codex index size: unfiltered=%d, under-conditions=%d" % [full_index, blocked_index])
	if full_index != blocked_index or full_index <= 0:
		lines.append("FAIL codex display index changed under Conditions"); fails += 1

	# ── (b) run_state More-Ammo cap seam ─────────────────────────────────────
	run.new_run()
	# _cond_ammo_cap math: 1.5× rounded, unmetered/zero passthrough.
	run.active_conditions = ["more_ammo"]
	var cap_100: int = run._cond_ammo_cap(100)
	var cap_neg: int = run._cond_ammo_cap(-1)
	var cap_zero: int = run._cond_ammo_cap(0)
	lines.append("more_ammo: _cond_ammo_cap 100->%d, -1->%d, 0->%d" % [cap_100, cap_neg, cap_zero])
	if cap_100 != roundi(100 * 1.5):
		lines.append("FAIL _cond_ammo_cap(100) expected %d" % roundi(100 * 1.5)); fails += 1
	if cap_neg != -1 or cap_zero != 0:
		lines.append("FAIL _cond_ammo_cap should pass unmetered/zero through"); fails += 1
	# No-condition identity.
	run.active_conditions = []
	if run._cond_ammo_cap(100) != 100:
		lines.append("FAIL _cond_ammo_cap identity without Conditions"); fails += 1

	# Drive _seed_secondary_ammo with a real metered secondary (Rocket Pod) and confirm the
	# established cap is the scaled value.
	run.active_conditions = ["more_ammo"]
	var rocket = PartCatalog._make_by_name("_make_rocket_pod", Slots.SlotType.HARDPOINT_WING)
	if rocket != null and rocket.has_method("_base_ammo"):
		var base_sec: int = int(rocket._base_ammo())
		run._seed_secondary_ammo(rocket, true)
		var expect_sec: int = run._cond_ammo_cap(base_sec)
		lines.append("more_ammo: rocket base_ammo=%d -> secondary_ammo_max=%d (expect %d)"
			% [base_sec, int(run.secondary_ammo_max), expect_sec])
		if base_sec > 0 and int(run.secondary_ammo_max) != expect_sec:
			lines.append("FAIL _seed_secondary_ammo did not scale the cap"); fails += 1
		if base_sec > 0 and int(run.secondary_ammo) != expect_sec:
			lines.append("FAIL _seed_secondary_ammo current != scaled cap at seed"); fails += 1

		# Fix 1 - the PART-APPLY cap must scale too, not just the run-side seed. Prior bug:
		# bullet_secondary wrote the ship cap from the UNSCALED _base_ammo() while current came
		# from the scaled run seed, giving current>max (90 rockets seeded into a 60 cap). Drive
		# Rocket Pod._apply_visuals against a stub ship; the recorded cap must be the scaled value
		# and current must never exceed it. (metered_primary / swarm_launcher / drone_swarm share
		# the identical set-cap seam - verified by parse + code-reading.)
		var rp = PartCatalog._make_by_name("_make_rocket_pod", Slots.SlotType.HARDPOINT_WING)
		if rp != null and rp.has_method("_apply_visuals") and rp.has_method("_base_ammo"):
			var rp_base: int = int(rp._base_ammo())
			run._seed_secondary_ammo(rp, true)  # run.secondary_ammo/_max = scaled cap
			var stub := StubShip.new()
			root.add_child(stub)
			rp._apply_visuals(stub)
			var got_cap: int = stub.last_cap
			var got_cur: int = stub.last_ammo
			root.remove_child(stub)
			stub.free()
			var rp_expect: int = run._cond_ammo_cap(rp_base)
			lines.append("more_ammo: rocket _apply_visuals ship cap=%d current=%d (expect cap=%d, current<=cap)"
				% [got_cap, got_cur, rp_expect])
			if got_cap != rp_expect:
				lines.append("FAIL bullet_secondary part-apply wrote an UNSCALED ship cap"); fails += 1
			if got_cur > got_cap:
				lines.append("FAIL part-apply produced a current>max transient"); fails += 1
		else:
			lines.append("NOTE rocket pod unavailable for part-apply cap assertion")
	else:
		lines.append("NOTE rocket pod has no _base_ammo — skipped secondary seed assertion")

	# ── (c) starting-kit skips ───────────────────────────────────────────────
	# Without the flags, both DEVICE_BAY_1 (super) and SHIFT_MODE (mode) are equipped.
	run.new_run()
	run.active_conditions = []
	var lo_full := StubLoadout.new()
	PartFactory.default_starting_loadout(lo_full)
	var has_super_full: bool = lo_full.equips.has(Slots.SlotType.DEVICE_BAY_1)
	var has_mode_full: bool = lo_full.equips.has(Slots.SlotType.SHIFT_MODE)
	lines.append("no-flags: super=%s mode=%s (expect true/true)" % [str(has_super_full), str(has_mode_full)])
	if not has_super_full or not has_mode_full:
		lines.append("FAIL baseline loadout missing super/mode"); fails += 1

	# With both flags, the super + mode are skipped (engine + cannon still equipped).
	run.active_conditions = ["no_starting_super", "no_starting_mode"]
	var lo_skip := StubLoadout.new()
	PartFactory.default_starting_loadout(lo_skip)
	var has_super_skip: bool = lo_skip.equips.has(Slots.SlotType.DEVICE_BAY_1)
	var has_mode_skip: bool = lo_skip.equips.has(Slots.SlotType.SHIFT_MODE)
	var has_cannon_skip: bool = lo_skip.equips.has(Slots.SlotType.CANNON)
	lines.append("both-flags: super=%s mode=%s cannon=%s (expect false/false/true)"
		% [str(has_super_skip), str(has_mode_skip), str(has_cannon_skip)])
	if has_super_skip:
		lines.append("FAIL No Starting Super did not skip DEVICE_BAY_1"); fails += 1
	if has_mode_skip:
		lines.append("FAIL No Starting Mode did not skip SHIFT_MODE"); fails += 1
	if not has_cannon_skip:
		lines.append("FAIL loadout dropped the cannon (over-filtered)"); fails += 1

	# _seed_default_loadout_snapshot honors the same flags (meta-scene snapshot parity).
	# Mirror new_run()'s fresh-dict precondition (it does loadout_snapshot = {} before seeding);
	# the seed only ADDS, never erases stale slots, so start clean.
	run.active_conditions = ["no_starting_super", "no_starting_mode"]
	run.loadout_snapshot = {}
	run._seed_default_loadout_snapshot()
	var snap_super: bool = run.loadout_snapshot.has(Slots.SlotType.DEVICE_BAY_1)
	var snap_mode: bool = run.loadout_snapshot.has(Slots.SlotType.SHIFT_MODE)
	lines.append("snapshot both-flags: super=%s mode=%s (expect false/false)" % [str(snap_super), str(snap_mode)])
	if snap_super or snap_mode:
		lines.append("FAIL _seed_default_loadout_snapshot ignored the skip flags"); fails += 1

	run.new_run()  # leave Run clean
	lines.append("CONDITIONS_PLAYER: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	for l in lines:
		print("[test] " + l)
	quit()
