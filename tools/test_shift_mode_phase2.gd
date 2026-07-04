extends SceneTree

# Shift-Mode runtime verification (unified system, in the Hangar — player, no enemies):
# - All modes: tap Shift -> activate for a duration, spending one discrete charge; can't
#   re-activate while active; charges refill per the mode's rule (TIME / KILLS).
# - Hyper: activate -> unlimited primary ammo + fire/dmg bonus while the window holds.
# - Phase: activate -> intangible burst (_invuln_t set) + offense locked; charges refill
#   by kills (on_enemy_killed).
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
	_equip("_make_hyper_mode", 2, loadout)  # Mk2: +10% fire, x1.10 dmg, 2 charges, 4s window
	_assert(int(player.active_mode) == 2, "active_mode == HYPER")
	_assert_eq(int(player.mode_charges), int(player.mode_charges_max), "Hyper starts at full charges")
	_assert_eq(int(player.mode_charges_max), 2, "Hyper has 2 charges")
	_assert_eqf(player.mode_duration, 4.0, "Hyper duration 4.0s")
	_assert_eqf(player.hyper_fire_bonus, 0.10, "hyper fire bonus = +10% (Mk2)")
	_assert_eqf(player.hyper_damage_mult, 1.10, "hyper dmg mult = x1.10 (Mk2)")
	# Equipping a mode must NOT hijack the super slot (Super Pulse Bomb stays).
	_assert(player.super_part == null or String(player.super_part.display_name) == "Super Pulse Bomb", "super_part untouched by Hyper (got %s)" % (String(player.super_part.display_name) if player.super_part else "null"))

	# Tap Shift -> activate (spend a charge, window opens).
	Input.action_press("focus")
	await process_frame
	Input.action_release("focus")
	await process_frame
	_assert(player._hyper_on(), "Hyper ACTIVE after Shift tap")
	_assert_eq(int(player.mode_charges), 1, "Hyper spent one charge (2 -> 1)")
	_assert(player.mode_active_t > 0.0, "Hyper window counting down (%.2f)" % player.mode_active_t)

	# Tap again WHILE active -> no second charge spent (can't re-activate mid-window).
	Input.action_press("focus")
	await process_frame
	Input.action_release("focus")
	await process_frame
	_assert_eq(int(player.mode_charges), 1, "Hyper does NOT re-activate while already active")

	# Force the window to expire, then re-activate -> spends the second charge.
	player.mode_active_t = 0.0
	await process_frame
	Input.action_press("focus")
	await process_frame
	Input.action_release("focus")
	await process_frame
	_assert_eq(int(player.mode_charges), 0, "Hyper re-activates after expiry (1 -> 0)")
	_assert(player._hyper_on(), "Hyper ACTIVE again on the second activation")

	# Unlimited ammo while active: give a metered primary, activate fresh, fire, ammo holds.
	# (Minigun = metered primary that fires immediately.)
	_equip_cannon("_make_minigun", 1, loadout)
	# Refresh charges + activate so we fire under an active Hyper window.
	player.mode_charges = int(player.mode_charges_max)
	player.mode_active_t = 0.0
	await process_frame
	var ammo_before: int = int(player.ammo) if "ammo" in player else -1
	if ammo_before > 0:
		Input.action_press("focus")
		await process_frame
		Input.action_release("focus")
		await process_frame
		_assert(player._hyper_on(), "Hyper active for the ammo check")
		Input.action_press("shoot")
		for i in range(30):
			await process_frame
		Input.action_release("shoot")
		await process_frame
		_assert(int(player.ammo) >= ammo_before, "Hyper unlimited ammo: ammo did not drop (%d -> %d)" % [ammo_before, int(player.ammo)])
	else:
		print("[test] (skipped ammo check — minigun ammo unavailable: %d)" % ammo_before)

	# ===== PHASE =====
	_equip("_make_phase_shift", 1, loadout)  # Mk1: 3.0s / 2 charges, KILLS regen
	_assert(int(player.active_mode) == 1, "active_mode == PHASE")
	_assert_eq(int(player.mode_charges), 2, "Phase starts with 2 charges")
	_assert_eq(int(player.mode_charges_max), 2, "Phase max 2 charges (Mk1)")
	_assert_eqf(player.mode_duration, 3.0, "Phase duration 3.0s (Mk1)")
	_assert_eq(int(player.mode_regen_kind), 1, "Phase regen kind == KILLS (1)")

	# Tap Shift -> phase out: charge spent, intangible, window open.
	Input.action_press("focus")
	await process_frame
	Input.action_release("focus")
	await process_frame
	_assert(player._phase_on(), "Phase ACTIVE after Shift tap (active_t=%.2f)" % player.mode_active_t)
	_assert_eq(int(player.mode_charges), 1, "Phase spent one charge (2 -> 1)")
	_assert(player._invuln_t > 0.0, "Phase is intangible (_invuln_t set)")

	# Kill-refill: 4 kills -> +1 charge (kills_per_charge default 4).
	for k in range(4):
		player.on_enemy_killed()
	_assert_eq(int(player.mode_charges), 2, "Phase refilled to 2 after 4 kills")
	# At max, further kills don't overflow.
	for k in range(4):
		player.on_enemy_killed()
	_assert_eq(int(player.mode_charges), 2, "Phase charges capped at max")

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
