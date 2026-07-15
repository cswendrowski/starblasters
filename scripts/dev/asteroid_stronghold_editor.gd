extends Control

# Asteroid Stronghold editor (Roman 2026-07-13) — a mouse-driven prefab editor. Generate an asteroid
# (near-layer look; seed/size/roundness/dither/tint knobs) and place destructible "building" enemies
# on it with the mouse, then save reusable prefabs. Native 480×270 dev tool (mirrors path_editor):
# controls in the side gutters, the rock + buildings in the center.
#
#   L-click empty : place the selected building brush at that offset (spawns a LIVE instance)
#   L-click a node: drag it (moves the offset + the live instance)
#   R-click a node: delete it
#
# The live buildings are the real ground-structure scenes (stronghold_building_palette.gd), so turrets
# actually track + fire at a cursor-following dummy "player" — the preview dogfoods the runtime. Save
# writes JSON to user://tuners/asteroid_strongholds.json; Copy GDScript emits a paste-ready DATA entry
# for scripts/levels/asteroid_strongholds.gd. The rock visual is built via the runtime scene's shared
# static builder (asteroid_stronghold.gd::build_rock_visual) so the editor and game look identical.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const Palette = preload("res://scripts/enemies/stronghold_building_palette.gd")
const Stronghold = preload("res://scripts/enemies/asteroid_stronghold.gd")
const Strongholds = preload("res://scripts/levels/asteroid_strongholds.gd")

const SAVE_PATH := "user://tuners/asteroid_strongholds.json"
const SZ := 7
const GRAB := 8.0                       # px pick radius for grabbing/deleting a building
const ROCK_CENTER := Vector2(240.0, 135.0)
const PANEL_L := 128.0                   # left gutter right edge — canvas starts past it
const PANEL_R := 348.0                   # right gutter left edge — canvas ends before it

# Asteroid tint presets cycled by the tint knob ([r, g, b]).
const TINTS := [
	[0.70, 0.66, 0.60],   # sand
	[0.55, 0.58, 0.66],   # slate
	[0.66, 0.52, 0.46],   # rust
	[0.50, 0.62, 0.58],   # jade
	[0.62, 0.58, 0.70],   # violet-grey
	[0.72, 0.70, 0.52],   # ochre
]

var _library: Array = []                # Array of prefab dicts
var _idx: int = 0
var _buildings: Array = []              # working building entries {type, x, y} for the current prefab
var _live: Array = []                   # parallel LIVE building instances
var _brush: String = "square_turret"
var _brush_rot: int = 0                 # rotation for NEW placements, locked to 90° steps (pixel-safe)
var _drag_i: int = -1
var _tint_i: int = 0

var _world: Node2D = null
var _overlay: Node2D = null
var _rock: Node = null                  # live rock visual
var _dummy: Node2D = null               # cursor-following target in group "player" (turret aim)
var _font: Font = null

var _name_edit: LineEdit = null
var _size_lbl: Label = null
var _round_lbl: Label = null
var _dither_btn: Button = null
var _tint_lbl: Label = null
var _drift_lbl: Label = null
var _seed_lbl: Label = null
var _status_lbl: Label = null
var _prefab_list: VBoxContainer = null
var _brush_btns: Dictionary = {}


func _ready() -> void:
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("silent")
	_font = UiTheme.active_font()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Default the brush to a building that actually exists (the palette self-discovers from the roster).
	if not Palette.is_type(_brush):
		var _bt := Palette.types()
		_brush = String(_bt[0]) if not _bt.is_empty() else ""
	_load_library()
	_build_bg()
	_build_world()
	_build_ui()
	_select_prefab(0)


# ---------------------------------------------------------------- library / prefab

func _blank_prefab() -> Dictionary:
	return {
		"name": "stronghold_%d" % _library.size(),
		"asteroid": {"seed": randi() % 100000, "size": 120.0, "roundness": 0.0,
			"dither": true, "tint": TINTS[0].duplicate(), "drift_speed": 40.0},
		"buildings": [],
	}


