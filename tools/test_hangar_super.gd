extends SceneTree

# Verifies the Hangar bullet_parent redirect: the Smart Bomb super shockwave must
# spawn into the Hangar's SubViewport _world (so it shares the dummy's space +
# renders centered), NOT get_tree().root (which put it in the top-left). Also
# sanity-checks the primary fire seam still registers DPS on the dummy.

const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	change_scene_to_file("res://scenes/hangar.tscn")
	await process_frame
	await process_frame
	await process_frame

	var hangar = root.get_node_or_null("Hangar")
	if hangar == null:
		# current_scene route (scene root name may differ)
		hangar = current_scene
	var player = hangar._player
	var world = hangar._world
	var dummy = hangar._dummy
	_assert(player != null, "player spawned")
	_assert(world != null, "world node exists")

	# --- Super into _world ---
	var bomb = PartCatalog._make_by_name("_make_smart_bomb", SlotTypes.SlotType.DEVICE_BAY_1)
	if bomb == null:
		# factory name may differ — search the pool for the Super Pulse Bomb
		for entry in PartCatalog._all_pool():
			if int(entry["slot"]) == SlotTypes.SlotType.DEVICE_BAY_1:
				var p = PartCatalog._make_by_name(String(entry["factory"]), SlotTypes.SlotType.DEVICE_BAY_1)
				if p != null and "display_name" in p and String(p.display_name) == "Super Pulse Bomb":
					bomb = p
					break
	_assert(bomb != null, "made a Super Pulse Bomb part")
	var run = root.get_node("/root/Run")
	run.equip_part(bomb)
	hangar._live_loadout().equip(SlotTypes.SlotType.DEVICE_BAY_1, bomb)
	player.super_charges = int(player.max_super_charges)

	player.fire_super()
	await process_frame
	await process_frame
	var found_wave := false
	for c in world.get_children():
		var scr = c.get_script()
		if scr != null and String(scr.resource_path).ends_with("smart_bomb_shockwave.gd"):
			found_wave = true
			print("[test] shockwave parent=%s pos=%s (player pos=%s)" % [c.get_parent().name, str(c.global_position), str(player.global_position)])
	_assert(found_wave, "shockwave spawned INTO _world (not root)")
	# Root viewport should NOT have a stray shockwave.
	var stray := false
	for c in root.get_children():
		var scr = c.get_script()
		if scr != null and String(scr.resource_path).ends_with("smart_bomb_shockwave.gd"):
			stray = true
	_assert(not stray, "no stray shockwave in root viewport")

	# --- Primary fire still hits the dummy ---
	Input.action_press("shoot")
	for i in range(70):
		await process_frame
	Input.action_release("shoot")
	await process_frame
	var dps: float = dummy.get_dps() if dummy != null and dummy.has_method("get_dps") else 0.0
	print("[test] measured DPS after ~1.1s of fire = %.2f" % dps)
	_assert(dps > 0.0, "primary fire registered DPS on the dummy")

	print("[test] ALL PASS")
	quit()


func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg)
		quit(1)
