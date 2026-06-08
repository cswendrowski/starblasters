extends Control

# Hangar V5 — HD Test Bench (Roman 2026-06-08 rework).
#
# Mirrors the Shipyard's proven HD three-zone + SubViewport skeleton
# (scripts/dev/shipyard.gd), but flips the roles: instead of spawning
# enemies that attack a dummy player, the LIVE player ship sits in a
# native 480×270 SubViewport firing at a stationary dummy target.
#
# Layout (1920×1080 HD; gameplay SubViewport 480×270 stretched to fill):
#   ┌──────────────────────────────────────────────────────────────────┐
#   │ HANGAR                                                    [Back] │
#   │ ┌────────┐                                       ┌────────────┐  │
#   │ │ SLOT   │            ★ DUMMY (top) ★             │  DPS       │  │
#   │ │ PART   │                                       │  STATUS    │  │
#   │ │ list   │                                       │  EQUIPPED  │  │
#   │ │ MARK   │            ★ PLAYER (bottom) ★         │  [Damage]  │  │
#   │ │ [Apply]│                                       │  SUPERS    │  │
#   │ └────────┘                                       └────────────┘  │
#   └──────────────────────────────────────────────────────────────────┘
#
# The SubViewport stays 480×270 (game-native) so Playfield math + the
# player's own movement/firing read correctly. The player self-drives via
# input (controls_enabled = true). Bullets are routed into the SubViewport
# world node via player.bullet_parent so they live + render in the same
# tree as the dummy and actually land hits.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const DummyTargetScript = preload("res://scripts/dev/hangar_dummy_target.gd")
const Playfield = preload("res://scripts/playfield.gd")

# HD font sizes — UiTheme defaults are sized for 480×270; bump for 1080p.
const FS_TITLE := 40
const FS_HEADER := 24
const FS_BODY := 18
const FS_CAPTION := 15

# HD overlay layout (1920×1080). Translucent panels float over the
# fullscreen playspace.
const RAIL_W := 360
const INFO_W := 360
const MARGIN := 20
const HEADER_H := 56
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.55)
const PANEL_BORDER := Color(0.35, 0.55, 0.75, 0.85)

# Logical equip groups → live-game SlotTypes the picker filters on.
const WEAPON_GROUPS := [
	{"name": "Primary",   "slot": SlotTypes.SlotType.CANNON},
	{"name": "Secondary", "slot": SlotTypes.SlotType.HARDPOINT_WING},
	{"name": "Super",     "slot": SlotTypes.SlotType.DEVICE_BAY_1},
]

# Quick-equip supers (DEVICE_BAY_1) by display name. These ARE the "mode
# modules" today — the design-only Mode/stance system is realized by these
# three. Resolved to factory names at build time via PartCatalog.
const SUPER_NAMES := ["Smart Bomb", "Hyper Mode", "Phase Shift"]

const STATUS_REFRESH := 0.1  # seconds between right-panel rebuilds


# ---- State ---------------------------------------------------------------

var _hd_scope: HdViewportScope = null

var _preview_vp: SubViewport = null
var _world: Node2D = null         # SubViewport world node — bullets + dummy live here
var _player: Node = null
var _dummy: Area2D = null

# Left rail (ship config).
var _slot_picker: OptionButton = null
var _part_list: ItemList = null
var _mark_slider: HSlider = null
var _mark_label: Label = null
var _status_label: Label = null

var _selected_slot: int = SlotTypes.SlotType.CANNON
var _slot_factories: Array = []   # factory names for the currently-shown slot

# Right panel (live status) labels.
var _dps_lbl: Label = null
var _theo_dps_lbl: Label = null
var _hull_lbl: Label = null
var _shield_lbl: Label = null
var _super_lbl: Label = null
var _ammo_lbl: Label = null
var _sec_ammo_lbl: Label = null
var _equip_lbl: Label = null

var _status_t: float = 0.0


# ---- Lifecycle -----------------------------------------------------------

func _ready() -> void:
	# HD attach — but only when this scene is the live current_scene. The
	# feature_showcase previews the hangar as a *child* of the showcase
	# scene; attaching there would swap the global content_scale out from
	# under the showcase. RAII scope auto-restores on exit.
	if get_tree().current_scene == self:
		_hd_scope = HdViewportScope.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_playspace()
	_build_overlay()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")
	# Player.gd's _ready calls default_starting_loadout() + reads
	# Run.loadout_snapshot — same loadout a fresh-run player would have.
	# Wait a frame for that to settle, then mirror it into the picker.
	await get_tree().process_frame
	_refresh_part_list()
	_refresh_status()


