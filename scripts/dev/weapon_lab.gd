extends Control

# Weapon Lab (overhauled 2026-07-09) — one HD bench to SEE and TUNE every weapon and
# projectile in the game, editing the LIVE canonical data (no detached JSON / replicated
# lists). Three tabs share the proven native 480×270 SubViewport play area (Hangar / Enemy
# Bench skeleton):
#
#   WEAPONS     — equip any player weapon (primary / secondary / super) on the LIVE ship
#                 firing UP at a dummy. Edit every tunable stat AND see the Mk.1→9 progression
#                 curve. Save writes resources/weapons/<name>.tres DIRECTLY (the .tres is the
#                 single source of truth the game loads) and runs the weapon-data invariants.
#   PROJECTILES — every projectile in one editor: Side (Player/Enemy) × Kind (Bullet/Rocket-
#                 Missile). Enemy bullets are BulletVariant .tres (saved to .tres); player/enemy
#                 bullets, rockets and missiles are scenes (saved back into the .tscn). Fields
#                 the weapon Part stamps at fire time (bullet speed/damage, missile damage) are
#                 flagged so you never tune a dead value. Live-fire at a dummy with real impact +
#                 explosion FX.
#   ENEMY       — build an enemy Weapon (fire pattern / aim / payload) on a stationary host
#                 firing DOWN at the player, previewing enemy bullet payloads.
#
# The SubViewportContainer.stretch_shrink = 4 keeps the play area native-480 under the HD scope
# (docs/godot-patterns.md "HD SubViewport host"). Esc / Back → dev menu.
#
# LIVE DATA (the whole point): every Save mutates the real shipping file in place —
# resources/weapons/*.tres, data/bullets/*.tres, scenes/projectiles/*.tscn. This only works from
# the editor/dev context (exported builds pack res:// read-only); saves are guarded + report why.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const DummyTargetScript = preload("res://scripts/dev/hangar_dummy_target.gd")
const Playfield = preload("res://scripts/systems/playfield.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const WS = preload("res://scripts/weapons/WeaponStyle.gd")
const Weapon = preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const DevData = preload("res://scripts/dev/dev_data.gd")
const DevField = preload("res://scripts/dev/dev_field.gd")

# A stationary enemy_core chassis to host the previewed enemy weapon (movement nulled so it sits
# at the top and just fires).
const ENEMY_HOST := "res://scenes/enemies/factions/corporate/enemy_c_s_hold.tscn"

enum Tab { WEAPONS, PROJECTILES, ENEMY }

# Player weapon groups → live SlotTypes (mirrors the Hangar).
const WEAPON_GROUPS := [
	{"name": "Primary", "slot": SlotTypes.SlotType.CANNON},
	{"name": "Secondary", "slot": SlotTypes.SlotType.HARDPOINT_WING},
	{"name": "Super", "slot": SlotTypes.SlotType.DEVICE_BAY_1},
]

const STYLE_NAMES := ["Energy", "Machinegun", "Rotary Laser", "Beam", "Autocannon", "Minigun"]

# Enemy weapon option pools (shared with the Enemy Bench).
const FIRE_PATTERNS := ["SINGLE", "AIMED", "SPREAD", "BURST", "BEAM", "BROADSIDE"]
const AIMS := ["AT_PLAYER", "STRAIGHT_DOWN", "TOWARD_CENTER", "FORWARD"]

# Projectiles-tab data sources.
const ENEMY_BULLET_DIR := "res://data/bullets/"
const PROJECTILE_SCENE_DIR := "res://scenes/projectiles/"
# Filename-prefix → side classifier for the scene scan (avoids a replicated hardcoded list — a
# newly added scene auto-appears). Enemy bullet render shells ("projectile_*") are excluded from
# the editable set because enemy bullet STATS live in the .tres, not the shell scene.
const PLAYER_PREFIXES := ["player_", "bullet_"]
const ENEMY_PREFIXES := ["enemy_", "drifting_"]

# Projectile Side / Kind selectors.
enum Side { PLAYER, ENEMY }
enum Kind { BULLET, MISSILE }

# Velocity @exports that are constrained to the motion-clarity speed rungs (multiples of 60 px/s,
# ceiling 480 = 8 px/f). `speed` = bullets/BulletVariant; `drift_speed`/`homing_max_speed` = the
# base_missile travel-speed fields (rockets + missiles). `speed_lock_mult` is a MULTIPLIER, not a
# speed — deliberately excluded. Constants come from Clarity (SSOT). The rung SpinBox sets .value
# BEFORE connecting value_changed, so loading never silently re-clamps — only a user edit snaps.
const RUNG_SPEED_FIELDS := ["speed", "drift_speed", "homing_max_speed"]

var PAYLOADS: Dictionary = {}   # family name -> BulletVariant (live from DevData.bullet_variants())

const FS_TITLE := 40
const FS_HEADER := 24
const FS_BODY := 18
const FS_CAPTION := 15
const RAIL_W := 470
const INFO_W := 470
const MARGIN := 20
const HEADER_H := 56
const TABBAR_Y := 64
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.58)
const PANEL_BORDER := Color(0.35, 0.55, 0.75, 0.85)

# Runtime/identity fields to hide from the player-stat editors (not designer-tunable stats).
const _STAT_SKIP := ["mark", "max_mark", "current_ammo", "ammo_max", "slot_type"]
# Progression-table mark columns (subset of 1–9 that reads cleanly in the panel width).
const PROG_MARKS := [1, 3, 5, 7, 9]

# ---- State ---------------------------------------------------------------

var _hd_scope: HdViewportScope = null
var _preview_vp: SubViewport = null
var _world: Node2D = null
var _player: Node = null
var _top_dummy: Area2D = null     # static enemy target (weapons/projectiles tabs)
var _enemy_host: Node = null      # live firing enemy (enemy tab)
var _orig_autofire: bool = false
var _tab: int = Tab.WEAPONS

var _tab_nodes: Dictionary = {}   # Tab -> Array[Control]

# Weapons tab widgets.
var _p_group_dd: OptionButton = null
var _p_list: ItemList = null
var _p_factories: Array = []
var _p_mark: HSlider = null
var _p_mark_lbl: Label = null
var _p_info: RichTextLabel = null
var _p_bullet_tex: TextureRect = null
var _p_part = null                      # the live Part instance currently tuned
var _p_slot: int = -1
var _p_factory: String = ""
var _p_stat_box: VBoxContainer = null
var _p_prog_grid: GridContainer = null  # Mk.1→9 progression readout
var _p_stat_status: Label = null
var _p_overrides: Dictionary = {}       # factory -> {stat: value}, in-memory buffer of unsaved edits

# Projectiles tab widgets.
var _pj_side_dd: OptionButton = null
var _pj_kind_dd: OptionButton = null
var _pj_list: ItemList = null
var _pj_items: Array = []               # paths (String)
var _pj_form: VBoxContainer = null
var _pj_status: Label = null
var _pj_edit_obj: Object = null         # BulletVariant (.tres, shared) OR scene instance (owned)
var _pj_is_tres: bool = false           # true = enemy BulletVariant .tres; false = scene .tscn
var _pj_path: String = ""
var _pj_baseline: Dictionary = {}       # scalar prop -> pristine value (scene diff on save)
var _pj_muzzle: Node2D = null
var _pj_fire_timer: Timer = null

# Enemy tab widgets.
var _e_fire_dd: OptionButton = null
var _e_aim_dd: OptionButton = null
var _e_payload_dd: OptionButton = null
var _e_info: RichTextLabel = null
var _e_bullet_tex: TextureRect = null

var _last_footer: HBoxContainer = null  # set by _rail_panel — the fixed action bar at the panel bottom
var _autofire: bool = false


func _ready() -> void:
	_build_payload_table()   # live data/bullets/*.tres inventory (before the UI reads PAYLOADS.keys())
	if get_parent() == get_tree().root:
		_hd_scope = HdViewportScope.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if has_node("/root/Settings"):
		_orig_autofire = bool(get_node("/root/Settings").autofire)
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("silent")
	_build_playspace()
	_build_overlay()
	await get_tree().process_frame
	HdScreen.verify_native_subviewport(_preview_vp, "Weapon Lab")
	_select_tab(Tab.WEAPONS)
	_refresh_weapon_list()


# Build the enemy-weapon payload inventory from the live data/bullets/*.tres scan.
func _build_payload_table() -> void:
	PAYLOADS = {}
	for v in DevData.bullet_variants():
		var name: String = String(v.get("name", ""))
		var path: String = String(v.get("path", ""))
		if name == "" or path == "":
			continue
		var res: Resource = load(path)
		if res != null:
			PAYLOADS[name] = res


# ---- Playspace -----------------------------------------------------------

func _build_playspace() -> void:
	var sub_container := SubViewportContainer.new()
	sub_container.stretch = true
	sub_container.stretch_shrink = 4
	sub_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sub_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub_container)

	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(480, 270)
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_vp.handle_input_locally = false
	_preview_vp.use_hdr_2d = bool(ProjectSettings.get_setting("rendering/viewport/hdr_2d", false))
	sub_container.add_child(_preview_vp)

	var bg_layer := CanvasLayer.new()
	bg_layer.name = "Backdrop"
	bg_layer.layer = -1
	_preview_vp.add_child(bg_layer)
	var gutter := ColorRect.new()
	gutter.color = Color(0.04, 0.05, 0.08, 1.0)
	gutter.size = Vector2(480, 270)
	bg_layer.add_child(gutter)
	var band := ColorRect.new()
	band.color = Color(0.07, 0.09, 0.13, 1.0)
	band.position = Vector2(Playfield.X_MIN, 0)
	band.size = Vector2(Playfield.W, Playfield.H)
	bg_layer.add_child(band)

	_world = Node2D.new()
	_world.name = "World"
	_world.add_to_group("bullet_world")
	_preview_vp.add_child(_world)

	_preview_vp.audio_listener_enable_2d = true
	var listener := AudioListener2D.new()
	listener.position = Vector2(Playfield.CENTER.x, Playfield.CENTER.y)
	_world.add_child(listener)
	listener.make_current()

	_spawn_top_dummy()
	_spawn_player()


func _spawn_top_dummy() -> void:
	_top_dummy = Area2D.new()
	_top_dummy.name = "TopDummy"
	_top_dummy.add_to_group("enemies")
	_top_dummy.position = Vector2(Playfield.CENTER.x, Playfield.Y_MIN + 36.0)
	_top_dummy.set_script(DummyTargetScript)
	var spr := Sprite2D.new()
	spr.name = "Sprite2D"
	var tex: Texture2D = load("res://graphics/extra-ships/ship_4.png")
	if tex == null:
		tex = load("res://graphics/extra-ships/ship_1.png")
	if tex:
		spr.texture = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_top_dummy.add_child(spr)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	_top_dummy.add_child(shape)
	_world.add_child(_top_dummy)


func _spawn_player() -> void:
	_player = PlayerScene.instantiate()
	_world.add_child(_player)
	_player.bullet_parent = _world
	if "controls_enabled" in _player:
		_player.controls_enabled = true
	if "invincible" in _player:
		_player.invincible = true   # the lab never dies; we're testing weapons
	_player.position = Vector2(Playfield.CENTER.x, Playfield.Y_MAX - 30.0)


# ---- Overlay -------------------------------------------------------------

func _build_overlay() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)

	var header := _label("WEAPON LAB", FS_TITLE, UiTheme.COLOR_ACCENT)
	header.position = Vector2(MARGIN, 8)
	header.add_theme_constant_override("outline_size", 6)
	ui.add_child(header)

	var back := Button.new()
	back.text = "Back"
	back.anchor_left = 1.0
	back.anchor_right = 1.0
	back.offset_left = -(MARGIN + 120)
	back.offset_right = -MARGIN
	back.offset_top = 14
	back.offset_bottom = 54
	UiTheme.style_button(back, true)
	back.add_theme_font_size_override("font_size", FS_BODY)
	back.pressed.connect(_on_back)
	ui.add_child(back)

	var tabs := TabBar.new()
	tabs.position = Vector2(MARGIN + 320, TABBAR_Y)
	tabs.add_theme_font_override("font", UiTheme.active_font())
	tabs.add_theme_font_size_override("font_size", FS_BODY)
	tabs.add_tab("Weapons")
	tabs.add_tab("Projectiles")
	tabs.add_tab("Enemy")
	tabs.tab_changed.connect(func(i): _select_tab(i))
	ui.add_child(tabs)

	# Shared autofire + manual-fire bar (top-center, under the tab bar).
	var fire_bar := HBoxContainer.new()
	fire_bar.position = Vector2(MARGIN + 320, TABBAR_Y + 40)
	fire_bar.add_theme_constant_override("separation", 12)
	ui.add_child(fire_bar)
	var auto_chk := CheckButton.new()
	auto_chk.text = "Autofire"
	auto_chk.add_theme_font_override("font", UiTheme.active_font())
	auto_chk.add_theme_font_size_override("font_size", FS_BODY)
	auto_chk.toggled.connect(_on_autofire_toggled)
	fire_bar.add_child(auto_chk)
	var fire_btn := _button("Fire ▶ (or hold Z)", _on_fire_once)
	fire_btn.custom_minimum_size = Vector2(220, 36)
	fire_bar.add_child(fire_btn)

	_build_weapons_tab(ui)
	_build_projectiles_tab(ui)
	_build_enemy_tab(ui)


