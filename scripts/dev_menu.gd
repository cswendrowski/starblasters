extends Control

# Developer menu — gathered from the dev shortcuts that used to live on the
# main menu (Test Bed, Test Hazard, Hangar) plus new tools (Maneuver Sim,
# Shipyard). Reached from a single "Dev Menu" button on the main menu so
# the main menu itself stays focused on player-facing entries.

const BACKDROP_SCRIPT = preload("res://scripts/galaxy_backdrop.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

var _test_hazard_modal: CanvasLayer = null
var _vbox: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_install_backdrop()
	_build_ui()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")


func _install_backdrop() -> void:
	var bd := Node2D.new()
	bd.name = "Backdrop"
	bd.set_script(BACKDROP_SCRIPT)
	bd.set("drift_speed", 10.0)
	bd.set("starfield_density", 30.0)
	bd.set("starfield_scroll", 5.0)
	bd.set("warp_streak_count", 6)
	bd.set("warp_streak_speed", 280.0)
	bd.set("asteroid_presence", 0.0)
	add_child(bd)
	move_child(bd, 0)


func _build_ui() -> void:
	# Wrap the menu in a ScrollContainer so the bottom-most button is
	# always reachable on the 320×400 viewport (Roman, 2026-05-18: "the
	# bottom most button is cut off"). Center horizontally + give a fixed
	# inset so the column is a consistent 180px wide.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 70)
	pad.add_theme_constant_override("margin_right", 70)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	var v := VBoxContainer.new()
	# Tighter separation — was 12, dev menu fits 400px with 8 (Roman
	# also wants the bottom button visible).
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size = Vector2(180, 0)
	pad.add_child(v)
	_vbox = v

	var title := Label.new()
	title.text = "DEV MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(title, UiTheme.LabelKind.TITLE)
	title.add_theme_font_size_override("font_size", 18)
	v.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "developer tools"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(subtitle, UiTheme.LabelKind.CAPTION)
	v.add_child(subtitle)

	v.add_child(HSeparator.new())

	# Roman, 2026-05-18: Maneuver Sim and Import/Export pulled from the
	# menu for now (kept in code, just not exposed).
	_add_button("[ Movement Test ]", _on_movement_test, true)
	_add_button("[ Movement Lab ]", _on_movement_lab, true)
	_add_button("[ Wave Tester ]", _on_wave_tester, true)
	_add_button("[ Shipyard ]", _on_shipyard, true)
	_add_button("[ Parallax Tuner ]", _on_parallax_tuner, true)
	_add_button("[ Test Bed ]", _on_test_bed, true)
	_add_button("[ Test Hazard ]", _on_test_hazard, true)
	_add_button("[ Boss Fight ]", _on_boss_fight, true)
	_add_button("[ Asteroid Lab ]", _on_asteroid_lab, true)
	_add_button("[ Hangar ]", _on_hangar, true)

	v.add_child(HSeparator.new())

	_add_button("Back", _on_back, false)


func _add_button(text: String, cb: Callable, dev_green: bool) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(140, 16)
	UiTheme.style_button(btn, true)
	if dev_green:
		btn.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6, 1.0))
	btn.pressed.connect(cb)
	_vbox.add_child(btn)


# ---- Button handlers ----

func _on_shipyard() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/shipyard.tscn")


func _on_movement_test() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/movement_test.tscn")


func _on_movement_lab() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/movement_lab.tscn")


func _on_wave_tester() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/wave_tester.tscn")


func _on_parallax_tuner() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev/parallax_tuner.tscn")




func _on_test_bed() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/debug_testbed.tscn")


func _on_hangar() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/hangar.tscn")


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
	for entry in MINEFIELD_OPTIONS:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(160, 18)
		UiTheme.style_button(btn)
		btn.pressed.connect(_on_minefield_option_pick.bind(entry[1]))
		panel.add_child(btn)
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
	["Reaver", "res://scenes/enemies/boss_reaver.tscn"],
	["Sentinel", "res://scenes/enemies/boss_sentinel.tscn"],
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
	for entry in BOSS_PICKS:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(140, 18)
		UiTheme.style_button(btn)
		btn.pressed.connect(_on_boss_pick.bind(entry[1]))
		panel.add_child(btn)
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
