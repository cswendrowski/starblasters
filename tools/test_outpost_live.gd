extends SceneTree

# Headless LIVE-path driver for the production dock (OutpostArrival wired to a real Run). The mock
# drivers only exercise run_seed==0; this seeds a real Run + loadout and runs every LIVE op, asserting
# the Run mutations — catching the bugs the mock path hides.

const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")

var _oa
var _fails: int = 0


func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  ok: %s" % msg)
	else:
		_fails += 1
		print("  FAIL: %s" % msg)


func _init() -> void:
	# Autoloads aren't loaded in `-s` SceneTree mode — instantiate Run manually at /root/Run.
	var run = get_root().get_node_or_null("/root/Run")
	if run == null:
		run = load("res://scripts/autoload/run_state.gd").new()
		run.name = "Run"
		get_root().add_child(run)
	if run.has_method("new_run"):
		run.new_run()
	run.run_seed = 12345
	run.bounty = 5000
	run.materials = 50
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	# Loadout: a metered primary cannon + a secondary; a module; two parts in the hold.
	var cannon = PartCatalog.roll_for_slot(rng, SlotTypes.SlotType.CANNON, 3)
	if cannon != null:
		run.equip_part(cannon)
	var secondary = PartCatalog.roll_for_slot(rng, SlotTypes.SlotType.HARDPOINT_WING, 2)
	if secondary != null:
		run.equip_part(secondary)
	var module = PartCatalog.roll_for_slot(rng, SlotTypes.SlotType.MODULE, 2)
	if module != null:
		run.add_module(module)
	var stored = PartCatalog.roll_for_slot(rng, SlotTypes.SlotType.HARDPOINT_WING, 1)
	if stored != null:
		run.weapon_storage.append(stored)
	var inv = PartCatalog.roll_for_slot(rng, SlotTypes.SlotType.MODULE, 1)
	if inv != null:
		run.inventory.append(inv)
	run.outpost_weapon_offers = []   # force a fresh market roll
	run.outpost_needs_refresh = false

	_oa = load("res://scenes/outpost_arrival.tscn").instantiate()
	_oa.manage_hd_scope = true
	_oa.return_to_map = false
	_oa.damage_level = 0.6
	get_root().add_child(_oa)
	var t := Timer.new()
	t.wait_time = 0.3
	t.one_shot = true
	t.autostart = true
	t.timeout.connect(_run)
	get_root().add_child(t)
	var guard := Timer.new()
	guard.wait_time = 8.0
	guard.one_shot = true
	guard.autostart = true
	guard.timeout.connect(func() -> void:
		print("VERDICT: FAIL (timeout)")
		quit(1))
	get_root().add_child(guard)