# ---- Playspace (fills the whole window) --------------------------------

func _build_playspace() -> void:
	var sub_container := SubViewportContainer.new()
	sub_container.stretch = true
	sub_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Don't eat input meant for the UI overlay above.
	sub_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub_container)

	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(480, 270)
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_vp.transparent_bg = false
	# The player reads input itself; let the subviewport see global input so
	# WASD / shoot reach it (handle_input_locally false routes events from the
	# parent viewport's Input singleton, which Input.is_action_* uses anyway).
	_preview_vp.handle_input_locally = false
	sub_container.add_child(_preview_vp)

	# Gutter dim + brighter playfield band, matching the real frame.
	var gutter := ColorRect.new()
	gutter.color = Color(0.04, 0.05, 0.08, 1.0)
	gutter.size = Vector2(480, 270)
	_preview_vp.add_child(gutter)
	var band := ColorRect.new()
	band.color = Color(0.07, 0.09, 0.13, 1.0)
	band.position = Vector2(Playfield.X_MIN, 0)
	band.size = Vector2(Playfield.W, Playfield.H)
	_preview_vp.add_child(band)

	# World node — bullets + dummy + player all live here so they share a
	# coordinate space and collide. This is the node we hand to the player's
	# bullet_parent.
	_world = Node2D.new()
	_world.name = "World"
	_preview_vp.add_child(_world)

	_spawn_dummy_target()
	_spawn_player()


func _spawn_dummy_target() -> void:
	_dummy = Area2D.new()
	_dummy.name = "DummyTarget"
	_dummy.add_to_group("enemies")
	# Top of the playfield band so bullets travel a full vertical sweep.
	_dummy.position = Vector2(Playfield.CENTER.x, Playfield.Y_MIN + 36.0)
	_dummy.set_script(DummyTargetScript)
	var spr := Sprite2D.new()
	spr.name = "Sprite2D"
	var tex: Texture2D = load("res://graphics/extra-ships/ship_4.png")
	if tex == null:
		tex = load("res://graphics/extra-ships/ship_1.png")
	if tex:
		spr.texture = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(1, 1)
	_dummy.add_child(spr)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	_dummy.add_child(shape)
	_world.add_child(_dummy)


func _spawn_player() -> void:
	_player = PlayerScene.instantiate()
	_world.add_child(_player)
	# CRITICAL: route bullets into the SubViewport world node so they live +
	# render in the same tree as the dummy and actually land hits. Set BEFORE
	# the player can fire (it's spawned into _world this frame, fires next).
	_player.bullet_parent = _world
	# Self-drive via input (reads shoot/shoot2/shoot_nose/focus in _process).
	if "controls_enabled" in _player:
		_player.controls_enabled = true
	# Damage button needs invincibility OFF.
	if "invincible" in _player:
		_player.invincible = false
	# Spawn at the live-game position (player.start() will also reposition to
	# screensize.y - 30; both land at the same bottom-center spot in 480×270).
	_player.position = Vector2(Playfield.CENTER.x, Playfield.Y_MAX - 30.0)


# ---- HD overlay UI (floats over playspace) -----------------------------

func _build_overlay() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 5
	ui_layer.name = "UiOverlay"
	add_child(ui_layer)

	var header := Label.new()
	header.text = "HANGAR"
	header.position = Vector2(MARGIN, 12)
	header.add_theme_font_override("font", UiTheme.active_font())
	header.add_theme_font_size_override("font_size", FS_TITLE)
	header.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
	header.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	header.add_theme_constant_override("outline_size", 6)
	ui_layer.add_child(header)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.position = Vector2(1920 - MARGIN - 120, 16)
	back_btn.size = Vector2(120, 40)
	UiTheme.style_button(back_btn, true)
	back_btn.add_theme_font_size_override("font_size", FS_BODY)
	back_btn.pressed.connect(_on_back)
	ui_layer.add_child(back_btn)

	_build_left_rail(ui_layer)
	_build_info_panel(ui_layer)


