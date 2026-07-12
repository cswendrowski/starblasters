extends Control

# Main menu. First scene shown on launch. Styled to match the in-game
# hologram aesthetic: parallax backdrop, big centered teal title, outlined
# buttons. Node structure (CanvasLayer host, buttons, anchors, HD sizing)
# lives in main_menu.tscn; this script only wires signals and applies the
# runtime UiTheme styling (theme boxes + holo material can't be baked).

const MenuBackdrop = preload("res://scripts/ui/menu_backdrop.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SectorMapRoute = preload("res://scripts/systems/sector_map_route.gd")
const ShipCatalog = preload("res://scripts/strings/ship_catalog.gd")

const PATROL_SCENE := "res://scenes/patrol_start.tscn"
# Everything patrol_start load()s at runtime (hangar stage, dressing scenes/sheets — see its consts).
# Background-requested at menu load so "New Patrol"'s direct swap doesn't hitch on synchronous loads;
# ship sprite sheets are appended from ShipCatalog (see _patrol_preload_paths).
const PATROL_PRELOADS := [
	PATROL_SCENE,
	"res://scenes/hangar_stage.tscn",
	"res://scenes/outpost/outpost_lifter.tscn",
	"res://scenes/outpost/outpost_tractor.tscn",
	"res://scenes/outpost/outpost_tractor_trailer.tscn",
	"res://scenes/enemies/factions/zealot/firecore_core.tscn",
	"res://graphics/backgrounds/outpost_tractor.png",
	"res://graphics/backgrounds/outpost_tractor_trailer.png",
	"res://graphics/backgrounds/outpost_lifter.png",
	"res://graphics/backgrounds/outpost_ammo_crates.png",
]

@onready var continue_btn: Button = $MenuUI/Center/VBox/ContinueBtn
@onready var new_game_btn: Button = $MenuUI/Center/VBox/NewGameBtn
@onready var options_btn: Button = $MenuUI/Center/VBox/OptionsBtn
@onready var credits_btn: Button = $MenuUI/Center/VBox/CreditsBtn
@onready var test_bed_btn: Button = $MenuUI/Center/VBox/TestBedBtn
@onready var dev_menu_btn: Button = $MenuUI/Center/VBox/DevMenuBtn
@onready var codex_btn: Button = $MenuUI/Center/VBox/CodexBtn
@onready var run_history_btn: Button = $MenuUI/Center/VBox/RunHistoryBtn
@onready var exit_btn: Button = $MenuUI/Center/VBox/ExitBtn
var _test_hazard_modal: CanvasLayer = null
var _hd_scope: HdViewportScope = null
# The upscaled-backdrop SubViewport (from HdScreen.add_upscaled_backdrop). Handed to patrol_start on a
# live "Start New Patrol" so the LIVE backdrop (drift + star scatter) survives the swap (Roman 2026-07-02).
var _backdrop_sub: SubViewport = null
@onready var version_label: Label = $MenuUI/VersionLabel
@onready var center: CenterContainer = $MenuUI/Center
@onready var vbox: VBoxContainer = $MenuUI/Center/VBox


func _ready() -> void:
	# Render the menu at HD (1920×1080) for clear, roomy layout. Scope frees
	# with the scene; SceneTransition keeps the screen black during the swap
	# so the native combat scene we hand off to doesn't flash an HD blow-up.
	_hd_scope = HdScreen.enter(self)
	_install_backdrop()
	_preload_patrol_assets()
	_style_buttons()
	_style_version()
	# Continue is enabled only if a save exists (placeholder for now)
	continue_btn.disabled = not _has_save()
	continue_btn.pressed.connect(_on_continue)
	new_game_btn.pressed.connect(_on_new_game)
	options_btn.pressed.connect(_on_options)
	credits_btn.pressed.connect(_on_credits)
	dev_menu_btn.pressed.connect(_on_dev_menu)
	codex_btn.pressed.connect(_on_codex)
	run_history_btn.pressed.connect(_on_run_history)
	exit_btn.pressed.connect(_on_exit)
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")
	# Debug-only: warn if any menu Control spills past the 480×270 viewport
	# (deferred so the layout pass has resolved). No-op in release.
	UiTheme.assert_inside_viewport.call_deferred(self)


# NOTE: the interactive UI lives under the MenuUI CanvasLayer in the .tscn.
# Root-canvas Controls under the runtime HD content_scale swap can show an
# input-vs-visual offset (hover/click landing off the buttons); CanvasLayer-
# hosted UI — like the outpost, options, pause — is immune. The root Control
# also keeps z_index=10 (baked in the scene) so parallax planet halos or
# transient overlays inside the Backdrop can't draw over the buttons.
func _install_backdrop() -> void:
	# Back-out from patrol_start: it hands the SAME live backdrop back via the `menu_backdrop_live`
	# Run meta (mirror of the forward handoff in _on_new_game) — adopt it so the sky doesn't visibly
	# regenerate, and fade the menu UI in to finish the reversed intro transition.
	if _adopt_backdrop_from_patrol():
		_fade_in_menu_ui()
		return
	# Fresh build: the same at-rest parallax setup the patrol-start lobby uses (static sky — motion
	# only happens during the patrol-start rise).
	var bd := MenuBackdrop.make()
	# The parallax backdrop renders in native 480×270; this menu is HD. Show it
	# via a native SubViewport upscaled 4× (nearest) so it fills the screen the
	# same way combat's canvas stretch does — see HdScreen.add_upscaled_backdrop.
	# Stash the SubViewport so a live "Start New Patrol" can HAND THE WHOLE LIVE
	# backdrop to patrol_start (star scatter intact) instead of rebuilding.
	_backdrop_sub = HdScreen.add_upscaled_backdrop(self, bd)
	# Drop the celestial bodies toward the centre of the menu (they normally stage near the top); the
	# patrol-start sequence starts them here and pans them up as the hangar rises (kept in sync).
	MenuBackdrop.drop_celestials(bd)
	# Menu is at rest — no scroll (make() sets drift 0), so the warp streaks park too.
	MenuBackdrop.still_streaks(bd)


# Adopt the live backdrop SubViewport stashed by patrol_start._back() (if any). Returns true when
# adopted; consumes the meta either way, freeing an unusable stashed node so it never dangles.
func _adopt_backdrop_from_patrol() -> bool:
	var run := get_node_or_null("/root/Run")
	if run == null or not run.has_meta("menu_backdrop_live"):
		return false
	var sub = run.get_meta("menu_backdrop_live")
	run.remove_meta("menu_backdrop_live")   # consume unconditionally
	if not (sub is SubViewport) or not is_instance_valid(sub):
		return false
	if HdScreen.adopt_upscaled_backdrop(self, sub) == null:
		(sub as SubViewport).queue_free()
		return false
	_backdrop_sub = sub
	return true


# Tail end of the reversed patrol-start intro: the bay has sunk away and the sky panned back —
# now the logo/buttons/version fade back in over the persistent backdrop.
func _fade_in_menu_ui() -> void:
	center.modulate.a = 0.0
	version_label.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(center, "modulate:a", 1.0, 0.5)
	tw.tween_property(version_label, "modulate:a", 1.0, 0.5)


# Kick background threaded loads for the patrol-start scene + everything it load()s at runtime.
# By the time the player clicks "New Patrol" these are normally finished; _on_new_game drains them
# into the resource cache so the direct swap doesn't hitch.
func _preload_patrol_assets() -> void:
	for p in _patrol_preload_paths():
		ResourceLoader.load_threaded_request(p, "", true)


func _patrol_preload_paths() -> Array:
	var paths: Array = PATROL_PRELOADS.duplicate()
	for i in ShipCatalog.count():
		var ship: Dictionary = ShipCatalog.get_ship(i)
		for key in ["body", "livery", "engine"]:
			if ship.has(key):
				paths.append(ship[key])
	return paths


# Title is the StarBlaster logo sprite (Logo TextureRect in the .tscn, native
# 265×108 art at a 2× integer scale, nearest-filtered) — it replaced the old
# holo-styled "STARBLASTER" Label 2026-07-11.
func _style_buttons() -> void:
	# HD sizes (460×64, VBox 460, separation 14) are baked in the .tscn; here
	# we only apply the runtime theme (StyleBoxes + fonts can't be baked).
	var btns: Array = [continue_btn, new_game_btn, options_btn, credits_btn, test_bed_btn, dev_menu_btn, codex_btn, run_history_btn, exit_btn]
	for b in btns:
		if b == null:
			continue
		UiTheme.style_button(b, true)  # dense — menu has 5+ buttons
	# Dev shortcuts keep their distinct green to mark them as such.
	for b in [test_bed_btn, dev_menu_btn]:
		if b != null:
			b.add_theme_color_override("font_color", UiTheme.COLOR_GREEN)


func _style_version() -> void:
	if version_label == null:
		return
	var v = ProjectSettings.get_setting("application/config/version", "?")
	version_label.text = "v%s" % v
	UiTheme.style_label(version_label, UiTheme.LabelKind.CAPTION)
	# Brighten + bump so the version reads clearly at HD scale (Roman
	# 2026-05-18 wanted it legible on the web build).
	version_label.add_theme_font_size_override("font_size", 24)
	version_label.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1.0))
	# Box placement (HD bottom-right anchors + offsets sized for the 24px font,
	# per the 2026-06-11 clipping fix) is baked in the .tscn.


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
	# New patrol opens the hangar PATROL START sequence (cinematic ship-select). We hand off WITHOUT a
	# fade-to-black: snapshot the live menu frame, flag a LIVE launch, and let patrol_start crossfade
	# that snapshot out as the hangar rises — so the menu dissolves smoothly straight into the patrol
	# start, no black flash and no second menu. (The dev-menu launch of the same scene leaves these
	# metas unset → its own dummy menu + Tune rail. See patrol_start._ready.)
	if has_node("/root/Run"):
		var run := get_node("/root/Run")
		run.set_meta("patrol_live_launch", true)
		var snap := await _capture_screen()
		if snap != null:
			run.set_meta("patrol_menu_snapshot", snap)
		# Hand the LIVE backdrop over: detach the upscaled-backdrop SubViewport from the menu tree
		# (AFTER the snapshot, so it's in the captured frame) and stash it, so patrol_start ADOPTS the
		# already-rendered sky (accumulated parallax drift + per-layer star scatter intact) instead of
		# building a fresh coordinator that resets both — which made the crossfade dissolve into a
		# visibly-different sky. remove_child (not free) so change_scene's free of this scene leaves it
		# alive; patrol_start re-parents + consumes it (freeing it if adoption is impossible).
		if _backdrop_sub != null and is_instance_valid(_backdrop_sub):
			if _backdrop_sub.get_parent() != null:
				_backdrop_sub.get_parent().remove_child(_backdrop_sub)
			run.set_meta("patrol_backdrop_live", _backdrop_sub)
	# Direct swap (no SceneTransition black) — patrol_start owns the crossfade reveal. main_menu's
	# backdrop renders in a SubViewport (off the root canvas), so the change_scene backdrop-free
	# SIGSEGV guard SceneTransition adds for combat's direct-child Backdrop doesn't apply here.
	# Drain the background preload first (kicked off in _ready): load_threaded_get finishes any
	# stragglers and parks every resource in the cache, so the swap + patrol_start's runtime load()s
	# don't hitch.
	var packed: PackedScene = null
	for p in _patrol_preload_paths():
		var st := ResourceLoader.load_threaded_get_status(p)
		if st != ResourceLoader.THREAD_LOAD_IN_PROGRESS and st != ResourceLoader.THREAD_LOAD_LOADED:
			continue   # bad path / never requested — fall through to the plain load
		var res := ResourceLoader.load_threaded_get(p)
		if p == PATROL_SCENE:
			packed = res as PackedScene
	if packed != null:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(PATROL_SCENE)


