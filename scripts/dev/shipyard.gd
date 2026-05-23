extends Control

# Shipyard V2 — Roman, 2026-05-18 rework: "function like the hangar, but
# for enemies." Drops the old maneuver-assignment tool.
#
# Layout:
#   - Left rail: scrollable list of enemy scenes
#   - Center: half-size playfield (160×200) where the selected enemy spawns
#     and runs its intended movement / shoot pattern
#   - Right rail: stats readout (Hull / Shield / Bounty / Rarity) +
#     Shoot toggle + Back button
#
# Design notes worth flagging:
#   * Enemies are instantiated from their .tscn unchanged — same code
#     path as live combat. Movement + shoot patterns are whatever the
#     scene defines.
#   * Half-size preview uses a SubViewport at 320×400 inside a
#     SubViewportContainer at 0.5× stretch, so the enemy's pixel scale
#     stays accurate against the standard viewport.
#   * Shoot toggle clears the enemy's shoot_pattern + halts ShootTimer.
#     Toggling on respawns so the patterns/timers wire up cleanly.
#   * Rarity is keyed off the codex tier table.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const EnemyManifest = preload("res://scripts/dev/enemy_manifest.gd")
const EnemyRoster = preload("res://scripts/levels/enemy_roster.gd")

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

var _list: ItemList = null
var _paths: Array[String] = []
var _selected_idx: int = -1
var _preview_holder: SubViewport = null
var _preview_anchor: Node2D = null
var _current_enemy: Node = null
var _current_path: String = ""
var _player_marker: Node2D = null
var _hull_label: Label = null
var _shield_label: Label = null
var _bounty_label: Label = null
var _rarity_label: Label = null
var _size_label: Label = null
var _tags_label: Label = null
var _shoot_toggle: CheckBox = null
# Ship Sizer integration (merged in, Cody 2026-05-20). Scale slider +
# orientation flip toggle so the Shipyard subsumes the Ship Sizer tool.
var _scale_slider: HSlider = null
var _scale_label: Label = null
var _flip_toggle: CheckBox = null
var _preview_scale: float = 1.0
var _preview_flipped: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_populate_list()
	if _list and _list.item_count > 0:
		_list.select(0)
		_on_list_select(0)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.12, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var header := Label.new()
	header.text = "SHIPYARD"
	header.position = Vector2(8, 4)
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	add_child(header)

	# Left rail — enemy list.
	var left_scroll := ScrollContainer.new()
	left_scroll.position = Vector2(8, 22)
	left_scroll.size = Vector2(80, 360)
	add_child(left_scroll)
	_list = ItemList.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 360)
	_list.add_theme_font_size_override("font_size", 9)
	_list.item_selected.connect(_on_list_select)
	left_scroll.add_child(_list)

	# Center — half-size playfield.
	var preview_container := SubViewportContainer.new()
	preview_container.stretch = true
	preview_container.position = Vector2(92, 22)
	preview_container.size = Vector2(160, 200)
	preview_container.custom_minimum_size = Vector2(160, 200)
	preview_container.stretch_shrink = 2  # 0.5×
	add_child(preview_container)
	_preview_holder = SubViewport.new()
	_preview_holder.size = Vector2i(320, 400)
	_preview_holder.transparent_bg = true
	_preview_holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_container.add_child(_preview_holder)
	var field_bg := ColorRect.new()
	field_bg.color = Color(0.08, 0.10, 0.14, 1.0)
	field_bg.size = Vector2(320, 400)
	_preview_holder.add_child(field_bg)
	# Player marker so chasing enemies have something to track.
	_player_marker = Node2D.new()
	_player_marker.name = "PlayerPointer"
	_player_marker.add_to_group("player")
	_player_marker.position = Vector2(160, 320)
	var marker := Polygon2D.new()
	marker.polygon = PackedVector2Array([
		Vector2(0, -8), Vector2(-6, 6), Vector2(0, 3), Vector2(6, 6),
	])
	marker.color = Color(0.55, 0.95, 0.75, 0.9)
	_player_marker.add_child(marker)
	_preview_holder.add_child(_player_marker)
	_preview_anchor = Node2D.new()
	_preview_anchor.name = "EnemyAnchor"
	_preview_holder.add_child(_preview_anchor)

	# Right rail — stats + controls.
	var right := VBoxContainer.new()
	right.position = Vector2(256, 22)
	right.size = Vector2(60, 360)
	right.custom_minimum_size = Vector2(60, 360)
	right.add_theme_constant_override("separation", 4)
	add_child(right)
	_add_caption(right, "Stats")
	_hull_label = _add_stat(right, "Hull: ?")
	_shield_label = _add_stat(right, "Shield: ?")
	_bounty_label = _add_stat(right, "Bounty: ?")
	_rarity_label = _add_stat(right, "Rarity: ?")
	_size_label = _add_stat(right, "Size: ?")
	_tags_label = _add_stat(right, "Tags: —")
	right.add_child(HSeparator.new())
	_shoot_toggle = CheckBox.new()
	_shoot_toggle.text = "Shoot"
	_shoot_toggle.button_pressed = true
	_shoot_toggle.add_theme_font_size_override("font_size", 9)
	_shoot_toggle.toggled.connect(_on_shoot_toggled)
	right.add_child(_shoot_toggle)
	# Ship Sizer fold-in: scale slider + orientation flip. Apply to the
	# spawned preview enemy so designers can eyeball it at any size.
	_scale_label = Label.new()
	_scale_label.text = "Scale: 1.0×"
	_scale_label.add_theme_font_size_override("font_size", 9)
	right.add_child(_scale_label)
	_scale_slider = HSlider.new()
	_scale_slider.min_value = 0.25
	_scale_slider.max_value = 3.0
	_scale_slider.step = 0.05
	_scale_slider.value = 1.0
	_scale_slider.custom_minimum_size = Vector2(0, 8)
	_scale_slider.value_changed.connect(_on_scale_changed)
	right.add_child(_scale_slider)
	_flip_toggle = CheckBox.new()
	_flip_toggle.text = "Flip"
	_flip_toggle.add_theme_font_size_override("font_size", 9)
	_flip_toggle.toggled.connect(_on_flip_toggled)
	right.add_child(_flip_toggle)
	right.add_child(HSeparator.new())
	var respawn_btn := Button.new()
	respawn_btn.text = "Respawn"
	respawn_btn.custom_minimum_size = Vector2(0, 14)
	UiTheme.style_button(respawn_btn, true)
	respawn_btn.pressed.connect(_respawn_current)
	right.add_child(respawn_btn)
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(0, 14)
	UiTheme.style_button(back_btn, true)
	back_btn.pressed.connect(_on_back)
	right.add_child(back_btn)


