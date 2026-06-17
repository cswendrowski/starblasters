extends Control

# Weapon Lab (Roman 2026-06-11) — replaces the old Weapons editor. A single HD
# bench to SEE and TUNE every weapon in the game, across three tabs sharing one
# native 480×270 SubViewport play area (the proven Hangar / Enemy Bench skeleton):
#
#   PLAYER  — equip any player cannon/secondary/super on the LIVE ship (bottom),
#             firing UP at a dummy enemy. Filter by weapon group, pick Mk, see the
#             bullet sprite + fire SFX + weapon style. Autofire toggle + Fire (Z).
#   ENEMY   — build an enemy Weapon (fire pattern / aim / payload) on a stationary
#             host (top) firing DOWN at the player. Same sound/sprite/bullet readout,
#             same autofire + manual-fire controls.
#   BULLETS — tune bullet settings. Enemy BulletVariant .tres are fully editable +
#             SAVED to disk (and live-reflect into the Enemy tab, since they're the
#             same shared resources). Player bullet scenes are reflected for author +
#             Copy-GDScript (their live stats are authored on the Part, not here).
#
# The SubViewportContainer.stretch_shrink = 4 is the load-bearing knob that keeps the
# play area native-480 under the HD scope (see docs/godot-patterns.md "HD SubViewport
# host"; the recurring "play area in the corner" regression). Esc / Back → dev menu.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const DummyTargetScript = preload("res://scripts/dev/hangar_dummy_target.gd")
const Playfield = preload("res://scripts/systems/playfield.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const WS = preload("res://scripts/weapons/WeaponStyle.gd")
const Weapon = preload("res://scripts/enemies/shoot_patterns/weapon.gd")
const EnemyRoster = preload("res://scripts/levels/enemy_roster.gd")

# A stationary enemy_core chassis to host the previewed enemy weapon (movement is
# nulled so it sits at the top and just fires).
const ENEMY_HOST := "res://scenes/enemies/core/enemy_hover.tscn"

enum Tab { PLAYER, ENEMY, BULLETS }

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
const PAYLOADS := {
	"Basic": EnemyRoster.BV_Basic, "Spread Pellet": EnemyRoster.BV_SpreadPellet,
	"Aimed Sniper": EnemyRoster.BV_AimedSniper, "Burst Round": EnemyRoster.BV_BurstRound,
	"Plasma Orb": EnemyRoster.BV_PlasmaOrb, "Heavy Slug": EnemyRoster.BV_HeavySlug,
	"Drop Pellet": EnemyRoster.BV_DropPellet,
}

# Bullet-tab resource pools.
const ENEMY_BULLET_DIR := "res://data/bullets/"
const PLAYER_BULLET_SCENES := [
	"res://scenes/projectiles/bullet_blaster.tscn",
	"res://scenes/projectiles/bullet_blaster_heavy.tscn",
	"res://scenes/projectiles/bullet_autocannon.tscn",
	"res://scenes/projectiles/bullet_minigun.tscn",
	"res://scenes/projectiles/bullet_auto_laser.tscn",
	"res://scenes/projectiles/bullet_rotary_laser.tscn",
	"res://scenes/projectiles/bullet_wave_small.tscn",
	"res://scenes/projectiles/bullet_wave_large.tscn",
	"res://scenes/projectiles/bullet_swarm.tscn",
]

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

# ---- State ---------------------------------------------------------------

var _hd_scope: HdViewportScope = null
var _preview_vp: SubViewport = null
var _world: Node2D = null
var _player: Node = null
var _top_dummy: Area2D = null     # static enemy target (player/bullets tabs)
var _enemy_host: Node = null      # live firing enemy (enemy tab)
var _orig_autofire: bool = false
var _tab: int = Tab.PLAYER

# Tab content roots (rail + panel per tab, shown/hidden together).
var _tab_nodes: Dictionary = {}   # Tab -> Array[Control]

# Player tab widgets.
var _p_group_dd: OptionButton = null
var _p_list: ItemList = null
var _p_factories: Array = []
var _p_mark: HSlider = null
var _p_mark_lbl: Label = null
var _p_info: RichTextLabel = null
var _p_bullet_tex: TextureRect = null

# Player-weapon STAT TUNING (Roman 2026-06-11): editable stat spinboxes on the live
# ship + a Save that writes user://tuners/player_weapons.json — which the integrator
# (tools/apply_player_weapon_tunes.gd) catches and writes into the weapons' .tres.
const PLAYER_WEAPONS_CFG := "user://tuners/player_weapons.json"
# Runtime/identity fields to hide from the stat editors (not designer-tunable stats).
const _STAT_SKIP := ["mark", "max_mark", "current_ammo", "ammo_max", "slot_type"]
var _p_part = null                      # the live Part instance currently tuned
var _p_slot: int = -1
var _p_factory: String = ""
var _p_stat_box: VBoxContainer = null   # holds one row per tunable stat
var _p_stat_status: Label = null
var _p_overrides: Dictionary = {}       # factory -> {stat: value}, persisted to disk

# Enemy tab widgets.
var _e_fire_dd: OptionButton = null
var _e_aim_dd: OptionButton = null
var _e_payload_dd: OptionButton = null
var _e_info: RichTextLabel = null
var _e_bullet_tex: TextureRect = null

# Bullets tab widgets.
var _b_kind_dd: OptionButton = null   # 0 = Enemy variants, 1 = Player scenes
var _b_list: ItemList = null
var _b_items: Array = []              # paths
var _b_form: VBoxContainer = null
var _b_status: Label = null
var _b_edit_obj: Object = null        # the resource/instance being edited
var _b_is_enemy: bool = true

# Shared firing state.
var _autofire: bool = false


func _ready() -> void:
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
	_load_player_overrides()   # tuned stats persist across sessions
	_select_tab(Tab.PLAYER)
	_refresh_player_list()


# ---- Playspace -----------------------------------------------------------

func _build_playspace() -> void:
	var sub_container := SubViewportContainer.new()
	sub_container.stretch = true
	# stretch_shrink=4 keeps the viewport native 480×270 under the 1920×1080 HD scope.
	# Default 1 would force it to 1920×1080 and render the 480 content in a corner —
	# the recurring regression (docs/godot-patterns.md "HD SubViewport host").
	sub_container.stretch_shrink = 4
	sub_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sub_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub_container)

	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(480, 270)
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_vp.handle_input_locally = false
	# HDR-2D parity: match the project's hdr_2d root or additive blends (muzzle flashes / bullet
	# glow) composite in the wrong colour space. (Roman 2026-06-11; docs/godot-patterns.md.)
	_preview_vp.use_hdr_2d = bool(ProjectSettings.get_setting("rendering/viewport/hdr_2d", false))
	sub_container.add_child(_preview_vp)

	# Opaque background → on a CanvasLayer BEHIND the gameplay. Bullets + glow halos render at
	# z_index=-1; a z=0 band in the same canvas would hide them. (Roman 2026-06-11; see hangar.gd.)
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
	_preview_vp.add_child(_world)

	# 2D audio listener so the player's per-ship loops (MG/AC/rotary) are audible.
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
	back.position = Vector2(1920 - MARGIN - 120, 14)
	back.size = Vector2(120, 40)
	UiTheme.style_button(back, true)
	back.add_theme_font_size_override("font_size", FS_BODY)
	back.pressed.connect(_on_back)
	ui.add_child(back)

	var tabs := TabBar.new()
	tabs.position = Vector2(MARGIN + 320, TABBAR_Y)
	tabs.add_theme_font_override("font", UiTheme.active_font())
	tabs.add_theme_font_size_override("font_size", FS_BODY)
	tabs.add_tab("Player")
	tabs.add_tab("Enemy")
	tabs.add_tab("Bullets")
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

	_build_player_tab(ui)
	_build_enemy_tab(ui)
	_build_bullets_tab(ui)