# Capture the current rendered frame as a texture for patrol_start's crossfade hand-off. Returns null
# if the viewport image isn't available (e.g. a headless dummy renderer) — the destination then just
# skips the crossfade and runs the rise.
func _capture_screen() -> ImageTexture:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null:
		return null
	var vtex := vp.get_texture()
	if vtex == null:
		return null
	var img := vtex.get_image()
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)

func _on_options() -> void:
	var OptionsOverlay = load("res://scripts/ui/options_overlay.gd")
	OptionsOverlay.open(self)

func _on_credits() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/credits.tscn")

func _on_exit() -> void:
	get_tree().quit()


# ----- Dev Menu shortcut --------------------------------------------------

# One green dev-shortcut button replaces the per-tool sprinkle (Test Bed,
# Test Hazard, Hangar). Opens scenes/dev_menu.tscn which carries all of
# those plus Maneuver Sim and Shipyard.
func _on_dev_menu() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


# Enemy Codex — main-menu entry into the holo-shaded enemy reference.
# Player-facing (not a dev shortcut) — placed between Credits and Exit.
func _on_codex() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/enemy_codex.tscn")


# Run History — main-menu entry into the dated past-runs list. Player-facing;
# placed just above Exit, next to the Codex entry.
func _on_run_history() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/run_history.tscn")