# Fill in any missing asteroid/building keys so partial JSON / DATA entries load safely.
func _normalize(p: Dictionary) -> Dictionary:
	var ast: Dictionary = p.get("asteroid", {}) if p.get("asteroid", null) is Dictionary else {}
	var tint: Variant = ast.get("tint", null)
	p["asteroid"] = {
		"seed": int(ast.get("seed", 0)),
		"size": float(ast.get("size", 120.0)),
		"roundness": float(ast.get("roundness", 0.0)),
		"dither": bool(ast.get("dither", true)),
		"tint": (tint if tint is Array and (tint as Array).size() >= 3 else TINTS[0].duplicate()),
		"drift_speed": float(ast.get("drift_speed", 40.0)),
	}
	if not (p.get("buildings", null) is Array):
		p["buildings"] = []
	if not p.has("name"):
		p["name"] = "stronghold_%d" % _library.size()
	return p


func _load_library() -> void:
	_library = []
	var user_names := {}
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Array:
				for e in parsed:
					if e is Dictionary:
						_library.append(_normalize(e))
						user_names[String(e.get("name", ""))] = true
	# Append committed DATA entries not shadowed by a user prefab of the same name.
	for d in Strongholds.DATA:
		if d is Dictionary and not user_names.has(String(d.get("name", ""))):
			_library.append(_normalize((d as Dictionary).duplicate(true)))
	if _library.is_empty():
		_library.append(_blank_prefab())


func _cur() -> Dictionary:
	if _library.is_empty():
		return {}
	_idx = clampi(_idx, 0, _library.size() - 1)
	return _library[_idx]


func _ast() -> Dictionary:
	var c := _cur()
	if not (c.get("asteroid", null) is Dictionary):
		c["asteroid"] = _blank_prefab()["asteroid"]
	return c["asteroid"]


func _select_prefab(i: int) -> void:
	_sync_current()
	_idx = (i + _library.size()) % _library.size()
	_buildings = []
	for b in _cur().get("buildings", []):
		if b is Dictionary:
			_buildings.append((b as Dictionary).duplicate(true))
	_tint_i = _match_tint(_ast().get("tint", []))
	_rebuild_rock()
	_rebuild_buildings()
	_refresh_labels()
	if _overlay:
		_overlay.queue_redraw()


func _sync_current() -> void:
	if _library.is_empty():
		return
	var out: Array = []
	for b in _buildings:
		out.append({
			"type": String(b.get("type", "")),
			"x": snappedf(float(b.get("x", 0.0)), 0.5),
			"y": snappedf(float(b.get("y", 0.0)), 0.5),
			"rot": int(b.get("rot", 0)) % 360,
		})
	_cur()["buildings"] = out


func _new_prefab() -> void:
	_sync_current()
	_library.append(_blank_prefab())
	_select_prefab(_library.size() - 1)


func _dup_prefab() -> void:
	_sync_current()
	var p: Dictionary = _cur().duplicate(true)
	p["name"] = String(p.get("name", "stronghold")) + "_copy"
	_library.append(p)
	_select_prefab(_library.size() - 1)


func _del_prefab() -> void:
	if _library.size() <= 1:
		_library[0] = _blank_prefab()
		_select_prefab(0)
		return
	_library.remove_at(_idx)
	_select_prefab(_idx)


func _match_tint(t: Variant) -> int:
	if t is Array and (t as Array).size() >= 3:
		for i in TINTS.size():
			if is_equal_approx(float(TINTS[i][0]), float(t[0])) \
				and is_equal_approx(float(TINTS[i][1]), float(t[1])) \
				and is_equal_approx(float(TINTS[i][2]), float(t[2])):
				return i
	return 0


# ---------------------------------------------------------------- world / preview

func _build_bg() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	# Cursor-following dummy in group "player" so turrets/guns resolve a target and visibly fire.
	_dummy = Node2D.new()
	_dummy.name = "CursorTarget"
	_dummy.add_to_group("player")
	_world.add_child(_dummy)
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay.draw.connect(_draw_overlay)
	_world.add_child(_overlay)


