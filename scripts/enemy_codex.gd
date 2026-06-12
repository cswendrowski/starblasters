extends Control

# Codex — a faction-organized, game-data-driven reference the player browses to
# learn about the things they've encountered. (Rebuilt 2026-06-08, Roman.)
# HD 1920×1080 layout (style guide): sector_bg backdrop, CanvasLayer-hosted UI,
# container layout, UiTheme LabelKind typography (no native font pins).
#
# Navigation (left column): the four factions + Bosses + the Starblaster (player).
# Selecting a faction shows its codex entry + a roster of its enemies (discovered
# ones named, the rest "???"). Selecting a discovered enemy shows a slowly-rotating
# sprite (hull + glowmap + dropshadow, NO other shaders), its name, classification,
# and codex blurb.
#
# Everything is PULLED FROM THE GAME, not authored here:
#   - faction list / display name / tint .... Factions (factions.gd)
#   - faction / Starblaster codex text ....... CodexStrings (codex_strings.gd)
#   - enemy -> home faction .................. Factions.ENEMY_TAGS
#   - enemy display name + codex blurb ....... EnemyStrings (enemy_strings.gd)
#   - tier / size ............................ EnemyRoster.entry_for_scene
#   - discovered? ............................ Run.encountered_enemies
#   - sprite + glowmap ....................... the enemy scene's Sprite2D + GlowMask

const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const Factions = preload("res://scripts/levels/factions.gd")
const EnemyRoster = preload("res://scripts/levels/enemy_roster.gd")
const EnemyStrings = preload("res://scripts/enemy_strings.gd")
const CodexStrings = preload("res://scripts/codex_strings.gd")
const ArmoryStrings = preload("res://scripts/armory_strings.gd")
const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const SPIN_SPEED := 0.5      # rad/s — slow turntable
const PREVIEW_SCALE := 4.0   # native pixel sprite shown crisp at HD (nearest)
const TIER_NAMES := ["Common", "Uncommon", "Rare"]

var _hd_scope: HdViewportScope = null
var _cats: Array = []          # [{kind, fid?, key?}]
var _sel_cat: int = 0
var _view: String = "list"     # "list" | "detail"
var _detail_path: String = ""
var _right_root: VBoxContainer = null
var _nav_buttons: Array = []
var _preview_spin: Node2D = null


func _ready() -> void:
	_hd_scope = HdScreen.enter(self)
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")
	_cats = []
	for fid in [Factions.Id.SUPREMACY, Factions.Id.PRIVATEER, Factions.Id.CORPORATE, Factions.Id.ZEALOT]:
		_cats.append({"kind": "faction", "fid": fid, "key": Factions.id_key(fid)})
	_cats.append({"kind": "bosses"})
	_cats.append({"kind": "starblaster"})
	# Armory — the player's own kit, one category per slot class.
	_cats.append({"kind": "armory", "label": "Blasters", "slot": SlotTypes.SlotType.CANNON})
	_cats.append({"kind": "armory", "label": "Secondaries", "slot": SlotTypes.SlotType.HARDPOINT_WING})
	_cats.append({"kind": "armory", "label": "Super", "slot": SlotTypes.SlotType.DEVICE_BAY_1})
	_cats.append({"kind": "armory", "label": "Shift Modes", "slot": SlotTypes.SlotType.SHIFT_MODE})
	_build_ui()
	_show_category(0)


func _process(delta: float) -> void:
	if _preview_spin != null and is_instance_valid(_preview_spin):
		_preview_spin.rotation += delta * SPIN_SPEED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_to_menu()
		get_viewport().set_input_as_handled()


# ---- Static frame --------------------------------------------------------

