extends Control

# Lane / Pattern Visualizer (M6a.0) — the verification surface for the modular-enemy
# work. Two modes:
#   CONDUCTOR — instantiate the real WaveDirector and run a CombatScore (Combat Slice
#     or WaveGen.build_score) so you can watch the conductor stream a whole level over
#     the lane + zone overlays.
#   PATTERN — spawn dummy enemies running a single movement pattern in isolation, with
#     a path trail, to read a behavior on its own.
#
# Overlays (toggleable): the 7 LANES (Lanes), the 3 firing ZONES (Zones), the playfield
# border (Playfield), and lane numbers.
#
# COORDINATE SPACE: everything here is ABSOLUTE viewport coords (NOT field-local like
# movement_lab) because the director places enemies at absolute lane centres
# (Lanes.lane_center → 150..330) and lane_path reads Lanes.nearest_lane(position.x).
# The world Node2D sits at (0,0); overlays + enemies + dummies all live in it.
#
# Native 480×270 tool (like movement_lab) — controls in the side gutters, the band
# (x 132–348) shows the live action. Esc / Back returns to the dev menu.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const DirectorScript = preload("res://scripts/levels/director.gd")
const CombatSlice = preload("res://scripts/dev/combat_slice.gd")
const WaveGen = preload("res://scripts/levels/wave_generator.gd")
const LanePath = preload("res://scripts/enemies/patterns/lane_path.gd")

# Movement patterns offered in PATTERN mode. ["label", kind, arg]
#   kind "lane"   → arg = lane_path Shape int (0 STRAIGHT / 1 WEAVE / 2 HOOK / 3 STEP)
#   kind "roster" → arg = EnemyRoster.make_movement key (real production tuning)
# Roster keys are the 2026-06-08 pattern set (see enemy_roster.make_movement).
const PATTERNS := [
	["lane STRAIGHT", "lane", 0],
	["lane WEAVE", "lane", 1],
	["lane HOOK", "lane", 2],
	["lane STEP", "lane", 3],
	# straight_* by speed rung (crawl 60 → reflex 360)
	["straight_crawl", "roster", "straight_crawl"],
	["straight_slow", "roster", "straight_slow"],
	["straight_medium", "roster", "straight_medium"],
	["straight_fast", "roster", "straight_fast"],
	["straight_reflex", "roster", "straight_reflex"],
	["straight_charge", "roster", "straight_charge"],
	# skirmish loops (replaces advance_retreat)
	["skirmish_loop", "roster", "skirmish_loop"],
	["skirmish_figure8", "roster", "skirmish_figure8"],
	# drift-in-lane (was bulwark_drift), by hover height
	["drift_low", "roster", "drift_low"],
	["drift_mid", "roster", "drift_mid"],
	["drift_high", "roster", "drift_high"],
	# loiter (Holder), by hover height
	["loiter_low", "roster", "loiter_low"],
	["loiter_mid", "roster", "loiter_mid"],
	["loiter_high", "roster", "loiter_high"],
	# lane-aware production patterns (lane_path engine). Spawn a ROW to see the
	# lane-occupancy free-check: Drifters/Shifters avoid merging into an occupied lane.
	["lane_weave (in-lane)", "roster", "lane_weave"],
	["lane_drift (lane->lane)", "roster", "lane_drift"],
	["lane_shift (commit)", "roster", "lane_shift"],
	["lane_hook (drop-return)", "roster", "lane_hook"],
	["lane_cut (curve-exit)", "roster", "lane_cut"],
	# side approaches
	["side_turn", "roster", "side_turn"],
	["side_dive", "roster", "side_dive"],
	["side_traverse", "roster", "side_traverse"],
	# player-hunters
	["hunt_beeline", "roster", "hunt_beeline"],
	["hunt_omni", "roster", "hunt_omni"],
]

var _world: Node2D = null
var _overlay: Node2D = null
var _player_marker: Node2D = null
var _director: Node = null
var _dummies: Array = []

var _mode: String = "conductor"        # "conductor" | "pattern"
var _show_lanes: bool = true
var _show_zones: bool = true
var _show_numbers: bool = true