# Builds a translucent panel + a scrolling VBox. Appends the two top-level nodes
# (panel bg + scroll) to `sink` so the caller can toggle them per tab. Returns the vbox.
func _rail_panel(ui: CanvasLayer, right: bool, sink: Array) -> VBoxContainer:
	var w := INFO_W if right else RAIL_W
	var x := (1920 - MARGIN - w) if right else MARGIN
	var y := TABBAR_Y + 84
	var h := 1080 - y - MARGIN
	var panel := _panel(Vector2(x, y), Vector2(w, h))
	ui.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(x + 14, y + 12)
	scroll.size = Vector2(w - 28, h - 24)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(w - 44, 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)
	sink.append(panel)
	sink.append(scroll)
	return vbox


# ---- Player tab ----------------------------------------------------------

func _build_player_tab(ui: CanvasLayer) -> void:
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
	_p_group_dd.item_selected.connect(func(_i): _refresh_player_list())
	rail.add_child(_p_group_dd)

	_p_list = ItemList.new()
	_p_list.add_theme_font_override("font", UiTheme.active_font())
	_p_list.add_theme_font_size_override("font_size", FS_BODY)
	_p_list.custom_minimum_size = Vector2(0, 360)
	_p_list.item_selected.connect(func(_i): _equip_player())
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
		_equip_player())
	mark_row.add_child(_p_mark)

	var panel := _rail_panel(ui, true, sink)
	panel.add_child(_label("EQUIPPED", FS_HEADER, UiTheme.COLOR_ACCENT))
	_p_info = _rich(panel)
	panel.add_child(HSeparator.new())
	panel.add_child(_label("Bullet sprite", FS_CAPTION, UiTheme.COLOR_FAINT))
	_p_bullet_tex = _tex_rect(panel)

	# Live stat tuning (Roman 2026-06-11).
	panel.add_child(HSeparator.new())
	panel.add_child(_label("STATS — edit live, then Save", FS_CAPTION, UiTheme.COLOR_ACCENT))
	_p_stat_box = VBoxContainer.new()
	_p_stat_box.add_theme_constant_override("separation", 4)
	panel.add_child(_p_stat_box)
	var pbtns := HBoxContainer.new()
	pbtns.add_theme_constant_override("separation", 8)
	panel.add_child(pbtns)
	pbtns.add_child(_button("Save", _save_player_overrides))
	pbtns.add_child(_button("Reset", _reset_player_stats))
	pbtns.add_child(_button("Copy .tres", _copy_tres_block))
	_p_stat_status = _label("", FS_CAPTION, UiTheme.COLOR_FAINT)
	_p_stat_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_p_stat_status.custom_minimum_size = Vector2(INFO_W - 60, 0)
	panel.add_child(_p_stat_status)

	_tab_nodes[Tab.PLAYER] = sink