func _build_ui() -> void:
	# Sector backdrop (mirrors run_summary.gd).
	var bg := TextureRect.new()
	bg.texture = load("res://graphics/ui/sector_bg.png")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)

	# UI on a CanvasLayer (mirrors manage_ship.gd) — immune to the HD input offset.
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 5
	ui_layer.name = "CodexUI"
	add_child(ui_layer)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 48)
	ui_layer.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 18)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "CODEX"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(title, UiTheme.LabelKind.TITLE)
	outer.add_child(title)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	# Left nav column (fixed width).
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	left.custom_minimum_size = Vector2(440, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	nav.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(nav)
	_nav_buttons = []
	for i in _cats.size():
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiTheme.style_button(b)
		b.pressed.connect(_show_category.bind(i))
		nav.add_child(b)
		_nav_buttons.append(b)
	# Spacer pushes Back to the bottom of the nav column.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	var back := Button.new()
	back.text = "Back to Menu"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(back)
	back.pressed.connect(_to_menu)
	nav.add_child(back)

	# Right content column (rebuilt on navigation).
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_right_root = VBoxContainer.new()
	_right_root.add_theme_constant_override("separation", 12)
	_right_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_right_root)

	_refresh_nav_labels()
	UiTheme.assert_inside_viewport.call_deferred(self)


func _to_menu() -> void:
	# If opened from the sector map (or another screen), return THERE instead of
	# the main menu (Roman 2026-06-11; one-shot meta set by the opener).
	var run := get_node_or_null("/root/Run")
	if run != null and run.has_meta("codex_return"):
		var dest := String(run.get_meta("codex_return"))
		run.remove_meta("codex_return")
		SceneTransition.change_scene(get_tree(), dest)
		return
	SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")


# ---- Navigation ----------------------------------------------------------

func _show_category(idx: int) -> void:
	_sel_cat = clampi(idx, 0, _cats.size() - 1)
	_view = "list"
	_detail_path = ""
	_refresh_nav_labels()
	_render_right()


func _show_enemy(path: String) -> void:
	_detail_path = path
	_view = "detail"
	_render_right()


func _refresh_nav_labels() -> void:
	for i in _nav_buttons.size():
		var b: Button = _nav_buttons[i]
		var cat: Dictionary = _cats[i]
		var label := _category_label(cat)
		if cat.kind == "faction" or cat.kind == "bosses":
			var paths := _category_paths(cat)
			label += "   %d/%d" % [_discovered_count(paths), paths.size()]
		b.text = label
		var col: Color = UiTheme.COLOR_ACCENT if i == _sel_cat else UiTheme.COLOR_TEXT
		b.add_theme_color_override("font_color", col)


# ---- Right pane render ----------------------------------------------------

func _render_right() -> void:
	_preview_spin = null
	if _right_root == null:
		return
	for c in _right_root.get_children():
		c.queue_free()
	var cat: Dictionary = _cats[_sel_cat]
	if cat.kind == "starblaster":
		_render_starblaster()
	elif cat.kind == "armory":
		if _view == "detail":
			_render_item_detail(cat, _detail_path)
		else:
			_render_armory_list(cat)
	elif _view == "detail":
		_render_enemy_detail(_detail_path)
	else:
		_render_category_list(cat)


func _render_category_list(cat: Dictionary) -> void:
	var header := _label(_category_label(cat), UiTheme.LabelKind.HEADER)
	if cat.kind == "faction":
		header.add_theme_color_override("font_color", _faction_tint(cat.fid))
	_right_root.add_child(header)
	if cat.kind == "faction":
		var blurb := _label(CodexStrings.faction_codex(cat.key), UiTheme.LabelKind.BODY)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_right_root.add_child(blurb)
	var paths := _category_paths(cat)
	var sub := _label("ROSTER   (%d/%d discovered)" % [_discovered_count(paths), paths.size()], UiTheme.LabelKind.CAPTION)
	_right_root.add_child(sub)
	# Scrollable roster.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_root.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	for path in paths:
		var row := Button.new()
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiTheme.style_button(row)
		if _is_discovered(path):
			row.text = EnemyStrings.display_name(path)
			row.pressed.connect(_show_enemy.bind(path))
		else:
			row.text = "???"
			row.disabled = true
		vb.add_child(row)