var _pattern_idx: int = 0
var _readout: Label = null
var _conductor_panel: VBoxContainer = null
var _pattern_panel: VBoxContainer = null
var _sector_val: int = 1
var _level_val: int = 0
var _sector_btn: Button = null
var _level_btn: Button = null
var _pattern_lbl: Label = null

# Live conductor stats (driven by director signals).
var _last_banner: String = "-"


func _ready() -> void:
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")
	# Clean Run context so leftover sector_modifiers don't mutate spawned enemies.
	var run := get_node_or_null("/root/Run")
	if run and run.has_method("new_run"):
		run.new_run()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_bg()
	_build_world()
	_build_player_marker()
	_build_ui()
	_refresh_mode_panels()


# ---------------------------------------------------------------- world + overlays

func _build_bg() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build_world() -> void:
	# Node2D at viewport origin → its children render in absolute viewport coords.
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	_overlay.draw.connect(_draw_overlay)
	_world.add_child(_overlay)
	_build_overlay_labels()


func _draw_overlay() -> void:
	var top: float = Playfield.Y_MIN
	var bot: float = Playfield.Y_MAX
	# Playfield border.
	_overlay.draw_rect(Rect2(Playfield.X_MIN, top, Playfield.W, Playfield.H),
		Color(0.4, 0.6, 0.9, 0.5), false, 1.0)
	# Zone bands (entry / engagement / departure).
	if _show_zones:
		_overlay.draw_rect(Rect2(Playfield.X_MIN, top, Playfield.W, Zones.ENTRY_END - top),
			Color(0.9, 0.5, 0.3, 0.08), true)  # entry (hold fire)
		_overlay.draw_rect(Rect2(Playfield.X_MIN, Zones.ENTRY_END, Playfield.W,
			Zones.DEPARTURE_START - Zones.ENTRY_END),
			Color(0.3, 0.9, 0.5, 0.07), true)  # engagement (fire)
		_overlay.draw_rect(Rect2(Playfield.X_MIN, Zones.DEPARTURE_START, Playfield.W,
			bot - Zones.DEPARTURE_START),
			Color(0.5, 0.5, 0.9, 0.07), true)  # departure (cease fire)
		_overlay.draw_line(Vector2(Playfield.X_MIN, Zones.ENTRY_END),
			Vector2(Playfield.X_MAX, Zones.ENTRY_END), Color(1, 1, 1, 0.18), 1.0)
		_overlay.draw_line(Vector2(Playfield.X_MIN, Zones.DEPARTURE_START),
			Vector2(Playfield.X_MAX, Zones.DEPARTURE_START), Color(1, 1, 1, 0.18), 1.0)
	# Lane columns.
	if _show_lanes:
		for i in Lanes.COUNT:
			var l: float = Lanes.lane_left(i)
			var w: float = Lanes.WIDTH
			_overlay.draw_rect(Rect2(l, top, w, Playfield.H), Color(0.5, 0.7, 1.0, 0.05), true)
			var cx: float = Lanes.lane_center(i)
			_overlay.draw_line(Vector2(cx, top), Vector2(cx, bot), Color(0.5, 0.7, 1.0, 0.12), 1.0)


func _build_overlay_labels() -> void:
	# Lane-number labels at the top of each lane (absolute coords).
	for i in Lanes.COUNT:
		var lbl := _new_label(str(i), UiTheme.COLOR_ACCENT, SZ_CAPTION)
		lbl.name = "lane_num_%d" % i
		lbl.position = Vector2(Lanes.lane_center(i) - 3.0, 1.0)
		_overlay.add_child(lbl)
	# Zone captions on the right edge of the band.
	_add_zone_caption("ENTRY", (Playfield.Y_MIN + Zones.ENTRY_END) * 0.5, Color(0.9, 0.6, 0.4, 0.6))
	_add_zone_caption("FIRE", (Zones.ENTRY_END + Zones.DEPARTURE_START) * 0.5, Color(0.5, 0.95, 0.6, 0.6))
	_add_zone_caption("EXIT", (Zones.DEPARTURE_START + Playfield.Y_MAX) * 0.5, Color(0.6, 0.6, 0.95, 0.6))


