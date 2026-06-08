extends Control

# Codex — a faction-organized, game-data-driven reference the player browses to
# learn about the things they've encountered. (Rebuilt 2026-06-08, Roman.)
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

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const SPIN_SPEED := 0.5   # rad/s — slow turntable
const TIER_NAMES := ["Common", "Uncommon", "Rare"]

var _cats: Array = []          # [{kind, fid?, key?}]
var _sel_cat: int = 0
var _view: String = "list"     # "list" | "detail"
var _detail_path: String = ""
var _right_root: Control = null
var _nav_buttons: Array = []
var _preview_spin: Node2D = null


func _ready() -> void:
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")
	_cats = []
	for fid in [Factions.Id.SUPREMACY, Factions.Id.PRIVATEER, Factions.Id.CORPORATE, Factions.Id.ZEALOT]:
		_cats.append({"kind": "faction", "fid": fid, "key": Factions.id_key(fid)})
	_cats.append({"kind": "bosses"})
	_cats.append({"kind": "starblaster"})
	_build_ui()
	_show_category(0)


func _process(delta: float) -> void:
	if _preview_spin != null and is_instance_valid(_preview_spin):
		_preview_spin.rotation += delta * SPIN_SPEED


# ---- Static frame --------------------------------------------------------

func _build_ui() -> void:
	var vp: Vector2 = get_viewport_rect().size
	size = vp
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.10, 1.0)
	bg.size = vp
	add_child(bg)
	var title := Label.new()
	title.text = "CODEX"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(vp.x, 22)
	title.position = Vector2(0, 6)
	UiTheme.style_label(title, UiTheme.LabelKind.HEADER)
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)
	# Left nav column.
	var left := Panel.new()
	left.add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	left.size = Vector2(118, 226)
	left.position = Vector2(8, 30)
	add_child(left)
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 3)
	nav.position = Vector2(6, 6)
	nav.size = Vector2(106, 214)
	left.add_child(nav)
	_nav_buttons = []
	for i in _cats.size():
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UiTheme.style_button(b, true, 4)
		b.add_theme_font_size_override("font_size", 11)
		b.custom_minimum_size = Vector2(106, 20)
		b.pressed.connect(_show_category.bind(i))
		nav.add_child(b)
		_nav_buttons.append(b)
	# Right content panel + a root we rebuild on navigation.
	var right := Panel.new()
	right.add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	right.size = Vector2(340, 226)
	right.position = Vector2(132, 30)
	add_child(right)
	_right_root = Control.new()
	_right_root.position = Vector2(6, 6)
	_right_root.size = right.size - Vector2(12, 12)
	right.add_child(_right_root)
	# Back-to-menu (bottom-left under the nav).
	var back := Button.new()
	back.text = "Back to Menu"
	UiTheme.style_button(back, true, 4)
	back.add_theme_font_size_override("font_size", 11)
	back.position = Vector2(8, vp.y - 22)
	back.size = Vector2(118, 18)
	back.pressed.connect(func():
		SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")
	)
	add_child(back)
	_refresh_nav_labels()


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
		# Faction/Bosses show a discovered count.
		if cat.kind == "faction" or cat.kind == "bosses":
			var paths := _category_paths(cat)
			label += "  %d/%d" % [_discovered_count(paths), paths.size()]
		b.text = label
		# Selection highlight via font color.
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
	elif _view == "detail":
		_render_enemy_detail(_detail_path)
	else:
		_render_category_list(cat)


