extends CanvasLayer

# Cleared summary screen. Reveals top-down with a brief per-element fade-in
# (total reveal ≈ 2.5s). Tally + button are bottom-anchored so their position
# is consistent regardless of how many enemy types are in the list.
#
# Inputs to populate():
#   enemy_stats: { scene_path: { "spawned": int, "killed": int, "bounty": int,
#                                 "total_bounty": int } }
#   total_bounty: int

const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SummaryUi = preload("res://scripts/ui/summary_ui.gd")
const SectorMapRoute = preload("res://scripts/sector_map_route.gd")
const SECTOR_MAP_SCENE := SectorMapRoute.SECTOR_MAP_SCENE

# Cached enemy sprite textures keyed by scene path.
static var _sprite_cache: Dictionary = {}

var _shared_mat: ShaderMaterial = null
var _hd_scope: HdViewportScope = null

func _ready() -> void:
	layer = 90
	_hd_scope = HdScreen.enter(self)
	_layout_hd()
	_build_material()
	# Painted sector backdrop so the cleared screen reads as the same
	# meta-state as the sector map / main menu (Roman, 2026-05-17).
	if has_node("Bg"):
		var bg: ColorRect = $Bg
		bg.visible = false
	_install_backdrop()
	# Decompress the combat track while the summary holds — and freeze the
	# intensity walk so the music doesn't keep ramping up/down behind the
	# CLEARED screen (Roman, 2026-05-16).
	if has_node("/root/Music"):
		var music = get_node("/root/Music")
		music.ramp_down()
		music.set_walk_frozen(true)

func _build_material() -> void:
	_shared_mat = UiTheme.make_holo_material(UiTheme.HoloPreset.OVERLAY)


# The .tscn lays its title/list/bottom bands out in absolute pixels for the old
# 480×270 canvas. Rescale them for the 1920×1080 HD viewport so the title isn't
# clipped and the bottom button band has room. Fonts come from populate()'s
# UiTheme.style_label calls (HD), which override the .tscn font_size values.
func _layout_hd() -> void:
	var root := $Root as Control
	root.offset_left = 60.0
	root.offset_top = 40.0
	root.offset_right = -60.0
	root.offset_bottom = -40.0
	($Root/Title as Control).offset_bottom = 96.0
	var list := $Root/List as Control
	# Inset so the tally rows read as a centered table instead of stretching
	# name-left / value-right across the full 1920 width.
	list.offset_left = 660.0
	list.offset_right = -660.0
	list.offset_top = 150.0
	list.offset_bottom = 760.0
	list.add_theme_constant_override("separation", 12)
	var bottom := $Root/Bottom as Control
	bottom.offset_top = -190.0
	bottom.add_theme_constant_override("separation", 18)


func _install_backdrop() -> void:
	# Shared sector-bg installer (same look as menu / sector map / run-end screen).
	SummaryUi.install_backdrop(self)

