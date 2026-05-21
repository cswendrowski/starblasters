extends Control

# Hangar V3 — Cobalt 2026-05-20 rework.
#
# HD UI viewport (1920×1080 logical) wrapping a native 480×270 SubViewport
# that hosts the actual playfield. Same pattern as the parallax tuner —
# pixel-art look + HD-legible controls.
#
# Lets the player configure all ten ship slots with whatever PartCatalog
# advertises, with a per-slot Mk slider, then fly around in the center
# play space and shoot a dummy target at the top.
#
# Player.gd's bullet_parent override routes spawned bullets / drone shots
# into the SubViewport so they collide with the target instead of
# escaping into the root scene tree.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const BackdropScript = preload("res://scripts/galaxy_backdrop.gd")
const DummyTargetScript = preload("res://scripts/dev/hangar_dummy_target.gd")

const HD_VIEWPORT := Vector2i(1920, 1080)
const PLAYFIELD_VIEWPORT := Vector2i(480, 270)

# Positions in the SubViewport's native 480×270 coordinate space.
const TARGET_POS_NATIVE := Vector2(240, 36)
const PLAYER_SPAWN_NATIVE := Vector2(240, 220)


# ---- State ---------------------------------------------------------------

var _prev_scale_size: Vector2i = Vector2i.ZERO
var _playfield_viewport: SubViewport = null
var _playfield_display: TextureRect = null
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

var _selected_slot: int = SlotTypes.SlotType.CANNON
var _equipped_per_slot: Dictionary = {}


# ---- Lifecycle -----------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_enter_hd_viewport()
	_build_playfield_pipeline()
	_spawn_backdrop()
	_spawn_player()
	_spawn_dummy_target()
	_build_ui()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")
	# Defer so player.start() finishes wiring before we apply the loadout.
	await get_tree().process_frame
	_set_default_loadout()


func _enter_hd_viewport() -> void:
	var w := get_window()
	if w == null:
		return
	_prev_scale_size = w.content_scale_size
	w.content_scale_size = HD_VIEWPORT


func _exit_hd_viewport() -> void:
	var w := get_window()
	if w == null:
		return
	if _prev_scale_size != Vector2i.ZERO:
		w.content_scale_size = _prev_scale_size


func _exit_tree() -> void:
	_exit_hd_viewport()


# ---- Playfield SubViewport ----------------------------------------------

func _build_playfield_pipeline() -> void:
	_playfield_viewport = SubViewport.new()
	_playfield_viewport.name = "PlayfieldViewport"
	_playfield_viewport.size = PLAYFIELD_VIEWPORT
	_playfield_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_playfield_viewport.transparent_bg = false
	_playfield_viewport.handle_input_locally = false
	add_child(_playfield_viewport)

	_playfield_display = TextureRect.new()
	_playfield_display.name = "PlayfieldDisplay"
	_playfield_display.texture = _playfield_viewport.get_texture()
	_playfield_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_playfield_display.stretch_mode = TextureRect.STRETCH_SCALE
	_playfield_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_playfield_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_playfield_display)
	move_child(_playfield_display, 0)


func _spawn_backdrop() -> void:
	_backdrop = Node2D.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_script(BackdropScript)
	_playfield_viewport.add_child(_backdrop)


func _spawn_player() -> void:
	_player = PlayerScene.instantiate()
	_playfield_viewport.add_child(_player)
	# Route bullets / drones into the SubViewport instead of the root tree
	# so they collide with the dummy target.
	_player.bullet_parent = _playfield_viewport
	# Defer so player.start() (called inside player._ready) finishes wiring
	# autoload signals before we reposition.
	await get_tree().process_frame
	_player.position = PLAYER_SPAWN_NATIVE
	if "controls_enabled" in _player:
		_player.controls_enabled = true