func _run() -> void:
	var run = get_root().get_node_or_null("/root/Run")
	_ck(bool(_oa._live), "dock detects a live run")
	_ck(run.outpost_weapon_offers.size() > 0, "market rolled real offers (%d)" % run.outpost_weapon_offers.size())
	if run.outpost_weapon_offers.size() > 0:
		_ck(run.outpost_weapon_offers[0].get("part") != null, "offers carry real Part refs")
	_ck(_oa._slots.get("BLASTER") != null, "BLASTER slot always present (mandatory cannon)")
	# Info blurb is sourced from the Codex (ArmoryStrings via factory_for_part), not part.description.
	var blsl = _oa._slots.get("BLASTER")
	if blsl != null and blsl.get("part") != null:
		_ck(_oa._codex_blurb(blsl) != "", "info blurb resolves from the Codex source")
	_ck(_oa._hold.size() >= 2, "hold reads storage+inventory (%d)" % _oa._hold.size())

	# Pull SECONDARY → storage.
	if run.loadout_snapshot.get(SlotTypes.SlotType.HARDPOINT_WING) != null:
		var sn = run.weapon_storage.size()
		_oa._pull("SECONDARY")
		_ck(run.loadout_snapshot.get(SlotTypes.SlotType.HARDPOINT_WING) == null, "pull SECONDARY clears the slot")
		_ck(run.weapon_storage.size() == sn + 1, "pulled part → weapon_storage")

	# Scrap a hold part → materials up + removed.
	if _oa._hold.size() > 0:
		var mat = int(run.materials)
		var hn = _oa._hold.size()
		_oa._scrap_hold(0)
		_ck(int(run.materials) > mat, "scrap a hold part credits materials")
		_ck(_oa._hold.size() < hn, "scrapped part removed from hold")

	# Sell a hold part → bounty up + buyback listed in the persisted stock.
	if _oa._hold.size() > 0:
		var b = int(run.bounty)
		var on = run.outpost_weapon_offers.size()
		_oa._sell_hold(0)
		_ck(int(run.bounty) > b, "sell a hold part credits bounty")
		_ck(run.outpost_weapon_offers.size() == on + 1, "sold part listed as buyback offer")

	# Buy a market offer → spends bounty.
	if _oa._market.size() > 0:
		var b2 = int(run.bounty)
		_oa._buy_market(_oa._market[0])
		_ck(int(run.bounty) <= b2, "buy spends bounty (or no-op if unaffordable)")

	# Upgrade an owned part (the BLASTER — always present).
	var prim = _oa._slots.get("BLASTER")
	if prim != null and prim.get("part") != null and run.can_upgrade_part(prim["part"]):
		var mk = int(prim["part"].mark)
		_oa._upgrade_part_live(prim["part"])
		_ck(int(prim["part"].mark) == mk + 1, "upgrade bumps Mk")

	# Repair — MUST be gated on the real hull deficit, NOT the visual damage_level (production never
	# sets damage_level, so the old gate left Repair permanently grayed). 1-pip + Repair-All.
	run.bounty = 5000
	run.repair_charges = 9
	run.current_hull = maxi(1, int(run.max_hull) - 3)
	var hb = int(run.current_hull)
	_oa._do_repair(1)
	_ck(int(run.current_hull) == hb + 1, "repair(1) raises hull by a pip (hull-gated, not damage_level)")
	_oa._do_repair(999)
	_ck(int(run.current_hull) == int(run.max_hull), "repair All fills the hull to max")

	# Refill super — 1 then All.
	run.bounty = 5000
	run.super_charges = 0
	if int(run.max_super_charges) > 0:
		_oa._on_refill_super(1)
		_ck(int(run.super_charges) == 1, "refill super(1) adds one charge")
		_oa._on_refill_super(999)
		_ck(int(run.super_charges) == int(run.max_super_charges), "refill super All tops up charges")
	else:
		_ck(true, "no super equipped — refill skipped")

	# Shift mode is now a first-class owned part (SHIFT slot reads loadout_snapshot[SHIFT_MODE]).
	var shift = _oa._slots.get("SHIFT")
	_ck(shift != null and shift.get("part") != null, "SHIFT slot reads the equipped shift mode")

	# Upgrade is its own shop mode now (like scrap/sell) — engaging + rebuilding must not error.
	_oa._set_shop_mode(OutpostArrival.ShopMode.UPGRADE)
	_ck(_oa._shop_mode == OutpostArrival.ShopMode.UPGRADE, "upgrade mode engages + renders")
	_oa._set_shop_mode(OutpostArrival.ShopMode.NONE)

	# Pull the shift mode → it lands in the hold (swappable/sellable like any part).
	if shift != null and shift.get("part") != null:
		var hn2 = _oa._hold.size()
		_oa._pull("SHIFT")
		_ck(run.loadout_snapshot.get(SlotTypes.SlotType.SHIFT_MODE) == null, "pull SHIFT clears the slot")
		_ck(_oa._hold.size() == hn2 + 1, "pulled shift mode → hold")

	# Blaster swap: slotting a DIFFERENT infinite blaster pulls the old blaster out to the hold (it
	# does NOT silently overwrite). The mandatory BLASTER slot stays filled.
	var old_blaster = _oa._slots.get("BLASTER")
	var old_blaster_name := String(old_blaster["part"].display_name) if old_blaster != null and old_blaster.get("part") != null else ""
	var swap_rng := RandomNumberGenerator.new()
	swap_rng.seed = 4242
	var newb = null
	for i in 24:
		var c = PartCatalog.roll_for_slot(swap_rng, SlotTypes.SlotType.CANNON, 2)
		if c != null and c.has_method("ammo_at_mark") and int(c.ammo_at_mark(int(c.mark))) < 0 and String(c.display_name) != old_blaster_name:
			newb = c
			break
	if newb != null and old_blaster_name != "":
		run.weapon_storage.append(newb)
		_oa._refresh_live()
		var hidx := -1
		for i in _oa._hold.size():
			if _oa._hold[i].get("part") == newb:
				hidx = i
		if hidx >= 0:
			_oa._swap_from_hold(hidx)
			_ck(String(run.cannon_pool[0].display_name) == String(newb.display_name), "blaster swap installs the new blaster")
			var in_hold := false
			for p in run.weapon_storage:
				if String(p.display_name) == old_blaster_name:
					in_hold = true
			_ck(in_hold, "blaster swap pulls the OLD blaster to the hold (no overwrite)")

	# Deck life: landing builds the DeckLife node (child of the plate) + spawns wandering crew; a
	# reaction dispatches without error.
	_oa.begin_landed()
	_ck(_oa._deck != null and is_instance_valid(_oa._deck), "deck life built on landing")
	if _oa._deck != null and is_instance_valid(_oa._deck):
		_ck(_oa._deck._crew.size() == _oa.deck_crew_count, "deck spawned the configured crew count")
		_ck(_oa._deck._crates.size() == _oa.deck_crate_count, "deck spawned the configured crate count")
		_oa.deck_react("repair")
		_ck(true, "deck reaction dispatched without error")
		# Two-crew crate carry: starts (pins 2 crew) then drives to completion without error.
		_oa.deck_carry_now()
		_ck(_oa._deck._carry != null, "crate carry started — 2 crew flank a crate")
		var guard := 0
		while _oa._deck._carry != null and guard < 6000:
			_oa._deck._tick_carry(0.05)
			guard += 1
		_ck(_oa._deck._carry == null, "crate carry ran to completion (approach → carry → set down)")
		# Lifter run: a crew boards the hover lifter, it moves a crate, returns, crew disembarks.
		_ck(is_instance_valid(_oa._deck._lifter), "lifter spawned from the real scene")
		_oa.deck_lifter_run_now()
		_ck(_oa._deck._lift_job != null, "lifter run started (crew boards)")
		var lguard := 0
		while _oa._deck._lift_job != null and lguard < 20000:
			_oa._deck._tick_lift_job(0.05)
			lguard += 1
		_ck(_oa._deck._lift_job == null, "lifter run ran to completion (board → haul → return → disembark)")

	# Info popup — now builds its stats + Mark ladder via the shared PartStatsView (owned path).
	if _oa._hold.size() > 0:
		_oa._show_info(_oa._hold[0])
		_ck(_oa._info_popup != null and is_instance_valid(_oa._info_popup), "info popup built (shared PartStatsView)")
		_oa._close_info()
		_ck(_oa._info_popup == null, "info popup closed")

	# Shared stats+mark widget, Codex reference path (owned=false → no "(current)" flag).
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	var demo_part = PartCatalog.roll_for_slot(rng2, SlotTypes.SlotType.CANNON, 3)
	if demo_part != null:
		var block = PartStatsView.build(demo_part, 1, 9, false)
		_ck(block != null and block.get_child_count() >= 3, "PartStatsView builds hint + ladder + stats box")
		var ladder = block.get_child(1)
		_ck(ladder is HBoxContainer and ladder.get_child_count() == 9, "mark ladder has 9 chips (Mk.1-9)")
		block.free()

	# Help overlay: builds every section + its live example widgets, then closes cleanly.
	_oa._show_help()
	_ck(_oa._info_popup != null and is_instance_valid(_oa._info_popup), "help overlay built")
	_oa._close_info()
	_ck(_oa._info_popup == null, "help overlay closed")

	print("live: hold=%d market=%d offers=%d bounty=%d materials=%d" %
		[_oa._hold.size(), _oa._market.size(), run.outpost_weapon_offers.size(), int(run.bounty), int(run.materials)])
	print("VERDICT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