func _add_zone_caption(text: String, y: float, col: Color) -> void:
	var lbl := _new_label(text, col, SZ_CAPTION)
	lbl.position = Vector2(Playfield.X_MAX - 22.0, y - 4.0)
	_overlay.add_child(lbl)


func _refresh_overlay() -> void:
	_overlay.queue_redraw()
	for i in Lanes.COUNT:
		var n := _overlay.get_node_or_null("lane_num_%d" % i)
		if n:
			n.visible = _show_numbers and _show_lanes


func _build_player_marker() -> void:
	_player_marker = Node2D.new()
	_player_marker.name = "PlayerPointer"
	_player_marker.add_to_group("player")
	_player_marker.position = Vector2(Playfield.CENTER.x, 210.0)
	_world.add_child(_player_marker)
	var ring := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 12:
		var a: float = float(i) / 12.0 * TAU
		pts.append(Vector2(cos(a), sin(a)) * 5.0)
	ring.polygon = pts
	ring.color = Color(1.0, 0.95, 0.55, 0.85)
	_player_marker.add_child(ring)


# ---------------------------------------------------------------- UI panels

func _build_ui() -> void:
	# Left gutter — controls. 128 wide so it stays clear of the band (x>=132).
	var left := _make_panel(Vector2(0, 0), Vector2(128, 270))
	add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 2)
	left.add_child(lv)
	_fill_panel(lv)

	lv.add_child(_new_label("LANE / PATTERN VIS", UiTheme.COLOR_ACCENT, SZ_HEADER))

	# Mode toggle.
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 3)
	lv.add_child(mode_row)
	_add_button(mode_row, "Conductor", func(): _set_mode("conductor"))
	_add_button(mode_row, "Pattern", func(): _set_mode("pattern"))

	lv.add_child(_sep())

	# Conductor sub-panel.
	_conductor_panel = VBoxContainer.new()
	_conductor_panel.add_theme_constant_override("separation", 3)
	lv.add_child(_conductor_panel)
	_add_caption(_conductor_panel, "SCORE")
	_add_button(_conductor_panel, "Combat Slice", func(): _run_score(CombatSlice.build()))
	# Sector / Level as compact cycle buttons (SpinBox chrome is HD-sized).
	var sl_row := HBoxContainer.new()
	sl_row.add_theme_constant_override("separation", 2)
	_conductor_panel.add_child(sl_row)
	_sector_btn = _add_button(sl_row, "S:1", _cycle_sector)
	_level_btn = _add_button(sl_row, "L:0", _cycle_level)
	_add_button(_conductor_panel, "Run WaveGen", _on_run_wavegen)
	_add_button(_conductor_panel, "Restart", _on_restart)
	_add_button(_conductor_panel, "Clear", func(): _clear_world())

	# Pattern sub-panel.
	_pattern_panel = VBoxContainer.new()
	_pattern_panel.add_theme_constant_override("separation", 2)
	lv.add_child(_pattern_panel)
	_add_caption(_pattern_panel, "PATTERN")
	# Prev / name / next (OptionButton's dropdown chrome is HD-sized).
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 2)
	_pattern_panel.add_child(pr)
	_add_fixed_button(pr, "<", func(): _cycle_pattern(-1), 16)
	_pattern_lbl = _new_label(str(PATTERNS[0][0]), UiTheme.COLOR_TEXT, SZ_BODY)
	_pattern_lbl.clip_text = true
	_pattern_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pattern_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pr.add_child(_pattern_lbl)
	_add_fixed_button(pr, ">", func(): _cycle_pattern(1), 16)
	_add_button(_pattern_panel, "Spawn row", func(): _spawn_pattern_row())
	_add_button(_pattern_panel, "Spawn one", func(): _spawn_pattern_one())
	_add_button(_pattern_panel, "Step wall", func(): _spawn_step_wall())
	_add_button(_pattern_panel, "Clear", func(): _clear_world())

	lv.add_child(_sep())

	# Overlay toggles (shared) — toggle buttons (CheckBox chrome is HD-sized).
	_add_caption(lv, "OVERLAYS")
	var ov := HBoxContainer.new()
	ov.add_theme_constant_override("separation", 2)
	lv.add_child(ov)
	_add_toggle(ov, "Lane", _show_lanes, func(p: bool): _show_lanes = p; _refresh_overlay())
	_add_toggle(ov, "Zone", _show_zones, func(p: bool): _show_zones = p; _refresh_overlay())
	_add_toggle(ov, "Num", _show_numbers, func(p: bool): _show_numbers = p; _refresh_overlay())

	lv.add_child(_sep())
	_add_button(lv, "Back", _on_back)

	# Right gutter — live readout.
	var right := _make_panel(Vector2(348, 0), Vector2(132, 270))
	add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 3)
	right.add_child(rv)
	_fill_panel(rv)
	_add_caption(rv, "LIVE")
	_readout = _new_label("", UiTheme.COLOR_TEXT, SZ_READOUT)
	_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_readout.custom_minimum_size = Vector2(124, 0)
	rv.add_child(_readout)
	var hint := _new_label("Drag mouse = player.\nGreen band = fire zone.", UiTheme.COLOR_FAINT, SZ_BODY)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(124, 0)
	rv.add_child(hint)