# Builds a translucent panel + a scrolling VBox. Appends the top-level nodes to `sink` so the
# caller can toggle them per tab. Returns the vbox. _last_footer = the fixed bottom action bar.
func _rail_panel(ui: CanvasLayer, right: bool, sink: Array) -> VBoxContainer:
	var w := INFO_W if right else RAIL_W
	var y := TABBAR_Y + 84
	var panel := _panel(Vector2.ZERO, Vector2(w, 100))
	_anchor_rail(panel, right, w, y, 0.0)
	ui.add_child(panel)
	var scroll := ScrollContainer.new()
	_anchor_rail(scroll, right, w, y + 12.0, 14.0)
	scroll.offset_bottom = -(MARGIN + 56)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(w - 44, 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	footer.anchor_top = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_top = -(MARGIN + 44)
	footer.offset_bottom = -(MARGIN + 6)
	if right:
		footer.anchor_left = 1.0
		footer.anchor_right = 1.0
		footer.offset_left = -(MARGIN + w) + 14
		footer.offset_right = -MARGIN - 14
	else:
		footer.anchor_left = 0.0
		footer.anchor_right = 0.0
		footer.offset_left = MARGIN + 14
		footer.offset_right = MARGIN + w - 14
	ui.add_child(footer)
	sink.append(panel)
	sink.append(scroll)
	sink.append(footer)
	_last_footer = footer
	return vbox


func _anchor_rail(c: Control, right: bool, w: float, top: float, inset: float) -> void:
	c.anchor_top = 0.0
	c.anchor_bottom = 1.0
	c.offset_top = top + inset
	c.offset_bottom = -MARGIN - inset
	if right:
		c.anchor_left = 1.0
		c.anchor_right = 1.0
		c.offset_left = -(MARGIN + w) + inset
		c.offset_right = -MARGIN - inset
	else:
		c.anchor_left = 0.0
		c.anchor_right = 0.0
		c.offset_left = MARGIN + inset
		c.offset_right = MARGIN + w - inset


# ---- Weapons tab ---------------------------------------------------------

func _build_weapons_tab(ui: CanvasLayer) -> void:
	var sink: Array = []
	var rail := _rail_panel(ui, false, sink)
	rail.add_child(_label("PLAYER WEAPONS", FS_HEADER, UiTheme.COLOR_ACCENT))
	rail.add_child(HSeparator.new())
	rail.add_child(_label("Group filter", FS_CAPTION, UiTheme.COLOR_FAINT))
	_p_group_dd = OptionButton.new()
	_p_group_dd.add_theme_font_override("font", UiTheme.active_font())
	_p_group_dd.add_theme_font_size_override("font_size", FS_BODY)
	_p_group_dd.custom_minimum_size = Vector2(0, 36)
	for g in WEAPON_GROUPS:
		_p_group_dd.add_item(String(g["name"]))
	_p_group_dd.item_selected.connect(func(_i): _refresh_weapon_list())
	rail.add_child(_p_group_dd)

	_p_list = ItemList.new()
	_p_list.add_theme_font_override("font", UiTheme.active_font())
	_p_list.add_theme_font_size_override("font_size", FS_BODY)
	_p_list.custom_minimum_size = Vector2(0, 360)
	_p_list.item_selected.connect(func(_i): _equip_weapon())
	rail.add_child(_p_list)

	var mark_row := HBoxContainer.new()
	mark_row.add_theme_constant_override("separation", 10)
	rail.add_child(mark_row)
	mark_row.add_child(_label("Mark", FS_CAPTION, UiTheme.COLOR_FAINT))
	_p_mark_lbl = _label("Mk.1", FS_BODY, UiTheme.COLOR_TEXT)
	mark_row.add_child(_p_mark_lbl)
	_p_mark = HSlider.new()
	_p_mark.min_value = 1
	_p_mark.max_value = 9
	_p_mark.step = 1
	_p_mark.value = 1
	_p_mark.custom_minimum_size = Vector2(200, 0)
	_p_mark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p_mark.value_changed.connect(func(v):
		_p_mark_lbl.text = "Mk.%d" % int(v)
		_equip_weapon())
	mark_row.add_child(_p_mark)

	var panel := _rail_panel(ui, true, sink)
	var footer := _last_footer
	panel.add_child(_label("EQUIPPED", FS_HEADER, UiTheme.COLOR_ACCENT))
	_p_info = _rich(panel)
	panel.add_child(HSeparator.new())
	panel.add_child(_label("Bullet sprite", FS_CAPTION, UiTheme.COLOR_FAINT))
	_p_bullet_tex = _tex_rect(panel)

	panel.add_child(HSeparator.new())
	panel.add_child(_label("STATS — edit live, then Save → .tres", FS_CAPTION, UiTheme.COLOR_ACCENT))
	_p_stat_box = VBoxContainer.new()
	_p_stat_box.add_theme_constant_override("separation", 4)
	panel.add_child(_p_stat_box)

	panel.add_child(HSeparator.new())
	panel.add_child(_label("PROGRESSION  (Mk %s)" % ("·".join(PackedStringArray(PROG_MARKS.map(func(m): return str(m))))), FS_CAPTION, UiTheme.COLOR_ACCENT))
	_p_prog_grid = GridContainer.new()
	_p_prog_grid.columns = PROG_MARKS.size() + 1
	_p_prog_grid.add_theme_constant_override("h_separation", 10)
	_p_prog_grid.add_theme_constant_override("v_separation", 2)
	panel.add_child(_p_prog_grid)

	for spec in [["Save → .tres", _save_weapon_tres], ["Reset", _reset_weapon_stats], ["Copy .tres", _copy_tres_block]]:
		var b := _button(String(spec[0]), spec[1] as Callable)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(b)
	_p_stat_status = _label("", FS_CAPTION, UiTheme.COLOR_FAINT)
	_p_stat_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_p_stat_status.custom_minimum_size = Vector2(INFO_W - 60, 0)
	panel.add_child(_p_stat_status)

	_tab_nodes[Tab.WEAPONS] = sink


func _refresh_weapon_list() -> void:
	if _p_list == null:
		return
	_p_list.clear()
	var slot: int = int(WEAPON_GROUPS[_p_group_dd.selected]["slot"])
	_p_factories = _parts_for_slot(slot)
	for f in _p_factories:
		_p_list.add_item(_display_name_for_factory(f, slot))
	if _p_list.item_count > 0:
		_p_list.select(0)
		_equip_weapon()


func _equip_weapon() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var sel := _p_list.get_selected_items()
	if sel.is_empty():
		return
	var slot: int = int(WEAPON_GROUPS[_p_group_dd.selected]["slot"])
	var factory: String = _p_factories[sel[0]]
	_p_slot = slot
	_p_factory = factory
	var part = _build_tuned_part(factory, slot)
	if part == null:
		return
	_p_part = part
	_equip_part_on_player(part, slot)
	_refresh_weapon_info(part)
	_rebuild_stat_editors(part)
	_refresh_progression(part)


# Build a fresh Part with the current Mark + any unsaved stat overrides applied.
func _build_tuned_part(factory: String, slot: int):
	var part = PartCatalog._make_by_name(factory, slot)
	if part == null:
		return null
	part.mark = int(_p_mark.value)
	_apply_overrides_to_part(factory, part)
	return part


func _apply_overrides_to_part(factory: String, part) -> void:
	if not _p_overrides.has(factory):
		return
	for stat in (_p_overrides[factory] as Dictionary).keys():
		if stat in part:
			part.set(stat, _p_overrides[factory][stat])


func _equip_part_on_player(part, slot: int) -> void:
	var loadout = _live_loadout()
	if slot == SlotTypes.SlotType.CANNON:
		if has_node("/root/Run"):
			get_node("/root/Run").active_cannon_idx = 0
		if loadout != null:
			loadout.equip(SlotTypes.SlotType.CANNON, part)
	else:
		if has_node("/root/Run"):
			get_node("/root/Run").equip_part(part)
		if loadout != null:
			loadout.equip(slot, part)
		if "secondary_ammo" in _player and int(_player.secondary_ammo_max) > 0:
			_player.secondary_ammo = int(_player.secondary_ammo_max)
		if "super_charges" in _player and "max_super_charges" in _player:
			_player.super_charges = int(_player.max_super_charges)


# Numeric/bool @export stats on the Part that are designer-tunable (skips runtime + identity).
func _tunable_stats(part) -> Array:
	var out: Array = []
	for pinfo in part.get_property_list():
		if not (int(pinfo.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = String(pinfo.name)
		if n.begins_with("_") or n in _STAT_SKIP:
			continue
		var t: int = int(pinfo.type)
		if t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_BOOL:
			out.append({"name": n, "type": t})
	return out


func _rebuild_stat_editors(part) -> void:
	if _p_stat_box == null:
		return
	for c in _p_stat_box.get_children():
		c.queue_free()
	# Default-vs-override baseline: a fresh UNTUNED Part at the same Mark = the committed .tres.
	var baked = _baked_ref_part()
	for spec in _tunable_stats(part):
		var stat: String = String(spec["name"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := _label(stat, FS_CAPTION, UiTheme.COLOR_TEXT)
		lbl.custom_minimum_size = Vector2(150, 0)
		row.add_child(lbl)
		var baked_val = (baked.get(stat) if (baked != null and stat in baked) else part.get(stat))
		if int(spec["type"]) == TYPE_BOOL:
			var cb := CheckButton.new()
			cb.button_pressed = bool(part.get(stat))
			cb.toggled.connect(func(v): _on_stat_changed(stat, v); DevField.refresh(cb))
			row.add_child(cb)
			DevField.decorate(cb, bool(baked_val), FS_CAPTION)
		else:
			var sb := SpinBox.new()
			var is_float: bool = int(spec["type"]) == TYPE_FLOAT
			sb.step = 0.01 if is_float else 1.0
			sb.min_value = -9999.0
			sb.max_value = 99999.0
			sb.value = float(part.get(stat))
			sb.custom_minimum_size = Vector2(110, 0)
			sb.value_changed.connect(func(v): _on_stat_changed(stat, v if is_float else int(round(v))); DevField.refresh(sb))
			row.add_child(sb)
			DevField.decorate(sb, float(baked_val), FS_CAPTION)
		_p_stat_box.add_child(row)


# A fresh Part at the current factory/slot/Mark with NO overrides — its stats are the committed
# .tres values (the baked default the affordance compares against).
func _baked_ref_part():
	if _p_factory == "":
		return null
	var p = PartCatalog._make_by_name(_p_factory, _p_slot)
	if p == null:
		return null
	p.mark = int(_p_mark.value)
	return p


func _on_stat_changed(stat: String, value) -> void:
	if not _p_overrides.has(_p_factory):
		_p_overrides[_p_factory] = {}
	_p_overrides[_p_factory][stat] = value
	var part = _build_tuned_part(_p_factory, _p_slot)
	if part != null:
		_p_part = part
		_equip_part_on_player(part, _p_slot)
		_refresh_weapon_info(part)
		_refresh_progression(part)
	if _p_stat_status:
		_p_stat_status.text = "%s = %s  (unsaved — Save → .tres to persist)" % [stat, str(value)]


func _reset_weapon_stats() -> void:
	_p_overrides.erase(_p_factory)
	_equip_weapon()  # full rebuild from the .tres defaults
	if _p_stat_status:
		_p_stat_status.text = "Reset %s to .tres defaults." % _p_factory


# Direct .tres write — the whole point of the overhaul. Rebuilds the Part from its current .tres,
# stamps the unsaved edits onto the base @exports, matches the .tres discipline (identity stays
# code-owned, resource_path cleared), and saves in place. Then refreshes the cache + validates.
func _save_weapon_tres() -> void:
	if _p_factory == "":
		return
	if not _can_write_res():
		_p_stat_status.text = "Save unavailable — res:// is read-only outside the editor."
		return
	var path: String = String(PartCatalog.weapon_tres_map().get(_p_factory, ""))
	if path == "":
		_p_stat_status.text = "%s has no .tres — its stats are code-authored (nothing to save here)." % _display_name_for_factory(_p_factory, _p_slot)
		return
	var part = PartCatalog._make_by_name(_p_factory, _p_slot)
	if part == null:
		_p_stat_status.text = "Save FAILED — could not rebuild %s." % _p_factory
		return
	_apply_overrides_to_part(_p_factory, part)
	# The .tres single-source-of-truth stores stats + slot; identity (display_name/description)
	# stays code-owned (Godot skips _init() on disk-loaded resources). Match the regen format.
	if "display_name" in part:
		part.display_name = ""
	if "description" in part:
		part.description = ""
	part.resource_path = ""
	var err := ResourceSaver.save(part, path)
	if err != OK:
		_p_stat_status.text = "Save FAILED (err %d) → %s" % [err, path.get_file()]
		return
	# Refresh the cached resource so the baked-ref affordance + any live loads see the new values.
	ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	_p_overrides.erase(_p_factory)   # baked into the .tres now — no longer an unsaved override
	_equip_weapon()                  # re-equip a clean part (affordance clears; game reads this .tres)
	_p_stat_status.text = "Saved → %s ✓   %s" % [path.get_file(), _validate_saved(path)]


# Lightweight per-weapon version of tools/validate_weapon_data.gd: every persisted [resource] key
# must be a live script property (no stale/ignored field), and the rebuilt part resolves its knobs.
func _validate_saved(path: String) -> String:
	var part = PartCatalog._make_by_name(_p_factory, _p_slot)
	if part == null:
		return "validate: build-fail"
	var always_ok := ["script", "resource_local_to_scene", "resource_name", "resource_path"]
	for k in _tres_resource_keys(path):
		if k in always_ok:
			continue
		if not (k in part):
			return "validate: STALE field '%s'" % k
	if "slot_type" in part and int(part.slot_type) < 0:
		return "validate: slot unresolved"
	if part.has_method("_mk_knobs"):
		var _k = part._mk_knobs()
	return "validated ✓"


func _tres_resource_keys(path: String) -> Array:
	var keys: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return keys
	var in_resource := false
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("[resource]"):
			in_resource = true
			continue
		if line.begins_with("["):
			in_resource = false
			continue
		if in_resource and "=" in line:
			keys.append(line.get_slice("=", 0).strip_edges())
	f.close()
	return keys


# Emit the [resource] stat lines for the current weapon's .tres, paste-ready.
func _copy_tres_block() -> void:
	if _p_part == null:
		return
	var lines := PackedStringArray()
	lines.append("# Paste into resources/weapons/<%s>.tres [resource] block:" % _p_factory)
	for spec in _tunable_stats(_p_part):
		var stat: String = String(spec["name"])
		var v = _p_part.get(stat)
		if int(spec["type"]) == TYPE_FLOAT:
			lines.append("%s = %s" % [stat, String.num(float(v), 4)])
		else:
			lines.append("%s = %s" % [stat, str(v)])
	var txt := "\n".join(lines)
	DisplayServer.clipboard_set(txt)
	if _p_stat_status:
		_p_stat_status.text = "Copied .tres stat block (%d lines)." % lines.size()


func _refresh_weapon_info(part) -> void:
	if _p_info == null:
		return
	var dn: String = String(part.display_name) if "display_name" in part else "?"
	var lines: PackedStringArray = []
	lines.append("[b]%s[/b]  Mk.%d" % [dn, int(part.mark)])
	var style: int = int(_player.weapon_style) if "weapon_style" in _player else 0
	lines.append("Style: %s" % (STYLE_NAMES[style] if style < STYLE_NAMES.size() else str(style)))
	var sfx: int = int(_player.fire_sfx_kind) if "fire_sfx_kind" in _player else -1
	lines.append("Fire SFX: %s" % WS.sfx_kind_string(sfx))
	var bscene: PackedScene = _player.bullet_scene if "bullet_scene" in _player else null
	if bscene != null:
		lines.append("Bullet: %s" % bscene.resource_path.get_file())
		_p_bullet_tex.texture = _first_texture_of_scene(bscene)
	else:
		lines.append("Bullet: (hitscan / none)")
		_p_bullet_tex.texture = null
	_p_info.text = "\n".join(lines)


# Rebuild the Mk.1→9 progression readout from the Part's _mk_knobs() curve + ammo formula.
func _refresh_progression(part) -> void:
	if _p_prog_grid == null:
		return
	for c in _p_prog_grid.get_children():
		c.queue_free()
	if part == null:
		return
	# Header row.
	_p_prog_grid.add_child(_grid_cell("", UiTheme.COLOR_FAINT, true))
	for m in PROG_MARKS:
		_p_prog_grid.add_child(_grid_cell("Mk%d" % m, UiTheme.COLOR_ACCENT, true))
	# One row per Mk-knob.
	var knobs: Dictionary = part._mk_knobs() if part.has_method("_mk_knobs") else {}
	for key in knobs.keys():
		_p_prog_grid.add_child(_grid_cell(String(key), UiTheme.COLOR_TEXT, false))
		for m in PROG_MARKS:
			_p_prog_grid.add_child(_grid_cell(_fmt_knob(_knob_value_at(knobs[key], int(m))), UiTheme.COLOR_TEXT, false))
	# Ammo row (only for weapons with a magazine).
	if part.has_method("ammo_at_mark") and int(part.ammo_at_mark(1)) > 0:
		_p_prog_grid.add_child(_grid_cell("ammo", UiTheme.COLOR_TEXT, false))
		for m in PROG_MARKS:
			_p_prog_grid.add_child(_grid_cell(str(int(part.ammo_at_mark(int(m)))), UiTheme.COLOR_TEXT, false))


# Resolve one _mk_knobs() spec at a mark — mirrors WeaponPart._compute_knob_value (Array = linear
# interp, Callable = picker, else pass-through) without needing a live ship.
func _knob_value_at(spec, mk: int):
	if spec is Callable:
		return spec.call(int(mk))
	if spec is Array and spec.size() == 2:
		var t: float = (clampf(float(mk), 1.0, 9.0) - 1.0) / 8.0
		var lerped: float = lerpf(float(spec[0]), float(spec[1]), t)
		if typeof(spec[0]) == TYPE_INT:
			return int(round(lerped))
		return lerped
	return spec


func _fmt_knob(v) -> String:
	if v is float:
		return String.num(v, 3)
	if v is Resource:
		return (v as Resource).resource_path.get_file()
	if v == null:
		return "—"
	return str(v)


func _grid_cell(text: String, color: Color, header: bool) -> Label:
	var l := _label(text, FS_CAPTION, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if header else HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size = Vector2(64, 0)
	return l


# ---- Projectiles tab -----------------------------------------------------

func _build_projectiles_tab(ui: CanvasLayer) -> void:
	var sink: Array = []
	var rail := _rail_panel(ui, false, sink)
	rail.add_child(_label("PROJECTILES", FS_HEADER, UiTheme.COLOR_ACCENT))
	rail.add_child(HSeparator.new())
	_pj_side_dd = _dropdown(rail, "Side", ["Player", "Enemy"])
	_pj_side_dd.item_selected.connect(func(_i): _on_projectile_filter_changed())
	_pj_kind_dd = _dropdown(rail, "Kind", ["Bullet", "Rocket / Missile"])
	_pj_kind_dd.item_selected.connect(func(_i): _on_projectile_filter_changed())
	_pj_list = ItemList.new()
	_pj_list.add_theme_font_override("font", UiTheme.active_font())
	_pj_list.add_theme_font_size_override("font_size", FS_BODY)
	_pj_list.custom_minimum_size = Vector2(0, 380)
	_pj_list.item_selected.connect(func(i): _load_projectile(i))
	rail.add_child(_pj_list)

	var panel := _rail_panel(ui, true, sink)
	var footer := _last_footer
	panel.add_child(_label("SETTINGS", FS_HEADER, UiTheme.COLOR_ACCENT))
	_pj_status = _label("", FS_CAPTION, UiTheme.COLOR_FAINT)
	_pj_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pj_status.custom_minimum_size = Vector2(INFO_W - 60, 0)
	panel.add_child(_pj_status)
	_pj_form = VBoxContainer.new()
	_pj_form.add_theme_constant_override("separation", 6)
	panel.add_child(_pj_form)
	for spec in [["Fire ▶", _fire_projectile_preview], ["Save", _save_projectile], ["Copy GD", _copy_projectile]]:
		var b := _button(String(spec[0]), spec[1] as Callable)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(b)

	_tab_nodes[Tab.PROJECTILES] = sink


func _on_projectile_filter_changed() -> void:
	_refresh_projectile_list()
	if _tab == Tab.PROJECTILES:
		_ensure_proj_muzzle()   # side dictates muzzle position (player=bottom, enemy=top)


func _refresh_projectile_list() -> void:
	_clear_projectile_form()
	_pj_items = _projectile_inventory(_pj_side_dd.selected, _pj_kind_dd.selected)
	_pj_list.clear()
	for p in _pj_items:
		_pj_list.add_item(String(p).get_file())
	if _pj_list.item_count > 0:
		_pj_list.select(0)
		_load_projectile(0)
	else:
		_pj_status.text = "No %s %s projectiles found." % [
			["player", "enemy"][_pj_side_dd.selected],
			["bullet", "rocket/missile"][_pj_kind_dd.selected]]


# Inventory, derived from canonical sources (no replicated hardcoded list):
#   Enemy Bullet   → data/bullets/*.tres  (BulletVariant — stats live in the .tres)
#   everything else → scenes/projectiles/*.tscn scanned + classified by root-script chain + prefix.
func _projectile_inventory(side: int, kind: int) -> Array:
	var out: Array = []
	if side == Side.ENEMY and kind == Kind.BULLET:
		var d := DirAccess.open(ENEMY_BULLET_DIR)
		if d != null:
			for f in d.get_files():
				if f.ends_with(".tres"):
					out.append(ENEMY_BULLET_DIR + f)
		out.sort()
		return out
	var prefixes: Array = PLAYER_PREFIXES if side == Side.PLAYER else ENEMY_PREFIXES
	var dir := DirAccess.open(PROJECTILE_SCENE_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".tscn"):
			continue
		var ok_prefix := false
		for pre in prefixes:
			if f.begins_with(pre):
				ok_prefix = true
				break
		if not ok_prefix:
			continue
		var path: String = PROJECTILE_SCENE_DIR + f
		var sk: int = _classify_scene_kind(path)
		if sk == kind:
			out.append(path)
	out.sort()
	return out


# Classify a projectile scene by walking its root script chain: base_missile.gd → MISSILE,
# base_bullet.gd → BULLET, else -1. Instantiated un-parented so _ready never runs.
func _classify_scene_kind(path: String) -> int:
	var ps := load(path) as PackedScene
	if ps == null:
		return -1
	var inst := ps.instantiate()
	var kind := -1
	var sc: Script = inst.get_script()
	while sc != null:
		var fn := sc.resource_path.get_file()
		if fn == "base_missile.gd":
			kind = Kind.MISSILE
			break
		if fn == "base_bullet.gd":
			kind = Kind.BULLET
			break
		sc = sc.get_base_script()
	inst.free()
	return kind


func _load_projectile(idx: int) -> void:
	if idx < 0 or idx >= _pj_items.size():
		return
	_clear_projectile_form()
	_pj_path = _pj_items[idx]
	_pj_is_tres = _pj_path.ends_with(".tres")
	_pj_baseline = {}
	if _pj_is_tres:
		# The SAME shared BulletVariant the enemies use — edits live-reflect in the Enemy tab.
		_pj_edit_obj = load(_pj_path)
		_pj_status.text = "%s — enemy bullet variant. Save writes the .tres (live for all enemies)." % _pj_path.get_file()
	else:
		# Scene projectile: instantiate the root un-parented (so _ready/game logic doesn't fire) and
		# reflect its @exports. Save writes the changed root-node values back into the .tscn.
		var ps := load(_pj_path) as PackedScene
		_pj_edit_obj = ps.instantiate() if ps != null else null
		if _pj_edit_obj != null:
			for spec in _scalar_props(_pj_edit_obj):
				_pj_baseline[String(spec["name"])] = _pj_edit_obj.get(String(spec["name"]))
		_pj_status.text = "%s — scene projectile. Save writes the .tscn." % _pj_path.get_file()
	if _pj_edit_obj != null:
		_build_object_form(_pj_form, _pj_edit_obj, _override_fields_for(_pj_side_dd.selected, _pj_kind_dd.selected))


# Fields the firing layer (weapon Part) stamps at spawn, so tuning them on the projectile is inert.
# Flagged in the form so the tool is honest. Player bullets: speed+damage set from the cannon.
# Missiles: damage/damage_on_contact set from secondary_damage; player seekers set `guided`.
func _override_fields_for(side: int, kind: int) -> PackedStringArray:
	if kind == Kind.MISSILE:
		return PackedStringArray(["damage", "damage_on_contact", "guided"]) if side == Side.PLAYER \
			else PackedStringArray(["damage", "damage_on_contact"])
	if side == Side.PLAYER:
		return PackedStringArray(["speed", "damage"])
	return PackedStringArray()   # enemy bullet variant IS the data — nothing overridden


# Scalar @export props (int/float/bool/String/Color/Vector2) — the set the scene text-writer + the
# baseline diff operate on.
func _scalar_props(obj: Object) -> Array:
	var out: Array = []
	for prop in obj.get_property_list():
		var usage: int = int(prop.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var t: int = int(prop["type"])
		if t in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME, TYPE_COLOR, TYPE_VECTOR2]:
			out.append({"name": String(prop["name"]), "type": t})
	return out


# Reflection form: SpinBox/CheckBox/LineEdit/Color/enum per editable property. `overridden` props
# get a faint "(set by weapon Part)" tag so a dead tune reads as dead.
func _build_object_form(vbox: VBoxContainer, obj: Object, overridden: PackedStringArray) -> void:
	for prop in obj.get_property_list():
		var usage: int = int(prop.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var pname: String = String(prop["name"])
		var ptype: int = int(prop["type"])
		var hint: int = int(prop.get("hint", 0))
		var hint_str: String = String(prop.get("hint_string", ""))
		var val = obj.get(pname)
		var is_over: bool = pname in overridden
		var cap := pname + ("   (set by weapon Part)" if is_over else "")
		var cap_col := UiTheme.COLOR_FAINT
		match ptype:
			TYPE_INT, TYPE_FLOAT:
				if pname in RUNG_SPEED_FIELDS:
					# Rung-clamped velocity: only 60·k px/s up to the 480 (8 px/f) ceiling. Snapping
					# routes through Clarity (SSOT). Rockets/missiles author their travel speed here too.
					var snapped: float = clampf(Clarity.snap_to_rung(float(val)), Clarity.RUNG_STEP, Clarity.ABS_MAX_SPEED)
					var over_tag := "   (set by weapon Part)" if is_over else ""
					vbox.add_child(_label("%s  →  %s%s" % [pname, Clarity.label_for_speed(snapped), over_tag], FS_CAPTION, cap_col))
					var rsb := SpinBox.new()
					rsb.add_theme_font_override("font", UiTheme.active_font())
					rsb.add_theme_font_size_override("font_size", FS_BODY)
					rsb.custom_minimum_size = Vector2(0, 32)
					rsb.min_value = Clarity.RUNG_STEP
					rsb.max_value = Clarity.ABS_MAX_SPEED
					rsb.step = Clarity.RUNG_STEP
					rsb.value = snapped
					rsb.value_changed.connect(func(v):
						obj.set(pname, clampf(Clarity.snap_to_rung(v), Clarity.RUNG_STEP, Clarity.ABS_MAX_SPEED)))
					vbox.add_child(rsb)
				elif hint == PROPERTY_HINT_ENUM:
					var opts := hint_str.split(",")
					var dd := _dropdown(vbox, cap, opts)
					dd.select(clampi(int(val), 0, opts.size() - 1))
					dd.item_selected.connect(func(i): obj.set(pname, i))
				else:
					vbox.add_child(_label(cap, FS_CAPTION, cap_col))
					var sb := SpinBox.new()
					sb.add_theme_font_override("font", UiTheme.active_font())
					sb.add_theme_font_size_override("font_size", FS_BODY)
					sb.custom_minimum_size = Vector2(0, 32)
					sb.min_value = -100000
					sb.max_value = 100000
					sb.step = 1.0 if ptype == TYPE_INT else 0.05
					sb.allow_greater = true
					sb.allow_lesser = true
					sb.value = float(val)
					sb.value_changed.connect(func(v):
						obj.set(pname, int(v) if ptype == TYPE_INT else float(v)))
					vbox.add_child(sb)
			TYPE_BOOL:
				var cb := CheckBox.new()
				cb.text = cap
				cb.add_theme_font_override("font", UiTheme.active_font())
				cb.add_theme_font_size_override("font_size", FS_BODY)
				cb.button_pressed = bool(val)
				cb.toggled.connect(func(on): obj.set(pname, on))
				vbox.add_child(cb)
			TYPE_COLOR:
				vbox.add_child(_label(cap, FS_CAPTION, cap_col))
				var cp := ColorPickerButton.new()
				cp.custom_minimum_size = Vector2(0, 32)
				cp.color = val
				cp.color_changed.connect(func(c): obj.set(pname, c))
				vbox.add_child(cp)
			TYPE_STRING, TYPE_STRING_NAME:
				vbox.add_child(_label(cap, FS_CAPTION, cap_col))
				var le := LineEdit.new()
				le.add_theme_font_override("font", UiTheme.active_font())
				le.add_theme_font_size_override("font_size", FS_BODY)
				le.text = String(val)
				le.text_changed.connect(func(t): obj.set(pname, t))
				vbox.add_child(le)
			TYPE_VECTOR2:
				vbox.add_child(_label(cap, FS_CAPTION, cap_col))
				var hb := HBoxContainer.new()
				hb.add_theme_constant_override("separation", 6)
				for axis in ["x", "y"]:
					var vsb := SpinBox.new()
					vsb.add_theme_font_size_override("font_size", FS_BODY)
					vsb.custom_minimum_size = Vector2(90, 32)
					vsb.min_value = -100000
					vsb.max_value = 100000
					vsb.step = 0.5
					vsb.allow_greater = true
					vsb.allow_lesser = true
					vsb.prefix = axis + ":"
					vsb.value = float(val[axis])
					vsb.value_changed.connect(func(v):
						var cur: Vector2 = obj.get(pname)
						cur[axis] = float(v)
						obj.set(pname, cur))
					hb.add_child(vsb)
				vbox.add_child(hb)
			_:
				var shown := "—" if val == null else str(val).get_file() if (val is Resource and val.resource_path != "") else "(set)"
				vbox.add_child(_label("%s: %s" % [pname, shown], FS_CAPTION, UiTheme.COLOR_FAINT))


# Live-fire the selected projectile into the preview world so its motion + IMPACT/EXPLOSION reads.
# Player projectiles fire UP from the bottom muzzle at the top dummy; enemy projectiles fire DOWN
# from the top muzzle at the player ship.
func _fire_projectile_preview() -> void:
	if _world == null or _pj_path == "":
		return
	_ensure_proj_muzzle()
	var side: int = _pj_side_dd.selected
	var origin: Vector2 = _pj_muzzle.position
	if _pj_is_tres:
		# Enemy bullet variant — fire DOWN via the real Weapon path (resolves the scene + faction).
		var bv = load(_pj_path)
		if bv == null:
			return
		var w := Weapon.new()
		w.fire_pattern = Weapon.FirePattern.SINGLE
		w.aim = Weapon.Aim.STRAIGHT_DOWN
		w.payload = bv
		w.fire(_pj_muzzle)
		return
	var ps := load(_pj_path) as PackedScene
	if ps == null:
		return
	var b = ps.instantiate()
	_world.add_child(b)
	# Give a visible damage so the dummy flashes / DPS ticks.
	if "damage" in b and int(b.damage) <= 0:
		b.damage = 3
	if "damage_on_contact" in b and int(b.damage_on_contact) <= 0:
		b.damage_on_contact = 3
	var dir := Vector2.UP if side == Side.PLAYER else Vector2.DOWN
	if _pj_kind_dd.selected == Kind.BULLET:
		if "speed" in b and absf(float(b.speed)) < 1.0:
			b.speed = 360.0
		if b.has_method("start"):
			b.start(origin, dir)
	else:
		# Missiles read their own initial_dir/target_group from the scene; just launch from the muzzle.
		if b.has_method("start"):
			b.start(origin)


# Visible dummy weapon the projectiles fire from — repositioned per Side (player=bottom firing up,
# enemy=top firing down) so the travel reads correctly against the right target.
func _ensure_proj_muzzle() -> void:
	if _world == null:
		return
	if _pj_muzzle == null or not is_instance_valid(_pj_muzzle):
		_pj_muzzle = Node2D.new()
		_pj_muzzle.name = "ProjMuzzle"
		var body := Polygon2D.new()
		body.polygon = PackedVector2Array([Vector2(-6, -5), Vector2(6, -5), Vector2(4, 4), Vector2(-4, 4)])
		body.color = Color(0.55, 0.72, 0.95)
		_pj_muzzle.add_child(body)
		var barrel := ColorRect.new()
		barrel.color = Color(0.85, 0.92, 1.0)
		barrel.size = Vector2(3, 6)
		barrel.position = Vector2(-1.5, 3)
		_pj_muzzle.add_child(barrel)
		_world.add_child(_pj_muzzle)
	var player_side: bool = _pj_side_dd.selected == Side.PLAYER
	_pj_muzzle.position = Vector2(Playfield.CENTER.x, (Playfield.Y_MAX - 44.0) if player_side else (Playfield.Y_MIN + 44.0))
	_pj_muzzle.rotation = 0.0 if player_side else PI


func _clear_proj_muzzle() -> void:
	if _pj_muzzle != null and is_instance_valid(_pj_muzzle):
		_pj_muzzle.queue_free()
	_pj_muzzle = null


func _save_projectile() -> void:
	if _pj_edit_obj == null or _pj_path == "":
		return
	if not _can_write_res():
		_pj_status.text = "Save unavailable — res:// is read-only outside the editor."
		return
	if _pj_is_tres:
		var res := _pj_edit_obj as Resource
		if res == null or res.resource_path == "":
			_pj_status.text = "No resource path to save."
			return
		var err := ResourceSaver.save(res, res.resource_path)
		_pj_status.text = ("Saved %s ✓ (live for all enemies)" % res.resource_path.get_file()) if err == OK else ("Save failed (err %d)" % err)
		return
	# Scene projectile: write only the root-node props that changed from the on-disk baseline.
	var changed: Dictionary = {}
	for spec in _scalar_props(_pj_edit_obj):
		var n: String = String(spec["name"])
		var cur = _pj_edit_obj.get(n)
		if not _pj_baseline.has(n) or not _values_equal(cur, _pj_baseline[n]):
			changed[n] = cur
	if changed.is_empty():
		_pj_status.text = "No changes to save."
		return
	var ok := _write_scene_root_props(_pj_path, changed)
	if ok:
		ResourceLoader.load(_pj_path, "", ResourceLoader.CACHE_MODE_REPLACE)   # refresh cache for next fire
		# Rebase the baseline so a second save doesn't re-flag the same fields.
		for k in changed.keys():
			_pj_baseline[k] = changed[k]
		_pj_status.text = "Saved → %s ✓  (%d field%s)" % [_pj_path.get_file(), changed.size(), "" if changed.size() == 1 else "s"]
	else:
		_pj_status.text = "Save FAILED — could not rewrite %s." % _pj_path.get_file()


# Rewrite `key = value` lines in the ROOT [node] block of a .tscn (the root has no `parent=`).
# Only the changed scalar props are touched; every other line (ext_resources, children, sub-
# resources, script) is preserved verbatim. Targeted text edit — safer than repacking a live
# instance (whose runtime children would get baked in).
func _write_scene_root_props(path: String, changed: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var lines := text.split("\n")
	var root_hdr := -1
	for i in lines.size():
		var ls := String(lines[i]).strip_edges()
		if ls.begins_with("[node ") and not ("parent=" in ls):
			root_hdr = i
			break
	if root_hdr < 0:
		return false
	# Region = property lines from root_hdr+1 up to the next section header.
	var region_end := lines.size()
	for i in range(root_hdr + 1, lines.size()):
		if String(lines[i]).strip_edges().begins_with("["):
			region_end = i
			break
	var out: Array = []
	for i in lines.size():
		out.append(lines[i])
	var pending: Dictionary = changed.duplicate()
	for i in range(root_hdr + 1, region_end):
		var name_part := String(out[i]).get_slice("=", 0).strip_edges()
		if pending.has(name_part):
			out[i] = "%s = %s" % [name_part, _fmt_tscn(pending[name_part])]
			pending.erase(name_part)
	# Any props not already present get appended at the end of the root block.
	if not pending.is_empty():
		var insert_at := region_end
		var addition: Array = []
		for k in pending.keys():
			addition.append("%s = %s" % [k, _fmt_tscn(pending[k])])
		var merged: Array = []
		for i in insert_at:
			merged.append(out[i])
		for a in addition:
			merged.append(a)
		for i in range(insert_at, out.size()):
			merged.append(out[i])
		out = merged
	var wf := FileAccess.open(path, FileAccess.WRITE)
	if wf == null:
		return false
	wf.store_string("\n".join(PackedStringArray(out.map(func(x): return String(x)))))
	wf.close()
	return true


# Format a value as a .tscn literal (matches Godot's text serialization for the scalar types).
func _fmt_tscn(v) -> String:
	match typeof(v):
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(int(v))
		TYPE_FLOAT:
			var s := String.num(float(v), 4)
			if not ("." in s or "e" in s):
				s += ".0"
			return s
		TYPE_STRING:
			return "\"%s\"" % String(v)
		TYPE_STRING_NAME:
			return "&\"%s\"" % String(v)
		TYPE_COLOR:
			var c: Color = v
			return "Color(%s, %s, %s, %s)" % [String.num(c.r, 4), String.num(c.g, 4), String.num(c.b, 4), String.num(c.a, 4)]
		TYPE_VECTOR2:
			var vec: Vector2 = v
			return "Vector2(%s, %s)" % [String.num(vec.x, 4), String.num(vec.y, 4)]
	return str(v)


func _values_equal(a, b) -> bool:
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return is_equal_approx(float(a), float(b))
	return a == b


func _copy_projectile() -> void:
	if _pj_edit_obj == null:
		return
	var txt := "# Weapon Lab — projectile settings (%s)\n" % _pj_path.get_file()
	for spec in _scalar_props(_pj_edit_obj):
		var pname: String = String(spec["name"])
		var val = _pj_edit_obj.get(pname)
		txt += "%s = %s\n" % [pname, _fmt_tscn(val)]
	DisplayServer.clipboard_set(txt)
	_pj_status.text = "Copied %d-line snippet to clipboard." % txt.split("\n").size()


func _clear_projectile_form() -> void:
	if _pj_form != null:
		for c in _pj_form.get_children():
			c.queue_free()
	# Free a scene instance we own (not the shared enemy .tres).
	if _pj_edit_obj != null and not _pj_is_tres and _pj_edit_obj is Node and not (_pj_edit_obj as Node).is_inside_tree():
		(_pj_edit_obj as Node).free()
	_pj_edit_obj = null
	_pj_baseline = {}


# ---- Enemy tab -----------------------------------------------------------

func _build_enemy_tab(ui: CanvasLayer) -> void:
	var sink: Array = []
	var rail := _rail_panel(ui, false, sink)
	rail.add_child(_label("ENEMY WEAPON", FS_HEADER, UiTheme.COLOR_ACCENT))
	rail.add_child(HSeparator.new())
	_e_fire_dd = _dropdown(rail, "Fire pattern", FIRE_PATTERNS)
	_e_fire_dd.item_selected.connect(func(_i): _spawn_enemy_host())
	_e_aim_dd = _dropdown(rail, "Aim", AIMS)
	_e_aim_dd.item_selected.connect(func(_i): _spawn_enemy_host())
	_e_payload_dd = _dropdown(rail, "Payload", PAYLOADS.keys())
	_e_payload_dd.item_selected.connect(func(_i): _spawn_enemy_host())
	rail.add_child(_label("Edit a payload's numbers in the Projectiles tab\n(Enemy · Bullet) — changes show live here.", FS_CAPTION, UiTheme.COLOR_FAINT))

	var panel := _rail_panel(ui, true, sink)
	panel.add_child(_label("WEAPON", FS_HEADER, UiTheme.COLOR_ACCENT))
	_e_info = _rich(panel)
	panel.add_child(HSeparator.new())
	panel.add_child(_label("Bullet sprite", FS_CAPTION, UiTheme.COLOR_FAINT))
	_e_bullet_tex = _tex_rect(panel)

	_tab_nodes[Tab.ENEMY] = sink


func _spawn_enemy_host() -> void:
	_clear_enemy_host()
	var ps := load(ENEMY_HOST) as PackedScene
	if ps == null:
		return
	var inst := ps.instantiate()
	if "movement" in inst:
		inst.movement = null
	if "auto_rotate" in inst:
		inst.auto_rotate = false
	if "shoot_pattern" in inst:
		inst.shoot_pattern = _build_enemy_weapon()
	if "fire_on_phase" in inst:
		inst.fire_on_phase = ""
	if "fire_interval_min" in inst:
		inst.fire_interval_min = 0.5
	if "fire_interval_max" in inst:
		inst.fire_interval_max = 0.9
	var pos := Vector2(Playfield.CENTER.x, Playfield.Y_MIN + 40.0)
	if inst is Node2D:
		(inst as Node2D).position = pos
	_world.add_child(inst)
	_enemy_host = inst
	if inst.has_method("start"):
		inst.start(pos)
	if "external_control" in inst:
		inst.external_control = not _autofire
	_refresh_enemy_info()


func _build_enemy_weapon() -> Weapon:
	var w := Weapon.new()
	w.fire_pattern = Weapon.FirePattern[FIRE_PATTERNS[_e_fire_dd.selected]]
	w.aim = Weapon.Aim[AIMS[_e_aim_dd.selected]]
	var pkeys: Array = PAYLOADS.keys()
	w.payload = PAYLOADS[String(pkeys[_e_payload_dd.selected])]
	return w


func _refresh_enemy_info() -> void:
	if _e_info == null:
		return
	var pkeys: Array = PAYLOADS.keys()
	var pname: String = String(pkeys[_e_payload_dd.selected])
	var bv = PAYLOADS[pname]
	var lines: PackedStringArray = []
	lines.append("[b]%s[/b]" % FIRE_PATTERNS[_e_fire_dd.selected])
	lines.append("Aim: %s" % AIMS[_e_aim_dd.selected])
	lines.append("Payload: %s" % pname)
	if bv != null:
		lines.append("Speed %.0f   Damage %d" % [float(bv.speed), int(bv.damage)])
		var sfx_kind: int = int(bv.enemy_sfx_kind) if "enemy_sfx_kind" in bv else -1
		lines.append("SFX kind: %d" % sfx_kind)
		var tex: Texture2D = bv.static_texture if ("static_texture" in bv and bv.static_texture != null) else null
		_e_bullet_tex.texture = tex
	_e_info.text = "\n".join(lines)


func _clear_enemy_host() -> void:
	if _enemy_host != null and is_instance_valid(_enemy_host):
		_enemy_host.queue_free()
	_enemy_host = null


# ---- Tab switching -------------------------------------------------------

func _select_tab(idx: int) -> void:
	_tab = idx
	for t in _tab_nodes.keys():
		var is_vis: bool = t == idx
		for n in _tab_nodes[t]:
			if is_instance_valid(n):
				n.visible = is_vis
	# Reconfigure the arena for the tab.
	if idx != Tab.PROJECTILES:
		_clear_proj_muzzle()
	if _pj_fire_timer != null:
		_pj_fire_timer.stop()
	if idx == Tab.ENEMY:
		_set_autofire_state(_autofire)
		_spawn_enemy_host()
		_refresh_enemy_info()
	else:
		_clear_enemy_host()
		if idx == Tab.WEAPONS:
			_set_autofire_state(_autofire)
		else:
			_refresh_projectile_list()
			_ensure_proj_muzzle()
			_set_autofire_state(_autofire)


# ---- Firing controls -----------------------------------------------------

func _on_autofire_toggled(on: bool) -> void:
	_autofire = on
	_set_autofire_state(on)


func _set_autofire_state(on: bool) -> void:
	if has_node("/root/Settings"):
		var s = get_node("/root/Settings")
		if s.has_method("set_autofire"):
			s.set_autofire(on and _tab == Tab.WEAPONS)
	if _enemy_host != null and is_instance_valid(_enemy_host) and "external_control" in _enemy_host:
		_enemy_host.external_control = not (on and _tab == Tab.ENEMY)
	if _tab == Tab.PROJECTILES:
		if _pj_fire_timer == null:
			_pj_fire_timer = Timer.new()
			_pj_fire_timer.wait_time = 0.5
			_pj_fire_timer.timeout.connect(_fire_projectile_preview)
			add_child(_pj_fire_timer)
		if on:
			_pj_fire_timer.start()
		else:
			_pj_fire_timer.stop()
	elif _pj_fire_timer != null:
		_pj_fire_timer.stop()


func _on_fire_once() -> void:
	if _tab == Tab.WEAPONS:
		if _player != null and is_instance_valid(_player) and _player.has_method("fire_primary"):
			# Fire the whole loadout so secondary/super previews fire too.
			_player.fire_primary()
			if _p_slot != SlotTypes.SlotType.CANNON:
				if _p_slot == SlotTypes.SlotType.HARDPOINT_WING and _player.has_method("fire_secondary"):
					_player.fire_secondary()
				elif _player.has_method("fire_super"):
					_player.fire_super()
	elif _tab == Tab.PROJECTILES:
		_fire_projectile_preview()
	elif _tab == Tab.ENEMY:
		if _enemy_host != null and is_instance_valid(_enemy_host) and _enemy_host.shoot_pattern != null:
			_enemy_host.shoot_pattern.fire(_enemy_host)


# ---- Helpers -------------------------------------------------------------

# res:// is writable only from the editor/dev context (exported builds pack it read-only).
func _can_write_res() -> bool:
	return OS.has_feature("editor")


func _parts_for_slot(slot: int) -> Array:
	var pool := PartCatalog._all_pool()
	var out: Array = []
	var seen: Dictionary = {}
	for entry in pool:
		if int(entry["slot"]) != slot:
			continue
		var f: String = String(entry["factory"])
		if not seen.has(f):
			out.append(f)
			seen[f] = true
	return out


func _display_name_for_factory(factory: String, slot: int) -> String:
	var part = PartCatalog._make_by_name(factory, slot)
	if part != null and "display_name" in part:
		var dn: String = String(part.display_name)
		if dn != "" and dn != "Unnamed Part":
			return dn
	var s := factory
	if s.begins_with("_make_"):
		s = s.substr(6)
	return s.replace("_", " ").capitalize()


func _live_loadout():
	if _player == null or not is_instance_valid(_player) or not _player.has_node("Loadout"):
		return null
	return _player.get_node("Loadout")


func _first_texture_of_scene(ps: PackedScene) -> Texture2D:
	if ps == null:
		return null
	var state := ps.get_state()
	for i in state.get_node_count():
		if state.get_node_type(i) != &"Sprite2D" and state.get_node_type(i) != &"AnimatedSprite2D":
			continue
		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) == &"texture":
				var tex := state.get_node_property_value(i, j) as Texture2D
				if tex != null:
					return tex
	return null


func _dropdown(vbox: VBoxContainer, caption: String, items) -> OptionButton:
	vbox.add_child(_label(caption, FS_CAPTION, UiTheme.COLOR_FAINT))
	var dd := OptionButton.new()
	dd.add_theme_font_override("font", UiTheme.active_font())
	dd.add_theme_font_size_override("font_size", FS_BODY)
	dd.custom_minimum_size = Vector2(0, 34)
	for it in items:
		dd.add_item(String(it))
	vbox.add_child(dd)
	return dd


func _rich(vbox: VBoxContainer) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.add_theme_font_override("normal_font", UiTheme.active_font())
	r.add_theme_font_override("bold_font", UiTheme.active_font())
	r.add_theme_font_size_override("normal_font_size", FS_BODY)
	r.add_theme_font_size_override("bold_font_size", FS_BODY)
	r.add_theme_color_override("default_color", UiTheme.COLOR_TEXT)
	r.custom_minimum_size = Vector2(INFO_W - 60, 120)
	vbox.add_child(r)
	return r


func _tex_rect(vbox: VBoxContainer) -> TextureRect:
	var t := TextureRect.new()
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.custom_minimum_size = Vector2(0, 80)
	vbox.add_child(t)
	return t


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.active_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	l.add_theme_constant_override("outline_size", 3)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	UiTheme.style_button(b, true)
	b.add_theme_font_size_override("font_size", FS_BODY)
	b.custom_minimum_size = Vector2(0, 36)
	b.pressed.connect(cb)
	return b


func _panel(pos: Vector2, sz: Vector2) -> Panel:
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = pos
	panel.size = sz
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _on_back() -> void:
	if has_node("/root/Settings"):
		var s = get_node("/root/Settings")
		if s.has_method("set_autofire"):
			s.set_autofire(_orig_autofire)
	var scope := _hd_scope
	_hd_scope = null
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn", func(): HdScreen.drop(scope))


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