func _make_panel_bg(pos: Vector2, sz: Vector2) -> Panel:
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = pos
	panel.size = sz
	# Panel ignores mouse so child controls receive clicks.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.active_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	l.add_theme_constant_override("outline_size", 3)
	return l


func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	UiTheme.style_button(b, true)
	b.add_theme_font_size_override("font_size", FS_BODY)
	b.custom_minimum_size = Vector2(0, 38)
	b.pressed.connect(cb)
	return b


func _build_left_rail(parent: CanvasLayer) -> void:
	var x := MARGIN
	var y := HEADER_H + MARGIN
	var h := 1080 - y - MARGIN

	var panel := _make_panel_bg(Vector2(x, y), Vector2(RAIL_W, h))
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(x + 16, y + 14)
	vbox.size = Vector2(RAIL_W - 32, h - 28)
	vbox.add_theme_constant_override("separation", 8)
	parent.add_child(vbox)

	vbox.add_child(_make_label("SHIP CONFIG", FS_HEADER, UiTheme.COLOR_ACCENT))
	vbox.add_child(HSeparator.new())

	vbox.add_child(_make_label("Slot", FS_CAPTION, UiTheme.COLOR_FAINT))
	_slot_picker = OptionButton.new()
	_slot_picker.add_theme_font_override("font", UiTheme.active_font())
	_slot_picker.add_theme_font_size_override("font_size", FS_BODY)
	_slot_picker.custom_minimum_size = Vector2(0, 38)
	for i in WEAPON_GROUPS.size():
		_slot_picker.add_item(String(WEAPON_GROUPS[i]["name"]), int(WEAPON_GROUPS[i]["slot"]))
	_slot_picker.item_selected.connect(_on_slot_picked)
	vbox.add_child(_slot_picker)

	vbox.add_child(_make_label("Part", FS_CAPTION, UiTheme.COLOR_FAINT))
	_part_list = ItemList.new()
	_part_list.add_theme_font_override("font", UiTheme.active_font())
	_part_list.add_theme_font_size_override("font_size", FS_BODY)
	_part_list.custom_minimum_size = Vector2(0, 300)
	_part_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_part_list.item_selected.connect(_on_part_list_select)
	vbox.add_child(_part_list)

	var mark_row := HBoxContainer.new()
	mark_row.add_theme_constant_override("separation", 10)
	vbox.add_child(mark_row)
	mark_row.add_child(_make_label("Mark", FS_CAPTION, UiTheme.COLOR_FAINT))
	_mark_label = _make_label("Mk.1", FS_BODY, UiTheme.COLOR_TEXT)
	mark_row.add_child(_mark_label)
	_mark_slider = HSlider.new()
	_mark_slider.min_value = 1
	_mark_slider.max_value = 9
	_mark_slider.step = 1
	_mark_slider.value = 1
	_mark_slider.custom_minimum_size = Vector2(160, 0)
	_mark_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mark_slider.value_changed.connect(_on_mark_changed)
	mark_row.add_child(_mark_slider)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)
	var apply_btn := _make_button("Apply", _on_apply_part)
	apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(apply_btn)
	var clear_btn := _make_button("Clear", _on_clear_slot)
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(clear_btn)

	_status_label = _make_label("", FS_CAPTION, UiTheme.COLOR_FAINT)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(RAIL_W - 32, 0)
	vbox.add_child(_status_label)