func _spawn_dummy_target() -> void:
	_target = Area2D.new()
	_target.name = "DummyTarget"
	_target.add_to_group("enemies")
	_target.position = TARGET_POS_NATIVE
	_target.set_script(DummyTargetScript)
	var spr := Sprite2D.new()
	var tex: Texture2D = load("res://graphics/extra-ships/ship_4.png")
	if tex == null:
		tex = load("res://graphics/extra-ships/ship_1.png")
	if tex:
		spr.texture = tex
	spr.scale = Vector2(2, 2)
	_target.add_child(spr)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 24)
	shape.shape = rect
	_target.add_child(shape)
	var lbl := Label.new()
	lbl.text = "TARGET"
	lbl.position = Vector2(-30, 18)
	lbl.size = Vector2(60, 12)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 9)
	_target.add_child(lbl)
	_playfield_viewport.add_child(_target)


# ---- HD UI rail ---------------------------------------------------------

func _build_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "HangarUI"
	ui_layer.layer = 20
	add_child(ui_layer)

	var header := Label.new()
	header.text = "HANGAR — WASD fly, SPACE primary, G secondary, X super, Esc closes"
	header.position = Vector2(24, 16)
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	ui_layer.add_child(header)

	# Left rail — slot + part selection + Mk + buttons.
	var left_panel := _make_panel(Vector2(24, 56), Vector2(420, 980))
	ui_layer.add_child(left_panel)
	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(left_scroll)
	var left_vb := VBoxContainer.new()
	left_vb.add_theme_constant_override("separation", 6)
	left_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left_vb)

	_add_caption(left_vb, "SLOT")
	_slot_picker = OptionButton.new()
	_slot_picker.custom_minimum_size = Vector2(0, 28)
	for slot_id in SlotTypes.ALL_SLOTS:
		_slot_picker.add_item(SlotTypes.slot_name(slot_id), slot_id)
	_slot_picker.item_selected.connect(_on_slot_picked)
	left_vb.add_child(_slot_picker)

	_add_caption(left_vb, "PART")
	_part_picker = OptionButton.new()
	_part_picker.custom_minimum_size = Vector2(0, 28)
	left_vb.add_child(_part_picker)

	_add_caption(left_vb, "MARK")
	_mark_label = Label.new()
	_mark_label.text = "Mk.1"
	UiTheme.style_label(_mark_label, UiTheme.LabelKind.BODY)
	left_vb.add_child(_mark_label)
	_mark_slider = HSlider.new()
	_mark_slider.min_value = 1
	_mark_slider.max_value = 9
	_mark_slider.step = 1
	_mark_slider.value = 1
	_mark_slider.custom_minimum_size = Vector2(0, 24)
	_mark_slider.value_changed.connect(_on_mark_changed)
	left_vb.add_child(_mark_slider)

	_add_button(left_vb, "Apply to Slot", _on_apply_part)
	_add_button(left_vb, "Clear Slot", _on_clear_slot)
	left_vb.add_child(HSeparator.new())
	_add_button(left_vb, "Reset Player Position", _on_reset_player)
	left_vb.add_child(HSeparator.new())
	_add_button(left_vb, "Back to Dev Menu", _on_back)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(380, 0)
	UiTheme.style_label(_status_label, UiTheme.LabelKind.CAPTION)
	left_vb.add_child(_status_label)

	# Right rail — equipped summary across all slots.
	var right_panel := _make_panel(Vector2(1476, 56), Vector2(420, 980))
	ui_layer.add_child(right_panel)
	var right_vb := VBoxContainer.new()
	right_vb.add_theme_constant_override("separation", 4)
	right_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(right_vb)
	_add_caption(right_vb, "EQUIPPED")
	_equipped_summary = Label.new()
	_equipped_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_equipped_summary.custom_minimum_size = Vector2(380, 0)
	UiTheme.style_label(_equipped_summary, UiTheme.LabelKind.BODY)
	right_vb.add_child(_equipped_summary)

	_refresh_part_picker()
	_refresh_equipped()


func _make_panel(pos: Vector2, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.size = size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.86)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	return p


func _add_caption(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	UiTheme.style_label(l, UiTheme.LabelKind.CAPTION)
	parent.add_child(l)


func _add_button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 28)
	UiTheme.style_button(b, true)
	b.pressed.connect(cb)
	parent.add_child(b)


# ---- Slot / part handling -----------------------------------------------

