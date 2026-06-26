extends Control

# Outpost Arrival Lab (Roman 2026-06-19) — in-situ test harness for the outpost
# arrival/dock sequence (scripts/screens/outpost_arrival.gd).
#
# Embeds a live OutpostArrival (manage_hd_scope=false — this lab owns the HD scope) and
# exposes its identity + cinematic knobs on a floating left rail: pick the ship + livery,
# tune the fly-in / shadow-settle / bar-reveal / departure feel, then Replay the arrival
# or Depart to preview the exit. The rail toggles with Tab (and auto-hides during the
# cinematics so the framing is unobstructed). "Copy GDScript" emits the tuned defaults to
# paste into outpost_arrival.gd (the tuner contract). Esc / Back returns to the dev menu.

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const ShipCatalog = preload("res://scripts/strings/ship_catalog.gd")
const OA_SCENE := "res://scenes/outpost_arrival.tscn"

const SWATCHES := [
	Color(0.90, 0.16, 0.16), Color(0.96, 0.55, 0.13), Color(0.98, 0.85, 0.25),
	Color(0.45, 0.85, 0.30), Color(0.25, 0.62, 0.97), Color(0.70, 0.38, 0.95),
	Color(0.92, 0.92, 0.95),
]

const RAIL_W := 458.0

var _oa: OutpostArrival = null
var _hd: HdViewportScope = null
var _rail: PanelContainer = null
var _rail_side: String = "left"
var _status: Label = null
var _val_labels: Dictionary = {}   # key -> value Label


func _ready() -> void:
	_hd = HdScreen.enter(self)
	_oa = load(OA_SCENE).instantiate()
	_oa.manage_hd_scope = false
	_oa.damage_level = 0.6   # arrive visibly battle-damaged so the shader + tells show for review
	_oa.landed.connect(_on_landed)
	_oa.departed.connect(_on_departed)
	add_child(_oa)
	_build_rail()