func _build_info_panel(parent: CanvasLayer) -> void:
	var x := 1920 - MARGIN - INFO_W
	var y := HEADER_H + MARGIN
	var h := 1080 - y - MARGIN

	var panel := _make_panel_bg(Vector2(x, y), Vector2(INFO_W, h))
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(x + 16, y + 14)
	vbox.size = Vector2(INFO_W - 32, h - 28)
	vbox.add_theme_constant_override("separation", 6)
	parent.add_child(vbox)

	# DPS — big.
	_dps_lbl = _make_label("DPS: 0.0", FS_TITLE, UiTheme.COLOR_BOUNTY)
	vbox.add_child(_dps_lbl)
	_theo_dps_lbl = _make_label("theoretical: —", FS_CAPTION, UiTheme.COLOR_FAINT)
	vbox.add_child(_theo_dps_lbl)
	var reset_btn := _make_button("Reset DPS", _on_reset_dps)
	vbox.add_child(reset_btn)
	vbox.add_child(HSeparator.new())

	# Status block.
	vbox.add_child(_make_label("STATUS", FS_HEADER, UiTheme.COLOR_ACCENT))
	_hull_lbl = _make_label("Hull: —", FS_BODY, UiTheme.COLOR_TEXT)
	vbox.add_child(_hull_lbl)
	_shield_lbl = _make_label("Shield: —", FS_BODY, UiTheme.COLOR_TEXT)
	vbox.add_child(_shield_lbl)
	_super_lbl = _make_label("Super: —", FS_BODY, UiTheme.COLOR_TEXT)
	vbox.add_child(_super_lbl)
	_ammo_lbl = _make_label("", FS_BODY, UiTheme.COLOR_TEXT)
	vbox.add_child(_ammo_lbl)
	_sec_ammo_lbl = _make_label("", FS_BODY, UiTheme.COLOR_TEXT)
	vbox.add_child(_sec_ammo_lbl)

	var dmg_btn := _make_button("Damage Player (-1)", _on_damage_player)
	vbox.add_child(dmg_btn)
	vbox.add_child(HSeparator.new())

	# Equipped block.
	vbox.add_child(_make_label("EQUIPPED", FS_HEADER, UiTheme.COLOR_ACCENT))
	_equip_lbl = _make_label("", FS_CAPTION, UiTheme.COLOR_TEXT)
	_equip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_equip_lbl)
	vbox.add_child(HSeparator.new())

	# Mode modules (supers).
	vbox.add_child(_make_label("MODE MODULES", FS_HEADER, UiTheme.COLOR_ACCENT))
	var super_row := HBoxContainer.new()
	super_row.add_theme_constant_override("separation", 6)
	vbox.add_child(super_row)
	for super_name in SUPER_NAMES:
		var b := _make_button(super_name, _on_quick_super.bind(super_name))
		b.add_theme_font_size_override("font_size", FS_CAPTION)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		super_row.add_child(b)
	var fire_row := HBoxContainer.new()
	fire_row.add_theme_constant_override("separation", 10)
	vbox.add_child(fire_row)
	var fire_btn := _make_button("Fire Super", _on_fire_super)
	fire_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fire_row.add_child(fire_btn)
	var refill_btn := _make_button("Refill Super", _on_refill_super)
	refill_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fire_row.add_child(refill_btn)
	vbox.add_child(_make_label("(also fires with X / shoot_nose)", FS_CAPTION, UiTheme.COLOR_FAINT))


# ---- Status refresh ------------------------------------------------------

func _process(delta: float) -> void:
	_status_t += delta
	if _status_t >= STATUS_REFRESH:
		_status_t = 0.0
		_refresh_status()


func _refresh_status() -> void:
	if _dummy != null and is_instance_valid(_dummy) and _dummy.has_method("get_dps"):
		_dps_lbl.text = "DPS: %.1f" % _dummy.get_dps()

	if _player == null or not is_instance_valid(_player):
		return

	var p := _player
	_hull_lbl.text = "Hull: %d / %d" % [int(p.hull), int(p.max_hull)]
	_shield_lbl.text = "Shield: %d / %d" % [int(p.shield), int(p.max_shield)]
	_super_lbl.text = "Super: %d / %d" % [int(p.super_charges), int(p.max_super_charges)]

	# Primary ammo — only when metered (ammo >= 0; -1 = infinite blaster).
	var ammo: int = int(p.ammo) if "ammo" in p else -1
	if ammo >= 0:
		_ammo_lbl.text = "Primary ammo: %d / %d" % [ammo, int(p.ammo_max)]
	else:
		_ammo_lbl.text = "Primary ammo: ∞"

	# Secondary ammo — only when metered (> 0).
	var sec: int = int(p.secondary_ammo) if "secondary_ammo" in p else -1
	if sec > 0 or (sec == 0 and int(p.secondary_ammo_max) > 0):
		_sec_ammo_lbl.text = "Secondary ammo: %d / %d" % [sec, int(p.secondary_ammo_max)]
	else:
		_sec_ammo_lbl.text = ""

	_refresh_equipped_label()