func populate(enemy_stats: Dictionary, total_bounty: int, hide_tally: bool = false, was_boss: bool = false) -> void:
	var title: Label = $Root/Title
	var list: VBoxContainer = $Root/List
	var total_label: Label = $Root/Bottom/TotalBounty
	var btn: Button = $Root/Bottom/MapBtn

	title.text = "SECTOR CLEARED" if was_boss else "CLEARED!"
	UiTheme.style_label(title, UiTheme.LabelKind.TITLE)
	title.material = _shared_mat
	for c in list.get_children():
		c.queue_free()
	var rows: Array = []
	# Hazards render a stripped-down summary: no enemy tally, no bounty.
	if hide_tally:
		total_label.visible = false
		_install_hazard_flavor(title)
	else:
		total_label.visible = true
		total_label.text = "TOTAL BOUNTY: %d" % total_bounty
		UiTheme.style_label(total_label, UiTheme.LabelKind.BOUNTY)
		total_label.material = _shared_mat
		# Header line: clear-time + total enemies destroyed this combat (worklist
		# #37). Clear-time comes from main.gd via Run meta; kills are summed from
		# the tally so the two always agree.
		_install_clear_header(title, enemy_stats)
		# Sort rows largest-threat first (descending per-kill bounty, a stable
		# proxy for chassis size) so cruisers/elites head the list and chaff
		# trails — replaces the old alphabetical order (worklist #37).
		# Group the tally into SIZE sections (large -> medium -> small), each with a
		# header, sorted within by per-kill bounty desc (Roman worklist: "sort by
		# size, with medium/large in their own section"). Size from the roster via
		# SummaryUi.section_for_scene; huge folds into LARGE. Headers only show when
		# more than one section is populated (a single-size combat reads flat).
		var buckets := {"large": [], "medium": [], "small": []}
		for path in enemy_stats.keys():
			buckets[SummaryUi.section_for_scene(path)].append(path)
		var multi_section: bool = _populated_section_count(buckets) > 1
		for bucket in SummaryUi.SECTION_ORDER:
			var paths: Array = buckets[bucket]
			if paths.is_empty():
				continue
			paths.sort_custom(func(a, b):
				var ba: int = int(enemy_stats[a].get("bounty", 0))
				var bb: int = int(enemy_stats[b].get("bounty", 0))
				if ba == bb:
					return String(a) < String(b)
				return ba > bb)
			if multi_section:
				var hdr := _section_header(SummaryUi.SECTION_TITLE[bucket])
				list.add_child(hdr)
				rows.append(hdr)
			for path in paths:
				var row := _build_row(path, enemy_stats[path])
				list.add_child(row)
				rows.append(row)

	btn.material = null
	_style_outline_button(btn)
	btn.custom_minimum_size = Vector2(300, 64)
	# Re-label when this is a Test Hazard run so the player knows the button
	# bounces them to the main menu, not a sector map (which doesn't exist
	# for a test launch).
	if has_node("/root/Run") and get_node("/root/Run").test_mode_active:
		btn.text = "[ MAIN MENU ]"
	if not btn.pressed.is_connected(_on_map_pressed):
		btn.pressed.connect(_on_map_pressed)

	# Boss arena clear → endless-mode prompt ONLY if every row boss in the
	# sector is dead. A single-row boss kill in V3 is just one of three
	# milestones; bounce the player back to the sector map so they can
	# pick another row.
	var endless_buttons: Array = []
	var sector_actually_done: bool = false
	var patrol_complete: bool = false
	if was_boss and has_node("/root/Run"):
		var _run = get_node("/root/Run")
		sector_actually_done = _run.is_sector_complete()
		# Final sector cleared = patrol complete (victory). sectors_cleared is still
		# PRE-bump here (it only bumps on NEXT SECTOR / the map return), so the
		# just-cleared sector index is sectors_cleared + 1.
		patrol_complete = sector_actually_done and int(_run.sectors_cleared) + 1 >= int(_run.TOTAL_SECTORS)
	if patrol_complete:
		# VICTORY — the patrol is done. Route to the run summary as a win instead of
		# looping back into the (endless) next-sector map.
		title.text = "PATROL COMPLETE"
		btn.text = "[ VIEW SUMMARY ]"
		if btn.pressed.is_connected(_on_map_pressed):
			btn.pressed.disconnect(_on_map_pressed)
		btn.pressed.connect(_on_victory)
	elif was_boss and sector_actually_done:
		btn.visible = false
		endless_buttons = _install_endless_buttons(btn.get_parent())
	elif was_boss:
		# Boss down but sector still has bosses left. Override the title
		# so the player knows there's more to come.
		title.text = "BOSS DOWN"

	var reveal_btn = btn
	if not endless_buttons.is_empty():
		# Reveal both buttons in sequence; pick the last one to align with the
		# existing single-button reveal slot.
		reveal_btn = endless_buttons[endless_buttons.size() - 1]
		# Animate the first one alongside.
		endless_buttons[0].modulate.a = 0.0
		var tw0 := create_tween()
		tw0.tween_interval(0.4)
		tw0.tween_property(endless_buttons[0], "modulate:a", 1.0, 0.25)
	_play_reveal(title, rows, total_label if not hide_tally else null, reveal_btn)


# A small subtitle under the title: "Cleared in M:SS  ·  N destroyed". Clear-time
# is the active-combat seconds main.gd stashed in Run meta; N is summed from the
# tally. Added as a sibling right after the Title so it rides the reveal fade.
func _install_clear_header(title: Label, enemy_stats: Dictionary) -> void:
	var total_killed: int = 0
	for s in enemy_stats.values():
		total_killed += int(s.get("killed", 0))
	var secs: float = 0.0
	if has_node("/root/Run"):
		secs = float(get_node("/root/Run").get_meta("last_combat_clear_time", 0.0))
	var hdr := Label.new()
	hdr.name = "ClearHeader"
	hdr.text = "Cleared in %s   ·   %d destroyed" % [_fmt_mmss(secs), total_killed]
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	hdr.add_theme_color_override("font_color", UiTheme.COLOR_HOLO)
	hdr.add_theme_font_override("font", UiTheme.menu_font())
	hdr.material = _shared_mat
	# Root is a plain Control with absolutely-positioned children, so place the
	# header explicitly in the gap between the title (bottom 96 from _layout_hd)
	# and the list (top 150) rather than relying on flow layout.
	var title_parent := title.get_parent() as Control
	hdr.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hdr.anchor_right = 1.0
	hdr.offset_left = 0.0
	hdr.offset_right = 0.0
	hdr.offset_top = 104.0
	hdr.offset_bottom = 140.0
	title_parent.add_child(hdr)
	title_parent.move_child(hdr, title.get_index() + 1)
	# Ride the reveal: fade in just after the title (which reveals first).
	hdr.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.2)
	tw.tween_property(hdr, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _fmt_mmss(secs: float) -> String:
	return SummaryUi.fmt_mmss(secs)


# Build a horizontal row with [ Main Menu ] and [ Next Sector ] buttons under
# the cleared summary's bottom anchor. Returned in order so the caller can
# fade them in.
func _install_endless_buttons(bottom: Node) -> Array:
	var row := HBoxContainer.new()
	row.name = "EndlessChoiceRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	bottom.add_child(row)
	var menu_btn := Button.new()
	menu_btn.text = "[ MAIN MENU ]"
	UiTheme.style_button(menu_btn)
	menu_btn.pressed.connect(_on_end_run)
	row.add_child(menu_btn)
	var next_btn := Button.new()
	next_btn.text = "[ NEXT SECTOR ]"
	UiTheme.style_button(next_btn)
	next_btn.pressed.connect(_on_next_sector)
	row.add_child(next_btn)
	return [menu_btn, next_btn]


# Patrol complete (final sector cleared) — go to the run summary as a VICTORY. The
# summary reads the "run_outcome" meta to log history + title itself a win.
func _on_victory() -> void:
	if has_node("/root/Run"):
		get_node("/root/Run").set_meta("run_outcome", "victory")
	var root: Control = $Root
	var tw = create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw.finished
	SceneTransition.change_scene(get_tree(), "res://scenes/run_summary.tscn")


# End the run — back to main menu, fresh start next time.
func _on_end_run() -> void:
	var root: Control = $Root
	var tw = create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw.finished
	SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")


# Next sector — bump sectors_cleared, generate a fresh V3 map, and bounce
# back to the sector map. Wave generator picks up `sectors_cleared` for
# difficulty scaling.
func _on_next_sector() -> void:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.combats_in_sector = 0
		run.current_node_id = ""
		run.current_node_type = -1
		run.sectors_cleared += 1
		run.run_seed = randi()
		# Build the next sector's cache up front so the map renders without
		# the empty-state bootstrap path.
		run.start_new_sector(run.sectors_cleared + 1, run.run_seed)
	var root: Control = $Root
	var tw = create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw.finished
	SceneTransition.change_scene(get_tree(), SectorMapRoute.SECTOR_MAP_SCENE)


func _play_reveal(title: Label, rows: Array, total_label, btn: Button) -> void:
	# Start everything invisible, then sequentially fade each element in.
	# Total budget: ~2.5s regardless of how many rows. `total_label` may be
	# null when the caller is hiding the tally (hazards).
	var elements: Array = [title]
	for r in rows:
		elements.append(r)
	if total_label != null:
		elements.append(total_label)
	elements.append(btn)
	for e in elements:
		e.modulate.a = 0.0
	# Cap per-step so total fits 2.5s even with many rows.
	var step: float = clamp(1.8 / float(max(1, elements.size())), 0.18, 0.32)
	var fade: float = 0.25
	for i in elements.size():
		var e = elements[i]
		var tw = create_tween()
		tw.tween_interval(step * float(i))
		tw.tween_property(e, "modulate:a", 1.0, fade).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# A section divider ("LARGE" / "MEDIUM" / "SMALL") between size groups in the tally.
# Centered, accent-coloured, caption-sized — rides the reveal like the rows do.
func _section_header(text: String) -> Control:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_CAPTION)
	lbl.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
	lbl.add_theme_font_override("font", UiTheme.menu_font())
	lbl.material = _shared_mat
	return lbl


# How many size buckets hold at least one enemy type — decides whether section
# headers show at all (a single-size combat reads cleaner flat).
func _populated_section_count(buckets: Dictionary) -> int:
	var n: int = 0
	for k in buckets:
		if not (buckets[k] as Array).is_empty():
			n += 1
	return n