func _refresh_mode_panels() -> void:
	_conductor_panel.visible = _mode == "conductor"
	_pattern_panel.visible = _mode == "pattern"
	_refresh_overlay()


func _set_mode(m: String) -> void:
	if m == _mode:
		return
	_mode = m
	_clear_world()
	_refresh_mode_panels()


# ---------------------------------------------------------------- conductor mode

func _on_run_wavegen() -> void:
	_run_score(WaveGen.build_score(_sector_val, _level_val, false))


func _cycle_sector() -> void:
	_sector_val = _sector_val % 9 + 1   # 1..9 wrap
	_sector_btn.text = "S:%d" % _sector_val


func _cycle_level() -> void:
	_level_val = (_level_val + 1) % 9   # 0..8 wrap
	_level_btn.text = "L:%d" % _level_val


func _cycle_pattern(dir: int) -> void:
	_pattern_idx = (_pattern_idx + dir + PATTERNS.size()) % PATTERNS.size()
	_pattern_lbl.text = str(PATTERNS[_pattern_idx][0])
	_update_readout()


func _run_score(score) -> void:
	_clear_world()
	if score == null:
		return
	_director = DirectorScript.new()
	_director.name = "WaveDirector"
	_world.add_child(_director)
	if "max_concurrent" in _director:
		_director.max_concurrent = 14
	_director.enemy_spawned.connect(func(_p, _b): _update_readout())
	_director.enemy_died.connect(func(_v, _p): _update_readout())
	_director.wave_started.connect(func(_i, _t, _s, txt):
		_last_banner = str(txt) if str(txt) != "" else "wave %d/%d" % [_i + 1, _t]
		_update_readout())
	_director.level_cleared.connect(func(): _last_banner = "CLEARED"; _update_readout())
	_director.start_score(score)
	_last_banner = "starting..."
	_update_readout()


func _on_restart() -> void:
	# Re-run whatever the last score source was; default to Combat Slice.
	_run_score(CombatSlice.build())


# ---------------------------------------------------------------- pattern mode

func _make_pattern() -> Resource:
	var p: Array = PATTERNS[_pattern_idx]
	var kind: String = str(p[1])
	if kind == "lane":
		var lp = LanePath.new()
		lp.shape = int(p[2])
		lp.down_speed = 120.0
		lp.weave_lanes = 1.0
		if int(p[2]) == 3:  # STEP
			lp.hold_time = 1.0
			lp.step_time = 0.3
			lp.step_lanes = 1
			lp.step_pingpong = true
		return lp
	# roster movement key → real production tuning
	return EnemyRoster.make_movement({"movement": str(p[2])})


func _spawn_pattern_row() -> void:
	_clear_dummies()
	# One dummy per lane, descending — reads the pattern's lane behavior across the band.
	for i in Lanes.COUNT:
		_make_dummy(Vector2(Lanes.lane_center(i), 12.0))
	_update_readout()


func _spawn_pattern_one() -> void:
	_make_dummy(Vector2(Lanes.lane_center(3), 12.0))
	_update_readout()


