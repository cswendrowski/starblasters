extends Control

# Shipyard V3 — Roman 2026-05-23 rework: "full-screen play space like other
# dev menus, but with hd-ui over it. The central play space should be where
# the enemies spawn and attack the dummy target."
#
# Layout (1920×1080 HD; gameplay SubViewport 480×270 stretched to fill):
#   ┌──────────────────────────────────────────────────────────────────┐
#   │ SHIPYARD                                                  [Back] │
#   │ ┌────────┐                                       ┌────────────┐  │
#   │ │ Rarity▾│                                       │  Name      │  │
#   │ │────────│                                       │  Rarity    │  │
#   │ │ • dart │           ★ FULL-WINDOW PLAYSPACE ★    │  HP/Bounty │  │
#   │ │ • drift│                                       │  Move/Shoot│  │
#   │ │ • …    │   (enemy spawns top, attacks dummy    │  Tags      │  │
#   │ │        │    player at bottom of playfield band)│  Blurb     │  │
#   │ │        │                                       │ [✓] Shoot  │  │
#   │ │        │                                       │ [Respawn]  │  │
#   │ └────────┘                                       └────────────┘  │
#   └──────────────────────────────────────────────────────────────────┘
#
# The SubViewport stays 480×270 (game-native) so all Playfield.X_MIN /
# X_MAX math + movement patterns read correctly. A fullscreen
# SubViewportContainer with stretch=true displays it at 4× across the
# whole 1920×1080 window. UI panels live on a CanvasLayer above with
# semi-transparent backgrounds so gameplay remains visible behind them.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const EnemyManifest = preload("res://scripts/dev/enemy_manifest.gd")
const EnemyRoster = preload("res://scripts/levels/enemy_roster.gd")
const EnemyCodex = preload("res://scripts/enemy_codex.gd")
const HangarDummy = preload("res://scripts/dev/hangar_dummy_target.gd")
const Playfield = preload("res://scripts/playfield.gd")
const PLAYER_SPRITE = preload("res://Mini Pixel Pack 3/Player ship/Player_ship (16 x 16).png")

# Tier table preserved from V2 — bosses + hazards aren't in EnemyRoster so
# we keep the explicit map. When adding a new enemy scene, add it here too.
const TIER_BY_PATH := {
	"res://scenes/enemies/boss.tscn": "Boss",
	"res://scenes/enemies/boss_reaver.tscn": "Boss",
	"res://scenes/enemies/boss_sentinel.tscn": "Boss",
	"res://scenes/enemies/enemy_dart.tscn": "Common",
	"res://scenes/enemies/enemy_drifter.tscn": "Common",
	"res://scenes/enemies/enemy_firecore.tscn": "Common",
	"res://scenes/enemies/enemy_hunter_drone.tscn": "Common",
	"res://scenes/enemies/enemy_cutter.tscn": "Uncommon",
	"res://scenes/enemies/enemy_frigate.tscn": "Uncommon",
	"res://scenes/enemies/enemy_hover.tscn": "Uncommon",
	"res://scenes/enemies/enemy_skirmisher.tscn": "Uncommon",
	"res://scenes/enemies/enemy_weaver.tscn": "Uncommon",
	"res://scenes/enemies/enemy_bulwark.tscn": "Rare",
	"res://scenes/enemies/enemy_crystal.tscn": "Rare",
	"res://scenes/enemies/enemy_interceptor.tscn": "Rare",
	"res://scenes/enemies/enemy_minelayer.tscn": "Rare",
	"res://scenes/enemies/enemy_asteroid.tscn": "Hazard",
	"res://scenes/enemies/enemy_mine.tscn": "Hazard",
	"res://scenes/enemies/enemy_mine_cluster.tscn": "Hazard",
	"res://scenes/enemies/enemy_mine_cluster_smart.tscn": "Hazard",
	"res://scenes/enemies/enemy_mine_shield.tscn": "Hazard",
}