func _render_category_list(cat: Dictionary) -> void:
	var w: float = _right_root.size.x
	var y := 2.0
	# Header (faction name in its tint, or "Bosses").
	var header := _label(_category_label(cat), UiTheme.LabelKind.HEADER, 13)
	header.position = Vector2(4, y)
	header.size = Vector2(w - 8, 16)
	if cat.kind == "faction":
		header.add_theme_color_override("font_color", _faction_tint(cat.fid))
	_right_root.add_child(header)
	y += 18
	# Faction codex blurb.
	if cat.kind == "faction":
		var blurb := _label(CodexStrings.faction_codex(cat.key), UiTheme.LabelKind.BODY, 10)
		blurb.position = Vector2(4, y)
		blurb.size = Vector2(w - 8, 44)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_right_root.add_child(blurb)
		y += 48
	# Roster sub-header.
	var paths := _category_paths(cat)
	var sub := _label("ROSTER  (%d/%d discovered)" % [_discovered_count(paths), paths.size()], UiTheme.LabelKind.CAPTION, 9)
	sub.position = Vector2(4, y)
	sub.size = Vector2(w - 8, 12)
	_right_root.add_child(sub)
	y += 14
	# Scrollable roster list.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(4, y)
	scroll.size = Vector2(w - 8, _right_root.size.y - y - 2)
	_right_root.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	for path in paths:
		var discovered: bool = _is_discovered(path)
		var row := Button.new()
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UiTheme.style_button(row, true, 4)
		row.add_theme_font_size_override("font_size", 11)
		row.custom_minimum_size = Vector2(w - 24, 18)
		if discovered:
			row.text = EnemyStrings.display_name(path)
			row.pressed.connect(_show_enemy.bind(path))
		else:
			row.text = "???"
			row.disabled = true
		vb.add_child(row)


func _render_enemy_detail(path: String) -> void:
	var w: float = _right_root.size.x
	# Back to the category roster.
	var back := Button.new()
	back.text = "<  %s" % _category_label(_cats[_sel_cat])
	UiTheme.style_button(back, true, 4)
	back.add_theme_font_size_override("font_size", 10)
	back.position = Vector2(2, 2)
	back.size = Vector2(120, 16)
	back.pressed.connect(_show_category.bind(_sel_cat))
	_right_root.add_child(back)
	# Rotating sprite preview, centered in the upper area.
	_add_preview(path, "Sprite2D", "GlowMask", -1, Vector2(w * 0.5, 70))
	# Name.
	var name_lbl := _label(EnemyStrings.display_name(path), UiTheme.LabelKind.HEADER, 14)
	name_lbl.position = Vector2(4, 112)
	name_lbl.size = Vector2(w - 8, 18)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_right_root.add_child(name_lbl)
	# Classification line.
	var cls := _label(_classification(path), UiTheme.LabelKind.CAPTION, 9)
	cls.position = Vector2(4, 130)
	cls.size = Vector2(w - 8, 12)
	cls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_right_root.add_child(cls)
	# Codex blurb.
	var blurb := _label(EnemyStrings.codex_entry(path), UiTheme.LabelKind.BODY, 10)
	blurb.position = Vector2(6, 146)
	blurb.size = Vector2(w - 12, _right_root.size.y - 148)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_right_root.add_child(blurb)


func _render_starblaster() -> void:
	var w: float = _right_root.size.x
	var header := _label(CodexStrings.STARBLASTER["name"], UiTheme.LabelKind.HEADER, 14)
	header.position = Vector2(4, 4)
	header.size = Vector2(w - 8, 18)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
	_right_root.add_child(header)
	# The player's ship — forward-facing frame, rotating.
	_add_preview(PLAYER_SCENE, "Ship", "", 1, Vector2(w * 0.5, 78))
	var blurb := _label(CodexStrings.STARBLASTER["codex"], UiTheme.LabelKind.BODY, 10)
	blurb.position = Vector2(6, 130)
	blurb.size = Vector2(w - 12, _right_root.size.y - 132)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_right_root.add_child(blurb)


# ---- Sprite preview (hull + glowmap + dropshadow, no other shaders) -------

func _add_preview(scene_path: String, hull_name: String, glow_name: String, frame_override: int, center: Vector2) -> void:
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
	holder.position = center
	_right_root.add_child(holder)
	# Static dropshadow — hull silhouette, dark, offset, behind.
	var shadow := _clone_sprite(hull, frame_override)
	shadow.modulate = Color(0, 0, 0, 0.32)
	shadow.position = Vector2(4, 5)
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
	return "  ·  ".join(parts)


func _faction_tint(fid: int) -> Color:
	var d: Dictionary = Factions.data(fid)
	return d.get("tint", UiTheme.COLOR_TEXT)


func _label(text: String, kind: int, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	UiTheme.style_label(l, kind)
	l.add_theme_font_size_override("font_size", font_size)
	return l
