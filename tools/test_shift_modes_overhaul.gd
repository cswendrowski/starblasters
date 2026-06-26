extends SceneTree

# Shift-mode overhaul verification (8 modes) — boots the Hangar (player, no enemies),
# equips each new mode, and checks: the slot flips active_mode, the effect tunables populate,
# and the key runtime effects fire (Rush invuln, Thief catch→shield, Reflect negate, Focus
# crit plumbing). Mechanics that need a live bullet/enemy are eyeballed by Roman; this gates
# the wiring + the testable-headless effects.

const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")

# ShiftMode enum mirror.
const FOCUS := 0
const PHASE := 1
const HYPER := 2
const RUSH := 3
const REFIRE := 4
const ECHO := 5
const THIEF := 6
const REFLECT := 7


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	change_scene_to_file("res://scenes/hangar.tscn")
	for i in range(5):
		await process_frame
	var hangar = current_scene
	var player = hangar._player
	var loadout = hangar._live_loadout()
	_assert(player != null and player.controls_enabled, "player ready")

	# --- Each new mode equips + flips active_mode + populates its tunable ---
	_equip("_make_rush_mode", 1, loadout)
	_assert_eq(int(player.active_mode), RUSH, "active_mode == RUSH")
	_assert(player.rush_speed_bonus > 0.0, "Rush populated speed_bonus (%.2f)" % player.rush_speed_bonus)

	_equip("_make_refire_mode", 1, loadout)
	_assert_eq(int(player.active_mode), REFIRE, "active_mode == REFIRE")
	_assert(player.refire_fire_bonus > 0.0, "Refire populated fire_bonus (%.2f)" % player.refire_fire_bonus)

	_equip("_make_echo_mode", 1, loadout)
	_assert_eq(int(player.active_mode), ECHO, "active_mode == ECHO")
	_assert(player.echo_delay > 0.0, "Echo populated delay (%.2f)" % player.echo_delay)

	_equip("_make_thief_mode", 1, loadout)
	_assert_eq(int(player.active_mode), THIEF, "active_mode == THIEF")
	_assert(player.thief_catch_radius > 0.0 and player.thief_regen_per_hit >= 1, "Thief populated radius+regen")

	_equip("_make_reflect_mode", 1, loadout)
	_assert_eq(int(player.active_mode), REFLECT, "active_mode == REFLECT")
	_assert(player.reflect_chance > 0.0, "Reflect populated chance (%.2f)" % player.reflect_chance)

	_equip("_make_focus_mode", 1, loadout)
	_assert_eq(int(player.active_mode), FOCUS, "active_mode == FOCUS")
	_assert(player.focus_crit_chance > 0.0, "Focus populated crit_chance (%.2f)" % player.focus_crit_chance)

	# --- Rush: activating grants full damage immunity, offense stays on ---
	_equip("_make_rush_mode", 1, loadout)
	player.set("max_shield", 10); player.set("shield", 8); player.set("invincible", false)
	player.mode_active_t = 2.0          # simulate an active window
	await process_frame                 # _tick_shift_mode applies the Rush invuln
	_assert(player._rush_on(), "Rush active")
	_assert(player._invuln_t > 0.0, "Rush sets i-frames (impacts do no damage)")
	var s_before: int = int(player.shield)
	player.take_damage(5)
	_assert_eq(int(player.shield), s_before, "Rush: took no damage")

	# --- Phase: true intangibility — collision is turned OFF while active ---
	_equip("_make_phase_shift", 1, loadout)
	player.mode_active_t = 2.0
	await process_frame
	_assert(player._phase_on(), "Phase active")
	_assert(not player.monitoring and not player.monitorable, "Phase disables collision (intangible)")
	player.mode_active_t = 0.0
	await process_frame
	await process_frame
	_assert(player.monitoring and player.monitorable, "collision restored after Phase ends")

	# --- Thief: field spawns; a caught bullet converts to shield ---
	_equip("_make_thief_mode", 1, loadout)
	player.set("shield", 2)
	player.mode_active_t = 2.0
	await process_frame
	_assert(player._thief_on(), "Thief active")
	_assert(player._mode_field != null and is_instance_valid(player._mode_field), "Thief field spawned")
	var fake_bullet := Area2D.new()
	fake_bullet.add_to_group("bullets")
	player.get_tree().root.add_child(fake_bullet)
	var st_before: int = int(player.shield)
	player._on_mode_field_hit(fake_bullet)
	_assert(int(player.shield) == st_before + int(player.thief_regen_per_hit), "Thief catch banked shield (%d -> %d)" % [st_before, int(player.shield)])

	# --- Reflect: a forced reflect bounces the actual bullet back at enemies ---
	_equip("_make_reflect_mode", 1, loadout)
	player.reflect_chance = 1.0          # guarantee the roll
	player.mode_active_t = 2.0
	await process_frame
	_assert(player._mode_field != null and is_instance_valid(player._mode_field), "Reflect field spawned")
	var eb = preload("res://scenes/projectiles/enemy_bullet.tscn").instantiate()
	player.get_tree().root.add_child(eb)
	eb.start(Vector2(240, 100), Vector2(0, 1))
	player._on_mode_field_hit(eb)
	_assert(not eb.is_in_group("bullets") and String(eb.target_group) == "enemies", "Reflect flipped the bullet to target enemies")
	eb.queue_free()

	print("[test] ALL PASS")
	quit()


func _equip(factory: String, mk: int, loadout) -> void:
	var part = PartCatalog._make_by_name(factory, SlotTypes.SlotType.SHIFT_MODE)
	part.mark = mk
	root.get_node("/root/Run").equip_part(part)
	loadout.equip(SlotTypes.SlotType.SHIFT_MODE, part)


func _assert(cond: bool, msg: String) -> void:
	if cond: print("[test] PASS: " + msg)
	else:
		print("[test] FAIL: " + msg); quit(1)

func _assert_eq(a: int, b: int, msg: String) -> void:
	_assert(a == b, "%s (got %d)" % [msg, a])
