extends Control

# Developer menu — gathered from the dev shortcuts that used to live on the
# main menu (Test Bed, Test Hazard, Hangar) plus new tools (Maneuver Sim,
# Shipyard). Reached from a single "Dev Menu" button on the main menu so
# the main menu itself stays focused on player-facing entries.
#
# Test Combat rework (2026-06-14): the old modal fan-out (hazard / faction /
# boss / minefield sub-modals) was replaced by the HD Combat Lab screen
# (scenes/dev/combat_lab.tscn) — configure a ship + pick an encounter + launch.
# The two niche one-offs (EM Torpedo + wreck test, All-Signal sector) stay as
# direct buttons; the Smart Mount Lab is a dedicated turret tuner.

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SectorMapRoute = preload("res://scripts/systems/sector_map_route.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")

var _vbox: VBoxContainer = null
var _grid: GridContainer = null
var _hd_scope: HdViewportScope = null
var _baked_btn: Button = null


func _ready() -> void:
	# Dev menu renders at HD (1920×1080) like the player-facing menus, so the
	# UiTheme HD fonts/buttons size correctly instead of blowing up at native.
	_hd_scope = HdScreen.enter(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_install_dark_background()
	_build_ui()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("silent")


func _install_dark_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.07, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -100
	add_child(bg)
	move_child(bg, 0)


func _build_ui() -> void:
	# Roman 2026-05-19: dev shortcuts now lay out as a 2-column grid (the
	# list grew past comfortable single-column scroll). Title + Back
	# button stay full-width above/below the grid.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 22)
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	pad.add_child(v)
	_vbox = v

	var title := Label.new()
	title.text = "DEV MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(title, UiTheme.LabelKind.TITLE)
	v.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "developer tools"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(subtitle, UiTheme.LabelKind.CAPTION)
	v.add_child(subtitle)

	v.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	_grid = grid

	# Authoring tools (Wave Editor / Movement+Shoot Pattern editors retired 2026-06-11)
	_add_button("[ Pattern Eligibility ]", _on_pattern_eligibility, true)
	_add_button("[ Formation Builder ]", _on_wave_pattern_editor, true)
	_add_button("[ Weapon Lab ]", _on_weapon_lab, true)
	_add_button("[ Enemy Bench ]", _on_enemy_bench, true)
	# Tuners / labs (Movement Lab / Sector Map HD Lab retired 2026-06-11)
	_add_button("[ Lane Visualizer ]", _on_lane_visualizer, true)
	_add_button("[ Parallax Tuner ]", _on_parallax_tuner, true)
	_add_button("[ Asteroid Lab ]", _on_asteroid_lab, true)
	_add_button("[ Asteroid Bake Lab ]", _on_asteroid_bake_lab, true)
	_add_button("[ Asteroid Field Test ]", _on_asteroid_field_test, true)
	# Crash-test toggle: flips the backdrop's asteroid layer to the baked Sprite2D path
	# (AsteroidBakeCache). Bakes the shared atlas on first enable. Then launch an asteroid
	# POI via Combat Lab to A/B whether baked asteroids stop the #116172 combat-load crash.
	_baked_btn = _add_button("[ Baked Asteroids: OFF ]", _on_toggle_baked_asteroids, true)
	_update_baked_btn()
	_add_button("[ Crash Loop ]", _on_crash_loop, true)
	_add_button("[ Shader Lab ]", _on_shader_lab, true)
	_add_button("[ Combat VFX Lab ]", _on_combat_vfx_lab, true)
	_add_button("[ Sequence Lab ]", _on_sequence_lab, true)
	_add_button("[ Player FX Lab ]", _on_player_fx_lab, true)
	_add_button("[ Loading Screen Lab ]", _on_loading_screen_lab, true)
	_add_button("[ Outpost Arrival Lab ]", _on_outpost_arrival_lab, true)
	_add_button("[ Recycle Tuner ]", _on_recycle_tuner, true)
	_add_button("[ Smart Mount Lab ]", _on_smart_mount_lab, true)
	# Test launchers
	_add_button("[ Combat Lab ]", _on_combat_lab, true)
	_add_button("[ Hangar ]", _on_hangar, true)
	_add_button("[ EM Torpedo Test ]", _launch_em_torpedo_test, true)
	# All-Signal Sector rolled into Combat Lab as the "All-Signal Sector" encounter (2026-06-17).

	v.add_child(HSeparator.new())

	# Back button stays in the outer VBox so it spans both columns.
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(300, 56)
	UiTheme.style_button(back, true)
	back.pressed.connect(_on_back)
	v.add_child(back)


func _add_button(text: String, cb: Callable, dev_green: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(300, 56)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(btn, true)
	if dev_green:
		btn.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6, 1.0))
	btn.pressed.connect(cb)
	_grid.add_child(btn)
	return btn


# Toggle the flagged baked-asteroid backdrop path (crash test). On first enable, bake the
# shared atlas (async, ~1s+). Persists statically, so once ON every asteroid POI this
# session uses baked rocks until toggled OFF (or the app restarts).
func _on_toggle_baked_asteroids() -> void:
	if AsteroidBakeCache.enabled:
		AsteroidBakeCache.enabled = false
		_update_baked_btn()
		return
	if _baked_btn != null:
		_baked_btn.disabled = true
		_baked_btn.text = "[ Baked Asteroids: BAKING… ]"
	await AsteroidBakeCache.ensure_baked(self)
	AsteroidBakeCache.enabled = true
	if _baked_btn != null:
		_baked_btn.disabled = false
	_update_baked_btn()


func _update_baked_btn() -> void:
	if _baked_btn == null:
		return
	_baked_btn.text = "[ Baked Asteroids: ON ]" if AsteroidBakeCache.enabled else "[ Baked Asteroids: OFF ]"


# ---- Button handlers ----

func _on_enemy_bench() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/enemy_bench.tscn")


func _on_wave_pattern_editor() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/wave_pattern_editor.tscn")


func _on_shader_lab() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/shader_lab.tscn")


func _on_combat_vfx_lab() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/combat_vfx_lab.tscn")


func _on_sequence_lab() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/sequence_lab.tscn")


func _on_recycle_tuner() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/recycle_tuner.tscn")


func _on_player_fx_lab() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/player_fx_lab.tscn")


func _on_loading_screen_lab() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/loading_screen_lab.tscn")


func _on_outpost_arrival_lab() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/outpost_arrival_lab.tscn")


func _on_lane_visualizer() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/lane_visualizer.tscn")


func _on_pattern_eligibility() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/pattern_eligibility_editor.tscn")


func _on_weapon_lab() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/weapon_lab.tscn")


func _on_parallax_tuner() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/parallax_tuner.tscn")


func _on_asteroid_lab() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/asteroid_lab.tscn")


func _on_asteroid_bake_lab() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/asteroid_bake_lab.tscn")


func _on_asteroid_field_test() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/asteroid_field_test.tscn")


func _on_crash_loop() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/crash_loop.tscn")


func _on_hangar() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/hangar.tscn")


# HD Combat Lab — configure a ship (primary + secondary + modules) and launch a chosen
# encounter. Replaces the old modal Test Combat fan-out.
func _on_combat_lab() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/combat_lab.tscn")


# Smart Mount Lab — controlled turret tuner (live player + randomized targets + knobs).
func _on_smart_mount_lab() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/smart_mount_lab.tscn")


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")


# EM Torpedo + Wreck Layer test (Roman 2026-06-10): start a combat with the EM Torpedo
# equipped from wave 1 so the lightning burst + inert wreck-drift kills can be eyeballed.
# Fire with C. The EM Torpedo is intentionally absent from the roll pool, so it's only
# reachable via _make_by_name here.
func _launch_em_torpedo_test() -> void:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.new_run()
		run.test_mode_active = true
		run.current_node_type = 0  # SectorNode.NodeType.COMBAT
		# Shallow depth = lots of soft chaff to vaporize so the wreck-drift reads clearly.
		run.sectors_cleared = 1
		run.combats_in_sector = 0
		# Disable death for non-EM kills too, so ONE test shows BOTH styles (primary 70/30
		# at the exit zone vs EM 20/80 off-screen). Roman 2026-06-10.
		run.set_meta("disable_deaths", true)
		var torp = PartCatalog._make_by_name("_make_em_torpedo", SlotTypes.SlotType.HARDPOINT_WING)
		if torp != null:
			if "mark" in torp:
				torp.mark = 3
			run.equip_part(torp)
	SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")