func _refresh_equipped_label() -> void:
	var lines: PackedStringArray = []
	var loadout = _live_loadout()
	for grp in WEAPON_GROUPS:
		var slot: int = int(grp["slot"])
		var label: String = String(grp["name"])
		var part = loadout.get_part(slot) if loadout != null else null
		if part != null:
			var dn: String = String(part.display_name) if "display_name" in part else "?"
			lines.append("%s: %s Mk.%d" % [label, dn, int(part.mark)])
		else:
			lines.append("%s: (empty)" % label)
	_equip_lbl.text = "\n".join(lines)

	# Theoretical DPS for the equipped cannon (reference next to measured).
	if loadout != null:
		var cannon = loadout.get_part(SlotTypes.SlotType.CANNON)
		if cannon != null:
			var stats := _stats_for_part(cannon, int(cannon.mark))
			var dmg: int = stats.get("dmg", 0)
			var rof: float = stats.get("rof", 0.0)
			_theo_dps_lbl.text = "theoretical: %.1f (dmg %d × %.1f/s)" % [float(dmg) * rof, dmg, rof]
			return
	_theo_dps_lbl.text = "theoretical: —"


# ---- Left rail: slot / part handling -------------------------------------

func _on_slot_picked(idx: int) -> void:
	_selected_slot = _slot_picker.get_item_id(idx)
	_refresh_part_list()


func _refresh_part_list() -> void:
	if _part_list == null:
		return
	_part_list.clear()
	_slot_factories = _parts_for_slot(_selected_slot)
	for f in _slot_factories:
		_part_list.add_item(_display_name_for_factory(f, _selected_slot))
	# Highlight whatever is equipped in this slot + sync the mark slider.
	var current = _loadout_part(_selected_slot)
	if current != null:
		var dn: String = String(current.display_name) if "display_name" in current else ""
		for i in _slot_factories.size():
			if _display_name_for_factory(_slot_factories[i], _selected_slot).to_lower() == dn.to_lower():
				_part_list.select(i)
				if _mark_slider:
					_mark_slider.set_value_no_signal(int(current.mark))
				if _mark_label:
					_mark_label.text = "Mk.%d" % int(current.mark)
				return


func _on_part_list_select(_idx: int) -> void:
	# Selection alone doesn't equip; Apply does. No-op hook (kept for clarity).
	pass


func _on_mark_changed(v: float) -> void:
	if _mark_label:
		_mark_label.text = "Mk.%d" % int(v)


func _on_apply_part() -> void:
	var sel := _part_list.get_selected_items()
	if sel.is_empty():
		_set_status("Select a part first")
		return
	var factory_idx: int = sel[0]
	if factory_idx < 0 or factory_idx >= _slot_factories.size():
		return
	var factory: String = _slot_factories[factory_idx]
	var part = PartCatalog._make_by_name(factory, _selected_slot)
	if part == null:
		_set_status("PartCatalog null for %s" % factory)
		return
	part.mark = int(_mark_slider.value)
	# Route through canonical Run.equip_part so secondary ammo + super charges
	# get seeded and any displaced same-slot part lands in weapon_storage. Then
	# mirror onto the LIVE Player's Loadout so the test-fire reflects it now.
	Run.equip_part(part)
	var loadout = _live_loadout()
	if loadout != null:
		loadout.equip(_selected_slot, part)
	_set_status("Equipped %s Mk.%d" % [_display_name_for_factory(factory, _selected_slot), int(part.mark)])
	_refresh_status()


func _on_clear_slot() -> void:
	Run.unequip_slot(_selected_slot)
	var loadout = _live_loadout()
	if loadout != null and loadout.has_method("unequip"):
		loadout.unequip(_selected_slot)
	_set_status("Cleared %s" % SlotTypes.slot_name(_selected_slot))
	_refresh_part_list()
	_refresh_status()


# ---- Right panel: damage + supers ----------------------------------------

func _on_reset_dps() -> void:
	if _dummy != null and is_instance_valid(_dummy) and _dummy.has_method("reset_dps"):
		_dummy.reset_dps()
	if _dps_lbl:
		_dps_lbl.text = "DPS: 0.0"


func _on_damage_player() -> void:
	# Dev-exact damage: bypass take_damage's sector scaling + i-frames by
	# poking set_shield/set_hull directly. Clamp hull at min 1 so the bench
	# never kills the ship (keeps firing alive for continued testing).
	if _player == null or not is_instance_valid(_player):
		return
	var p := _player
	if int(p.shield) > 0:
		p.set_shield(int(p.shield) - 1)
	else:
		p.set_hull(maxi(1, int(p.hull) - 1))
	_refresh_status()