func _build_rail() -> void:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.10, 0.88)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(2)
	sb.set_content_margin_all(16)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	_rail = panel
	_position_rail()

	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(424, 0)
	scroll.add_child(v)

	v.add_child(_mk_label("OUTPOST ARRIVAL LAB", UiTheme.FONT_SIZE_HEADER, UiTheme.COLOR_ACCENT))
	v.add_child(_mk_label("Tab: hide/show rail · Esc: back", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))

	# Move the rail to the other side so the shop panel it covers becomes visible to review.
	var swap_side := UiTheme.make_button("Swap Rail Side ⇄", true)
	swap_side.pressed.connect(_on_swap_side)
	v.add_child(swap_side)

	# --- Ship variant ---
	v.add_child(_mk_label("Ship", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	var dd := OptionButton.new()
	for i in ShipCatalog.SHIPS.size():
		dd.add_item(String(ShipCatalog.SHIPS[i]["name"]), i)
	dd.selected = clampi(_oa.ship_variant, 0, ShipCatalog.count() - 1)
	dd.item_selected.connect(func(i: int) -> void: _oa.set_ship(i, _oa.livery_color, _oa.livery_set))
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
		b.pressed.connect(func() -> void: _oa.set_ship(_oa.ship_variant, c, true))
		sw.add_child(b)
	v.add_child(sw)

	v.add_child(HSeparator.new())

	# --- Fly-in ---
	_add_slider(v, "arrival_time", "Fly-in duration (s)", 0.8, 5.0, 0.05, _oa.arrival_time, func(x): _oa.arrival_time = x)
	_add_slider(v, "start_y", "Start Y (below screen)", 280.0, 400.0, 1.0, _oa.start_y, func(x): _oa.start_y = x)
	_add_slider(v, "land_y", "Land Y (rest)", 100.0, 200.0, 1.0, _oa.land_y, func(x): _oa.land_y = x)
	_add_slider(v, "idle_bob", "Idle bob amplitude", 0.0, 6.0, 0.1, _oa.idle_bob, func(x): _oa.idle_bob = x)
	_add_slider(v, "engine_drift", "Engine plume drift (0 = motion-driven)", 0.0, 420.0, 5.0, _oa.engine_drift, func(x): _oa.engine_drift = x)
	_add_slider(v, "star_drift", "Star parallax scroll (fly-in/out)", 0.0, 6000.0, 50.0, _oa.star_drift, func(x): _oa.star_drift = x)
	_add_slider(v, "scene_dim", "Scene dim (whole bay; 1 = full bright)", 0.2, 1.0, 0.02, _oa.scene_dim, func(x): _oa.set_scene_dim(x))
	_add_slider(v, "runway_speed", "Runway pulse speed (rad/s)", 0.2, 5.0, 0.1, _oa.runway_speed, func(x): _oa.set_runway_speed(x))
	_add_slider(v, "engine_spool", "Engine spool fade (on/off, s)", 0.1, 2.5, 0.05, _oa.engine_spool, func(x): _oa.engine_spool = x)
	_add_slider(v, "damage_level", "Damage (shader + smoke/sparks)", 0.0, 1.0, 0.05, _oa.damage_level, func(x): _oa.set_damage(x))

	v.add_child(HSeparator.new())

	# --- Drop shadow ---
	_add_slider(v, "fly_off_x", "Shadow fly offset X", 0.0, 28.0, 0.5, _oa.shadow_fly_offset.x, func(x): _oa.shadow_fly_offset.x = x)
	_add_slider(v, "fly_off_y", "Shadow fly offset Y", 0.0, 32.0, 0.5, _oa.shadow_fly_offset.y, func(x): _oa.shadow_fly_offset.y = x)
	_add_slider(v, "land_off_x", "Shadow land offset X", 0.0, 16.0, 0.5, _oa.shadow_land_offset.x, func(x): _oa.shadow_land_offset.x = x)
	_add_slider(v, "land_off_y", "Shadow land offset Y", 0.0, 16.0, 0.5, _oa.shadow_land_offset.y, func(x): _oa.shadow_land_offset.y = x)
	_add_slider(v, "fly_scale", "Shadow fly scale", 0.8, 1.6, 0.02, _oa.shadow_fly_scale, func(x): _oa.shadow_fly_scale = x)
	_add_slider(v, "land_scale", "Shadow land scale", 0.6, 1.2, 0.02, _oa.shadow_land_scale, func(x): _oa.shadow_land_scale = x)
	_add_slider(v, "fly_alpha", "Shadow fly alpha", 0.0, 1.0, 0.02, _oa.shadow_fly_alpha, func(x): _oa.shadow_fly_alpha = x)
	_add_slider(v, "land_alpha", "Shadow land alpha", 0.0, 1.0, 0.02, _oa.shadow_land_alpha, func(x): _oa.shadow_land_alpha = x)
	_add_slider(v, "settle_time", "Shadow settle time (s)", 0.1, 1.2, 0.05, _oa.shadow_settle_time, func(x): _oa.shadow_settle_time = x)

	v.add_child(HSeparator.new())

	# --- Reveal / exit ---
	_add_slider(v, "bars_fade_time", "Bar reveal/hide time (s)", 0.2, 1.4, 0.05, _oa.bars_fade_time, func(x): _oa.bars_fade_time = x)
	_add_slider(v, "rise_time", "Lift-off rise time (s)", 0.2, 1.2, 0.05, _oa.rise_time, func(x): _oa.rise_time = x)
	_add_slider(v, "flyoff_time", "Fly-off duration (s)", 0.4, 2.6, 0.05, _oa.flyoff_time, func(x): _oa.flyoff_time = x)

	v.add_child(HSeparator.new())

	# --- Actions ---
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var replay := UiTheme.make_button("Replay Arrival")
	replay.pressed.connect(_on_replay)
	actions.add_child(replay)
	var depart := UiTheme.make_button("Depart")
	depart.pressed.connect(_on_depart)
	actions.add_child(depart)
	v.add_child(actions)

	var copy := UiTheme.make_button("Copy GDScript")
	copy.pressed.connect(_on_copy_gdscript)
	v.add_child(copy)

	_status = _mk_label("Watch the arrival, then Depart. Tweak → Replay to apply.", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)

	var back := UiTheme.make_button("Back")
	back.pressed.connect(_back)
	v.add_child(back)


# label + slider + live value readout (mirrors loading_screen_lab._add_slider).
func _add_slider(parent: Node, key: String, label: String, mn: float, mx: float, step: float, val: float, on_change: Callable) -> void:
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
	parent.add_child(s)


func _fmt(v: float, step: float) -> String:
	return str(int(round(v))) if step >= 1.0 else "%.2f" % v


func _on_replay() -> void:
	_set_rail_visible(false)
	_oa.begin_arrival()
	if _status != null:
		_status.text = "Arriving…"


func _on_depart() -> void:
	if _oa.get_state() != OutpostArrival.State.LANDED:
		if _status != null:
			_status.text = "Depart only works once landed — Replay first."
		return
	_set_rail_visible(false)
	_oa.depart()
	if _status != null:
		_status.text = "Departing…"


func _on_landed() -> void:
	_set_rail_visible(true)
	if _status != null:
		_status.text = "Landed — menus revealed. Depart to preview the exit."


func _on_departed() -> void:
	_set_rail_visible(true)
	if _status != null:
		_status.text = "Departed (ship off-screen). Replay to re-test."


func _set_rail_visible(v: bool) -> void:
	if _rail != null and is_instance_valid(_rail):
		_rail.visible = v


func _on_swap_side() -> void:
	_rail_side = "right" if _rail_side == "left" else "left"
	_position_rail()


# Anchor the rail full-height on the chosen side (absolute HD coords, root is 1920×1080).
func _position_rail() -> void:
	if _rail == null or not is_instance_valid(_rail):
		return
	_rail.anchor_left = 0.0
	_rail.anchor_top = 0.0
	_rail.anchor_right = 0.0
	_rail.anchor_bottom = 1.0
	_rail.offset_top = 12.0
	_rail.offset_bottom = -12.0
	if _rail_side == "left":
		_rail.offset_left = 12.0
		_rail.offset_right = 12.0 + RAIL_W
	else:
		_rail.offset_left = 1920.0 - 12.0 - RAIL_W
		_rail.offset_right = 1920.0 - 12.0


func _on_copy_gdscript() -> void:
	var lines := [
		"# outpost_arrival.gd tuned defaults (Outpost Arrival Lab):",
		"arrival_time = %s" % _f(_oa.arrival_time),
		"start_y = %s" % _f(_oa.start_y),
		"land_y = %s" % _f(_oa.land_y),
		"idle_bob = %s" % _f(_oa.idle_bob),
		"engine_drift = %s" % _f(_oa.engine_drift),
		"engine_spool = %s" % _f(_oa.engine_spool),
		"star_drift = %s" % _f(_oa.star_drift),
		"scene_dim = %s" % _f(_oa.scene_dim),
		"runway_speed = %s" % _f(_oa.runway_speed),
		"shadow_fly_offset = Vector2(%s, %s)" % [_f(_oa.shadow_fly_offset.x), _f(_oa.shadow_fly_offset.y)],
		"shadow_land_offset = Vector2(%s, %s)" % [_f(_oa.shadow_land_offset.x), _f(_oa.shadow_land_offset.y)],
		"shadow_fly_scale = %s" % _f(_oa.shadow_fly_scale),
		"shadow_land_scale = %s" % _f(_oa.shadow_land_scale),
		"shadow_fly_alpha = %s" % _f(_oa.shadow_fly_alpha),
		"shadow_land_alpha = %s" % _f(_oa.shadow_land_alpha),
		"shadow_settle_time = %s" % _f(_oa.shadow_settle_time),
		"bars_fade_time = %s" % _f(_oa.bars_fade_time),
		"rise_time = %s" % _f(_oa.rise_time),
		"flyoff_time = %s" % _f(_oa.flyoff_time),
	]
	DisplayServer.clipboard_set("\n".join(lines))
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
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_back()
		elif event.keycode == KEY_TAB:
			_set_rail_visible(not _rail.visible)
			get_viewport().set_input_as_handled()
