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


const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")


func _ready() -> void:
	_hd = HdScreen.enter(self)
	_seed_live_run()   # render the LIVE outpost (real Run loadout/economy + split slots), not the mock
	_oa = load(OA_SCENE).instantiate()
	_oa.manage_hd_scope = false
	_oa.return_to_map = false   # lab owns depart (don't navigate to the sector map)
	_oa.landed.connect(_on_landed)
	_oa.departed.connect(_on_departed)
	add_child(_oa)
	_build_rail()
	_build_tune_button()


# A persistent config-collapser (copied from patrol_start's "Tune ⚙"): toggles the rail so the shop
# panel underneath is reachable (the rail covers the left services column, incl. the scrap/sell toggles).
func _build_tune_button() -> void:
	var tune := UiTheme.make_button("Tune ⚙", true)
	tune.position = Vector2(16, 10)
	tune.custom_minimum_size = Vector2(120, 38)
	tune.size = Vector2(120, 38)
	tune.pressed.connect(func() -> void: _set_rail_visible(not _rail.visible))
	add_child(tune)   # added after the rail → drawn on top, always clickable even when the rail is hidden


# Seed a demo mid-run so the embedded dock detects `_live` and shows the current live UI (BLASTER +
# PRIMARY split, hull/super header, live services with 1/All + icons, real market offers, battle-worn
# ship). NOTE: this mutates the global Run autoload — fine for a dev tool; a real run start re-seeds it.
func _seed_live_run() -> void:
	var run := get_node_or_null("/root/Run")
	if run == null:
		return
	if run.has_method("new_run"):
		run.new_run()
	run.run_seed = 0xDECA11   # non-zero → the dock renders the live path
	run.bounty = 3500
	run.materials = 18
	run.repair_charges = 5
	run.ammo_restock_charges = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var prim = PartCatalog.roll_for_slot(rng, SlotTypes.SlotType.CANNON, 3)
	if prim != null:
		run.equip_part(prim)
	var sec = PartCatalog.roll_for_slot(rng, SlotTypes.SlotType.HARDPOINT_WING, 2)
	if sec != null:
		run.equip_part(sec)
	var mod = PartCatalog.roll_for_slot(rng, SlotTypes.SlotType.MODULE, 2)
	if mod != null:
		run.add_module(mod)
	var stored = PartCatalog.roll_for_slot(rng, SlotTypes.SlotType.HARDPOINT_WING, 1)
	if stored != null:
		run.weapon_storage.append(stored)
	var inv = PartCatalog.roll_for_slot(rng, SlotTypes.SlotType.MODULE, 3)
	if inv != null:
		run.inventory.append(inv)
	# Battle-worn: low hull + partial super so the ship shows damage and Repair/Refill have work to do.
	run.current_hull = maxi(1, int(run.max_hull) - 3)
	run.super_charges = maxi(0, int(run.max_super_charges) - 1)
	run.outpost_weapon_offers = []
	run.outpost_needs_refresh = false


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

	# Fixed header + tabs (Sequence / Activity, each its own scroll) + fixed footer actions.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	outer.add_child(_mk_label("OUTPOST ARRIVAL LAB", UiTheme.FONT_SIZE_HEADER, UiTheme.COLOR_ACCENT))
	outer.add_child(_mk_label("Tab: hide/show rail · Esc: back", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	var swap_side := UiTheme.make_button("Swap Rail Side ⇄", true)
	swap_side.pressed.connect(_on_swap_side)
	outer.add_child(swap_side)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_override("font", UiTheme.menu_font())
	tabs.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	outer.add_child(tabs)

	# ===== Sequence tab (the base cinematic + ship) =====
	var seq := _add_tab(tabs, "Sequence")

	seq.add_child(_mk_label("Ship", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	var dd := OptionButton.new()
	for i in ShipCatalog.SHIPS.size():
		dd.add_item(String(ShipCatalog.SHIPS[i]["name"]), i)
	dd.selected = clampi(_oa.ship_variant, 0, ShipCatalog.count() - 1)
	dd.item_selected.connect(func(i: int) -> void: _oa.set_ship(i, _oa.livery_color, _oa.livery_set))
	seq.add_child(dd)

	seq.add_child(_mk_label("Livery", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
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
	seq.add_child(sw)

	seq.add_child(HSeparator.new())

	# --- Fly-in ---
	_add_slider(seq, "arrival_time", "Fly-in duration (s)", 0.8, 5.0, 0.05, _oa.arrival_time, func(x): _oa.arrival_time = x)
	_add_slider(seq, "start_y", "Start Y (below screen)", 280.0, 400.0, 1.0, _oa.start_y, func(x): _oa.start_y = x)
	_add_slider(seq, "land_y", "Land Y (rest)", 100.0, 200.0, 1.0, _oa.land_y, func(x): _oa.land_y = x)
	_add_slider(seq, "idle_bob", "Idle bob amplitude", 0.0, 6.0, 0.1, _oa.idle_bob, func(x): _oa.idle_bob = x)
	_add_slider(seq, "engine_drift", "Engine plume drift (0 = motion-driven)", 0.0, 420.0, 5.0, _oa.engine_drift, func(x): _oa.engine_drift = x)
	_add_slider(seq, "star_drift", "Star parallax scroll (fly-in/out)", 0.0, 6000.0, 50.0, _oa.star_drift, func(x): _oa.star_drift = x)
	_add_slider(seq, "scene_dim", "Scene dim (whole bay; 1 = full bright)", 0.2, 1.0, 0.02, _oa.scene_dim, func(x): _oa.set_scene_dim(x))
	_add_slider(seq, "runway_speed", "Runway pulse speed (rad/s)", 0.2, 5.0, 0.1, _oa.runway_speed, func(x): _oa.set_runway_speed(x))
	_add_slider(seq, "engine_spool", "Engine spool fade (on/off, s)", 0.1, 2.5, 0.05, _oa.engine_spool, func(x): _oa.engine_spool = x)
	_add_slider(seq, "damage_level", "Damage (shader + smoke/sparks)", 0.0, 1.0, 0.05, _oa.damage_level, func(x): _oa.set_damage(x))

	seq.add_child(HSeparator.new())

	# --- Drop shadow ---
	_add_slider(seq, "fly_off_x", "Shadow fly offset X", 0.0, 28.0, 0.5, _oa.shadow_fly_offset.x, func(x): _oa.shadow_fly_offset.x = x)
	_add_slider(seq, "fly_off_y", "Shadow fly offset Y", 0.0, 32.0, 0.5, _oa.shadow_fly_offset.y, func(x): _oa.shadow_fly_offset.y = x)
	_add_slider(seq, "land_off_x", "Shadow land offset X", 0.0, 16.0, 0.5, _oa.shadow_land_offset.x, func(x): _oa.shadow_land_offset.x = x)
	_add_slider(seq, "land_off_y", "Shadow land offset Y", 0.0, 16.0, 0.5, _oa.shadow_land_offset.y, func(x): _oa.shadow_land_offset.y = x)
	_add_slider(seq, "fly_scale", "Shadow fly scale", 0.8, 1.6, 0.02, _oa.shadow_fly_scale, func(x): _oa.shadow_fly_scale = x)
	_add_slider(seq, "land_scale", "Shadow land scale", 0.6, 1.2, 0.02, _oa.shadow_land_scale, func(x): _oa.shadow_land_scale = x)
	_add_slider(seq, "fly_alpha", "Shadow fly alpha", 0.0, 1.0, 0.02, _oa.shadow_fly_alpha, func(x): _oa.shadow_fly_alpha = x)
	_add_slider(seq, "land_alpha", "Shadow land alpha", 0.0, 1.0, 0.02, _oa.shadow_land_alpha, func(x): _oa.shadow_land_alpha = x)
	_add_slider(seq, "settle_time", "Shadow settle time (s)", 0.1, 1.2, 0.05, _oa.shadow_settle_time, func(x): _oa.shadow_settle_time = x)

	seq.add_child(HSeparator.new())

	# --- Reveal / exit ---
	_add_slider(seq, "bars_fade_time", "Bar reveal/hide time (s)", 0.2, 1.4, 0.05, _oa.bars_fade_time, func(x): _oa.bars_fade_time = x)
	_add_slider(seq, "rise_time", "Lift-off rise time (s)", 0.2, 1.2, 0.05, _oa.rise_time, func(x): _oa.rise_time = x)
	_add_slider(seq, "flyoff_time", "Fly-off duration (s)", 0.4, 2.6, 0.05, _oa.flyoff_time, func(x): _oa.flyoff_time = x)

	seq.add_child(HSeparator.new())

	# --- Shadows (prototype: light-derived vs legacy drop shadows) ---
	seq.add_child(_mk_label("Shadows (prototype)", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	var sm := OptionButton.new()
	sm.add_item("Legacy (drop)", OutpostArrival.ShadowMode.LEGACY)
	sm.add_item("Key light", OutpostArrival.ShadowMode.KEY)
	sm.add_item("Fill lights (2x3)", OutpostArrival.ShadowMode.FILL)
	sm.selected = _oa.shadow_mode
	sm.item_selected.connect(func(i: int) -> void: _oa.set_shadow_mode(i))
	seq.add_child(sm)
	var dyn := CheckBox.new()
	dyn.text = "Dynamic (engine) casters"
	dyn.button_pressed = _oa.shadow_dynamic
	dyn.toggled.connect(func(on: bool) -> void: _oa.set_shadow_dynamic(on))
	seq.add_child(dyn)
	_add_slider(seq, "shadow_length", "Shadow length (px)", 0.0, 16.0, 0.5, _oa.shadow_length, func(x): _oa.set_shadow_length(x))
	_add_slider(seq, "shadow_alpha", "Shadow alpha (per light)", 0.0, 1.0, 0.02, _oa.shadow_alpha, func(x): _oa.set_shadow_alpha(x))
	_add_slider(seq, "shadow_falloff", "Shadow falloff (px)", 20.0, 300.0, 5.0, _oa.shadow_falloff, func(x): _oa.set_shadow_falloff(x))
	_add_slider(seq, "shadow_softness", "Shadow softness (scale+)", 0.0, 1.0, 0.05, _oa.shadow_softness, func(x): _oa.set_shadow_softness(x))
	_add_slider(seq, "shadow_max", "Max shadows / object", 1.0, 8.0, 1.0, float(_oa.shadow_max), func(x): _oa.set_shadow_max(x))

	# ===== Activity tab (deck life — tuned separately from the sequence) =====
	var act := _add_tab(tabs, "Activity")
	act.add_child(_mk_label("Deck crew", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	_add_slider(act, "deck_crew_count", "Crew count", 0.0, 16.0, 1.0, float(_oa.deck_crew_count), func(x): _oa.set_deck_crew_count(int(x)))
	_add_slider(act, "deck_crew_speed", "Crew speed (px/f)", 0.2, 2.5, 0.05, _oa.deck_crew_speed, func(x): _oa.set_deck_crew_speed(x))
	_add_slider(act, "deck_crate_count", "Crate count", 0.0, 8.0, 1.0, float(_oa.deck_crate_count), func(x): _oa.set_deck_crate_count(int(x)))
	act.add_child(HSeparator.new())
	act.add_child(_mk_label("Trigger a reaction", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	# HFlowContainer so the reaction buttons wrap to the next line instead of running off the rail.
	var react_flow := HFlowContainer.new()
	react_flow.add_theme_constant_override("h_separation", 6)
	react_flow.add_theme_constant_override("v_separation", 6)
	for kind in ["repair", "buy", "upgrade", "scrap"]:
		var rb := UiTheme.make_button("→ %s" % kind, true)
		rb.pressed.connect(func() -> void: _oa.deck_react(kind))
		react_flow.add_child(rb)
	var carry := UiTheme.make_button("→ carry crate", true)
	carry.pressed.connect(func() -> void: _oa.deck_carry_now())
	react_flow.add_child(carry)
	var lift := UiTheme.make_button("→ lifter run", true)
	lift.pressed.connect(func() -> void: _oa.deck_lifter_run_now())
	react_flow.add_child(lift)
	act.add_child(react_flow)

	# ===== Fixed footer (Replay / Depart / Copy / Back) =====
	outer.add_child(HSeparator.new())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var replay := UiTheme.make_button("Replay Arrival")
	replay.pressed.connect(_on_replay)
	actions.add_child(replay)
	var depart := UiTheme.make_button("Depart")
	depart.pressed.connect(_on_depart)
	actions.add_child(depart)
	outer.add_child(actions)

	var copy := UiTheme.make_button("Copy GDScript")
	copy.pressed.connect(_on_copy_gdscript)
	outer.add_child(copy)

	_status = _mk_label("Watch the arrival, then Depart. Tweak → Replay to apply.", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_status)

	var back := UiTheme.make_button("Back")
	back.pressed.connect(_back)
	outer.add_child(back)


# A scrollable tab page (vertical scroll only); the ScrollContainer's name becomes the tab title.
func _add_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	tabs.add_child(scroll)
	return v


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
		"shadow_mode = %d" % _oa.shadow_mode,
		"shadow_dynamic = %s" % str(_oa.shadow_dynamic),
		"shadow_length = %s" % _f(_oa.shadow_length),
		"shadow_alpha = %s" % _f(_oa.shadow_alpha),
		"shadow_falloff = %s" % _f(_oa.shadow_falloff),
		"shadow_softness = %s" % _f(_oa.shadow_softness),
		"shadow_max = %d" % _oa.shadow_max,
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