func _on_quick_super(super_name: String) -> void:
	var factory := _super_factory_for(super_name)
	if factory == "":
		_set_status("No super: %s" % super_name)
		return
	var part = PartCatalog._make_by_name(factory, SlotTypes.SlotType.DEVICE_BAY_1)
	if part == null:
		_set_status("PartCatalog null for %s" % super_name)
		return
	part.mark = int(_mark_slider.value)
	Run.equip_part(part)
	var loadout = _live_loadout()
	if loadout != null:
		loadout.equip(SlotTypes.SlotType.DEVICE_BAY_1, part)
	# Top off charges so it can be test-fired immediately.
	if "max_super_charges" in _player:
		_player.super_charges = int(_player.max_super_charges)
		_player.super_charges_changed.emit(int(_player.super_charges), int(_player.max_super_charges))
	_set_status("Super: %s Mk.%d" % [super_name, int(part.mark)])
	_refresh_status()


func _on_fire_super() -> void:
	if _player != null and is_instance_valid(_player) and _player.has_method("fire_super"):
		_player.fire_super()
	_refresh_status()


func _on_refill_super() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if "max_super_charges" in _player:
		_player.super_charges = int(_player.max_super_charges)
		_player.super_charges_changed.emit(int(_player.super_charges), int(_player.max_super_charges))
	_refresh_status()


# ---- Equip / stat helpers (reused from the old hangar) -------------------

func _live_loadout():
	if _player == null or not is_instance_valid(_player) or not _player.has_node("Loadout"):
		return null
	return _player.get_node("Loadout")


func _loadout_part(slot_id: int) -> Resource:
	var lo = _live_loadout()
	if lo != null and lo.has_method("get_part"):
		return lo.get_part(slot_id)
	return null


func _parts_for_slot(slot: int) -> Array:
	var pool := PartCatalog._all_pool()
	var out: Array = []
	var seen: Dictionary = {}
	for entry in pool:
		if int(entry["slot"]) == slot:
			var f: String = String(entry["factory"])
			if not seen.has(f):
				out.append(f)
				seen[f] = true
	return out


# Resolve a super display name (e.g. "Smart Bomb") to its factory function
# name within the DEVICE_BAY_1 pool. Empty string if not found.
func _super_factory_for(super_name: String) -> String:
	for f in _parts_for_slot(SlotTypes.SlotType.DEVICE_BAY_1):
		if _display_name_for_factory(f, SlotTypes.SlotType.DEVICE_BAY_1).to_lower() == super_name.to_lower():
			return f
	return ""


# Authoritative display_name from the Part itself, falling back to the
# derived short-name only when the part can't be instantiated.
func _display_name_for_factory(factory: String, slot: int) -> String:
	var part = PartCatalog._make_by_name(factory, slot)
	if part != null and "display_name" in part:
		var dn: String = String(part.display_name)
		if dn != "" and dn != "Unnamed Part":
			return dn
	return _short_name(factory)


func _short_name(factory: String) -> String:
	var s := factory
	if s.begins_with("_make_"):
		s = s.substr(6)
	return s.replace("_", " ").capitalize()


# Returns {dmg, rof, ammo, homing, pods}. ammo = -1 means unlimited.
func _stats_for_part(part: Resource, mk: int) -> Dictionary:
	mk = clampi(mk, 1, 9)
	var base_dmg: int = int(part.base_damage) if "base_damage" in part else 0
	var dmg_per_mk: int = int(part.dmg_per_mark) if "dmg_per_mark" in part else 0
	var dmg: int = base_dmg + dmg_per_mk * max(0, mk - 1)
	var cooldown: float = float(part.base_cooldown) if "base_cooldown" in part else 0.0
	var rof: float = (1.0 / cooldown) if cooldown > 0.0 else 0.0
	var ammo: int = -1
	if part.has_method("_base_ammo"):
		ammo = int(part._base_ammo())
	var homing: bool = false
	if part.has_method("_homing"):
		homing = bool(part._homing())
	var pods: int = 0
	if part.has_method("_pod_count"):
		pods = int(part._pod_count())
	return {"dmg": dmg, "rof": rof, "ammo": ammo, "homing": homing, "pods": pods}


# ---- Misc ----------------------------------------------------------------

func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg


func _on_back() -> void:
	if _hd_scope != null and is_instance_valid(_hd_scope):
		_hd_scope.free()
		_hd_scope = null
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