# Build a CanvasLayer modal with a dim backdrop + centered panel that asks
# which hazard to drop the player into. Clicking a hazard sets up Run.test_mode
# and transitions into combat; cancel just closes the modal.
func _show_test_hazard_modal() -> void:
	if _test_hazard_modal != null and is_instance_valid(_test_hazard_modal):
		return
	# Shared modal scaffold (dim + centered panel). Picks scroll the hazard
	# list so it fits the 480×270 viewport regardless of how many are listed.
	var m := UiTheme.make_modal(80, Vector2(520, 0))
	var vbox: VBoxContainer = m["vbox"]
	vbox.add_theme_constant_override("separation", 12)

	var header := Label.new()
	header.text = "TEST HAZARD"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	vbox.add_child(header)
	var body := Label.new()
	body.text = "Which hazard do you want to drop into?"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(body, UiTheme.LabelKind.BODY)
	vbox.add_child(body)

	# Hazard picks in a height-capped scroll so the list never overflows.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 560)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var picks := VBoxContainer.new()
	picks.add_theme_constant_override("separation", 6)
	picks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(picks)

	var hazards := [
		["Minefield", "minefield"],
		["Asteroid Field", "asteroid_field"],
		["New Enemy Roster", "roster_test"],
		["Firecore Drone Showcase", "firecore_drone_showcase"],
		["Missile Cruiser Showcase", "missile_cruiser_showcase"],
	]
	for h in hazards:
		var btn := UiTheme.make_button(h[0])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_test_hazard_pick.bind(h[1]))
		picks.add_child(btn)

	var cancel_btn := UiTheme.make_button("Cancel", true)
	cancel_btn.pressed.connect(_close_test_hazard_modal)
	vbox.add_child(cancel_btn)

	add_child(m["layer"])
	_test_hazard_modal = m["layer"]


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
