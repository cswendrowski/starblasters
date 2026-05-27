extends Node2D

# Hangar V4 — Cobalt 2026-05-20 redirect.
#
# Drops the HD-viewport + SubViewport setup (it made the player blurry,
# moved bullets into the wrong coordinate space, and didn't match what a
# "new game" player would see). Instead, the hangar IS the live combat
# scene: same native 480×270 viewport, same Playfield band, same
# backdrop, same player at the same spawn position. The wave director
# is replaced by a single dummy target the player can shoot for as long
# as the menu is open.
#
# UI sits on a CanvasLayer overlay at native viewport scale, panels
# tucked into the side gutters so the playable band stays unobstructed.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const BackdropScript = preload("res://scripts/galaxy_backdrop.gd")
const DummyTargetScript = preload("res://scripts/dev/hangar_dummy_target.gd")

const TARGET_POS := Vector2(240, 36)

# Same three logical groups as before — Primary, Secondary, Super —
# mapping to the live-game SlotTypes the picker filters on.
const WEAPON_GROUPS := [
	{"name": "Primary (Z / SPACE)",   "slot": SlotTypes.SlotType.CANNON},
	{"name": "Secondary (C)",         "slot": SlotTypes.SlotType.HARDPOINT_WING},
	{"name": "Super (X)",             "slot": SlotTypes.SlotType.DEVICE_BAY_1},
]


# ---- State ---------------------------------------------------------------

var _backdrop: Node2D = null
var _player: Node = null
var _target: Area2D = null

# UI nodes
var _slot_picker: OptionButton = null
var _part_picker: OptionButton = null
var _mark_slider: HSlider = null
var _mark_label: Label = null
var _status_label: Label = null
var _equipped_summary: Label = null
var _preview_label: Label = null

var _selected_slot: int = SlotTypes.SlotType.CANNON


# ---- Lifecycle -----------------------------------------------------------

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.0, 0.0, 0.0))
	_spawn_backdrop()
	_spawn_player()
	_spawn_dummy_target()
	_build_ui()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")
	# Player.gd's _ready calls PartFactoryCls.default_starting_loadout()
	# — same loadout a fresh-run player would have. Wait a frame for that
	# to settle, then mirror it into the picker.
	await get_tree().process_frame
	_refresh_part_picker()
	_refresh_equipped()


func _spawn_backdrop() -> void:
	_backdrop = Node2D.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_script(BackdropScript)
	add_child(_backdrop)


func _spawn_player() -> void:
	_player = PlayerScene.instantiate()
	add_child(_player)
	# Match the live-game spawn — Playfield.CENTER bottom-ish — exactly
	# where new_game() puts the player. No SubViewport routing; bullets
	# spawn at get_tree().root just like in combat.
	await get_tree().process_frame
	if "controls_enabled" in _player:
		_player.controls_enabled = true
	# Playfield is the autoload class with the band constants.
	_player.position = Vector2(Playfield.CENTER.x, Playfield.Y_MAX - 30.0)


func _spawn_dummy_target() -> void:
	_target = Area2D.new()
	_target.name = "DummyTarget"
	_target.add_to_group("enemies")
	# Position near the top of the playfield band so bullets travel a
	# full vertical sweep to reach it.
	_target.position = Vector2(Playfield.CENTER.x, Playfield.Y_MIN + 36.0)
	_target.set_script(DummyTargetScript)
	var spr := Sprite2D.new()
	var tex: Texture2D = load("res://graphics/extra-ships/ship_4.png")
	if tex == null:
		tex = load("res://graphics/extra-ships/ship_1.png")
	if tex:
		spr.texture = tex
	# 1:1 pixel parity with the player.
	spr.scale = Vector2(1, 1)
	_target.add_child(spr)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	_target.add_child(shape)
	var lbl := Label.new()
	lbl.text = "TARGET"
	lbl.position = Vector2(-20, 14)
	lbl.size = Vector2(40, 8)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 6)
	_target.add_child(lbl)
	add_child(_target)


# ---- UI ----------------------------------------------------------------