func _on_slot_picked(idx: int) -> void:
	_selected_slot = _slot_picker.get_item_id(idx)
	_refresh_part_picker()


func _refresh_part_picker() -> void:
	_part_picker.clear()
	_part_picker.add_item("(none)", -1)
	var factories := _parts_for_slot(_selected_slot)
	for i in factories.size():
		_part_picker.add_item(_short_name(factories[i]), i)
	# Highlight what's currently equipped in this slot, if anything.
	if _equipped_per_slot.has(_selected_slot):
		var cur = _equipped_per_slot[_selected_slot]
		var cur_factory: String = String(cur.get_meta("factory", ""))
		for i in factories.size():
			if factories[i] == cur_factory:
				_part_picker.select(i + 1)
				if _mark_slider:
					_mark_slider.set_value_no_signal(int(cur.mark))
					if _mark_label:
						_mark_label.text = "Mk.%d" % int(cur.mark)
				return
	_part_picker.select(0)


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
		_set_status("PartCatalog returned null for %s" % factory)
		return
	part.mark = int(_mark_slider.value)
	# Stash the factory name on the part so the picker can resync when the
	# user swaps slots and back.
	part.set_meta("factory", factory)
	_equipped_per_slot[_selected_slot] = part
	if _player and _player.has_node("Loadout"):
		_player.get_node("Loadout").equip(_selected_slot, part)
	_set_status("Equipped %s Mk.%d in %s" % [_short_name(factory), int(part.mark), SlotTypes.slot_name(_selected_slot)])
	_refresh_equipped()


func _on_clear_slot() -> void:
	if _equipped_per_slot.has(_selected_slot):
		_equipped_per_slot.erase(_selected_slot)
	if _player and _player.has_node("Loadout"):
		var loadout = _player.get_node("Loadout")
		if loadout.has_method("clear"):
			loadout.clear(_selected_slot)
		elif loadout.has_method("unequip"):
			loadout.unequip(_selected_slot)
	_set_status("Cleared %s" % SlotTypes.slot_name(_selected_slot))
	_refresh_equipped()


func _refresh_equipped() -> void:
	if _equipped_summary == null:
		return
	var lines: PackedStringArray = []
	for slot_id in SlotTypes.ALL_SLOTS:
		var nm: String = SlotTypes.slot_name(slot_id)
		if _equipped_per_slot.has(slot_id):
			var p = _equipped_per_slot[slot_id]
			var dn: String = String(p.display_name) if "display_name" in p else "?"
			lines.append("%s — %s Mk.%d" % [nm, dn, int(p.mark)])
		else:
			lines.append("%s — (empty)" % nm)
	_equipped_summary.text = "\n".join(lines)


func _set_default_loadout() -> void:
	# Seed slots with a sane default loadout so the user can fly + fire on
	# entry without configuring anything. Mirrors the PlayerLoadout defaults
	# the live game uses on a new run.
	var defaults := [
		[SlotTypes.SlotType.CANNON,    "_make_basic_blaster"],
		[SlotTypes.SlotType.SHIELD,    "_make_basic_shield"],
		[SlotTypes.SlotType.WING_LEFT, "_make_basic_wing"],
		[SlotTypes.SlotType.WING_RIGHT, "_make_basic_wing"],
		[SlotTypes.SlotType.TAIL,      "_make_basic_tail"],
		[SlotTypes.SlotType.ENGINE,    "_make_basic_engine"],
	]
	for d in defaults:
		var slot: int = d[0]
		var factory: String = d[1]
		var part = PartCatalog._make_by_name(factory, slot)
		if part == null:
			continue
		part.mark = 1
		part.set_meta("factory", factory)
		_equipped_per_slot[slot] = part
		if _player and _player.has_node("Loadout"):
			_player.get_node("Loadout").equip(slot, part)
	_refresh_part_picker()
	_refresh_equipped()


# ---- Misc ---------------------------------------------------------------

func _on_reset_player() -> void:
	if _player and is_instance_valid(_player):
		_player.position = PLAYER_SPAWN_NATIVE


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()


func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg
