extends Control

# Main menu. First scene shown on launch. Styled to match the in-game
# hologram aesthetic: parallax backdrop, big centered teal title, outlined
# buttons. All styling is code-driven so the .tscn cache-bind trap doesn't
# bite when we iterate.

const BACKDROP_SCRIPT = preload("res://scripts/galaxy_backdrop.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SectorMapRoute = preload("res://scripts/sector_map_route.gd")

@onready var continue_btn: Button = $Center/VBox/ContinueBtn
@onready var new_game_btn: Button = $Center/VBox/NewGameBtn
@onready var options_btn: Button = $Center/VBox/OptionsBtn
@onready var credits_btn: Button = $Center/VBox/CreditsBtn
@onready var test_bed_btn: Button = $Center/VBox/TestBedBtn if has_node("Center/VBox/TestBedBtn") else null
@onready var exit_btn: Button = $Center/VBox/ExitBtn
# Test Hazard button is code-injected next to the Test Bed shortcut so we
# don't have to edit the .tscn (which triggers the scene-cache bind trap).
var test_hazard_btn: Button = null
var _test_hazard_modal: CanvasLayer = null
@onready var title_label: Label = $Center/VBox/Title
@onready var version_label: Label = $VersionLabel if has_node("VersionLabel") else null
@onready var center: CenterContainer = $Center
@onready var vbox: VBoxContainer = $Center/VBox


func _ready() -> void:
	_fix_center_anchors()
	_install_backdrop()
	_style_title()
	_add_subtitle()
	_style_buttons()
	_style_version()
	# Continue is enabled only if a save exists (placeholder for now)
	continue_btn.disabled = not _has_save()
	continue_btn.pressed.connect(_on_continue)
	new_game_btn.pressed.connect(_on_new_game)
	options_btn.pressed.connect(_on_options)
	credits_btn.pressed.connect(_on_credits)
	exit_btn.pressed.connect(_on_exit)
	# Dev shortcuts moved to a dedicated Dev Menu (Roman, 2026-05-16). The
	# old Test Bed button in the .tscn stays hidden; everything dev-related
	# lives behind one entry now.
	if test_bed_btn != null:
		test_bed_btn.visible = false
	_install_dev_menu_button()
	_install_codex_button()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")


# The packed scene's CenterContainer doesn't actually center because its
# anchors weren't fully set. Force full-rect anchors so the VBox centers on
# the viewport.
func _fix_center_anchors() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = vp_size
	# Bump the menu Control's render bucket above 0 so any parallax planet
	# halos or transient overlays inside the Backdrop can't accidentally
	# draw over the buttons.
	z_index = 10
	z_as_relative = false
	if center == null:
		return
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.position = Vector2.ZERO
	center.size = vp_size
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH


func _install_backdrop() -> void:
	# Spawn the same parallax setup the combat scene uses. Slower planet drift
	# so the menu's planet doesn't blow past — this is the lobby, not a level.
	var bd := Node2D.new()
	bd.name = "Backdrop"
	bd.set_script(BACKDROP_SCRIPT)
	# Reasonable tune for a menu — present, calm but with motion. Asteroids
	# might or might not roll in; same call as combat.
	bd.set("drift_speed", 14.0)
	bd.set("starfield_density", 36.0)
	bd.set("starfield_scroll", 6.0)
	bd.set("warp_streak_count", 8)
	bd.set("warp_streak_speed", 432.0)
	bd.set("asteroid_presence", 0.5)
	add_child(bd)
	move_child(bd, 0)


func _style_title() -> void:
	if title_label == null:
		return
	title_label.text = "STARBLASTER"
	UiTheme.style_label(title_label, UiTheme.LabelKind.TITLE)
	# Main menu title is the biggest text in the game — override the theme
	# title size up from the canonical 64 to a dramatic 88.
	title_label.add_theme_font_size_override("font_size", 24)  # 320×400 res
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.material = UiTheme.make_holo_material(UiTheme.HoloPreset.TITLE)


func _add_subtitle() -> void:
	# Subtitle cut by design — title carries the menu on its own. Keep the
	# function as a no-op hook in case we want to bring it back later.
	return


func _style_buttons() -> void:
	var btns: Array = [continue_btn, new_game_btn, options_btn, credits_btn, test_bed_btn, exit_btn]
	for b in btns:
		UiTheme.style_button(b, true)  # dense — menu has 5+ buttons
	# Test bed keeps its distinct green to mark it as a dev shortcut.
	if test_bed_btn != null:
		test_bed_btn.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6, 1.0))


func _style_version() -> void:
	if version_label == null:
		return
	var v = ProjectSettings.get_setting("application/config/version", "?")
	version_label.text = "v%s" % v
	UiTheme.style_label(version_label, UiTheme.LabelKind.CAPTION)
	# CAPTION is 10pt — version label was unreadable on the web build
	# (Roman 2026-05-18 "0.1.31 or 0.1.91"). Bump to 14pt and brighten.
	version_label.add_theme_font_size_override("font_size", 14)
	version_label.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1.0))


func _on_test_bed() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/debug_testbed.tscn")

func _has_save() -> bool:
	if has_node("/root/Run"):
		return get_node("/root/Run").has_save_on_disk()
	return false

func _on_continue() -> void:
	# Resume Patrol: load the saved run into the Run autoload, then jump to
	# the sector map (the only mid-run save point). Falls back to a fresh
	# run if the load fails for any reason — better than booting into a
	# half-applied state.
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if not run.load_from_disk():
			run.new_run()
	SceneTransition.change_scene(get_tree(), SectorMapRoute.SECTOR_MAP_SCENE)

func _on_new_game() -> void:
	if has_node("/root/Run"):
		get_node("/root/Run").new_run()
	# New game funnels through onboarding before the sector map (Roman,
	# 2026-05-16). The onboarding screen's "Begin Run" / "Skip" both jump
	# the player to the sector map.
	SceneTransition.change_scene(get_tree(), "res://scenes/onboarding.tscn")

func _on_options() -> void:
	var OptionsOverlay = load("res://scripts/ui/options_overlay.gd")
	OptionsOverlay.open(self)

func _on_credits() -> void:
	pass  # Placeholder

func _on_exit() -> void:
	get_tree().quit()


# ----- Dev Menu shortcut --------------------------------------------------

# One green dev-shortcut button replaces the per-tool sprinkle (Test Bed,
# Test Hazard, Hangar). Opens scenes/dev_menu.tscn which carries all of
# those plus Maneuver Sim and Shipyard.
func _install_dev_menu_button() -> void:
	var btn := Button.new()
	btn.text = "[ Dev Menu ]"
	btn.custom_minimum_size = Vector2(160, 22)
	UiTheme.style_button(btn, true)
	btn.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6, 1.0))
	btn.pressed.connect(func():
		SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")
	)
	vbox.add_child(btn)
	if exit_btn != null:
		vbox.move_child(btn, exit_btn.get_index())


# Enemy Codex — main-menu entry into the holo-shaded enemy reference.
# Player-facing (not a dev shortcut) — placed between Credits and Exit.
func _install_codex_button() -> void:
	var btn := Button.new()
	btn.text = "Codex"
	btn.custom_minimum_size = Vector2(160, 22)
	UiTheme.style_button(btn)
	btn.pressed.connect(func():
		var SceneTransition = load("res://scripts/scene_transition.gd")
		SceneTransition.change_scene(get_tree(), "res://scenes/enemy_codex.tscn")
	)
	vbox.add_child(btn)
	if exit_btn != null:
		vbox.move_child(btn, exit_btn.get_index())


# Build a CanvasLayer modal with a dim backdrop + centered panel that asks
# which hazard to drop the player into. Clicking a hazard sets up Run.test_mode
# and transitions into combat; cancel just closes the modal.
func _show_test_hazard_modal() -> void:
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
	panel.custom_minimum_size = Vector2(440, 280)
	panel.add_theme_constant_override("separation", 16)
	center.add_child(panel)
	var header := Label.new()
	header.text = "TEST HAZARD"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	header.material = UiTheme.make_holo_material(UiTheme.HoloPreset.TITLE)
	panel.add_child(header)
	var body := Label.new()
	body.text = "Which hazard do you want to drop into?"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(body, UiTheme.LabelKind.BODY)
	panel.add_child(body)
	var minefield_btn := Button.new()
	minefield_btn.text = "Minefield"
	minefield_btn.custom_minimum_size = Vector2(320, 50)
	UiTheme.style_button(minefield_btn)
	minefield_btn.pressed.connect(_on_test_hazard_pick.bind("minefield"))
	panel.add_child(minefield_btn)
	var asteroid_btn := Button.new()
	asteroid_btn.text = "Asteroid Field"
	asteroid_btn.custom_minimum_size = Vector2(320, 50)
	UiTheme.style_button(asteroid_btn)
	asteroid_btn.pressed.connect(_on_test_hazard_pick.bind("asteroid_field"))
	panel.add_child(asteroid_btn)
	var roster_btn := Button.new()
	roster_btn.text = "New Enemy Roster"
	roster_btn.custom_minimum_size = Vector2(320, 50)
	UiTheme.style_button(roster_btn)
	roster_btn.pressed.connect(_on_test_hazard_pick.bind("roster_test"))
	panel.add_child(roster_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(320, 40)
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
	_close_test_hazard_modal()
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		# Fresh run state so the hazard runs in isolation; flag test_mode so
		# cleared_summary knows to bounce back to the main menu instead of
		# the sector map.
		run.new_run()
		run.test_mode_active = true
		run.current_hazard_subtype = subtype
		run.current_node_type = 5  # SectorNode.NodeType.HAZARD
	SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")