func _rebuild_rock() -> void:
	if _rock != null and is_instance_valid(_rock):
		_rock.queue_free()
	_rock = Stronghold.build_rock_visual(_world, _ast())
	if _rock != null:
		_rock.position += ROCK_CENTER
	_restack()


func _rebuild_buildings() -> void:
	for inst in _live:
		if inst != null and is_instance_valid(inst):
			inst.queue_free()
	_live = []
	for b in _buildings:
		var t := String(b.get("type", ""))
		if Palette.is_type(t):
			var off := ROCK_CENTER + Vector2(float(b.get("x", 0.0)), float(b.get("y", 0.0)))
			_live.append(Palette.spawn(t, _world, off, float(b.get("rot", 0))))
		else:
			_live.append(null)
	_restack()


# Keep the rock behind the buildings and the overlay on top.
func _restack() -> void:
	if _rock != null and is_instance_valid(_rock):
		_world.move_child(_rock, 0)
	if _overlay != null and is_instance_valid(_overlay):
		_world.move_child(_overlay, _world.get_child_count() - 1)


func _draw_overlay() -> void:
	# Rock body radius (authoring guide — the contact hitbox in game).
	var r: float = float(_ast().get("size", 120.0)) * 0.45
	_overlay.draw_arc(ROCK_CENTER, r, 0.0, TAU, 48, Color(0.5, 0.7, 1.0, 0.25), 1.0)
	# Building handles.
	for i in _buildings.size():
		var c: Vector2 = ROCK_CENTER + Vector2(float(_buildings[i].get("x", 0.0)), float(_buildings[i].get("y", 0.0)))
		var col: Color = Color(1.0, 0.9, 0.4, 0.95) if i == _drag_i else Color(0.6, 0.85, 1.0, 0.95)
		_overlay.draw_circle(c, 2.5, col)
		var t: String = String(_buildings[i].get("type", ""))
		var lbl: String = Palette.label_for(t).substr(0, 1)
		_overlay.draw_string(_font, c + Vector2(3.0, -2.0), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(1, 1, 1, 0.7))
		# Orientation tick — points in the building's "up" rotated by its rot (0/90/180/270).
		var rr: float = float(int(_buildings[i].get("rot", 0)))
		_overlay.draw_line(c, c + Vector2.UP.rotated(deg_to_rad(rr)) * 5.0, col, 1.0)


func _process(_delta: float) -> void:
	if _dummy != null:
		_dummy.global_position = get_global_mouse_position()
	if _overlay:
		_overlay.queue_redraw()


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
		return
	# R: rotate 90° (pixel-safe). On a building under the cursor → rotate it; otherwise cycle the brush
	# rotation for the next placements.
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		var mpos: Vector2 = get_global_mouse_position()
		var hit: int = _pick_building(mpos) if _in_canvas(mpos) else -1
		if hit >= 0:
			_rotate_building(hit)
		else:
			_brush_rot = (_brush_rot + 90) % 360
			_update_status()
		return
	if event is InputEventMouseButton and event.pressed:
		var pos: Vector2 = get_global_mouse_position()
		if not _in_canvas(pos):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			var hit: int = _pick_building(pos)
			if hit >= 0:
				_drag_i = hit
			else:
				_place_building(pos)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var h: int = _pick_building(pos)
			if h >= 0:
				_delete_building(h)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _drag_i >= 0:
			_drag_i = -1
			_sync_current()
			_update_status()
	elif event is InputEventMouseMotion and _drag_i >= 0 and _drag_i < _buildings.size():
		var mp: Vector2 = get_global_mouse_position()
		var off: Vector2 = mp - ROCK_CENTER
		_buildings[_drag_i]["x"] = snappedf(off.x, 0.5)
		_buildings[_drag_i]["y"] = snappedf(off.y, 0.5)
		if _drag_i < _live.size() and _live[_drag_i] != null and is_instance_valid(_live[_drag_i]):
			(_live[_drag_i] as Node2D).position = mp
		if _overlay:
			_overlay.queue_redraw()


func _in_canvas(pos: Vector2) -> bool:
	return pos.x > PANEL_L and pos.x < PANEL_R and pos.y >= 0.0 and pos.y <= 270.0


