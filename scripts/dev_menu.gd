extends Control

# Developer menu — gathered from the dev shortcuts that used to live on the
# main menu (Test Bed, Test Hazard, Hangar) plus new tools (Maneuver Sim,
# Shipyard). Reached from a single "Dev Menu" button on the main menu so
# the main menu itself stays focused on player-facing entries.

const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const Factions = preload("res://scripts/levels/factions.gd")
const SectorMapRoute = preload("res://scripts/sector_map_route.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")

var _test_hazard_modal: CanvasLayer = null
var _vbox: VBoxContainer = null
var _grid: GridContainer = null
var _hd_scope: HdViewportScope = null


func _ready() -> void:
	# Dev menu renders at HD (1920×1080) like the player-facing menus, so the
	# UiTheme HD fonts/buttons size correctly instead of blowing up at native.
	_hd_scope = HdScreen.enter(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_install_dark_background()
	_build_ui()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")


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

	# Authoring tools
	_add_button("[ Wave Editor ]", _on_wave_editor, true)
	_add_button("[ Movement Patterns ]", _on_movement_pattern_editor, true)
	_add_button("[ Pattern Eligibility ]", _on_pattern_eligibility, true)
	_add_button("[ Shoot Patterns ]", _on_shoot_pattern_editor, true)
	_add_button("[ Weapons ]", _on_weapon_editor, true)
	_add_button("[ Enemy Bench ]", _on_enemy_bench, true)
	# Tuners / labs
	_add_button("[ Movement Lab ]", _on_movement_lab, true)
	_add_button("[ Lane Visualizer ]", _on_lane_visualizer, true)
	_add_button("[ Parallax Tuner ]", _on_parallax_tuner, true)
	_add_button("[ Asteroid Lab ]", _on_asteroid_lab, true)
	_add_button("[ Shader Lab ]", _on_shader_lab, true)
	_add_button("[ Sector Map HD Lab ]", _on_sector_map_hd_lab, true)
	# Test launchers
	_add_button("[ Test Combat ]", _on_test_combat, true)
	_add_button("[ Combat Slice ]", _on_combat_slice, true)
	_add_button("[ Hangar ]", _on_hangar, true)
	_add_button("[ UI Plotter ]", _on_ui_plotter, true)

	v.add_child(HSeparator.new())

	# Back button stays in the outer VBox so it spans both columns.
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(300, 56)
	UiTheme.style_button(back, true)
	back.pressed.connect(_on_back)
	v.add_child(back)


func _add_button(text: String, cb: Callable, dev_green: bool) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(300, 56)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(btn, true)
	if dev_green:
		btn.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6, 1.0))
	btn.pressed.connect(cb)
	_grid.add_child(btn)


# ---- Button handlers ----

func _on_enemy_bench() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/enemy_bench.tscn")


func _on_movement_lab() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/movement_lab.tscn")


func _on_shader_lab() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/shader_lab.tscn")


func _on_lane_visualizer() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/lane_visualizer.tscn")


func _on_wave_editor() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/wave_editor.tscn")


func _on_movement_pattern_editor() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/movement_pattern_editor.tscn")


func _on_pattern_eligibility() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/pattern_eligibility_editor.tscn")


func _on_shoot_pattern_editor() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/shoot_pattern_editor.tscn")


func _on_weapon_editor() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/weapon_editor.tscn")


# Load resources/levels/test_level.tres and launch combat with it. Designers
# author waves/enemies as .tres in the Godot inspector, point test_level.tres
# at them, then come here to play. No code edits required for a new wave.
const TEST_LEVEL_PATH := "res://resources/levels/test_level.tres"


func _on_test_level() -> void:
	if not ResourceLoader.exists(TEST_LEVEL_PATH):
		push_warning("Test Level: %s missing. Create one as a LevelData .tres." % TEST_LEVEL_PATH)
		return
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		# Fresh run state so HUD doesn't carry shop / sector context in.
		if run.has_method("new_run"):
			run.new_run()
		run.test_mode_active = true
		run.set_meta("custom_level_path", TEST_LEVEL_PATH)
	SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")


func _on_combat_slice() -> void:
	# Vertical-slice showcase of the composed combat model (formations + filler +
	# breathers + lanes). main.gd routes start_score(CombatSlice.build()).
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if run.has_method("new_run"):
			run.new_run()
		run.test_mode_active = true
		run.set_meta("combat_slice", true)
	SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")


func _on_parallax_tuner() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/parallax_tuner.tscn")


func _on_hangar() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/hangar.tscn")


func _on_ui_plotter() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/ui_plotter.tscn")


func _on_sector_map_hd_lab() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/sector_map_hd_lab.tscn")