func _add_caption(parent: Container, text: String) -> void:
	var l := Label.new()
	l.text = text
	UiTheme.style_label(l, UiTheme.LabelKind.CAPTION)
	parent.add_child(l)


func _add_stat(parent: Container, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	parent.add_child(l)
	return l


func _populate_list() -> void:
	_paths = []
	for p in EnemyManifest.paths():
		_paths.append(String(p))
	_paths.sort()
	for p in _paths:
		var nm: String = p.get_file().get_basename()
		if nm.begins_with("enemy_"):
			nm = nm.substr(6)
		_list.add_item(nm.capitalize())


func _on_list_select(idx: int) -> void:
	_selected_idx = idx
	if idx < 0 or idx >= _paths.size():
		return
	_current_path = _paths[idx]
	_respawn_current()


func _on_scale_changed(v: float) -> void:
	_preview_scale = v
	if _scale_label:
		_scale_label.text = "Scale: %.2f×" % v
	_apply_preview_transform()


func _on_flip_toggled(pressed: bool) -> void:
	_preview_flipped = pressed
	_apply_preview_transform()


# Apply scale + flip to the currently-spawned enemy. Flip = rotate 180°
# in-place so a sprite authored facing the wrong way for combat reads
# correctly in the preview.
func _apply_preview_transform() -> void:
	if _current_enemy == null or not is_instance_valid(_current_enemy):
		return
	if not (_current_enemy is Node2D):
		return
	var n2d := _current_enemy as Node2D
	n2d.scale = Vector2(_preview_scale, _preview_scale)
	n2d.rotation = PI if _preview_flipped else 0.0


func _on_shoot_toggled(_v: bool) -> void:
	_respawn_current()


func _respawn_current() -> void:
	if _current_enemy != null and is_instance_valid(_current_enemy):
		_current_enemy.queue_free()
		_current_enemy = null
	if _current_path == "":
		return
	var ps = load(_current_path)
	if ps == null:
		return
	var inst = ps.instantiate()
	if inst is Node2D:
		inst.position = Vector2(160, 60)
	if _shoot_toggle and not _shoot_toggle.button_pressed:
		if "shoot_pattern" in inst:
			inst.shoot_pattern = null
		if inst.has_node("ShootTimer"):
			inst.get_node("ShootTimer").stop()
	_preview_anchor.add_child(inst)
	_current_enemy = inst
	_apply_preview_transform()
	_refresh_stats(inst)


func _lookup_roster_entry(path: String) -> Dictionary:
	for entry in EnemyRoster.ENTRIES:
		if String(entry.get("scene", "")) == path:
			return entry
	return {}


func _refresh_stats(inst: Node) -> void:
	var hull: int = int(inst.max_health) if "max_health" in inst else 0
	var bounty: int = int(inst.bounty_value) if "bounty_value" in inst else 0
	var shield_text: String = "-"
	if "shield_health" in inst:
		shield_text = "%d" % int(inst.shield_health)
	elif "shield" in inst and "max_shield" in inst:
		shield_text = "%d/%d" % [int(inst.shield), int(inst.max_shield)]
	var rarity: String = String(TIER_BY_PATH.get(_current_path, "?"))
	_hull_label.text = "Hull: %d" % hull
	_shield_label.text = "Shield: %s" % shield_text
	_bounty_label.text = "Bounty: %d" % bounty
	_rarity_label.text = "Rarity: %s" % rarity
	var entry: Dictionary = _lookup_roster_entry(_current_path)
	_size_label.text = "Size: %s" % String(entry.get("size", "?")).capitalize()
	var tags: Array = entry.get("tags", [])
	_tags_label.text = "Tags: %s" % (", ".join(tags).capitalize() if not tags.is_empty() else "—")


func _process(_delta: float) -> void:
	if _player_marker and _preview_holder:
		var local: Vector2 = _preview_holder.get_mouse_position()
		if local.x >= 0 and local.x <= 320 and local.y >= 0 and local.y <= 400:
			_player_marker.position = local
	# Auto-respawn when the enemy recycles off-screen so the tester
	# always has something to watch.
	if _current_path != "" and (_current_enemy == null or not is_instance_valid(_current_enemy)):
		_respawn_current()


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
