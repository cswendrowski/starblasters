extends SceneTree

# Per-ship starting-kit verification (2026-07-11 — docs/ship_starting_loadouts_2026-07-11.md).
# For each ShipCatalog variant: new_run + reseed_loadout_for_ship, then assert the seeded
# cannon pool / secondary / module bay / shift mode / meta hull+shield capacities match the
# authored kit. Instantiates run_state.gd directly (autoloads don't exist under -s).
# Run: godot --headless -s res://tools/test_ship_loadouts.gd  (prints VERDICT: PASS/FAIL)

const ShipCatalog = preload("res://scripts/strings/ship_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")

var _fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func _module_ids(run) -> Array:
	var out: Array = []
	for m in run.modules:
		out.append("%s@%d" % [String(m.module_id), int(m.mark)])
	return out


func _mode_name(run) -> String:
	var mode = run.loadout_snapshot.get(SlotTypes.SlotType.SHIFT_MODE, null)
	return String(mode.display_name) if mode != null else "(none)"


func _init() -> void:
	var run = load("res://scripts/autoload/run_state.gd").new()

	# ship: [pool_names(mk), active_idx, secondary_name, module ids@mk, mode, max_shield, max_hull]
	var expected := {
		0: {"pool": ["Energy Blaster@1"], "active": 0, "sec": "", "mods": ["shield_core@1"], "mode": "Refire", "shield": 10, "hull": 3},
		1: {"pool": ["Energy Blaster@1", "Minigun@3"], "active": 1, "sec": "", "mods": ["ablative_plating@2", "repair_nanites@1", "ammo_pods@1"], "mode": "Focus", "shield": 0, "hull": 3},
		2: {"pool": ["Energy Blaster@1", "Autocannon@2"], "active": 1, "sec": "", "mods": ["reinforced_hull@3", "repair_nanites@1", "ammo_pods@1"], "mode": "Focus", "shield": 0, "hull": 6},
		3: {"pool": ["Energy Blaster@1"], "active": 0, "sec": "", "mods": ["ablative_plating@2", "reinforced_hull@4"], "mode": "Rush", "shield": 0, "hull": 7},
		4: {"pool": ["Twin Blaster@3"], "active": 0, "sec": "", "mods": ["system_delimiter@1", "overcharge_core@2"], "mode": "Refire", "shield": 0, "hull": 3},
		5: {"pool": ["Scatter Blaster@1"], "active": 0, "sec": "", "mods": ["shield_core_corpo@1"], "mode": "Echo", "shield": 5, "hull": 3},
		6: {"pool": ["Energy Blaster@1"], "active": 0, "sec": "Seeking Missile", "mods": ["shield_core_corpo@1"], "mode": "Hyper Mode", "shield": 5, "hull": 3},
		7: {"pool": ["Heavy Blaster@1"], "active": 0, "sec": "", "mods": ["overclock_core@2", "targeting_computer@2", "thrusters@2"], "mode": "Focus", "shield": 0, "hull": 3},
		8: {"pool": ["Twin Blaster@1", "Auto Laser@1"], "active": 1, "sec": "", "mods": ["reinforced_hull@4"], "mode": "Rush", "shield": 0, "hull": 7},
		9: {"pool": ["Energy Blaster@1"], "active": 0, "sec": "Combat Drones", "mods": ["shield_core_corpo@1", "intercept_drones@1", "micro_fabricator@1", "repair_nanites@1"], "mode": "Thief", "shield": 5, "hull": 3},
	}
	_check(ShipCatalog.count() == expected.size(), "ship count %d != expected %d" % [ShipCatalog.count(), expected.size()])

	for v in expected.keys():
		var e: Dictionary = expected[v]
		run.new_run()
		run.ship_variant = v
		run.reseed_loadout_for_ship()
		var ship_name := String(ShipCatalog.get_ship(v)["name"])

		var pool: Array = []
		for c in run.cannon_pool:
			pool.append("%s@%d" % [String(c.display_name), int(c.mark)])
		_check(pool == e["pool"], "%s: cannon_pool %s != %s" % [ship_name, pool, e["pool"]])
		_check(int(run.active_cannon_idx) == int(e["active"]), "%s: active idx %d != %d" % [ship_name, run.active_cannon_idx, e["active"]])
		var snap_cannon = run.loadout_snapshot.get(SlotTypes.SlotType.CANNON, null)
		_check(snap_cannon == run.get_active_cannon(), "%s: snapshot CANNON is not the active cannon" % ship_name)

		var sec = run.loadout_snapshot.get(SlotTypes.SlotType.HARDPOINT_WING, null)
		var sec_name := String(sec.display_name) if sec != null else ""
		_check(sec_name == String(e["sec"]), "%s: secondary '%s' != '%s'" % [ship_name, sec_name, e["sec"]])
		if sec != null:
			# Only ammo-backed secondaries seed Run.secondary_ammo (mirrors _seed_secondary_ammo:
			# Combat Drones carry no base_ammo — the part owns its counts at combat apply).
			var has_ammo: bool = sec.has_method("_base_ammo") or ("base_ammo" in sec and int(sec.base_ammo) > 0)
			if has_ammo:
				_check(int(run.secondary_ammo) >= 0, "%s: secondary_ammo not seeded (%d)" % [ship_name, run.secondary_ammo])

		_check(_module_ids(run) == e["mods"], "%s: modules %s != %s" % [ship_name, _module_ids(run), e["mods"]])
		_check(_mode_name(run) == String(e["mode"]), "%s: mode '%s' != '%s'" % [ship_name, _mode_name(run), e["mode"]])
		_check(int(run.max_shield) == int(e["shield"]), "%s: max_shield %d != %d" % [ship_name, run.max_shield, e["shield"]])
		_check(int(run.max_hull) == int(e["hull"]), "%s: max_hull %d != %d" % [ship_name, run.max_hull, e["hull"]])

		# Metered kit primaries must arrive with a full seeded magazine.
		if int(e["active"]) == 1:
			var prim = run.cannon_pool[1]
			_check(int(prim.current_ammo) > 0, "%s: primary magazine not seeded" % ship_name)

		# Super Pulse Bomb is universal.
		var sup = run.loadout_snapshot.get(SlotTypes.SlotType.DEVICE_BAY_1, null)
		_check(sup != null, "%s: missing starting super" % ship_name)

	# Shop pricing overrides on the two cores.
	var PartCatalog = load("res://scripts/parts/part_catalog.gd")
	var vintage = PartCatalog.make_part("_make_shield_core", 1)
	var corpo = PartCatalog.make_part("_make_corpo_shield_core", 1)
	_check(int(vintage.shop_base_cost) == 520 and int(vintage.shop_cost_per_mk) == 140,
		"vintage core pricing %d/%d != 520/140" % [vintage.shop_base_cost, vintage.shop_cost_per_mk])
	_check(int(corpo.shop_base_cost) == 380 and int(corpo.shop_cost_per_mk) == 90,
		"corpo core pricing %d/%d != 380/90" % [corpo.shop_base_cost, corpo.shop_cost_per_mk])
	_check(int(corpo.base_charges()) == 5 and int(vintage.base_charges()) == 10, "core base charges wrong")
	var corpo9 = PartCatalog.make_part("_make_corpo_shield_core", 9)
	_check(int(corpo9.base_charges()) + int(corpo9._capacity_bonus()) == 15, "corpo Mk.9 capacity != 15")

	run.free()
	if _fails.is_empty():
		print("VERDICT: PASS (%d ships)" % expected.size())
	else:
		for f in _fails:
			print("FAIL: ", f)
		print("VERDICT: FAIL (%d)" % _fails.size())
	quit(0 if _fails.is_empty() else 1)