# Unified Test Combat launcher (Cody 2026-05-19): one modal that fans
# out to the three existing test paths instead of three separate dev
# menu buttons. Each option re-uses its own modal/flow downstream.
func _on_test_combat() -> void:
	if _test_hazard_modal != null and is_instance_valid(_test_hazard_modal):
		return
	var layer := CanvasLayer.new()
	layer.layer = 80
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(200, 140)
	panel.add_theme_constant_override("separation", 12)
	center.add_child(panel)
	var header := Label.new()
	header.text = "TEST COMBAT"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	panel.add_child(header)
	var body := Label.new()
	body.text = "What kind of fight?"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(body, UiTheme.LabelKind.BODY)
	panel.add_child(body)
	# Each option closes this modal, then fans out:
	#   Level   → directly loads resources/levels/test_level.tres
	#   Hazard  → opens the hazard sub-modal (minefield / asteroid field)
	#   Boss    → opens the boss picker sub-modal
	var level_btn := Button.new()
	level_btn.text = "Custom Level (test_level.tres)"
	level_btn.custom_minimum_size = Vector2(180, 18)
	UiTheme.style_button(level_btn)
	level_btn.pressed.connect(func():
		_close_test_hazard_modal()
		_on_test_level()
	)
	panel.add_child(level_btn)
	var hazard_btn := Button.new()
	hazard_btn.text = "Hazard..."
	hazard_btn.custom_minimum_size = Vector2(180, 18)
	UiTheme.style_button(hazard_btn)
	hazard_btn.pressed.connect(func():
		_close_test_hazard_modal()
		_on_test_hazard()
	)
	panel.add_child(hazard_btn)
	var boss_btn := Button.new()
	boss_btn.text = "Boss..."
	boss_btn.custom_minimum_size = Vector2(180, 18)
	UiTheme.style_button(boss_btn)
	boss_btn.pressed.connect(func():
		_close_test_hazard_modal()
		_on_boss_fight()
	)
	panel.add_child(boss_btn)
	# Faction... (M6b): force a specific faction so all four can be eyeballed on demand.
	var faction_btn := Button.new()
	faction_btn.text = "Faction..."
	faction_btn.custom_minimum_size = Vector2(180, 18)
	UiTheme.style_button(faction_btn)
	faction_btn.pressed.connect(func():
		_close_test_hazard_modal()
		_on_test_faction()
	)
	panel.add_child(faction_btn)
	# Beam-enemy showcase (M6a.2): a live combat slice of all converted beam
	# enemies (Beamer sweep/track, Burner pair, Beam Turret) for eyeballing.
	var beam_btn := Button.new()
	beam_btn.text = "Beam Enemies (showcase)"
	beam_btn.custom_minimum_size = Vector2(180, 18)
	UiTheme.style_button(beam_btn)
	beam_btn.pressed.connect(func():
		_close_test_hazard_modal()
		_launch_hazard("beam_showcase")
	)
	panel.add_child(beam_btn)
	# EM Torpedo + Wreck Layer test (Roman 2026-06-10): start a combat with the EM Torpedo equipped
	# from wave 1 so the lightning burst + inert wreck-drift kills can be eyeballed. Fire with C.
	var torpedo_btn := Button.new()
	torpedo_btn.text = "EM Torpedo + Wreck Test"
	torpedo_btn.custom_minimum_size = Vector2(180, 18)
	UiTheme.style_button(torpedo_btn)
	torpedo_btn.pressed.connect(func():
		_close_test_hazard_modal()
		_launch_em_torpedo_test()
	)
	panel.add_child(torpedo_btn)
	# All-Signal Sector — launch a sector map where every POI is a Signal Event,
	# for testing the signal-event screen (Roman 2026-06-08).
	var signal_btn := Button.new()
	signal_btn.text = "All-Signal Sector"
	signal_btn.custom_minimum_size = Vector2(180, 18)
	UiTheme.style_button(signal_btn)
	signal_btn.pressed.connect(func():
		_close_test_hazard_modal()
		_on_all_signal_sector()
	)
	panel.add_child(signal_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(140, 16)
	UiTheme.style_button(cancel_btn, true)
	cancel_btn.pressed.connect(_close_test_hazard_modal)
	panel.add_child(cancel_btn)
	add_child(layer)
	_test_hazard_modal = layer


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")


# ---- Test Hazard modal (same logic as main_menu had) ----

func _on_test_hazard() -> void:
	if _test_hazard_modal != null and is_instance_valid(_test_hazard_modal):
		return
	var layer := CanvasLayer.new()
	layer.layer = 80
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(200, 140)
	panel.add_theme_constant_override("separation", 16)
	center.add_child(panel)
	var header := Label.new()
	header.text = "TEST HAZARD"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	panel.add_child(header)
	var body := Label.new()
	body.text = "Which hazard do you want to drop into?"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(body, UiTheme.LabelKind.BODY)
	panel.add_child(body)
	# Only live hazards (Roman 2026-05-18 — roster_test was a one-off dev
	# scenario, not something players see; pulled).
	for entry in [["Minefield", "minefield"], ["Asteroid Field", "asteroid_field"]]:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(140, 18)
		UiTheme.style_button(btn)
		btn.pressed.connect(_on_test_hazard_pick.bind(entry[1]))
		panel.add_child(btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(140, 16)
	UiTheme.style_button(cancel_btn, true)
	cancel_btn.pressed.connect(_close_test_hazard_modal)
	panel.add_child(cancel_btn)
	add_child(layer)
	_test_hazard_modal = layer


func _close_test_hazard_modal() -> void:
	if _test_hazard_modal != null and is_instance_valid(_test_hazard_modal):
		_test_hazard_modal.queue_free()
	_test_hazard_modal = null


func _on_test_hazard_pick(subtype: String) -> void:
	# Minefield gets a sub-modal so the tester can pick mine composition
	# (Roman 2026-05-18). Other hazards launch immediately.
	if subtype == "minefield":
		_close_test_hazard_modal()
		_show_minefield_options_modal()
		return
	_close_test_hazard_modal()
	_launch_hazard(subtype)


func _launch_hazard(subtype: String) -> void:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.new_run()
		run.test_mode_active = true
		run.current_hazard_subtype = subtype
		run.current_node_type = 5  # SectorNode.NodeType.HAZARD
	SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")


# Faction picker (M6b) — force a specific faction onto a standard combat level so all
# four can be eyeballed on demand (otherwise the faction is deterministic per level).
func _on_test_faction() -> void:
	if _test_hazard_modal != null and is_instance_valid(_test_hazard_modal):
		return
	var layer := CanvasLayer.new()
	layer.layer = 80
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(200, 150)
	panel.add_theme_constant_override("separation", 10)
	center.add_child(panel)
	var header := Label.new()
	header.text = "FORCE FACTION"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	panel.add_child(header)
	for fid in [Factions.Id.SUPREMACY, Factions.Id.PRIVATEER, Factions.Id.CORPORATE, Factions.Id.ZEALOT]:
		var btn := Button.new()
		btn.text = String(Factions.data(fid).get("lore_name", "Faction %d" % fid))
		btn.custom_minimum_size = Vector2(180, 18)
		UiTheme.style_button(btn)
		btn.pressed.connect(_launch_faction.bind(fid))
		panel.add_child(btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(140, 16)
	UiTheme.style_button(cancel_btn, true)
	cancel_btn.pressed.connect(_close_test_hazard_modal)
	panel.add_child(cancel_btn)
	add_child(layer)
	_test_hazard_modal = layer


func _launch_em_torpedo_test() -> void:
	_close_test_hazard_modal()
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.new_run()
		run.test_mode_active = true
		run.current_node_type = 0  # SectorNode.NodeType.COMBAT
		# Shallow depth = lots of soft chaff to vaporize so the wreck-drift reads clearly.
		run.sectors_cleared = 1
		run.combats_in_sector = 0
		# Equip the EM Torpedo into the wing secondary so it's live from wave 1. The player's _ready()
		# overlays Run.loadout_snapshot, so equipping before the scene change is enough — no main.gd
		# edit needed. Mk.3 for a punchier burst while testing.
		var torp = PartCatalog._make_by_name("_make_em_torpedo", SlotTypes.SlotType.HARDPOINT_WING)
		if torp != null:
			if "mark" in torp:
				torp.mark = 3
			run.equip_part(torp)
	SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")


func _launch_faction(faction_id: int) -> void:
	_close_test_hazard_modal()
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.new_run()
		run.test_mode_active = true
		run.current_node_type = 0  # SectorNode.NodeType.COMBAT
		# Launch at a RICH depth (sd=3, li=2): at the shallowest coord only the
		# universal commons are unlocked, so every faction looks identical — depth is
		# where the faction-exclusive enemies (beamers, bulwark, frigate, firecore_*)
		# come online and the rosters actually diverge.
		run.sectors_cleared = 2     # -> sector_depth = 3
		run.combats_in_sector = 2   # -> level_index = 2
		run.set_meta("forced_faction", faction_id)
	SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")


# Launch a sector map where EVERY POI is a Signal Event, for testing the signal
# screen. The force_all_signal meta is read by run_state._gen_row_pois when the
# sector cache builds on map entry, and cleared by the next new_run(). Bosses are
# a separate row, untouched — click the signal POIs directly.
func _on_all_signal_sector() -> void:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.new_run()
		run.set_meta("force_all_signal", true)  # AFTER new_run (new_run clears metas)
	SceneTransition.change_scene(get_tree(), SectorMapRoute.SECTOR_MAP_SCENE)


# Mine type sub-modal — Roman 2026-05-18.
const MINEFIELD_OPTIONS := [
	["Mixed (default)", "mixed"],
	["Basic only", "basic"],
	["Smart", "smart"],
	["Shielded", "shielded"],
	["Cluster", "cluster"],
	["Mega Cluster", "mega"],
]


func _show_minefield_options_modal() -> void:
	if _test_hazard_modal != null and is_instance_valid(_test_hazard_modal):
		return
	var layer := CanvasLayer.new()
	layer.layer = 80
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(200, 200)
	panel.add_theme_constant_override("separation", 10)
	center.add_child(panel)
	var header := Label.new()
	header.text = "MINEFIELD COMPOSITION"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	panel.add_child(header)
	var body := Label.new()
	body.text = "Mine type for the field:"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(body, UiTheme.LabelKind.BODY)
	panel.add_child(body)
	# Roman 2026-05-24: 6 mine types in 2 columns for vertical safety at
	# 480x270 (matches boss picker layout).
	var mine_grid := GridContainer.new()
	mine_grid.columns = 2
	mine_grid.add_theme_constant_override("h_separation", 6)
	mine_grid.add_theme_constant_override("v_separation", 4)
	panel.add_child(mine_grid)
	for entry in MINEFIELD_OPTIONS:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(100, 16)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiTheme.style_button(btn)
		btn.pressed.connect(_on_minefield_option_pick.bind(entry[1]))
		mine_grid.add_child(btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(160, 16)
	UiTheme.style_button(cancel_btn, true)
	cancel_btn.pressed.connect(_close_test_hazard_modal)
	panel.add_child(cancel_btn)
	add_child(layer)
	_test_hazard_modal = layer


func _on_minefield_option_pick(mine_type: String) -> void:
	_close_test_hazard_modal()
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.set_meta("minefield_mine_type", mine_type)
	_launch_hazard("minefield")


# ---- Boss Fight modal (Roman 2026-05-18) ----
# Mirrors the Test Hazard pattern but for individual boss scenes.

const BOSS_PICKS := [
	["Commander", "res://scenes/enemies/boss.tscn"],
	["Lash", "res://scenes/enemies/boss_reaver.tscn"],
	["Aegis", "res://scenes/enemies/boss_sentinel.tscn"],
	["Howler", "res://scenes/enemies/boss_howler.tscn"],
	["Voidmaw", "res://scenes/enemies/boss_voidmaw.tscn"],
	["Spinwright", "res://scenes/enemies/boss_spinwright.tscn"],
	["Conductor", "res://scenes/enemies/boss_conductor.tscn"],
]


func _on_asteroid_lab() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/asteroid_lab.tscn")


func _on_boss_fight() -> void:
	if _test_hazard_modal != null and is_instance_valid(_test_hazard_modal):
		return
	var layer := CanvasLayer.new()
	layer.layer = 80
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(200, 140)
	panel.add_theme_constant_override("separation", 12)
	center.add_child(panel)
	var header := Label.new()
	header.text = "BOSS FIGHT"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	panel.add_child(header)
	var body := Label.new()
	body.text = "Which boss?"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(body, UiTheme.LabelKind.BODY)
	panel.add_child(body)
	# Roman 2026-05-24: roster grew to 7, single-column VBox overflowed the
	# 480x270 viewport. 2-column grid fits 7 entries in 4 rows.
	var boss_grid := GridContainer.new()
	boss_grid.columns = 2
	boss_grid.add_theme_constant_override("h_separation", 6)
	boss_grid.add_theme_constant_override("v_separation", 4)
	panel.add_child(boss_grid)
	for entry in BOSS_PICKS:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(90, 16)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiTheme.style_button(btn)
		btn.pressed.connect(_on_boss_pick.bind(entry[1]))
		boss_grid.add_child(btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(140, 16)
	UiTheme.style_button(cancel_btn, true)
	cancel_btn.pressed.connect(_close_test_hazard_modal)
	panel.add_child(cancel_btn)
	add_child(layer)
	_test_hazard_modal = layer


func _on_boss_pick(scene_path: String) -> void:
	_close_test_hazard_modal()
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.new_run()
		run.test_mode_active = true
		run.forced_boss_scene = scene_path
		run.current_node_type = 3  # SectorNode.NodeType.BOSS
	SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")