func _build_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "HangarUI"
	ui_layer.layer = 5
	add_child(ui_layer)

	var header := Label.new()
	header.text = "HANGAR  Esc closes"
	header.position = Vector2(4, 2)
	UiTheme.style_label(header, UiTheme.LabelKind.CAPTION)
	header.add_theme_font_size_override("font_size", 9)
	ui_layer.add_child(header)

	# Left gutter panel — slot + part picker + Mk slider + actions.
	# Playfield band is x 132-348; we have x 0-132 on the left and x
	# 348-480 on the right to work with.
	var left_panel := _make_panel(Vector2(4, 16), Vector2(124, 250))
	ui_layer.add_child(left_panel)
	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(left_scroll)
	var left_vb := VBoxContainer.new()
	left_vb.add_theme_constant_override("separation", 4)
	left_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left_vb)

	_add_caption(left_vb, "GROUP")
	_slot_picker = OptionButton.new()
	_slot_picker.custom_minimum_size = Vector2(0, 12)
	_slot_picker.add_theme_font_size_override("font_size", 9)
	for i in WEAPON_GROUPS.size():
		_slot_picker.add_item(String(WEAPON_GROUPS[i]["name"]), int(WEAPON_GROUPS[i]["slot"]))
	_slot_picker.item_selected.connect(_on_slot_picked)
	left_vb.add_child(_slot_picker)

	_add_caption(left_vb, "PART")
	_part_picker = OptionButton.new()
	_part_picker.custom_minimum_size = Vector2(0, 12)
	_part_picker.add_theme_font_size_override("font_size", 9)
	_part_picker.item_selected.connect(_on_part_selected)
	left_vb.add_child(_part_picker)

	_add_caption(left_vb, "MARK")
	_mark_label = Label.new()
	_mark_label.text = "Mk.1"
	_mark_label.add_theme_font_size_override("font_size", 9)
	left_vb.add_child(_mark_label)
	_mark_slider = HSlider.new()
	_mark_slider.min_value = 1
	_mark_slider.max_value = 9
	_mark_slider.step = 1
	_mark_slider.value = 1
	_mark_slider.custom_minimum_size = Vector2(0, 10)
	_mark_slider.value_changed.connect(_on_mark_changed)
	left_vb.add_child(_mark_slider)

	_add_button(left_vb, "Apply", _on_apply_part)
	_add_button(left_vb, "Clear", _on_clear_slot)
	_add_button(left_vb, "Back", _on_back)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(118, 0)
	_status_label.add_theme_font_size_override("font_size", 8)
	UiTheme.style_label(_status_label, UiTheme.LabelKind.CAPTION)
	left_vb.add_child(_status_label)

	# Preview label — shows stats for the currently-selected (not yet applied) part.
	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.custom_minimum_size = Vector2(118, 0)
	_preview_label.add_theme_font_size_override("font_size", 8)
	UiTheme.style_label(_preview_label, UiTheme.LabelKind.CAPTION)
	left_vb.add_child(_preview_label)

	# Right gutter — equipped summary.
	var right_panel := _make_panel(Vector2(352, 16), Vector2(124, 250))
	ui_layer.add_child(right_panel)
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(right_scroll)
	var right_vb := VBoxContainer.new()
	right_vb.add_theme_constant_override("separation", 4)
	right_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right_vb)
	_add_caption(right_vb, "EQUIPPED")
	_equipped_summary = Label.new()
	_equipped_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_equipped_summary.custom_minimum_size = Vector2(118, 0)
	_equipped_summary.add_theme_font_size_override("font_size", 9)
	UiTheme.style_label(_equipped_summary, UiTheme.LabelKind.BODY)
	right_vb.add_child(_equipped_summary)


func _make_panel(pos: Vector2, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.size = size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.85)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	return p


func _add_caption(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 8)
	UiTheme.style_label(l, UiTheme.LabelKind.CAPTION)
	parent.add_child(l)


func _add_button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 12)
	b.add_theme_font_size_override("font_size", 9)
	UiTheme.style_button(b, true)
	b.pressed.connect(cb)
	parent.add_child(b)


