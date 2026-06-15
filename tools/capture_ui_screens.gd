extends SceneTree

# One static PNG per clickable screen into captures/ui_review/<name>.png, for
# reviewing the UI-unification pass (native-480 shop, themed menus). Run via
# tools/capture_ui_screens.ps1 (NOT --headless — needs a real render target).
#
# Each screen is instantiated as a child of root with seeded Run state so the
# stateful ones (shop, summaries, sector map) populate, given a few frames to
# resolve deferred layout + reveal tweens, then the 480×270 viewport is grabbed
# and upscaled 3× nearest for readability.

const BASE := "res://captures/ui_review"
const HdScreenLib := preload("res://scripts/ui/hd_screen.gd")
# The viewport grab is already the full 1920×1080 window (480×270 content
# upscaled 4× by the canvas stretch, nearest-filtered = crisp pixels), so no
# extra upscale is needed for review.
const UPSCALE := 1
const OptionsOverlay := preload("res://scripts/ui/options_overlay.gd")

# name, scene path (or "" for special handling), settle seconds
const SHOTS := [
	["main_menu", "res://scenes/main_menu.tscn", 0.6],
	["dev_menu", "res://scenes/dev_menu.tscn", 0.5],
	["onboarding", "res://scenes/onboarding.tscn", 0.5],
	["enemy_codex", "res://scenes/enemy_codex.tscn", 0.6],
	["options", "", 0.6],
	["pause_menu", "res://scenes/pause_menu.tscn", 0.4],
	["signal_event", "res://scenes/signal_event.tscn", 0.5],
	["outpost", "res://scenes/outpost.tscn", 0.6],
	["sector_map", "res://scenes/sector_map_v3.tscn", 0.8],
	["sector_map_hd", "res://scenes/sector_map_hd.tscn", 1.0],
	["run_summary", "res://scenes/run_summary.tscn", 0.5],
	["cleared_summary", "res://scenes/cleared_summary.tscn", 3.0],
	["hangar", "res://scenes/hangar.tscn", 0.6],
]


func _initialize() -> void:
	_run.call_deferred()


func _seed_run() -> void:
	var run = root.get_node_or_null("Run")
	if run == null:
		print("[ui] WARNING: /root/Run autoload not present — stateful screens will be empty")
		return
	run.new_run()
	run.bounty = 1800
	run.max_bounty_earned = 2400
	run.current_hull = 2
	run.max_hull = 3
	run.current_shield = 8
	run.max_shield = 10
	run.enemies_killed = 37
	run.sectors_cleared = 2
	run.bosses_defeated = 1
	run.run_distance = 1830.0
	# Some owned upgrades so Manage Ship's UPGRADES column has content.
	run.hull_mk = 3
	run.thrusters_mk = 2
	run.shield_cap_mk = 1
	# An extra primary cannon (so the multi-primary loadout shows) + a stored
	# secondary (so OWNED KIT has an Equip row).
	var pc = load("res://scripts/parts/part_catalog.gd")
	var st = load("res://scripts/weapons/SlotTypes.gd")
	if pc != null and st != null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var cannon = pc.roll_for_slot(rng, st.SlotType.CANNON, 4)
		if cannon != null:
			run.equip_part(cannon)  # appends to cannon_pool, becomes active
		var sec = pc.roll_for_slot(rng, st.SlotType.HARDPOINT_WING, 3)
		if sec != null:
			run.weapon_storage.append(sec)
	# Build a sector map so sector_map_v3 has rows to draw.
	if run.has_method("start_new_sector"):
		run.start_new_sector(0, 1337)
	# Point at the first POI so the map shows a current node.
	var rows: Array = run.sector_map_cache.get("rows", [])
	if rows.size() > 0:
		var pois: Array = rows[0].get("pois", [])
		if pois.size() > 0:
			run.current_node_id = String(pois[0].get("id", ""))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE))
	_seed_run()
	# Optional subset: pass screen names after `--` (e.g. `-- hangar`)
	# to capture only those — avoids re-rendering every screen when iterating on one.
	var only := PackedStringArray(OS.get_cmdline_user_args())
	for shot in SHOTS:
		if only.size() > 0 and not only.has(shot[0]):
			continue
		await _capture(shot[0], shot[1], shot[2])
	print("[ui] done")
	quit()


func _capture(sname: String, scene_path: String, settle: float) -> void:
	var hosts: Array = []  # nodes to free afterwards
	if sname == "options":
		# Options is an overlay, not a scene — show it over the main menu.
		var menu = load("res://scenes/main_menu.tscn").instantiate()
		root.add_child(menu)
		hosts.append(menu)
		await create_timer(0.2).timeout
		var ov = OptionsOverlay.open(root)
		hosts.append(ov)
	elif sname == "pause_menu":
		# Show the pause menu without pausing the tree (the capture loop's
		# timers must keep ticking). Make it visible + attach the HD scope
		# the way _toggle() would, minus get_tree().paused.
		var inst = load(scene_path).instantiate()
		root.add_child(inst)
		hosts.append(inst)
		await process_frame
		inst.visible = true
		hosts.append(HdScreenLib.enter(inst))
	elif sname == "cleared_summary":
		var inst = load(scene_path).instantiate()
		root.add_child(inst)
		hosts.append(inst)
		await process_frame
		# Sample tally so the screen shows real content.
		var stats := {
			"res://scenes/enemies/core/enemy_dart.tscn": {"spawned": 12, "killed": 12, "bounty": 5, "total_bounty": 60},
			"res://scenes/enemies/core/enemy_cruiser.tscn": {"spawned": 3, "killed": 3, "bounty": 40, "total_bounty": 120},
		}
		if inst.has_method("populate"):
			inst.populate(stats, 180, false, false)
	else:
		var inst = load(scene_path).instantiate()
		root.add_child(inst)
		hosts.append(inst)

	await create_timer(settle).timeout

	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		if UPSCALE > 1:
			img.resize(img.get_width() * UPSCALE, img.get_height() * UPSCALE, Image.INTERPOLATE_NEAREST)
		img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [BASE, sname]))
		print("[ui] %s (%dx%d)" % [sname, img.get_width(), img.get_height()])
	else:
		print("[ui] %s: NULL image" % sname)

	paused = false
	for h in hosts:
		if is_instance_valid(h):
			h.queue_free()
	await create_timer(0.25).timeout