const RARITY_FILTERS := ["All", "Common", "Uncommon", "Rare", "Boss", "Hazard"]

# HD font sizes — UiTheme defaults are sized for 480×270; bump for 1080p.
const FS_TITLE := 40
const FS_HEADER := 26
const FS_BODY := 20
const FS_CAPTION := 16

# HD overlay layout (1920×1080). Panels are narrower than the V2 columns
# and translucent so the gameplay shows through behind them.
const RAIL_W := 280
const INFO_W := 300
const MARGIN := 20
const HEADER_H := 56
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.55)
const PANEL_BORDER := Color(0.35, 0.55, 0.75, 0.85)

const RESPAWN_DELAY := 1.5

var _rarity_filter: String = "All"
var _list: ItemList = null
var _filter_dd: OptionButton = null
var _paths_all: Array[String] = []   # sorted master list from manifest
var _paths_filtered: Array[String] = []
var _selected_path: String = ""

var _preview_vp: SubViewport = null
var _enemy_layer: Node2D = null
var _dummy: Area2D = null
var _current_enemy: Node = null
var _respawn_timer: Timer = null

# Info panel labels.
var _name_lbl: Label = null
var _tier_lbl: Label = null
var _hp_lbl: Label = null
var _bounty_lbl: Label = null
var _move_lbl: Label = null
var _shoot_lbl: Label = null
var _tags_lbl: Label = null
var _blurb_lbl: Label = null
var _shoot_toggle: CheckBox = null


func _ready() -> void:
	# Native 1920×1080 for this scene; restored on exit. Same pattern as
	# sector_map_hd.gd so all HD overlay geometry is authored in HD coords.
	get_tree().get_root().content_scale_size = Vector2i(1920, 1080)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_playspace()
	_build_overlay()
	_load_manifest()
	_apply_filter()
	if _list.item_count > 0:
		_list.select(0)
		_on_list_select(0)


func _exit_tree() -> void:
	get_tree().get_root().content_scale_size = Vector2i(480, 270)


# ---- Playspace (fills the whole window) --------------------------------

func _build_playspace() -> void:
	# A SubViewportContainer that fills the entire 1920×1080 window with
	# stretch=true — the inner 480×270 SubViewport upscales 4× to fill.
	# Nearest filter keeps the pixel art crisp.
	var sub_container := SubViewportContainer.new()
	sub_container.stretch = true
	sub_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Don't eat input events that should reach the UI overlay above.
	sub_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub_container)

	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(480, 270)
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_vp.transparent_bg = false
	# Disable input handling inside the subviewport — it's display-only.
	_preview_vp.handle_input_locally = false
	sub_container.add_child(_preview_vp)

	# Gutters (matches the real game's frame: dark side bands, slightly
	# lighter 216-wide playfield strip in the middle).
	var gutter := ColorRect.new()
	gutter.color = Color(0.04, 0.05, 0.08, 1.0)
	gutter.size = Vector2(480, 270)
	_preview_vp.add_child(gutter)
	var band := ColorRect.new()
	band.color = Color(0.07, 0.09, 0.13, 1.0)
	band.position = Vector2(Playfield.X_MIN, 0)
	band.size = Vector2(Playfield.W, Playfield.H)
	_preview_vp.add_child(band)

	# Dummy player — Area2D from hangar_dummy_target.gd. Group "player" so
	# patterns like BeelinePlayer / AimedShot can target it.
	_dummy = Area2D.new()
	_dummy.set_script(HangarDummy)
	_dummy.name = "DummyPlayer"
	_dummy.add_to_group("player")
	_dummy.position = Vector2(Playfield.CENTER.x, 230)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = PLAYER_SPRITE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dummy.add_child(sprite)
	var hit := CollisionShape2D.new()
	var cs := RectangleShape2D.new()
	cs.size = Vector2(12, 12)
	hit.shape = cs
	_dummy.add_child(hit)
	_preview_vp.add_child(_dummy)

	_enemy_layer = Node2D.new()
	_enemy_layer.name = "EnemyLayer"
	_preview_vp.add_child(_enemy_layer)

	_respawn_timer = Timer.new()
	_respawn_timer.one_shot = true
	_respawn_timer.wait_time = RESPAWN_DELAY
	_respawn_timer.timeout.connect(_spawn_current)
	add_child(_respawn_timer)


# ---- HD overlay UI (floats over playspace) -----------------------------

func _build_overlay() -> void:
	# Layer 5 matches main.tscn's HUD convention — well above the
	# SubViewportContainer at the default layer 0.
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 5
	ui_layer.name = "UiOverlay"
	add_child(ui_layer)

	# Header label (top-left).
	var header := Label.new()
	header.text = "SHIPYARD"
	header.position = Vector2(MARGIN, 12)
	header.add_theme_font_override("font", UiTheme.active_font())
	header.add_theme_font_size_override("font_size", FS_TITLE)
	header.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
	header.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	header.add_theme_constant_override("outline_size", 6)
	ui_layer.add_child(header)

	# Back button (top-right corner).
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
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 10
	sb.content_margin_top = 10
	sb.content_margin_right = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = pos
	panel.size = sz
	# Let the panel itself ignore mouse so child controls receive clicks.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _build_left_rail(parent: CanvasLayer) -> void:
	var x := MARGIN
	var y := HEADER_H + MARGIN
	# Take ~3/4 of remaining vertical space, leaving open air at the bottom.
	var h := int((1080 - y - MARGIN) * 0.78)

	var panel := _make_panel_bg(Vector2(x, y), Vector2(RAIL_W, h))
	parent.add_child(panel)

	var filter_lbl := Label.new()
	filter_lbl.text = "Rarity"
	filter_lbl.position = Vector2(x + 14, y + 10)
	filter_lbl.add_theme_font_override("font", UiTheme.active_font())
	filter_lbl.add_theme_font_size_override("font_size", FS_CAPTION)
	filter_lbl.add_theme_color_override("font_color", UiTheme.COLOR_FAINT)
	parent.add_child(filter_lbl)

	_filter_dd = OptionButton.new()
	_filter_dd.position = Vector2(x + 14, y + 32)
	_filter_dd.size = Vector2(RAIL_W - 28, 36)
	_filter_dd.add_theme_font_override("font", UiTheme.active_font())
	_filter_dd.add_theme_font_size_override("font_size", FS_BODY)
	for f in RARITY_FILTERS:
		_filter_dd.add_item(f)
	_filter_dd.select(0)
	_filter_dd.item_selected.connect(_on_filter_changed)
	parent.add_child(_filter_dd)

	var list_y := y + 78
	var list_h := h - 78 - 14
	_list = ItemList.new()
	_list.position = Vector2(x + 14, list_y)
	_list.size = Vector2(RAIL_W - 28, list_h)
	_list.add_theme_font_override("font", UiTheme.active_font())
	_list.add_theme_font_size_override("font_size", FS_BODY)
	_list.fixed_icon_size = Vector2i(28, 28)
	_list.item_selected.connect(_on_list_select)
	parent.add_child(_list)