func _build_row(scene_path: String, stats: Dictionary) -> Control:
	var row := HBoxContainer.new()
	# Tighter separation + name/bounty labels capped so the bounty math
	# doesn't overflow the right edge of the 320-wide viewport (Roman,
	# 2026-05-17 playtest: "number killed and bounty value is too far
	# right and off screen").
	row.add_theme_constant_override("separation", 16)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Sprite preview — render the actual enemy scene into a SubViewport.
	var preview: Control = SummaryUi.make_enemy_preview(scene_path, 56)
	row.add_child(preview)
	# Name + kills. HD body size + smooth menu font (the crisp face renders
	# jagged at HD 1:1). Sizes standardized to docs/ui_color_reference.md.
	var name_str := scene_path.get_file().get_basename()
	if name_str.begins_with("enemy_"):
		name_str = name_str.substr(6)
	name_str = name_str.capitalize()
	var counts := Label.new()
	counts.text = "%s  %d/%d" % [name_str, stats.killed, stats.spawned]
	counts.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	counts.add_theme_color_override("font_color", UiTheme.COLOR_HOLO)
	counts.add_theme_font_override("font", UiTheme.menu_font())
	counts.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	counts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	counts.material = _shared_mat
	row.add_child(counts)
	# Bounty math — right-justified, fixed width so the "= total" lands at
	# a consistent x across rows.
	var bounty_label := Label.new()
	bounty_label.text = "%d×%d=%d" % [stats.bounty, stats.killed, stats.total_bounty]
	bounty_label.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	bounty_label.add_theme_color_override("font_color", UiTheme.COLOR_BOUNTY)
	bounty_label.add_theme_font_override("font", UiTheme.menu_font())
	bounty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bounty_label.custom_minimum_size = Vector2(180, 0)
	bounty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bounty_label.material = _shared_mat
	row.add_child(bounty_label)
	return row


func _style_outline_button(btn: Button) -> void:
	UiTheme.style_button(btn)


# Hazard flavor line — historically used to inject the Asteroid Miners
# thank-you here. As of 2026-05-24 the asteroid_field hazard skips this
# scene entirely (main.gd jumps straight to sector_map) and the banner
# lives above the sector map instead. Kept the function as a no-op so
# existing callers don't break; new hazard subtypes can hook in here.
func _install_hazard_flavor(_title: Label) -> void:
	# asteroid_field hazard skips this scene entirely (main.gd routes
	# straight to sector_map_v3 after the wipe; the miners thank-you is
	# rendered there via Run.post_combat_banner meta). No other hazard
	# subtype emits flavor here yet — add new branches above this comment
	# rather than gating on subtype lists.
	return


# Spacebar (and the `shoot` action generally — Space + Z + gamepad A) advances
# the summary to its primary action: back to the sector map. When the boss-
# sector endless prompt is up, default to NEXT SECTOR (the forward action).
# (Roman, 2026-05-23: "spacebar on the level clear screen should move back to
# sector map".)
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("shoot"):
		return
	get_viewport().set_input_as_handled()
	# Pick the primary action: NEXT SECTOR if it's available (boss + sector
	# complete), otherwise MAP. Fire the handler directly so we don't depend
	# on the button being focused.
	var endless: Node = get_node_or_null("Root/Bottom/EndlessChoiceRow")
	if endless != null:
		# Sector-complete endless prompt up — there's no "sector map" option
		# at this point (MAIN MENU vs NEXT SECTOR is a meaningful run-level
		# choice). Don't auto-advance; let the player pick deliberately.
		return
	_on_map_pressed()


func _on_map_pressed() -> void:
	var btn: Button = $Root/Bottom/MapBtn
	btn.disabled = true
	# Flicker / fade out, then transition back to the sector map — or the main
	# menu if this was a Test Hazard run launched from the main menu.
	var target := SECTOR_MAP_SCENE
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if run.test_mode_active:
			# Honor a custom return scene (e.g. wave editor) when the test
			# was launched from a dev tool. Defaults to main menu.
			target = String(run.get_meta("test_return_scene", "res://scenes/main_menu.tscn"))
			run.test_mode_active = false
			if run.has_meta("test_return_scene"):
				run.remove_meta("test_return_scene")
	var root: Control = $Root
	var tw = create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw.finished
	SceneTransition.change_scene(get_tree(), target)