func _refresh_player_list() -> void:
	if _p_list == null:
		return
	_p_list.clear()
	var slot: int = int(WEAPON_GROUPS[_p_group_dd.selected]["slot"])
	_p_factories = _parts_for_slot(slot)
	for f in _p_factories:
		_p_list.add_item(_display_name_for_factory(f, slot))
	if _p_list.item_count > 0:
		_p_list.select(0)
		_equip_player()


func _equip_player() -> void:
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
	_refresh_player_info(part)
	_rebuild_stat_editors(part)


# Build a fresh Part with the current Mark + any saved/unsaved stat overrides applied.
func _build_tuned_part(factory: String, slot: int):
	var part = PartCatalog._make_by_name(factory, slot)
	if part == null:
		return null
	part.mark = int(_p_mark.value)
	_apply_overrides_to_part(factory, part)
	return part


# Stamp the tuned override values onto a freshly-built Part (before it's equipped).
func _apply_overrides_to_part(factory: String, part) -> void:
	if not _p_overrides.has(factory):
		return
	for stat in (_p_overrides[factory] as Dictionary).keys():
		if stat in part:
			part.set(stat, _p_overrides[factory][stat])


# Equip mechanics, factored out so a stat tweak can re-equip a fresh tuned Part WITHOUT
# rebuilding the editor widgets (which would steal focus mid-edit).
func _equip_part_on_player(part, slot: int) -> void:
	var loadout = _live_loadout()
	if slot == SlotTypes.SlotType.CANNON:
		# Bench cannon equip: keep active_cannon_idx 0 (infinite blaster path, no
		# ammo-revert) and apply LIVE so style/damage/bullet take effect. (See the
		# Hangar's _on_apply_part for the full rationale.)
		if has_node("/root/Run"):
			get_node("/root/Run").active_cannon_idx = 0
		if loadout != null:
			loadout.equip(SlotTypes.SlotType.CANNON, part)
	else:
		if has_node("/root/Run"):
			get_node("/root/Run").equip_part(part)
		if loadout != null:
			loadout.equip(slot, part)
		# Top off secondary ammo / super charges so the bench fires freely.
		if "secondary_ammo" in _player and int(_player.secondary_ammo_max) > 0:
			_player.secondary_ammo = int(_player.secondary_ammo_max)
		if "super_charges" in _player and "max_super_charges" in _player:
			_player.super_charges = int(_player.max_super_charges)


# ---- Player-weapon stat tuning (Roman 2026-06-11) ------------------------

# Numeric/bool @export stats on the Part that are designer-tunable (skips runtime +
# identity fields). Same surface the .tres single-source-of-truth persists.
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


# Rebuild the stat-editor rows for the equipped Part (one SpinBox/CheckButton each).
func _rebuild_stat_editors(part) -> void:
	if _p_stat_box == null:
		return
	for c in _p_stat_box.get_children():
		c.queue_free()
	for spec in _tunable_stats(part):
		var stat: String = String(spec["name"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := _label(stat, FS_CAPTION, UiTheme.COLOR_TEXT)
		lbl.custom_minimum_size = Vector2(150, 0)
		row.add_child(lbl)
		if int(spec["type"]) == TYPE_BOOL:
			var cb := CheckButton.new()
			cb.button_pressed = bool(part.get(stat))
			cb.toggled.connect(func(v): _on_stat_changed(stat, v))
			row.add_child(cb)
		else:
			var sb := SpinBox.new()
			var is_float: bool = int(spec["type"]) == TYPE_FLOAT
			sb.step = 0.01 if is_float else 1.0
			sb.min_value = -9999.0
			sb.max_value = 99999.0
			sb.value = float(part.get(stat))
			sb.custom_minimum_size = Vector2(110, 0)
			sb.value_changed.connect(func(v): _on_stat_changed(stat, v if is_float else int(round(v))))
			row.add_child(sb)
		_p_stat_box.add_child(row)


# A stat changed: record the override, re-equip a fresh tuned Part on the live ship so
# the change is felt immediately (no editor rebuild — keeps focus).
func _on_stat_changed(stat: String, value) -> void:
	if not _p_overrides.has(_p_factory):
		_p_overrides[_p_factory] = {}
	_p_overrides[_p_factory][stat] = value
	var part = _build_tuned_part(_p_factory, _p_slot)
	if part != null:
		_p_part = part
		_equip_part_on_player(part, _p_slot)
		_refresh_player_info(part)
	if _p_stat_status:
		_p_stat_status.text = "%s = %s  (unsaved — Save to persist)" % [stat, str(value)]


func _reset_player_stats() -> void:
	_p_overrides.erase(_p_factory)
	_equip_player()  # full rebuild from the .tres defaults
	if _p_stat_status:
		_p_stat_status.text = "Reset %s to .tres defaults." % _p_factory


func _save_player_overrides() -> void:
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(PLAYER_WEAPONS_CFG, FileAccess.WRITE)
	if f == null:
		if _p_stat_status:
			_p_stat_status.text = "Save FAILED (can't open file)."
		return
	f.store_string(JSON.stringify(_p_overrides, "  ", true))
	f.close()
	if _p_stat_status:
		_p_stat_status.text = "Saved → %s  (run tools/apply_player_weapon_tunes.gd to write the .tres)" % PLAYER_WEAPONS_CFG


func _load_player_overrides() -> void:
	if not FileAccess.file_exists(PLAYER_WEAPONS_CFG):
		return
	var f := FileAccess.open(PLAYER_WEAPONS_CFG, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_p_overrides = parsed


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


func _refresh_player_info(part) -> void:
	if _p_info == null:
		return
	var dn: String = String(part.display_name) if "display_name" in part else "?"
	var lines: PackedStringArray = []
	lines.append("[b]%s[/b]  Mk.%d" % [dn, int(part.mark)])
	# Style + SFX read off the live player (the equip wrote them).
	var style: int = int(_player.weapon_style) if "weapon_style" in _player else 0
	lines.append("Style: %s" % (STYLE_NAMES[style] if style < STYLE_NAMES.size() else str(style)))
	var sfx: int = int(_player.fire_sfx_kind) if "fire_sfx_kind" in _player else -1
	lines.append("Fire SFX: %s" % WS.sfx_kind_string(sfx))
	# Bullet scene.
	var bscene: PackedScene = _player.bullet_scene if "bullet_scene" in _player else null
	if bscene != null:
		lines.append("Bullet: %s" % bscene.resource_path.get_file())
		_p_bullet_tex.texture = _first_texture_of_scene(bscene)
	else:
		lines.append("Bullet: (hitscan / none)")
		_p_bullet_tex.texture = null
	_p_info.text = "\n".join(lines)


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
	rail.add_child(_label("Edit a payload's numbers in the Bullets tab —\nchanges show live here.", FS_CAPTION, UiTheme.COLOR_FAINT))

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
		inst.movement = null   # stationary so it sits at the top and just fires
	if "auto_rotate" in inst:
		inst.auto_rotate = false   # static enemy: don't let the anchor-tween rotate it to face up
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
	if not _autofire and inst.has_node("ShootTimer"):
		inst.get_node("ShootTimer").stop()
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


# ---- Bullets tab ---------------------------------------------------------

func _build_bullets_tab(ui: CanvasLayer) -> void:
	var sink: Array = []
	var rail := _rail_panel(ui, false, sink)
	rail.add_child(_label("BULLETS", FS_HEADER, UiTheme.COLOR_ACCENT))
	rail.add_child(HSeparator.new())
	_b_kind_dd = _dropdown(rail, "Kind", ["Enemy variants (.tres)", "Player bullets (scene)"])
	_b_kind_dd.item_selected.connect(func(_i): _refresh_bullet_list())
	_b_list = ItemList.new()
	_b_list.add_theme_font_override("font", UiTheme.active_font())
	_b_list.add_theme_font_size_override("font_size", FS_BODY)
	_b_list.custom_minimum_size = Vector2(0, 420)
	_b_list.item_selected.connect(func(i): _load_bullet(i))
	rail.add_child(_b_list)

	var panel := _rail_panel(ui, true, sink)
	panel.add_child(_label("SETTINGS", FS_HEADER, UiTheme.COLOR_ACCENT))
	_b_status = _label("", FS_CAPTION, UiTheme.COLOR_FAINT)
	_b_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_b_status.custom_minimum_size = Vector2(INFO_W - 60, 0)
	panel.add_child(_b_status)
	_b_form = VBoxContainer.new()
	_b_form.add_theme_constant_override("separation", 6)
	panel.add_child(_b_form)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	panel.add_child(btn_row)
	btn_row.add_child(_button("Save", _on_bullet_save))
	btn_row.add_child(_button("Copy GDScript", _on_bullet_copy))

	_tab_nodes[Tab.BULLETS] = sink


func _refresh_bullet_list() -> void:
	_b_is_enemy = _b_kind_dd.selected == 0
	_b_items.clear()
	_b_list.clear()
	if _b_is_enemy:
		var d := DirAccess.open(ENEMY_BULLET_DIR)
		if d != null:
			for f in d.get_files():
				if f.ends_with(".tres"):
					_b_items.append(ENEMY_BULLET_DIR + f)
		_b_items.sort()
	else:
		for p in PLAYER_BULLET_SCENES:
			if ResourceLoader.exists(p):
				_b_items.append(p)
	for p in _b_items:
		_b_list.add_item(String(p).get_file())
	_clear_form()
	if _b_list.item_count > 0:
		_b_list.select(0)
		_load_bullet(0)


func _load_bullet(idx: int) -> void:
	if idx < 0 or idx >= _b_items.size():
		return
	var path: String = _b_items[idx]
	_clear_form()
	if _b_is_enemy:
		# The SAME preloaded .tres the enemies use — edits live-reflect in the Enemy tab.
		_b_edit_obj = load(path)
		_b_status.text = "Editing %s — Save writes the .tres. Live-reflects in the Enemy tab." % path.get_file()
	else:
		# Player bullet: instance the root (NOT added to tree, so _ready/_init game
		# logic doesn't fire) and reflect its @export. Author + Copy only — player
		# bullet damage/speed is authored on the Part, so we don't rewrite the scene.
		var ps := load(path) as PackedScene
		_b_edit_obj = ps.instantiate() if ps != null else null
		_b_status.text = "%s — author values, then Copy GDScript. (Player bullet stats are set by the Part; Save is disabled.)" % path.get_file()
	if _b_edit_obj != null:
		_build_object_form(_b_form, _b_edit_obj)


# Reflection form: SpinBox/CheckBox/LineEdit/Color/enum per editable property.
func _build_object_form(vbox: VBoxContainer, obj: Object) -> void:
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
		match ptype:
			TYPE_INT, TYPE_FLOAT:
				if pname == "speed":
					# Bullet speed is RUNG-CLAMPED to the 1–8 px/frame scale (Roman
					# 2026-06-11): only multiples of 60 px/s (rung 1=60 … rung 8=480).
					vbox.add_child(_label("speed  (rung 1–8 → px/s)", FS_CAPTION, UiTheme.COLOR_FAINT))
					var rsb := SpinBox.new()
					rsb.add_theme_font_override("font", UiTheme.active_font())
					rsb.add_theme_font_size_override("font_size", FS_BODY)
					rsb.custom_minimum_size = Vector2(0, 32)
					rsb.min_value = 60.0    # rung 1
					rsb.max_value = 480.0   # rung 8 (the readability ceiling)
					rsb.step = 60.0         # one rung
					rsb.value = clampf(roundf(float(val) / 60.0) * 60.0, 60.0, 480.0)
					rsb.value_changed.connect(func(v):
						obj.set("speed", clampf(roundf(v / 60.0) * 60.0, 60.0, 480.0)))
					vbox.add_child(rsb)
				elif hint == PROPERTY_HINT_ENUM:
					var opts := hint_str.split(",")
					var dd := _dropdown(vbox, pname, opts)
					dd.select(clampi(int(val), 0, opts.size() - 1))
					dd.item_selected.connect(func(i): obj.set(pname, i))
				else:
					vbox.add_child(_label(pname, FS_CAPTION, UiTheme.COLOR_FAINT))
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
				cb.text = pname
				cb.add_theme_font_override("font", UiTheme.active_font())
				cb.add_theme_font_size_override("font_size", FS_BODY)
				cb.button_pressed = bool(val)
				cb.toggled.connect(func(on): obj.set(pname, on))
				vbox.add_child(cb)
			TYPE_COLOR:
				vbox.add_child(_label(pname, FS_CAPTION, UiTheme.COLOR_FAINT))
				var cp := ColorPickerButton.new()
				cp.custom_minimum_size = Vector2(0, 32)
				cp.color = val
				cp.color_changed.connect(func(c): obj.set(pname, c))
				vbox.add_child(cp)
			TYPE_STRING, TYPE_STRING_NAME:
				vbox.add_child(_label(pname, FS_CAPTION, UiTheme.COLOR_FAINT))
				var le := LineEdit.new()
				le.add_theme_font_override("font", UiTheme.active_font())
				le.add_theme_font_size_override("font_size", FS_BODY)
				le.text = String(val)
				le.text_changed.connect(func(t): obj.set(pname, t))
				vbox.add_child(le)
			_:
				# Objects/arrays (textures, sprite_frames) — show read-only.
				var shown := "—" if val == null else str(val).get_file() if (val is Resource and val.resource_path != "") else "(set)"
				vbox.add_child(_label("%s: %s" % [pname, shown], FS_CAPTION, UiTheme.COLOR_FAINT))


func _on_bullet_save() -> void:
	if _b_edit_obj == null:
		return
	if not _b_is_enemy:
		_b_status.text = "Player bullets aren't saved here — use Copy GDScript and paste onto the Part/scene."
		return
	var res := _b_edit_obj as Resource
	if res == null or res.resource_path == "":
		_b_status.text = "No resource path to save."
		return
	var err := ResourceSaver.save(res, res.resource_path)
	_b_status.text = ("Saved %s" % res.resource_path.get_file()) if err == OK else ("Save failed (err %d)" % err)


func _on_bullet_copy() -> void:
	if _b_edit_obj == null:
		return
	var txt := "# Weapon Lab — bullet settings\n"
	for prop in _b_edit_obj.get_property_list():
		var usage: int = int(prop.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var pname: String = String(prop["name"])
		var ptype: int = int(prop["type"])
		var val = _b_edit_obj.get(pname)
		match ptype:
			TYPE_INT, TYPE_BOOL:
				txt += "%s = %s\n" % [pname, str(val)]
			TYPE_FLOAT:
				txt += "%s = %.3f\n" % [pname, float(val)]
			TYPE_STRING, TYPE_STRING_NAME:
				txt += "%s = \"%s\"\n" % [pname, String(val)]
			TYPE_COLOR:
				txt += "%s = Color%s\n" % [pname, str(val)]
	DisplayServer.clipboard_set(txt)
	_b_status.text = "Copied %d-line snippet to clipboard." % txt.split("\n").size()


func _clear_form() -> void:
	if _b_form == null:
		return
	for c in _b_form.get_children():
		c.queue_free()
	# Free a player-bullet instance we own (not the shared enemy .tres).
	if _b_edit_obj != null and not _b_is_enemy and _b_edit_obj is Node and not (_b_edit_obj as Node).is_inside_tree():
		(_b_edit_obj as Node).free()
	_b_edit_obj = null


# ---- Tab switching -------------------------------------------------------

func _select_tab(idx: int) -> void:
	_tab = idx
	for t in _tab_nodes.keys():
		var is_vis: bool = t == idx
		for n in _tab_nodes[t]:
			if is_instance_valid(n):
				n.visible = is_vis
	# Reconfigure the arena for the tab.
	if idx == Tab.ENEMY:
		_set_autofire_state(_autofire)   # keep current; enemy host respects it
		_spawn_enemy_host()
		_refresh_enemy_info()
	else:
		_clear_enemy_host()
		if idx == Tab.PLAYER:
			_set_autofire_state(_autofire)
		else:
			_set_autofire_state(false)   # bullets tab: quiet
			_refresh_bullet_list()


# ---- Firing controls -----------------------------------------------------

func _on_autofire_toggled(on: bool) -> void:
	_autofire = on
	_set_autofire_state(on)


func _set_autofire_state(on: bool) -> void:
	# Player auto-fire rides the real Settings.autofire latch (restored on exit).
	if has_node("/root/Settings"):
		var s = get_node("/root/Settings")
		if s.has_method("set_autofire"):
			s.set_autofire(on and _tab == Tab.PLAYER)
	# Enemy host fires on its ShootTimer.
	if _enemy_host != null and is_instance_valid(_enemy_host) and _enemy_host.has_node("ShootTimer"):
		var t = _enemy_host.get_node("ShootTimer")
		if on and _tab == Tab.ENEMY:
			if t.is_stopped():
				t.start()
		else:
			t.stop()


func _on_fire_once() -> void:
	if _tab == Tab.PLAYER:
		if _player != null and is_instance_valid(_player) and _player.has_method("fire_primary"):
			_player.fire_primary()
	elif _tab == Tab.ENEMY:
		if _enemy_host != null and is_instance_valid(_enemy_host) and _enemy_host.shoot_pattern != null:
			_enemy_host.shoot_pattern.fire(_enemy_host)


# ---- Helpers -------------------------------------------------------------

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
	# Restore the user's real autofire latch before leaving.
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