func _build_info_panel(parent: CanvasLayer) -> void:
	var x := 1920 - MARGIN - INFO_W
	var y := HEADER_H + MARGIN
	var h := int((1080 - y - MARGIN) * 0.78)

	var panel := _make_panel_bg(Vector2(x, y), Vector2(INFO_W, h))
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(x + 16, y + 14)
	vbox.size = Vector2(INFO_W - 32, h - 28)
	vbox.add_theme_constant_override("separation", 8)
	parent.add_child(vbox)

	_name_lbl = _make_label("—", FS_HEADER, UiTheme.COLOR_ACCENT)
	vbox.add_child(_name_lbl)
	_tier_lbl = _make_label("Rarity: —", FS_BODY, UiTheme.COLOR_FAINT)
	vbox.add_child(_tier_lbl)
	vbox.add_child(HSeparator.new())

	_hp_lbl = _make_label("HP: —", FS_BODY, UiTheme.COLOR_TEXT)
	vbox.add_child(_hp_lbl)
	_bounty_lbl = _make_label("Bounty: —", FS_BODY, UiTheme.COLOR_BOUNTY)
	vbox.add_child(_bounty_lbl)
	_move_lbl = _make_label("Movement: —", FS_BODY, UiTheme.COLOR_TEXT)
	_move_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_move_lbl)
	_shoot_lbl = _make_label("Shoot: —", FS_BODY, UiTheme.COLOR_TEXT)
	_shoot_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_shoot_lbl)
	_tags_lbl = _make_label("Tags: —", FS_CAPTION, UiTheme.COLOR_FAINT)
	_tags_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_tags_lbl)
	vbox.add_child(HSeparator.new())

	_blurb_lbl = _make_label("", FS_CAPTION, UiTheme.COLOR_TEXT)
	_blurb_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb_lbl.custom_minimum_size = Vector2(INFO_W - 32, 80)
	vbox.add_child(_blurb_lbl)
	vbox.add_child(HSeparator.new())

	_shoot_toggle = CheckBox.new()
	_shoot_toggle.text = "Shoot enabled"
	_shoot_toggle.button_pressed = true
	_shoot_toggle.add_theme_font_override("font", UiTheme.active_font())
	_shoot_toggle.add_theme_font_size_override("font_size", FS_BODY)
	_shoot_toggle.toggled.connect(_on_shoot_toggled)
	vbox.add_child(_shoot_toggle)

	var respawn_btn := Button.new()
	respawn_btn.text = "Respawn"
	UiTheme.style_button(respawn_btn, true)
	respawn_btn.add_theme_font_size_override("font_size", FS_BODY)
	respawn_btn.custom_minimum_size = Vector2(0, 40)
	respawn_btn.pressed.connect(_spawn_current)
	vbox.add_child(respawn_btn)


func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.active_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	l.add_theme_constant_override("outline_size", 3)
	return l


# ---- Data --------------------------------------------------------------

func _load_manifest() -> void:
	_paths_all.clear()
	for p in EnemyManifest.paths():
		_paths_all.append(String(p))
	_paths_all.sort()


func _on_filter_changed(idx: int) -> void:
	_rarity_filter = RARITY_FILTERS[idx]
	_apply_filter()
	if _list.item_count > 0:
		_list.select(0)
		_on_list_select(0)
	else:
		_clear_enemy()
		_selected_path = ""


func _apply_filter() -> void:
	_list.clear()
	_paths_filtered.clear()
	for p in _paths_all:
		if _rarity_filter != "All":
			var tier: String = String(TIER_BY_PATH.get(p, ""))
			if tier != _rarity_filter:
				continue
		_paths_filtered.append(p)
		_list.add_item(_display_name(p), _icon_for(p))


func _display_name(path: String) -> String:
	# Prefer codex display name when present, else fall back to filename.
	for e in EnemyCodex.ENTRIES:
		if String(e.get("path", "")) == path:
			return String(e.get("name", ""))
	var nm := path.get_file().get_basename()
	if nm.begins_with("enemy_"):
		nm = nm.substr(6)
	return nm.capitalize()


# Pull a small icon from the enemy scene's first Sprite2D texture so the
# left rail reads visually. Best-effort — if the scene has no Sprite2D we
# return null and the list shows text only.
func _icon_for(path: String) -> Texture2D:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var state := ps.get_state()
	for i in state.get_node_count():
		if state.get_node_type(i) != &"Sprite2D":
			continue
		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) == &"texture":
				var tex := state.get_node_property_value(i, j) as Texture2D
				if tex != null:
					return tex
	return null


# ---- Selection / spawn -------------------------------------------------

func _on_list_select(idx: int) -> void:
	if idx < 0 or idx >= _paths_filtered.size():
		return
	_selected_path = _paths_filtered[idx]
	_spawn_current()


func _on_shoot_toggled(_v: bool) -> void:
	_spawn_current()


func _spawn_current() -> void:
	_respawn_timer.stop()
	_clear_enemy()
	if _selected_path == "":
		return
	var ps := load(_selected_path) as PackedScene
	if ps == null:
		return
	var inst := ps.instantiate()
	if inst is Node2D:
		# Spawn at top-centre of the playfield band so default downward
		# movement (StraightDown, TopDive, SCurve…) reads naturally.
		(inst as Node2D).position = Vector2(Playfield.CENTER.x, -20)
	if _shoot_toggle and not _shoot_toggle.button_pressed:
		if "shoot_pattern" in inst:
			inst.shoot_pattern = null
		if inst.has_node("ShootTimer"):
			(inst.get_node("ShootTimer") as Timer).stop()
	_enemy_layer.add_child(inst)
	_current_enemy = inst
	_refresh_info(inst)


func _clear_enemy() -> void:
	if _current_enemy != null and is_instance_valid(_current_enemy):
		_current_enemy.queue_free()
	_current_enemy = null


func _process(_delta: float) -> void:
	if _current_enemy == null or not is_instance_valid(_current_enemy):
		return
	if not (_current_enemy is Node2D):
		return
	var p: Vector2 = (_current_enemy as Node2D).position
	# Exited the preview viewport — schedule a respawn. Generous margin so
	# loiter-style patterns that briefly dip past the edge still settle.
	if p.y > 320 or p.x < -40 or p.x > 520:
		_clear_enemy()
		if _respawn_timer.is_stopped():
			_respawn_timer.start()


# ---- Info readout ------------------------------------------------------

func _refresh_info(inst: Node) -> void:
	_name_lbl.text = _display_name(_selected_path)
	_tier_lbl.text = "Rarity: %s" % String(TIER_BY_PATH.get(_selected_path, "?"))

	var hp: int = int(inst.max_health) if "max_health" in inst else 0
	var bounty: int = int(inst.bounty_value) if "bounty_value" in inst else 0
	_hp_lbl.text = "HP: %d" % hp
	_bounty_lbl.text = "Bounty: %d" % bounty

	_move_lbl.text = "Movement: %s" % _pattern_name_of(inst, "movement")
	_shoot_lbl.text = "Shoot: %s" % _pattern_name_of(inst, "shoot_pattern")

	var entry: Dictionary = _roster_entry(_selected_path)
	var tags: Array = entry.get("conflict_tags", entry.get("tags", []))
	_tags_lbl.text = "Tags: %s" % (", ".join(tags) if not tags.is_empty() else "—")

	_blurb_lbl.text = _codex_blurb(_selected_path)


func _pattern_name_of(inst: Node, prop: String) -> String:
	if not (prop in inst):
		return "—"
	var res = inst.get(prop)
	if res == null:
		return "—"
	var scr := (res as Resource).get_script() as Script
	if scr == null:
		return String((res as Resource).resource_path.get_file().get_basename())
	var path: String = scr.resource_path
	if path == "":
		return "?"
	var base := path.get_file().get_basename()
	return base.capitalize()


func _roster_entry(path: String) -> Dictionary:
	for e in EnemyRoster.ENTRIES:
		if String(e.get("scene", "")) == path:
			return e
	return {}


func _codex_blurb(path: String) -> String:
	for e in EnemyCodex.ENTRIES:
		if String(e.get("path", "")) == path:
			return String(e.get("blurb", ""))
	return ""


# ---- Back --------------------------------------------------------------

func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