# ---- Slot / part handling -----------------------------------------------

func _on_slot_picked(idx: int) -> void:
	_selected_slot = _slot_picker.get_item_id(idx)
	_refresh_part_picker()


func _refresh_part_picker() -> void:
	if _part_picker == null:
		return
	_part_picker.clear()
	_part_picker.add_item("(none)", -1)
	var factories := _parts_for_slot(_selected_slot)
	for i in factories.size():
		_part_picker.add_item(_short_name(factories[i]), i)
	# Highlight what's already equipped in this slot via the live Loadout.
	var current = _loadout_part(_selected_slot)
	if current:
		var dn: String = String(current.display_name) if "display_name" in current else ""
		for i in factories.size():
			if _short_name(factories[i]) == _short_name(dn) or _short_name(factories[i]).to_lower() == dn.to_lower():
				_part_picker.select(i + 1)
				if _mark_slider:
					_mark_slider.set_value_no_signal(int(current.mark))
					if _mark_label:
						_mark_label.text = "Mk.%d" % int(current.mark)
				# Trigger preview for the now-selected item without firing the signal.
				_on_part_selected(_part_picker.selected)
				return
	_part_picker.select(0)
	# Trigger preview for "(none)" selection.
	_on_part_selected(0)


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


func _short_name(factory: String) -> String:
	var s := factory
	if s.begins_with("_make_"):
		s = s.substr(6)
	return s.replace("_", " ").capitalize()


func _on_mark_changed(v: float) -> void:
	if _mark_label:
		_mark_label.text = "Mk.%d" % int(v)
	# Refresh preview with updated mark — use current picker visual index.
	if _part_picker:
		_on_part_selected(_part_picker.selected)


# _on_part_selected: fires when item_selected signal fires (visual index),
# and is called manually after programmatic select() calls.
func _on_part_selected(visual_idx: int) -> void:
	if _preview_label == null:
		return
	# visual_idx 0 = "(none)"
	if visual_idx <= 0:
		_preview_label.text = ""
		return
	var factories := _parts_for_slot(_selected_slot)
	var factory_idx: int = visual_idx - 1
	if factory_idx >= factories.size():
		_preview_label.text = ""
		return
	var factory: String = factories[factory_idx]
	var mk: int = int(_mark_slider.value) if _mark_slider else 1
	var part = PartCatalog._make_by_name(factory, _selected_slot)
	if part == null:
		_preview_label.text = "PREVIEW\n(unavailable)"
		return
	var stats := _stats_for_part(part, mk)
	var part_name: String = String(part.display_name) if "display_name" in part else _short_name(factory)
	var lines: PackedStringArray = []
	lines.append("PREVIEW")
	lines.append("%s  Mk.%d" % [part_name, mk])
	lines.append(_format_stat_line(stats))
	var tags: PackedStringArray = []
	if stats.get("homing", false):
		tags.append("HOMING")
	var pods: int = stats.get("pods", 0)
	if pods > 1:
		tags.append("PODS x%d" % pods)
	if tags.size() > 0:
		lines.append(" ".join(tags))
	_preview_label.text = "\n".join(lines)


func _on_apply_part() -> void:
	var part_idx: int = _part_picker.get_selected_id()
	if part_idx < 0:
		_on_clear_slot()
		return
	var factories := _parts_for_slot(_selected_slot)
	if part_idx >= factories.size():
		return
	var factory: String = factories[part_idx]
	var part = PartCatalog._make_by_name(factory, _selected_slot)
	if part == null:
		_set_status("PartCatalog null for %s" % factory)
		return
	part.mark = int(_mark_slider.value)
	# Route through canonical Run.equip_part so secondary ammo + super charges
	# get seeded and any displaced same-slot part lands in weapon_storage. Then
	# mirror onto the live Player's Loadout so the in-Hangar test-fire reflects
	# the new part immediately (combat-start apply_to_player is what does this
	# in the real run; Hangar has a live ship already).
	Run.equip_part(part)
	if _player and _player.has_node("Loadout"):
		_player.get_node("Loadout").equip(_selected_slot, part)
	_set_status("Equipped %s Mk.%d" % [_short_name(factory), int(part.mark)])
	_refresh_equipped()