# P2d: spawn a COORDINATED step wall — a contiguous block leaving one edge gap, all
# members sharing synced-STEP params (same offset bounds/dir/timing, same-frame), so
# they shift in unison and the gap relocates. Mirrors director._dispatch_step_wall.
func _spawn_step_wall() -> void:
	_clear_dummies()
	var n: int = Lanes.COUNT - 1            # fill all but one edge lane
	var start_lane: int = 0                 # left block, gap on the right
	var lo: int = -start_lane               # = 0
	var hi: int = (Lanes.COUNT - 1) - (start_lane + n - 1)  # room to shift right
	for i in n:
		var p = LanePath.new()
		p.shape = LanePath.Shape.STEP
		p.step_synced = true
		p.step_offset_lo = lo
		p.step_offset_hi = hi
		p.step_start_dir = 1
		p.hold_time = 0.9
		p.step_time = 0.35
		p.down_speed = 80.0
		var d := PatternDummy.new()
		d.pattern = p
		d.position = Vector2(Lanes.lane_center(start_lane + i), 24.0)
		_world.add_child(d)
		_dummies.append(d)
	_update_readout()


func _make_dummy(pos: Vector2) -> void:
	var d := PatternDummy.new()
	d.pattern = _make_pattern()
	d.position = pos
	_world.add_child(d)
	_dummies.append(d)


# ---------------------------------------------------------------- clear / process

func _clear_world() -> void:
	if _director and is_instance_valid(_director):
		if _director.has_method("stop"):
			_director.stop()
		_director.queue_free()
	_director = null
	for grp in ["enemies", "enemy_bullets", "bullets"]:
		for n in get_tree().get_nodes_in_group(grp):
			if is_instance_valid(n):
				n.queue_free()
	_clear_dummies()
	_last_banner = "-"
	_update_readout()


func _clear_dummies() -> void:
	for d in _dummies:
		if is_instance_valid(d):
			d.queue_free()
	_dummies = []


func _process(_delta: float) -> void:
	# Mouse drives the player marker, clamped to the playfield band.
	if _player_marker:
		var m: Vector2 = get_global_mouse_position()
		_player_marker.position = Playfield.clamp_pos(m, 4.0)
	_update_readout()


func _update_readout() -> void:
	if _readout == null:
		return
	if _mode == "conductor":
		var alive: int = get_tree().get_nodes_in_group("enemies").size()
		_readout.text = "mode: conductor\nbanner: %s\nalive: %d" % [_last_banner, alive]
	else:
		var p: Array = PATTERNS[_pattern_idx]
		_readout.text = "mode: pattern\n%s\ndummies: %d" % [str(p[0]), _dummies.size()]


# ---------------------------------------------------------------- UI helpers
# Conforms to the in-game HUD convention (ui.gd._make_label): crisp pixel font
# (UiTheme.active_font), UiTheme palette, 1px dark outline, small native sizes.
# UiTheme's named font-size constants are HD (16-48) — this is a NATIVE 480 tool,
# so it uses small literal sizes like the HUD, but the face + colors conform.
# All panel UI conforms to ONE size — the right-panel tooltip size (Roman). Kept as
# named consts (= same value) so call sites stay readable.
const SZ_HEADER := 7
const SZ_BODY := 7
const SZ_CAPTION := 7
const SZ_READOUT := 7


