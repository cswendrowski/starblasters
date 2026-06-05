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
const PATTERNS := [
	["lane STRAIGHT", "lane", 0],
	["lane WEAVE", "lane", 1],
	["lane HOOK", "lane", 2],
	["lane STEP", "lane", 3],
	["straight_down", "roster", "straight"],
	["drifter", "roster", "drifter_straight"],
	["fast (dart)", "roster", "fast_straight"],
	["s_curve", "roster", "s_curve"],
	["loiter", "roster", "loiter"],
	["slow_advance", "roster", "slow_advance"],
	["advance_retreat", "roster", "advance_retreat"],
	["top_dive", "roster", "top_dive"],
	["beeline", "roster", "beeline"],
	["side_traverse", "roster", "side_traverse"],
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
var _sector_spin: SpinBox = null
var _level_spin: SpinBox = null

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
		var lbl := Label.new()
		lbl.name = "lane_num_%d" % i
		lbl.text = str(i)
		lbl.add_theme_font_size_override("font_size", 6)
		lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 0.7))
		lbl.position = Vector2(Lanes.lane_center(i) - 3.0, 1.0)
		_overlay.add_child(lbl)
	# Zone captions on the right edge of the band.
	_add_zone_caption("ENTRY", (Playfield.Y_MIN + Zones.ENTRY_END) * 0.5, Color(0.9, 0.6, 0.4, 0.6))
	_add_zone_caption("FIRE", (Zones.ENTRY_END + Zones.DEPARTURE_START) * 0.5, Color(0.5, 0.95, 0.6, 0.6))
	_add_zone_caption("EXIT", (Zones.DEPARTURE_START + Playfield.Y_MAX) * 0.5, Color(0.6, 0.6, 0.95, 0.6))


func _add_zone_caption(text: String, y: float, col: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 6)
	lbl.add_theme_color_override("font_color", col)
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
	# Left gutter — controls.
	var left := _make_panel(Vector2(0, 0), Vector2(132, 270))
	add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 3)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(lv)

	var header := Label.new()
	header.text = "LANE / PATTERN VIS"
	header.add_theme_font_size_override("font_size", 7)
	header.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
	lv.add_child(header)

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
	var sl_row := HBoxContainer.new()
	sl_row.add_theme_constant_override("separation", 3)
	_conductor_panel.add_child(sl_row)
	_add_mini_label(sl_row, "S")
	_sector_spin = _make_spin(1, 9, 1)
	sl_row.add_child(_sector_spin)
	_add_mini_label(sl_row, "L")
	_level_spin = _make_spin(0, 8, 0)
	sl_row.add_child(_level_spin)
	_add_button(_conductor_panel, "Run WaveGen", _on_run_wavegen)
	_add_button(_conductor_panel, "Restart", _on_restart)
	_add_button(_conductor_panel, "Stop / Clear", func(): _clear_world())

	# Pattern sub-panel.
	_pattern_panel = VBoxContainer.new()
	_pattern_panel.add_theme_constant_override("separation", 3)
	lv.add_child(_pattern_panel)
	_add_caption(_pattern_panel, "PATTERN")
	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", 7)
	for p in PATTERNS:
		opt.add_item(str(p[0]))
	opt.item_selected.connect(func(idx: int): _pattern_idx = idx)
	_pattern_panel.add_child(opt)
	_add_button(_pattern_panel, "Spawn row", func(): _spawn_pattern_row())
	_add_button(_pattern_panel, "Spawn one", func(): _spawn_pattern_one())
	_add_button(_pattern_panel, "Clear", func(): _clear_world())

	lv.add_child(_sep())

	# Overlay toggles (shared).
	_add_caption(lv, "OVERLAYS")
	_add_check(lv, "Lanes", _show_lanes, func(v: bool): _show_lanes = v; _refresh_overlay())
	_add_check(lv, "Zones", _show_zones, func(v: bool): _show_zones = v; _refresh_overlay())
	_add_check(lv, "Numbers", _show_numbers, func(v: bool): _show_numbers = v; _refresh_overlay())

	lv.add_child(_sep())
	_add_button(lv, "Back", _on_back)

	# Right gutter — live readout.
	var right := _make_panel(Vector2(348, 0), Vector2(132, 270))
	add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 3)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(rv)
	_add_caption(rv, "LIVE")
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 6)
	_readout.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_readout.custom_minimum_size = Vector2(126, 0)
	rv.add_child(_readout)
	var hint := Label.new()
	hint.text = "Drag mouse = player.\nGreen band = fire zone."
	hint.add_theme_font_size_override("font_size", 6)
	hint.add_theme_color_override("font_color", Color(0.55, 0.65, 0.8))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(126, 0)
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
	var sd: int = int(_sector_spin.value)
	var li: int = int(_level_spin.value)
	_run_score(WaveGen.build_score(sd, li, false))


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

func _make_panel(pos: Vector2, sz: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.size = sz
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.9)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(1)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	return p


func _sep() -> HSeparator:
	return HSeparator.new()


func _add_caption(parent: Node, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 6)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.7, 0.9))
	parent.add_child(lbl)


func _add_mini_label(parent: Node, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 7)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(lbl)


func _make_spin(lo: int, hi: int, val: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = val
	s.custom_minimum_size = Vector2(40, 0)
	s.add_theme_font_size_override("font_size", 7)
	return s


func _add_button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 12)
	b.add_theme_font_size_override("font_size", 7)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(b, true)
	b.pressed.connect(cb)
	parent.add_child(b)


func _add_check(parent: Node, text: String, on: bool, cb: Callable) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.add_theme_font_size_override("font_size", 7)
	c.toggled.connect(cb)
	parent.add_child(c)


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