func _pick_building(pos: Vector2) -> int:
	for i in _buildings.size():
		var c: Vector2 = ROCK_CENTER + Vector2(float(_buildings[i].get("x", 0.0)), float(_buildings[i].get("y", 0.0)))
		if c.distance_to(pos) <= GRAB:
			return i
	return -1


func _place_building(pos: Vector2) -> void:
	var off: Vector2 = pos - ROCK_CENTER
	_buildings.append({"type": _brush, "x": snappedf(off.x, 0.5), "y": snappedf(off.y, 0.5), "rot": _brush_rot})
	_live.append(Palette.spawn(_brush, _world, pos, float(_brush_rot)))
	_restack()
	_sync_current()
	_update_status()
	if _overlay:
		_overlay.queue_redraw()


# Rotate a placed building by +90° (locked to 0/90/180/270 so nearest-filter pixels stay crisp).
func _rotate_building(i: int) -> void:
	if i < 0 or i >= _buildings.size():
		return
	var r: int = (int(_buildings[i].get("rot", 0)) + 90) % 360
	_buildings[i]["rot"] = r
	if i < _live.size() and _live[i] != null and is_instance_valid(_live[i]) and _live[i] is Node2D:
		(_live[i] as Node2D).rotation_degrees = float(r)
	_sync_current()
	if _overlay:
		_overlay.queue_redraw()


func _delete_building(i: int) -> void:
	if i < 0 or i >= _buildings.size():
		return
	if i < _live.size() and _live[i] != null and is_instance_valid(_live[i]):
		_live[i].queue_free()
	if i < _live.size():
		_live.remove_at(i)
	_buildings.remove_at(i)
	_sync_current()
	_update_status()
	if _overlay:
		_overlay.queue_redraw()


# ---------------------------------------------------------------- knobs

func _new_asteroid() -> void:
	_ast()["seed"] = randi() % 100000
	_rebuild_rock()
	_refresh_labels()


func _cycle_size(d: int) -> void:
	_ast()["size"] = clampf(float(_ast().get("size", 120.0)) + 8.0 * float(d), 48.0, 220.0)
	_rebuild_rock()
	_refresh_labels()


func _cycle_round(d: int) -> void:
	_ast()["roundness"] = clampf(float(_ast().get("roundness", 0.0)) + 0.1 * float(d), 0.0, 1.0)
	_rebuild_rock()
	_refresh_labels()


func _toggle_dither() -> void:
	_ast()["dither"] = not bool(_ast().get("dither", true))
	_rebuild_rock()
	_refresh_labels()


func _cycle_tint(d: int) -> void:
	_tint_i = (_tint_i + d + TINTS.size()) % TINTS.size()
	_ast()["tint"] = TINTS[_tint_i].duplicate()
	_rebuild_rock()
	_refresh_labels()


func _cycle_drift(d: int) -> void:
	_ast()["drift_speed"] = clampf(float(_ast().get("drift_speed", 40.0)) + 10.0 * float(d), 0.0, 120.0)
	_refresh_labels()


func _set_brush(t: String) -> void:
	_brush = t
	_refresh_brush_btns()


# ---------------------------------------------------------------- save / copy

func _save_json() -> void:
	_sync_current()
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_library, "\t"))
		f.close()
		_set_status("saved %d prefabs" % _library.size())
	else:
		_set_status("save failed")


func _copy_gdscript() -> void:
	_sync_current()
	# Emit a paste-ready DATA element for asteroid_strongholds.gd (JSON literal = valid GDScript).
	var text: String = "\t" + JSON.stringify(_cur(), "\t") + ",\n"
	DisplayServer.clipboard_set(text)
	_set_status("copied '%s' → clipboard" % String(_cur().get("name", "stronghold")))


func _commit_name(t: String) -> void:
	var nm: String = t.strip_edges()
	if nm != "":
		_cur()["name"] = nm
		if _prefab_list:
			_rebuild_prefab_list()