func _style_label(l: Label, color: Color, size: int) -> void:
	l.add_theme_font_override("font", UiTheme.active_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	l.add_theme_constant_override("outline_size", 1)


func _new_label(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	_style_label(l, color, size)
	return l


# Fixed-size clipped Panel (NOT PanelContainer, which auto-grows to its content's
# min width and spilled into the playfield band). Children are anchored to fill it
# via _fill_panel, and buttons clip_text, so long labels never widen the panel.
func _make_panel(pos: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = sz
	p.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.COLOR_PANEL_BG
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	return p


# Anchor a control to fill its parent Panel with a small inset.
func _fill_panel(c: Control) -> void:
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 3
	c.offset_top = 3
	c.offset_right = -3
	c.offset_bottom = -3


func _sep() -> HSeparator:
	return HSeparator.new()


func _add_caption(parent: Node, text: String) -> void:
	parent.add_child(_new_label(text, UiTheme.COLOR_FAINT, SZ_CAPTION))


func _native_button_stylebox(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(1)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb


func _style_button(b: Button) -> void:
	b.clip_text = true  # long labels clip instead of widening the fixed panel
	b.add_theme_font_override("font", UiTheme.active_font())
	b.add_theme_font_size_override("font_size", SZ_BODY)
	b.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
	b.add_theme_color_override("font_hover_color", UiTheme.COLOR_TEXT)
	b.add_theme_color_override("font_pressed_color", UiTheme.COLOR_TEXT)
	b.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	b.add_theme_constant_override("outline_size", 1)
	b.add_theme_stylebox_override("normal", _native_button_stylebox(Color(0.08, 0.11, 0.16, 0.9)))
	b.add_theme_stylebox_override("hover", _native_button_stylebox(Color(0.12, 0.17, 0.24, 0.95)))
	b.add_theme_stylebox_override("pressed", _native_button_stylebox(Color(0.06, 0.09, 0.13, 1.0)))


func _add_button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 12)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(b)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _add_fixed_button(parent: Node, text: String, cb: Callable, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 12)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(b)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# Toggle button — active state shows an accent stylebox (CheckBox chrome is HD-sized,
# so toggles are styled buttons instead).
func _add_toggle(parent: Node, text: String, on: bool, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.custom_minimum_size = Vector2(0, 12)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(b)
	b.add_theme_color_override("font_color", UiTheme.COLOR_FAINT)  # dim when off
	var on_sb := _native_button_stylebox(Color(0.20, 0.34, 0.50, 0.95))
	on_sb.border_color = UiTheme.COLOR_ACCENT
	b.add_theme_stylebox_override("pressed", on_sb)  # toggled-on appearance
	b.toggled.connect(cb)
	parent.add_child(b)


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()


# ---------------------------------------------------------------- dummy enemy

# Minimal Node2D that ticks one movement pattern in absolute coords + draws a path
# trail. Resets to its spawn point on leaving the band so the path repeats. Exposes
# only the fields movement patterns read (auto_rotate / allow_side_exit / position +
# the "player" group for player-tracking patterns).
class PatternDummy extends Node2D:
	var pattern = null
	var auto_rotate: bool = true
	var allow_side_exit: bool = false
	var _spawn: Vector2 = Vector2.ZERO
	var _trail: Line2D = null
	const MAX_TRAIL := 240

	func _ready() -> void:
		_spawn = position
		# Join the "enemies" group so LaneTraffic occupancy queries see this dummy —
		# lets lane-aware patterns (Drifter/Shifter) avoid each other in a spawned row.
		add_to_group("enemies")
		var body := Polygon2D.new()
		body.polygon = PackedVector2Array([
			Vector2(0, -6), Vector2(-5, 5), Vector2(0, 2), Vector2(5, 5)])
		body.color = Color(0.6, 0.95, 1.0)
		add_child(body)
		_trail = Line2D.new()
		_trail.width = 1.0
		_trail.default_color = Color(0.6, 0.95, 1.0, 0.5)
		get_parent().add_child(_trail)
		if pattern and pattern.has_method("on_start"):
			pattern.on_start(self)

	func _process(delta: float) -> void:
		if pattern == null:
			return
		var safe: float = min(delta, 1.0 / 30.0)
		position += pattern.compute_step(self, safe)
		if _trail and is_instance_valid(_trail):
			_trail.add_point(global_position)
			if _trail.get_point_count() > MAX_TRAIL:
				_trail.remove_point(0)
		# Reset when it leaves the band (descenders fall through; traversers exit a side).
		if position.y > Playfield.Y_MAX + 16.0 or position.y < -24.0 \
				or position.x < Playfield.X_MIN - 28.0 or position.x > Playfield.X_MAX + 28.0:
			_reset()

	func _reset() -> void:
		position = _spawn
		if _trail and is_instance_valid(_trail):
			_trail.clear_points()
		if pattern and pattern.has_method("on_start"):
			pattern.on_start(self)

	func _exit_tree() -> void:
		if _trail and is_instance_valid(_trail):
			_trail.queue_free()
