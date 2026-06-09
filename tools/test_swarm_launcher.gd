extends SceneTree

# Swarm Launcher secondary: registration + Mk count + equip + salvo spawn with
# DISTINCT-target assignment (round-robin when fewer enemies) + ammo/cooldown gate.

const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const WS = preload("res://scripts/weapons/WeaponStyle.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var player = PlayerScene.instantiate()
	world.add_child(player)
	player.bullet_parent = world
	if "controls_enabled" in player:
		player.controls_enabled = true
	await process_frame
	await process_frame
	var loadout = player.get_node("Loadout")

	# Registration + Mk count.
	var part = PartCatalog._make_by_name("_make_swarm_launcher", SlotTypes.SlotType.HARDPOINT_WING)
	_assert(part != null and String(part.display_name) == "Swarm Launcher", "swarm launcher makeable")
	_assert(int(part.slot_type) == int(SlotTypes.SlotType.HARDPOINT_WING), "slot HARDPOINT_WING")
	_assert(part._missiles_at_mark(1) == 4, "4 missiles @ Mk1")
	_assert(part._missiles_at_mark(2) == 6, "6 missiles @ Mk2")
	_assert(part._missiles_at_mark(9) == 20, "20 missiles @ Mk9")

	# Equip @ Mk1 → mode/ammo/cooldown.
	part.mark = 1
	root.get_node("/root/Run").equip_part(part)
	loadout.equip(SlotTypes.SlotType.HARDPOINT_WING, part)
	await process_frame
	_assert(int(player.secondary_mode) == int(WS.SecondaryMode.SALVO), "secondary_mode == SALVO")
	_assert(int(player.secondary_ammo) == 6, "ammo == 6 (got %d)" % int(player.secondary_ammo))
	_assert(absf(float(player.secondary_cooldown) - 3.0) < 0.01, "cooldown == 3s")

	# 5 dummy enemies at distinct positions.
	var enemies := []
	for i in range(5):
		var e := Area2D.new()
		e.add_to_group("enemies")
		world.add_child(e)
		e.global_position = Vector2(150 + i * 12, 60 + i * 9)
		enemies.append(e)
	await process_frame

	# Salvo: 4 missiles, 5 enemies → all distinct.
	_assert(part.fire_salvo(player), "fire_salvo returned true")
	await process_frame
	await process_frame
	var missiles := _missiles_in(world)
	_assert(missiles.size() == 4, "4 missiles spawned (got %d)" % missiles.size())
	var distinct := {}
	for m in missiles:
		_assert(m._assigned_target != null, "missile has an assigned target")
		distinct[m._assigned_target] = true
	_assert(distinct.size() == 4, "4 DISTINCT targets (got %d)" % distinct.size())

	# Round-robin: leave 2 enemies, re-fire → 4 missiles share 2 targets.
	for m in missiles:
		m.free()
	for i in range(3):
		enemies[i].free()
	await process_frame
	part.fire_salvo(player)
	await process_frame
	await process_frame
	missiles = _missiles_in(world)
	_assert(missiles.size() == 4, "4 missiles again (got %d)" % missiles.size())
	var distinct2 := {}
	for m in missiles:
		if m._assigned_target != null:
			distinct2[m._assigned_target] = true
	_assert(distinct2.size() == 2, "2 enemies → 2 distinct targets via round-robin (got %d)" % distinct2.size())

	# Ammo + cooldown through the player input path.
	player._secondary_t = player.secondary_cooldown  # cooldown ready
	var ammo_before: int = int(player.secondary_ammo)
	Input.action_press("shoot2")
	await process_frame
	Input.action_release("shoot2")
	await process_frame
	_assert(int(player.secondary_ammo) == ammo_before - 1, "salvo consumed 1 ammo (%d->%d)" % [ammo_before, int(player.secondary_ammo)])
	_assert(player._secondary_t < player.secondary_cooldown, "cooldown restarted after fire")

	print("[test] ALL PASS")
	quit()


func _missiles_in(world) -> Array:
	var out := []
	for c in world.get_children():
		var sc = c.get_script()
		if sc != null and String(sc.resource_path).ends_with("swarm_missile.gd"):
			out.append(c)
	return out


func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)