func _render_enemy_detail(path: String) -> void:
	var back := Button.new()
	back.text = "<  %s" % _category_label(_cats[_sel_cat])
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiTheme.style_button(back)
	back.pressed.connect(_show_category.bind(_sel_cat))
	_right_root.add_child(back)
	# Rotating sprite preview.
	_add_preview(path, "Sprite2D", "GlowMask", -1)
	# Name.
	var name_lbl := _label(EnemyStrings.display_name(path), UiTheme.LabelKind.HEADER)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_root.add_child(name_lbl)
	# Classification.
	var cls := _label(_classification(path), UiTheme.LabelKind.CAPTION)
	cls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_root.add_child(cls)
	# Codex blurb (scrollable).
	_add_blurb(EnemyStrings.codex_entry(path))


func _render_starblaster() -> void:
	var header := _label(CodexStrings.STARBLASTER["name"], UiTheme.LabelKind.HEADER)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
	_right_root.add_child(header)
	_add_preview(PLAYER_SCENE, "Ship", "", 1)
	_add_blurb(CodexStrings.STARBLASTER["codex"])


# ---- Armory (the player's own kit) ---------------------------------------

func _armory_factories(cat: Dictionary) -> Array:
	var out: Array = []
	for entry in PartCatalog._all_pool():
		if int(entry["slot"]) == int(cat.slot):
			out.append(String(entry["factory"]))
	# Focus mode is default-equipped (not in the roll pool) — list it anyway.
	if int(cat.slot) == int(SlotTypes.SlotType.SHIFT_MODE):
		out.push_front("_make_focus_mode")
	return out


func _render_armory_list(cat: Dictionary) -> void:
	var header := _label(String(cat.label), UiTheme.LabelKind.HEADER)
	header.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
	_right_root.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_root.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	for factory in _armory_factories(cat):
		var part = PartCatalog._make_by_name(factory, int(cat.slot))
		var row := Button.new()
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiTheme.style_button(row)
		row.text = String(part.display_name) if part != null else factory
		row.pressed.connect(_show_item.bind(factory))
		vb.add_child(row)


func _show_item(factory: String) -> void:
	_detail_path = factory
	_view = "detail"
	_render_right()


func _render_item_detail(cat: Dictionary, factory: String) -> void:
	var back := Button.new()
	back.text = "<  %s" % String(cat.label)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiTheme.style_button(back)
	back.pressed.connect(_show_category.bind(_sel_cat))
	_right_root.add_child(back)
	var part = PartCatalog._make_by_name(factory, int(cat.slot))
	# Preview the projectile sprite if the item has one (cannons / missiles). Modes,
	# the super, the beam + drones have no projectile sprite → name + blurb only (art TBD).
	if part != null and "bullet_scene" in part and part.bullet_scene != null:
		_add_preview(part.bullet_scene.resource_path, "Sprite2D", "", -1)
	var nm: String = String(part.display_name) if part != null else factory
	var name_lbl := _label(nm, UiTheme.LabelKind.HEADER)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_root.add_child(name_lbl)
	var cls := _label(String(cat.label), UiTheme.LabelKind.CAPTION)
	cls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_root.add_child(cls)
	var blurb: String = ArmoryStrings.codex_for(factory)
	if blurb == "" and part != null:
		blurb = String(part.description)
	_add_blurb(blurb)


func _add_blurb(text: String) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_root.add_child(scroll)
	var blurb := _label(text, UiTheme.LabelKind.BODY)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(blurb)


# ---- Sprite preview (hull + glowmap + dropshadow, no other shaders) -------

func _add_preview(scene_path: String, hull_name: String, glow_name: String, frame_override: int) -> void:
	# A fixed-size stage the rotating Node2D parents into, centered.
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, 320)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_root.add_child(stage)
	var packed = load(scene_path)
	if packed == null:
		return
	var inst = packed.instantiate()   # _init only — NOT added to the tree, so no _ready/movement/shaders
	var hull := _grab_named_or_first_sprite(inst, hull_name)
	var glow: Sprite2D = null
	if glow_name != "":
		var g = inst.get_node_or_null(glow_name)
		if g is Sprite2D:
			glow = g
	if hull == null:
		inst.free()
		return
	var holder := Node2D.new()
	holder.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	stage.add_child(holder)
	# Re-center the holder once the stage has a resolved width.
	_center_holder.call_deferred(holder, stage)
	# Static dropshadow — hull silhouette, dark, offset, behind.
	var shadow := _clone_sprite(hull, frame_override)
	shadow.modulate = Color(0, 0, 0, 0.32)
	shadow.position = Vector2(3, 4)
	shadow.z_index = -2
	holder.add_child(shadow)
	# Rotating hull (+ glowmap on top).
	var spin := Node2D.new()
	holder.add_child(spin)
	spin.add_child(_clone_sprite(hull, frame_override))
	if glow != null:
		spin.add_child(_clone_sprite(glow, -1))
	_preview_spin = spin
	inst.free()


