extends SceneTree

# Shift-Mode Phase 2 runtime verification (in the Hangar — player, no enemies):
# - Hyper: bar inits full; held Shift engages + drains; release ends it; can't
#   re-engage until full; unlimited primary ammo while active.
# - Phase: press Shift -> intangible burst (_invuln_t set) + charge spent + offense
#   locked; on_enemy_killed refills charges by threshold.
# - Modes are NOT supers: equipping them leaves super_part (Smart Bomb) untouched.

const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	change_scene_to_file("res://scenes/hangar.tscn")
	for i in range(5):
		await process_frame
	var hangar = current_scene
	var player = hangar._player
	var loadout = hangar._live_loadout()
	_assert(player != null and player.controls_enabled, "player ready + controls enabled")

	# ===== HYPER =====
	_equip("_make_hyper_mode", 2, loadout)  # Mk2: +10% fire, x1.10 dmg
	_assert(int(player.active_mode) == 2, "active_mode == HYPER")
	_assert_eqf(player.hyper_charge, player.hyper_charge_max, "hyper bar starts FULL")
	_assert_eqf(player.hyper_fire_bonus, 0.10, "hyper fire bonus = +10% (Mk2)")
	_assert_eqf(player.hyper_damage_mult, 1.10, "hyper dmg mult = x1.10 (Mk2)")
	# Equipping a mode must NOT hijack the super slot (Smart Bomb stays).
	_assert(player.super_part == null or String(player.super_part.display_name) == "Smart Bomb", "super_part untouched by Hyper (got %s)" % (String(player.super_part.display_name) if player.super_part else "null"))

	# Hold Shift -> engage from full + drain.
	Input.action_press("focus")
	for i in range(12):
		await process_frame
	_assert(player._hyper_active, "Hyper ENGAGED while holding Shift from full bar")
	_assert(player.hyper_charge < player.hyper_charge_max, "Hyper bar draining while active (%.2f)" % player.hyper_charge)

	# Release -> ends; bar not full -> cannot immediately re-engage.
	Input.action_release("focus")
	await process_frame
	await process_frame
	_assert(not player._hyper_active, "Hyper ENDS on release")
	var charge_after_release: float = player.hyper_charge
	Input.action_press("focus")
	for i in range(3):
		await process_frame
	_assert(not player._hyper_active, "Hyper CANNOT re-engage from a non-full bar (gated)")
	Input.action_release("focus")
	await process_frame

	# Unlimited ammo while active: give a metered primary, engage, fire, ammo holds.
	# (Minigun = metered primary that fires immediately — the retired Machinegun factory is
	# gone, and the Autocannon's 1.5s spin-up would outlast this test's ~0.5s fire window.)
	_equip_cannon("_make_minigun", 1, loadout)
	# Top the bar so we can engage, then fire under Hyper.
	player.hyper_charge = player.hyper_charge_max
	await process_frame
	var ammo_before: int = int(player.ammo) if "ammo" in player else -1
	if ammo_before > 0:
		Input.action_press("focus")
		await process_frame
		await process_frame
		Input.action_press("shoot")
		for i in range(30):
			await process_frame
		Input.action_release("shoot")
		Input.action_release("focus")
		await process_frame
		_assert(int(player.ammo) >= ammo_before, "Hyper unlimited ammo: ammo did not drop (%d -> %d)" % [ammo_before, int(player.ammo)])
	else:
		print("[test] (skipped ammo check — machinegun ammo unavailable: %d)" % ammo_before)

	# ===== PHASE =====
	_equip("_make_phase_shift", 1, loadout)  # Mk1: 3.0s / 2 charges (Roman 2026-06-10: 3s window)
	_assert(int(player.active_mode) == 1, "active_mode == PHASE")
	_assert_eq(int(player.phase_charges), 2, "Phase starts with 2 charges")
	_assert_eqf(player.phase_duration, 3.0, "Phase duration 3.0s (Mk1)")

	# Press Shift -> phase out: charge spent, intangible, offense locked.
	Input.action_press("focus")
	await process_frame
	Input.action_release("focus")
	await process_frame
	_assert(player._phase_t > 0.0, "Phase ACTIVE after Shift press (_phase_t=%.2f)" % player._phase_t)
	_assert_eq(int(player.phase_charges), 1, "Phase spent one charge (2 -> 1)")
	_assert(player._invuln_t > 0.0, "Phase is intangible (_invuln_t set)")

	# Kill-refill: 4 kills -> +1 charge (kills_per_charge default 4).
	for k in range(4):
		player.on_enemy_killed()
	_assert_eq(int(player.phase_charges), 2, "Phase refilled to 2 after 4 kills")
	# At max, further kills don't overflow.
	for k in range(4):
		player.on_enemy_killed()
	_assert_eq(int(player.phase_charges), 2, "Phase charges capped at max")

	print("[test] ALL PASS")
	quit()


func _equip(factory: String, mk: int, loadout) -> void:
	var part = PartCatalog._make_by_name(factory, SlotTypes.SlotType.SHIFT_MODE)
	part.mark = mk
	root.get_node("/root/Run").equip_part(part)
	loadout.equip(SlotTypes.SlotType.SHIFT_MODE, part)


func _equip_cannon(factory: String, mk: int, loadout) -> void:
	var part = PartCatalog._make_by_name(factory, SlotTypes.SlotType.CANNON)
	part.mark = mk
	root.get_node("/root/Run").equip_part(part)
	loadout.equip(SlotTypes.SlotType.CANNON, part)


func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)

func _assert_eq(a: int, b: int, msg: String) -> void:
	_assert(a == b, "%s (got %d)" % [msg, a])

func _assert_eqf(a: float, b: float, msg: String) -> void:
	_assert(abs(a - b) < 0.001, "%s (got %.3f)" % [msg, a])