func _on_back() -> void:
	_sync_current()
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	# Left gutter — prefab nav + asteroid knobs + actions.
	var left := _make_panel(Vector2(0, 0), Vector2(128, 270))
	add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 2)
	left.add_child(lv)
	_fill_panel(lv)

	lv.add_child(_new_label("ASTEROID STRONGHOLD", UiTheme.COLOR_ACCENT, SZ))

	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 2)
	lv.add_child(pr)
	_add_fixed_button(pr, "<", func(): _select_prefab(_idx - 1), 14)
	_name_edit = LineEdit.new()
	_name_edit.add_theme_font_size_override("font_size", SZ)
	_name_edit.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.text_submitted.connect(_commit_name)
	_name_edit.focus_exited.connect(func(): _commit_name(_name_edit.text))
	pr.add_child(_name_edit)
	_add_fixed_button(pr, ">", func(): _select_prefab(_idx + 1), 14)
	var pr2 := HBoxContainer.new()
	pr2.add_theme_constant_override("separation", 2)
	lv.add_child(pr2)
	_add_button(pr2, "New", _new_prefab)
	_add_button(pr2, "Dup", _dup_prefab)
	_add_button(pr2, "Del", _del_prefab)

	lv.add_child(_sep())
	_add_caption(lv, "ASTEROID")
	_add_button(lv, "New Asteroid", _new_asteroid)
	_seed_lbl = _new_label("seed -", UiTheme.COLOR_FAINT, SZ)
	lv.add_child(_seed_lbl)
	_size_lbl = _knob_row(lv, "size", func(): _cycle_size(-1), func(): _cycle_size(1))
	_round_lbl = _knob_row(lv, "round", func(): _cycle_round(-1), func(): _cycle_round(1))
	_dither_btn = _add_button(lv, "dither: on", _toggle_dither)
	_tint_lbl = _knob_row(lv, "tint", func(): _cycle_tint(-1), func(): _cycle_tint(1))
	_drift_lbl = _knob_row(lv, "drift", func(): _cycle_drift(-1), func(): _cycle_drift(1))

	lv.add_child(_sep())
	var a1 := HBoxContainer.new()
	a1.add_theme_constant_override("separation", 2)
	lv.add_child(a1)
	_add_button(a1, "Save", _save_json)
	_add_button(a1, "Copy GDScript", _copy_gdscript)
	_add_button(lv, "Back", _on_back)
	_status_lbl = _new_label("", UiTheme.COLOR_FAINT, SZ)
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.custom_minimum_size = Vector2(120, 0)
	lv.add_child(_status_lbl)

	# Right gutter — building brush + help + prefab list.
	var right := _make_panel(Vector2(348, 0), Vector2(132, 270))
	add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 2)
	right.add_child(rv)
	_fill_panel(rv)
	_add_caption(rv, "BUILDING")
	# Bounded scroll so a growing building roster doesn't shove HELP / PREFABS off the bottom of the panel.
	var bscroll := ScrollContainer.new()
	bscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bscroll.custom_minimum_size = Vector2(0, 90)
	rv.add_child(bscroll)
	var bvb := VBoxContainer.new()
	bvb.add_theme_constant_override("separation", 1)
	bvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bscroll.add_child(bvb)
	for t in Palette.types():
		var key: String = String(t)
		var b := _add_button(bvb, Palette.label_for(key), func(): _set_brush(key))
		_brush_btns[key] = b
	rv.add_child(_sep())
	_add_caption(rv, "HELP")
	rv.add_child(_new_label("L-click: place", UiTheme.COLOR_TEXT, SZ))
	rv.add_child(_new_label("drag: move", UiTheme.COLOR_TEXT, SZ))
	rv.add_child(_new_label("R-click: delete", UiTheme.COLOR_TEXT, SZ))
	rv.add_child(_new_label("R: rotate 90", UiTheme.COLOR_TEXT, SZ))
	rv.add_child(_sep())
	_add_caption(rv, "PREFABS")
	var lscroll := ScrollContainer.new()
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(lscroll)
	_prefab_list = VBoxContainer.new()
	_prefab_list.add_theme_constant_override("separation", 1)
	_prefab_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lscroll.add_child(_prefab_list)
	_rebuild_prefab_list()
	_refresh_brush_btns()


func _rebuild_prefab_list() -> void:
	if _prefab_list == null:
		return
	for ch in _prefab_list.get_children():
		_prefab_list.remove_child(ch)
		ch.queue_free()
	for i in _library.size():
		var idx: int = i
		var nm: String = String(_library[i].get("name", "stronghold"))
		var b := _add_button(_prefab_list, nm, func(): _select_prefab(idx))
		b.custom_minimum_size = Vector2(0, 14)


func _refresh_brush_btns() -> void:
	for k in _brush_btns.keys():
		var b: Button = _brush_btns[k]
		if b == null:
			continue
		b.add_theme_color_override("font_color", UiTheme.COLOR_TEXT if k == _brush else UiTheme.COLOR_ACCENT)


func _refresh_labels() -> void:
	if _name_edit and not _name_edit.has_focus():
		_name_edit.text = String(_cur().get("name", "-"))
	if _seed_lbl:
		_seed_lbl.text = "seed %d" % int(_ast().get("seed", 0))
	if _size_lbl:
		_size_lbl.text = "size: %d" % int(_ast().get("size", 120.0))
	if _round_lbl:
		_round_lbl.text = "round: %.1f" % float(_ast().get("roundness", 0.0))
	if _dither_btn:
		_dither_btn.text = "dither: on" if bool(_ast().get("dither", true)) else "dither: off"
	if _tint_lbl:
		_tint_lbl.text = "tint: %d" % (_tint_i + 1)
	if _drift_lbl:
		_drift_lbl.text = "drift: %d" % int(_ast().get("drift_speed", 40.0))
	if _prefab_list:
		_rebuild_prefab_list()
	_update_status()


func _update_status() -> void:
	if _status_lbl == null:
		return
	_status_lbl.text = "%d bld  %s  r%d" % [_buildings.size(), Palette.label_for(_brush), _brush_rot]


func _set_status(s: String) -> void:
	if _status_lbl:
		_status_lbl.text = s


# ---------------------------------------------------------------- UI helpers (mirrors path_editor)

func _style_label(l: Label, color: Color, size: int) -> void:
	l.add_theme_font_override("font", UiTheme.active_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	l.add_theme_constant_override("outline_size", 1)


func _new_label(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.clip_text = true
	_style_label(l, color, size)
	return l


func _make_panel(pos: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = sz
	p.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.COLOR_PANEL_BG
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _fill_panel(c: Control) -> void:
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 3
	c.offset_top = 3
	c.offset_right = -3
	c.offset_bottom = -3


func _sep() -> HSeparator:
	return HSeparator.new()


func _add_caption(parent: Node, text: String) -> void:
	parent.add_child(_new_label(text, UiTheme.COLOR_FAINT, SZ))


func _native_button_stylebox(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(1)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb


func _style_button(b: Button) -> void:
	b.clip_text = true
	b.add_theme_font_override("font", UiTheme.active_font())
	b.add_theme_font_size_override("font_size", SZ)
	b.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
	b.add_theme_color_override("font_hover_color", UiTheme.COLOR_TEXT)
	b.add_theme_color_override("font_pressed_color", UiTheme.COLOR_TEXT)
	b.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	b.add_theme_constant_override("outline_size", 1)
	b.add_theme_stylebox_override("normal", _native_button_stylebox(Color(0.08, 0.11, 0.16, 0.9)))
	b.add_theme_stylebox_override("hover", _native_button_stylebox(Color(0.12, 0.17, 0.24, 0.95)))
	b.add_theme_stylebox_override("pressed", _native_button_stylebox(Color(0.06, 0.09, 0.13, 1.0)))


func _add_button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 12)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(b)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _add_fixed_button(parent: Node, text: String, cb: Callable, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 12)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(b)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _knob_row(parent: Node, knob_name: String, dec: Callable, inc: Callable) -> Label:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 2)
	parent.add_child(r)
	_add_fixed_button(r, "<", dec, 14)
	var l := _new_label(knob_name, UiTheme.COLOR_TEXT, SZ)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.add_child(l)
	_add_fixed_button(r, ">", inc, 14)
	return l