func _center_holder(holder: Node2D, stage: Control) -> void:
	if is_instance_valid(holder) and is_instance_valid(stage):
		holder.position = Vector2(stage.size.x * 0.5, stage.custom_minimum_size.y * 0.5)


func _grab_named_or_first_sprite(inst, preferred: String) -> Sprite2D:
	var n = inst.get_node_or_null(preferred)
	if n is Sprite2D:
		return n
	return _search_sprite(inst)


func _search_sprite(node) -> Sprite2D:
	for c in node.get_children():
		if c is Sprite2D:
			return c
	for c in node.get_children():
		var r := _search_sprite(c)
		if r != null:
			return r
	return null


func _clone_sprite(src: Sprite2D, frame_override: int) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = src.texture
	sp.hframes = src.hframes
	sp.vframes = src.vframes
	sp.frame = frame_override if frame_override >= 0 else src.frame
	sp.flip_h = src.flip_h
	sp.flip_v = src.flip_v
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sp


# ---- Data helpers (all pulled from game sources) --------------------------

func _category_label(cat: Dictionary) -> String:
	match cat.kind:
		"faction":   return CodexStrings.faction_name(cat.key)
		"bosses":    return "Bosses"
		"starblaster": return CodexStrings.STARBLASTER["name"]
		"armory":    return String(cat.label)
	return "?"


func _category_paths(cat: Dictionary) -> Array:
	match cat.kind:
		"faction": return _faction_enemies(int(cat.fid))
		"bosses":  return _boss_paths()
	return []


func _faction_enemies(fid: int) -> Array:
	var out: Array = []
	for path in Factions.ENEMY_TAGS:
		if int(Factions.ENEMY_TAGS[path].get("home", -1)) == fid:
			out.append(path)
	out.sort_custom(func(a, b): return EnemyStrings.display_name(a) < EnemyStrings.display_name(b))
	return out


func _boss_paths() -> Array:
	var out: Array = []
	for path in EnemyStrings.STRINGS:
		if String(path).get_file().begins_with("boss"):
			out.append(path)
	out.sort()
	return out


func _is_discovered(path: String) -> bool:
	if not has_node("/root/Run"):
		return false
	return get_node("/root/Run").encountered_enemies.has(path)


func _discovered_count(paths: Array) -> int:
	var n := 0
	for p in paths:
		if _is_discovered(p):
			n += 1
	return n


func _classification(path: String) -> String:
	var parts: Array = []
	if Factions.ENEMY_TAGS.has(path):
		var fid := int(Factions.ENEMY_TAGS[path].get("home", -1))
		parts.append(CodexStrings.faction_name(Factions.id_key(fid)))
	elif String(path).get_file().begins_with("boss"):
		parts.append("Boss")
	var e: Dictionary = EnemyRoster.entry_for_scene(path)
	if not e.is_empty():
		var tier := int(e.get("tier", 0))
		if tier >= 0 and tier < TIER_NAMES.size():
			parts.append(TIER_NAMES[tier])
		var sz := String(e.get("size", ""))
		if sz != "":
			parts.append(sz.capitalize())
	return "   ·   ".join(parts)


func _faction_tint(fid: int) -> Color:
	var d: Dictionary = Factions.data(fid)
	return d.get("tint", UiTheme.COLOR_TEXT)


func _label(text: String, kind: int) -> Label:
	var l := Label.new()
	l.text = text
	UiTheme.style_label(l, kind)
	return l
