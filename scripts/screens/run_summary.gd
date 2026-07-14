extends Control

# Run summary shown after death. Black backdrop, big title, stats, two
# buttons (New Game + Main Menu) + Quit. Code-driven layout to avoid the
# old .tscn's broken Panel anchors that caused a black-screen-only result.

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SummaryUi = preload("res://scripts/ui/summary_ui.gd")
const SectorMapRoute = preload("res://scripts/systems/sector_map_route.gd")

@onready var title_label: Label = $Center/Panel/VBox/Title
@onready var stats_label: Label = $Center/Panel/VBox/Stats
@onready var new_game_btn: Button = $Center/Panel/Buttons/NewGameBtn
@onready var menu_btn: Button = $Center/Panel/Buttons/MenuBtn
@onready var quit_btn: Button = $Center/Panel/Buttons/QuitBtn

var _hd_scope: HdViewportScope = null
# "died" (default, reached via main.gd) or "victory" (cleared_summary sets the
# Run meta "run_outcome" on a final-sector clear). Drives the title + history log.
var _outcome: String = "died"

func _ready() -> void:
	# Render at HD (1920×1080) for a roomy summary card.
	_hd_scope = HdScreen.enter(self)
	# Run is over (death or victory) — wipe the resume save so Main Menu's
	# Resume Patrol doesn't drop the player back into a corpse run.
	if has_node("/root/Run"):
		var _run = get_node("/root/Run")
		_run.clear_save()
		# Append this run to the dated history index — but only on the REAL death
		# flow (this scene IS the current scene), not when run_summary is instanced
		# under a Node2D for showcase capture (which would log a bogus 0-stat run).
		if get_tree().current_scene == self:
			# Victory routes through here too (cleared_summary sets the meta); death is
			# the default. Consume the meta so a later run can't inherit a stale outcome.
			if _run.has_meta("run_outcome"):
				_outcome = String(_run.get_meta("run_outcome"))
				_run.remove_meta("run_outcome")
			_run.record_run_history(_outcome)
	# Force the root + Center to fill the viewport, regardless of parent.
	# When this scene is loaded by change_scene_to_file Godot auto-fills,
	# but when instanced under a Node2D (showcase capture) it stays 0x0.
	var vp: Vector2 = get_viewport_rect().size
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = vp
	z_index = 100
	# Belt-and-braces: keep the panel visible from the jump. The previous
	# fade-in tween was hiding the menu when SceneTransition's in-wipe ran
	# slow, leaving the player staring at black.
	$Center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$Center.position = Vector2.ZERO
	$Center.size = vp
	$Center.modulate = Color(1, 1, 1, 1)
	$Center.visible = true
	# Sector backdrop so the death screen reads as the same meta state
	# as the main menu / cleared screen (Roman, 2026-05-17).
	if $Bg:
		$Bg.color = Color(0, 0, 0, 0)
	# Shared sector-bg installer (same look as menu / sector map / level-clear screen).
	SummaryUi.install_backdrop(self)
	new_game_btn.text = "New Patrol"
	menu_btn.text = "Main Menu"
	quit_btn.text = "Quit"
	# Unified styling.
	if title_label:
		title_label.text = "PATROL COMPLETE" if _outcome == "victory" else "RUN ENDED"
		UiTheme.style_label(title_label, UiTheme.LabelKind.TITLE)
		title_label.material = UiTheme.make_holo_material(UiTheme.HoloPreset.OVERLAY)
	if stats_label:
		UiTheme.style_label(stats_label, UiTheme.LabelKind.BODY)
		stats_label.material = UiTheme.make_holo_material(UiTheme.HoloPreset.OVERLAY)
	# Roomy HD card + buttons (the .tscn sizes assume the old 480 canvas).
	var panel := $Center/Panel
	if panel is Control:
		(panel as Control).custom_minimum_size = Vector2(760, 0)
	for b in [new_game_btn, menu_btn, quit_btn]:
		UiTheme.style_button(b)
		b.custom_minimum_size = Vector2(220, 60)
	new_game_btn.pressed.connect(_new_game)
	menu_btn.pressed.connect(_to_menu)
	quit_btn.pressed.connect(_quit)
	_render()


func _style_outline_button(btn: Button) -> void:
	UiTheme.style_button(btn)

func _render() -> void:
	var text := ""
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		var st: Dictionary = run.run_stats if "run_stats" in run else {}
		var sf: int = int(st.get("shots_fired", 0))
		var sh: int = int(st.get("shots_hit", 0))
		var acc: String = ("%d%%" % int(round(100.0 * float(sh) / float(sf)))) if sf > 0 else "—"
		var uniq_weapons: int = int((st.get("weapons_used", {}) as Dictionary).size())
		# Seed line: always shown so a player can note/replay the run; "(custom)" when they
		# entered it themselves. strings.gd is mid-edit in another session, so this label is
		# inlined like the rest of the summary text rather than pulled from a strings const.
		var seed_suffix: String = "  (custom)" if ("seed_was_custom" in run and run.seed_was_custom) else ""
		text = "Time: %s\nEnemies destroyed: %d\nBosses defeated: %d\nSectors cleared: %d\nBounty earned: %d\nBounty spent: %d\nDamage taken: %d shield · %d hull\nShots: %d fired · %d hit  (%s)\nUnique weapons: %d\nLocations: %d   ·   Outposts: %d   ·   Signals: %d\nAsteroids destroyed: %d\nMines cleared: %d\nDistance: %d\nSeed: %d%s" % [
			_fmt_time(run.run_time_seconds if "run_time_seconds" in run else 0.0),
			run.enemies_killed, run.bosses_defeated, run.sectors_cleared,
			int(st.get("bounty_gained", run.max_bounty_earned)),
			int(st.get("bounty_spent", 0)),
			int(st.get("damage_shield", 0)), int(st.get("damage_hull", 0)),
			sf, sh, acc,
			uniq_weapons,
			int(st.get("locations_visited", 0)), int(st.get("stations_visited", 0)), int(st.get("signals_visited", 0)),
			int(st.get("asteroids", 0)), int(st.get("mines_cleared", 0)),
			int(run.run_distance),
			int(run.run_seed), seed_suffix
		]
	else:
		text = "No run data."
	stats_label.text = text


func _fmt_time(secs: float) -> String:
	return SummaryUi.fmt_mmss(secs)

func _new_game() -> void:
	# New Patrol → the hangar patrol-start sequence (same as the main menu, 2026-06-27). It resets
	# the run, writes the chosen hull/livery, and hands off to onboarding / the sector map.
	# Flag a LIVE launch (like main_menu._on_new_game) so patrol_start builds the real player-facing
	# menu — default hull pre-readied on the pad, NO dummy main-menu bridge, NO Tune ⚙ dev rail. Without
	# this the death screen dropped into the dev-clone tuner. We don't hand over a backdrop/snapshot
	# (the death screen's backdrop is a static painting, not the live parallax), so SceneTransition's
	# black fade covers the swap and patrol_start builds a fresh backdrop.
	var run := get_node_or_null("/root/Run")
	if run != null:
		run.set_meta("patrol_live_launch", true)
	SceneTransition.change_scene(get_tree(), "res://scenes/patrol_start.tscn")

func _to_menu() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")

func _quit() -> void:
	get_tree().quit()