func _on_clear_slot() -> void:
	# Canonical Run-side clear first (snapshot + ammo/super state), then mirror
	# onto the live Player so the test ship loses the part immediately.
	Run.unequip_slot(_selected_slot)
	if _player and _player.has_node("Loadout"):
		var loadout = _player.get_node("Loadout")
		if loadout.has_method("unequip"):
			loadout.unequip(_selected_slot)
	_set_status("Cleared")
	_refresh_equipped()


func _refresh_equipped() -> void:
	if _equipped_summary == null:
		return
	var lines: PackedStringArray = []
	var is_super := false
	for group in WEAPON_GROUPS:
		var slot_id: int = int(group["slot"])
		is_super = (slot_id == SlotTypes.SlotType.DEVICE_BAY_1)
		# Short label: first word of group name, e.g. "Primary", "Secondary", "Super".
		var nm: String = String(group["name"]).split(" ")[0].to_upper()
		var p = _loadout_part(slot_id)
		if p != null:
			var dn: String = String(p.display_name) if "display_name" in p else "?"
			var mk: int = int(p.mark)
			lines.append(nm)
			lines.append("%s  Mk.%d" % [dn, mk])
			if not is_super:
				# Read live stats from the player for equipped weapons.
				var stat_line := _equipped_stat_line(slot_id)
				lines.append(stat_line)
		else:
			lines.append(nm)
			lines.append("—")  # em dash
		lines.append("")  # blank separator between groups
	# Trim trailing blank line.
	while lines.size() > 0 and lines[-1] == "":
		lines.resize(lines.size() - 1)
	_equipped_summary.text = "\n".join(lines)


func _equipped_stat_line(slot_id: int) -> String:
	if _player == null:
		return ""
	var dmg: int = 0
	var cooldown: float = 0.0
	var ammo: int = -1
	if slot_id == SlotTypes.SlotType.CANNON:
		if "bullet_damage" in _player:
			dmg = int(_player.bullet_damage)
		if "cooldown" in _player:
			cooldown = float(_player.cooldown)
		if "ammo" in _player:
			ammo = int(_player.ammo)
	elif slot_id == SlotTypes.SlotType.HARDPOINT_WING:
		if "secondary_damage" in _player:
			dmg = int(_player.secondary_damage)
		if "secondary_cooldown" in _player:
			cooldown = float(_player.secondary_cooldown)
		if "secondary_ammo" in _player:
			ammo = int(_player.secondary_ammo)
	var rof_str := "—"
	if cooldown > 0.0:
		rof_str = "%.1f/s" % (1.0 / cooldown)
	var ammo_str := "∞" if ammo < 0 else str(ammo)
	return "DMG %d  ROF %s  AMMO %s" % [dmg, rof_str, ammo_str]


func _loadout_part(slot_id: int) -> Resource:
	if _player == null or not _player.has_node("Loadout"):
		return null
	var lo = _player.get_node("Loadout")
	if lo.has_method("get_part"):
		return lo.get_part(slot_id)
	return null


# ---- Stat helpers --------------------------------------------------------

# Returns {dmg: int, rof: float, ammo: int, homing: bool, pods: int}
# ammo = -1 means unlimited.
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


# Formats the DMG/ROF/AMMO stat line from a stats dict.
func _format_stat_line(stats: Dictionary) -> String:
	var dmg: int = stats.get("dmg", 0)
	var rof: float = stats.get("rof", 0.0)
	var ammo: int = stats.get("ammo", -1)
	var rof_str := "—"
	if rof > 0.0:
		rof_str = "%.1f/s" % rof
	var ammo_str := "∞" if ammo < 0 else str(ammo)
	return "DMG %d  ROF %s  AMMO %s" % [dmg, rof_str, ammo_str]


# ---- Misc ---------------------------------------------------------------

func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()


func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg
