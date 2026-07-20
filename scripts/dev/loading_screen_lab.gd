extends Control

# Loading Screen Lab (Roman 2026-06-19) — in-situ test harness for the inter-node
# loading screen (scripts/screens/loading_screen.gd) BEFORE it is wired live.
#
# Embeds a live LoadingScreen (manage_hd_scope=false — this lab owns the HD scope) and
# exposes its identity + visual knobs on a left rail: pick the ship + livery, type or
# reroll the destination POI name, tune the star/streak/drift feel with sliders, then
# hit "Fly Off" to preview the launch-and-vanish exit (and "Replay" to reset). The
# "Copy GDScript" button emits the tuned defaults to paste into loading_screen.gd
# (the tuner contract). Esc / Back returns to the dev menu.

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const FlyoverPlanner = preload("res://scripts/parallax/flyover_planner.gd")
const LOADING_SCENE := "res://scenes/loading_screen.tscn"

# Destination dropdown labels for each eligible flyover planet_type (keys of
# FlyoverPlanner.TYPE_TO_PRESET). "Space" (the normal starfield) is prepended at runtime.
const PTYPE_LABELS := {
	0: "Lava World", 1: "Dry Terran", 2: "No Atmosphere",
	3: "Land Masses", 5: "Ice World", 7: "Rivers",
}

const SWATCHES := [
	Color(0.90, 0.16, 0.16), Color(0.96, 0.55, 0.13), Color(0.98, 0.85, 0.25),
	Color(0.45, 0.85, 0.30), Color(0.25, 0.62, 0.97), Color(0.70, 0.38, 0.95),
	Color(0.92, 0.92, 0.95),
]

var _ls: LoadingScreen = null
var _hd: HdViewportScope = null
var _poi_edit: LineEdit = null
var _status: Label = null
var _val_labels: Dictionary = {}   # key -> value Label
var _dest_map: Array = [-1]        # dropdown index -> planet_type (-1 = Space)
var _planet_seed: int = 20260718   # flyover colour/terrain seed; Reroll randomizes it
var _night_on: bool = false        # Night CheckButton state (forces the flyover night bool)


func _ready() -> void:
	_hd = HdScreen.enter(self)
	_ls = load(LOADING_SCENE).instantiate()
	_ls.manage_hd_scope = false
	_ls.flight_complete.connect(_on_flight_complete)
	add_child(_ls)
	_build_panel()


func _build_panel() -> void:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.10, 0.92)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(2)
	sb.set_content_margin_all(16)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_right = 470.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(430, 0)
	scroll.add_child(v)

	v.add_child(_mk_label("LOADING SCREEN LAB", UiTheme.FONT_SIZE_HEADER, UiTheme.COLOR_ACCENT))

	# --- Ship variant ---
	v.add_child(_mk_label("Ship", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	var dd := OptionButton.new()
	dd.add_item("ALPHA", 0)
	dd.add_item("BETA", 1)
	dd.add_item("GAMMA", 2)
	dd.selected = clampi(_ls.ship_variant, 0, 2)
	dd.item_selected.connect(func(i: int) -> void:
		_ls.ship_variant = i
		_ls.rebuild_ship())
	v.add_child(dd)

	# --- Livery swatches ---
	v.add_child(_mk_label("Livery", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", 6)
	for c in SWATCHES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(34, 34)
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = c
		bsb.set_corner_radius_all(3)
		b.add_theme_stylebox_override("normal", bsb)
		b.add_theme_stylebox_override("hover", bsb)
		b.add_theme_stylebox_override("pressed", bsb)
		b.pressed.connect(func() -> void: _set_livery(c))
		sw.add_child(b)
	v.add_child(sw)

	# --- Hull / damage state (the loading screen mirrors the player's carried damage) ---
	v.add_child(_mk_label("Hull — drag Current down to batter the ship", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	var init_max: int = _ls.ship_max_hull if _ls.ship_max_hull > 0 else 3
	var init_cur: int = _ls.ship_hull if _ls.ship_hull >= 0 else init_max
	_ls.ship_max_hull = init_max
	_ls.ship_hull = init_cur
	_add_slider(v, "ship_max_hull", "Max hull", 1.0, 9.0, 1.0, float(init_max), func(x): _set_max_hull(x))
	_add_slider(v, "ship_hull", "Current hull", 0.0, 9.0, 1.0, float(init_cur), func(x): _set_cur_hull(x))

	# --- POI name ---
	v.add_child(_mk_label("Destination POI", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_poi_edit = LineEdit.new()
	_poi_edit.text = _ls.poi_name
	_poi_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_poi_edit.text_changed.connect(func(t: String) -> void: _ls.set_poi_name(t))
	row.add_child(_poi_edit)
	var reroll := UiTheme.make_button("Reroll", true)
	reroll.pressed.connect(_on_reroll)
	row.add_child(reroll)
	v.add_child(row)

	v.add_child(HSeparator.new())

	# --- Destination backdrop: Space (starfield) or a flyover planet type ---
	v.add_child(_mk_label("Destination backdrop", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 6)
	var dest := OptionButton.new()
	dest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dest.add_item("Space", 0)
	_dest_map = [-1]
	for t in FlyoverPlanner.TYPE_TO_PRESET.keys():
		dest.add_item(String(PTYPE_LABELS.get(t, "Type %d" % t)))
		_dest_map.append(int(t))
	dest.selected = 0
	dest.item_selected.connect(_on_dest_selected)
	drow.add_child(dest)
	var seed_btn := UiTheme.make_button("Reroll", true)
	seed_btn.pressed.connect(func() -> void:
		_planet_seed = randi()
		_rebuild_backdrop())
	drow.add_child(seed_btn)
	v.add_child(drow)

	var night := CheckButton.new()
	night.text = "Night"
	night.button_pressed = _night_on
	night.toggled.connect(_on_night_toggled)
	v.add_child(night)

	v.add_child(HSeparator.new())

	# --- Visual knobs ---
	_add_slider(v, "star_drift", "Star drift (swiftness)", 0.0, 18000.0, 100.0, _ls.star_drift,
		func(x): _ls.star_drift = x)
	_add_slider(v, "star_alpha", "Star brightness", 0.2, 1.0, 0.05, _ls.star_alpha,
		func(x): _ls.star_alpha = x, func(): _ls.apply_star_alpha())
	_add_slider(v, "streak_count", "Streak count", 4.0, 90.0, 1.0, float(_ls.streak_count),
		func(x): _ls.streak_count = int(x), func(): _ls.rebuild_streaks())
	_add_slider(v, "streak_speed", "Streak speed", 400.0, 2400.0, 10.0, _ls.streak_speed,
		func(x): _ls.streak_speed = x, func(): _ls.rebuild_streaks())
	_add_slider(v, "streak_width_min", "Streak width min (px)", 0.5, 3.0, 0.1, _ls.streak_width_min,
		func(x): _ls.streak_width_min = x, func(): _ls.rebuild_streaks())
	_add_slider(v, "streak_width_max", "Streak width max (px)", 0.5, 3.0, 0.1, _ls.streak_width_max,
		func(x): _ls.streak_width_max = x, func(): _ls.rebuild_streaks())
	_add_slider(v, "streak_length", "Streak length (px)", 20.0, 220.0, 2.0, _ls.streak_length,
		func(x): _ls.streak_length = x, func(): _ls.rebuild_streaks())
	_add_slider(v, "ship_rest_y", "Ship rest Y", 80.0, 230.0, 1.0, _ls.ship_rest_y,
		func(x): _ls.ship_rest_y = x)
	_add_slider(v, "ship_drift_ax", "Drift amplitude X", 0.0, 24.0, 0.5, _ls.ship_drift_ax,
		func(x): _ls.ship_drift_ax = x)
	_add_slider(v, "ship_drift_ay", "Drift amplitude Y", 0.0, 24.0, 0.5, _ls.ship_drift_ay,
		func(x): _ls.ship_drift_ay = x)
	_add_slider(v, "flyoff_time", "Fly-off duration", 0.4, 2.6, 0.05, _ls.flyoff_time,
		func(x): _ls.flyoff_time = x)

	v.add_child(HSeparator.new())

	# --- Actions ---
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var fly := UiTheme.make_button("Fly Off")
	fly.pressed.connect(func() -> void: _ls.fly_off())
	actions.add_child(fly)
	var replay := UiTheme.make_button("Replay")
	replay.pressed.connect(func() -> void: _ls.replay())
	actions.add_child(replay)
	v.add_child(actions)

	var copy := UiTheme.make_button("Copy GDScript")
	copy.pressed.connect(_on_copy_gdscript)
	v.add_child(copy)

	_status = _mk_label("", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT)
	v.add_child(_status)

	var back := UiTheme.make_button("Back")
	back.pressed.connect(_back)
	v.add_child(back)


# label + slider + live value readout. on_change fires every value change; on_commit
# (optional) fires on drag-release — use it for knobs that need an expensive rebuild.
func _add_slider(parent: Node, key: String, label: String, mn: float, mx: float, step: float, val: float, on_change: Callable, on_commit: Callable = Callable()) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var name_lbl := _mk_label(label, UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_TEXT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_lbl)
	var val_lbl := _mk_label(_fmt(val, step), UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_ACCENT)
	_val_labels[key] = val_lbl
	head.add_child(val_lbl)
	parent.add_child(head)

	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(0, 22)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(x: float) -> void:
		on_change.call(x)
		(_val_labels[key] as Label).text = _fmt(x, step))
	if on_commit.is_valid():
		s.drag_ended.connect(func(_changed: bool) -> void: on_commit.call())
	parent.add_child(s)


func _fmt(v: float, step: float) -> String:
	return str(int(round(v))) if step >= 1.0 else "%.2f" % v


func _on_reroll() -> void:
	var nm := SectorNameGenerator.generate(randi())
	_poi_edit.text = nm
	_ls.set_poi_name(nm)


func _on_flight_complete() -> void:
	if _status != null:
		_status.text = "flight_complete fired — hit Replay to re-test."


# Destination dropdown → Space (clear override + forced_flyover meta) or a flyover planet type
# (inject a stellar_override dict + force the plan past its chance roll via Run meta). The lab
# writing Run meta is established dev practice here (same as the livery swatches writing Run).
func _on_dest_selected(index: int) -> void:
	var ptype: int = int(_dest_map[index]) if index < _dest_map.size() else -1
	if ptype < 0:
		_ls.stellar_override = {}
		_clear_forced_flyover()
	else:
		_ls.stellar_override = {"obj_kind": 0, "planet_type": ptype, "planet_seed": _planet_seed}
		_set_forced_flyover()
	_rebuild_backdrop()


func _on_night_toggled(on: bool) -> void:
	_night_on = on
	_ls.night_override = 1 if on else 0
	_rebuild_backdrop()


# Re-plan + swap the live LoadingScreen's backdrop, keeping the instance (and the slider closures
# that capture it) intact rather than re-instancing.
func _rebuild_backdrop() -> void:
	if _ls != null and is_instance_valid(_ls):
		_ls.rebuild_backdrop()


# Force the planner past its chance roll (dev override read by FlyoverPlanner._forced_meta).
func _set_forced_flyover() -> void:
	var run := get_node_or_null("/root/Run")
	if run != null:
		run.set_meta("forced_flyover", {"force": true})


func _clear_forced_flyover() -> void:
	var run := get_node_or_null("/root/Run")
	if run != null and run.has_meta("forced_flyover"):
		run.remove_meta("forced_flyover")


# Livery comes from Run (the real player reads it on spawn), so preview a swatch by writing Run
# then respawning the ship. Dev-only mutation of Run is fine here.
func _set_livery(c: Color) -> void:
	var run := get_node_or_null("/root/Run")
	if run != null:
		run.livery_color = c
		if "livery_chosen" in run:
			run.livery_chosen = true
	_ls.rebuild_ship()


func _set_max_hull(x: float) -> void:
	_ls.ship_max_hull = int(x)
	_ls.apply_hull()


func _set_cur_hull(x: float) -> void:
	_ls.ship_hull = int(x)
	_ls.apply_hull()


func _on_copy_gdscript() -> void:
	var lines := [
		"# loading_screen.gd tuned defaults (Loading Screen Lab):",
		"star_drift = %s" % _f(_ls.star_drift),
		"star_alpha = %s" % _f(_ls.star_alpha),
		"streak_count = %d" % _ls.streak_count,
		"streak_speed = %s" % _f(_ls.streak_speed),
		"streak_width_min = %s" % _f(_ls.streak_width_min),
		"streak_width_max = %s" % _f(_ls.streak_width_max),
		"streak_length = %s" % _f(_ls.streak_length),
		"ship_rest_y = %s" % _f(_ls.ship_rest_y),
		"ship_drift_ax = %s" % _f(_ls.ship_drift_ax),
		"ship_drift_ay = %s" % _f(_ls.ship_drift_ay),
		"flyoff_time = %s" % _f(_ls.flyoff_time),
		"# Flyover destination preview (lab-only injection; not shipped defaults):",
		"# stellar_override = %s" % str(_ls.stellar_override),
		"# night_override = %d  # -1 auto / 0 day / 1 night" % _ls.night_override,
	]
	var text := "\n".join(lines)
	DisplayServer.clipboard_set(text)
	if _status != null:
		_status.text = "Copied tuned defaults to clipboard."


func _f(v: float) -> String:
	return "%.1f" % v


func _mk_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.menu_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _back() -> void:
	_clear_forced_flyover()   # don't leak the dev override into the next scene
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _exit_tree() -> void:
	_clear_forced_flyover()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_back()
