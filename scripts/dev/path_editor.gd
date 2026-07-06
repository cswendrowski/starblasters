extends Control

# Path Editor (2026-07-06) — hand-author enemy flight PATHS on the playfield band, then bake them
# into scripts/enemies/patterns/authored_path_library.gd for the runtime AuthoredPath pattern.
# Native 480×270 dev tool (mirrors wave_pattern_editor / lane_visualizer): controls in the side
# gutters, the lane + zone canvas in the 216-wide band.
#
# A path = an ordered list of waypoints in NORMALIZED authoring space (x = lane units 0..6, y = band
# progress 0..1). Click empty band to append a waypoint; drag a node to move it; right-click a node
# to delete. The smoothed path draws live and an animated ghost ship flies it AT REAL SPEED using the
# actual AuthoredPath pattern (no separate preview math). Per-path knobs: speed_scale, smoothing,
# relative, mirror, per-waypoint dwell. Save writes JSON to user://tuners/enemy_paths.json; Copy
# GDScript emits a paste-ready DATA entry for the library.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const AuthoredPath = preload("res://scripts/enemies/patterns/authored_path.gd")
const AuthoredPathLibrary = preload("res://scripts/enemies/patterns/authored_path_library.gd")

const SAVE_PATH := "user://tuners/enemy_paths.json"
const SZ := 7
const NODE_GRAB := 6.0   # px pick radius for grabbing/deleting a waypoint

# Chassis speed picker (Clarity rungs) — the ghost previews at this move_speed × speed_scale.
const SPEED_RUNGS := [60.0, 120.0, 180.0, 240.0, 300.0, 360.0, 420.0, 480.0]

var _library: Array = []       # Array of path-definition dicts
var _idx: int = 0
var _wps: Array = []           # working waypoints for the current path: Array[Vector2] (authoring space)
var _dwell: Array = []         # parallel per-waypoint dwell seconds

var _drag_i: int = -1          # index of the waypoint being dragged, or -1
var _speed_i: int = 2          # index into SPEED_RUNGS (180 default)

var _world: Node2D = null
var _overlay: Node2D = null
var _ghost: Node2D = null      # bare Node2D stub the AuthoredPath drives (dogfoods the runtime)
var _ghost_mv: Resource = null
var _ghost_t: float = 0.0
var _preview_on: bool = true
var _mirror_preview: bool = false
var _font: Font = null

var _path_list: VBoxContainer = null
var _name_edit: LineEdit = null
var _speed_lbl: Label = null
var _scale_lbl: Label = null
var _smooth_lbl: Label = null
var _rel_btn: Button = null
var _mir_btn: Button = null
var _status_lbl: Label = null


func _ready() -> void:
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("silent")
	_font = UiTheme.active_font()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_library()
	_build_bg()
	_build_world()
	_build_ui()
	_select_path(0)


# ---------------------------------------------------------------- library / path

func _blank_path() -> Dictionary:
	return {"name": "new_path", "relative": true, "speed_scale": 1.0, "smoothing": 1.0,
		"mirror": false, "waypoints": [[0.0, 0.0], [0.0, 1.0]], "dwell": []}


func _load_library() -> void:
	_library = []
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Array:
				_library = parsed
	if _library.is_empty():
		for n in AuthoredPathLibrary.DATA:
			_library.append((AuthoredPathLibrary.DATA[n] as Dictionary).duplicate(true))
	if _library.is_empty():
		_library.append(_blank_path())


func _cur() -> Dictionary:
	return _library[_idx]


func _select_path(i: int) -> void:
	_sync_current()   # persist the outgoing edits first
	_idx = (i + _library.size()) % _library.size()
	_wps = []
	for wp in _cur().get("waypoints", []):
		if wp is Array and (wp as Array).size() >= 2:
			_wps.append(Vector2(float(wp[0]), float(wp[1])))
		elif wp is Vector2:
			_wps.append(wp)
	_dwell = []
	for d in _cur().get("dwell", []):
		_dwell.append(float(d))
	_speed_i = 2
	_refresh_labels()
	_rebuild_ghost()
	if _overlay:
		_overlay.queue_redraw()


# Write the working waypoints/dwell back into the current library dict.
func _sync_current() -> void:
	if _library.is_empty():
		return
	var wps: Array = []
	for wp in _wps:
		wps.append([snappedf((wp as Vector2).x, 0.01), snappedf((wp as Vector2).y, 0.01)])
	_cur()["waypoints"] = wps
	# Trim trailing zero-dwell entries.
	var dw: Array = _dwell.duplicate()
	while dw.size() > 0 and float(dw[dw.size() - 1]) <= 0.0:
		dw.remove_at(dw.size() - 1)
	_cur()["dwell"] = dw


func _new_path() -> void:
	_sync_current()
	var p := _blank_path()
	p["name"] = "path_%d" % _library.size()
	_library.append(p)
	_select_path(_library.size() - 1)


func _dup_path() -> void:
	_sync_current()
	var p: Dictionary = _cur().duplicate(true)
	p["name"] = String(p.get("name", "path")) + "_copy"
	_library.append(p)
	_select_path(_library.size() - 1)


func _del_path() -> void:
	if _library.size() <= 1:
		_library[0] = _blank_path()
		_select_path(0)
		return
	_library.remove_at(_idx)
	_select_path(_idx)


# ---------------------------------------------------------------- world / draw

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
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay.draw.connect(_draw_overlay)
	_world.add_child(_overlay)
	# Ghost ship — a bare Node2D the AuthoredPath drives, dogfooding the runtime step math.
	_ghost = Node2D.new()
	_ghost.name = "Ghost"
	_world.add_child(_ghost)


func _draw_overlay() -> void:
	var top: float = Playfield.Y_MIN
	var bot: float = Playfield.Y_MAX
	_overlay.draw_rect(Rect2(Playfield.X_MIN, top, Playfield.W, Playfield.H), Color(0.4, 0.6, 0.9, 0.5), false, 1.0)
	# Lane columns + centers.
	for i in Lanes.COUNT:
		var cx: float = Lanes.lane_center(i)
		_overlay.draw_line(Vector2(cx, top), Vector2(cx, bot), Color(0.5, 0.7, 1.0, 0.10), 1.0)
		_overlay.draw_string(_font, Vector2(cx - 3.0, top + 7.0), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.5, 0.7, 1.0, 0.5))
	# Zone lines (entry / departure bands) — the path-phase firing gates.
	_zone_line(Zones.ENTRY_END, "entry", Color(0.5, 1.0, 0.6, 0.35))
	_zone_line(Zones.DEPARTURE_START, "depart", Color(1.0, 0.6, 0.5, 0.35))
	# The authored path (resolved via the runtime pattern's own math so the editor matches play).
	_draw_path(false)
	if _mirror_preview:
		_draw_path(true)
	# Waypoint handles.
	for i in _wps.size():
		var p: Vector2 = _resolve(_wps[i], false)
		var col: Color = Color(1.0, 0.9, 0.4, 0.95) if i == _drag_i else Color(0.6, 0.85, 1.0, 0.95)
		_overlay.draw_circle(p, 2.5, col)
		_overlay.draw_string(_font, p + Vector2(3.0, -2.0), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(1, 1, 1, 0.7))
		if i < _dwell.size() and float(_dwell[i]) > 0.0:
			_overlay.draw_string(_font, p + Vector2(3.0, 6.0), "d%.1f" % float(_dwell[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(1.0, 0.85, 0.4, 0.8))
	# Ghost ship marker.
	if _preview_on and _ghost != null:
		_overlay.draw_circle(_ghost.position, 3.0, Color(1.0, 0.5, 0.3, 0.95))
		_overlay.draw_circle(_ghost.position, 4.5, Color(1.0, 0.5, 0.3, 0.35))


func _zone_line(y: float, label: String, col: Color) -> void:
	_overlay.draw_line(Vector2(Playfield.X_MIN, y), Vector2(Playfield.X_MAX, y), col, 1.0)
	_overlay.draw_string(_font, Vector2(Playfield.X_MIN + 1.0, y - 1.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, col)


# Draw the smoothed resolved polyline by building the pattern + sampling its resolved points.
func _draw_path(mirror: bool) -> void:
	if _wps.size() < 2:
		return
	var pts: PackedVector2Array = _sample_polyline(mirror)
	if pts.size() < 2:
		return
	var col: Color = Color(1.0, 0.55, 0.55, 0.5) if mirror else Color(0.55, 0.85, 1.0, 0.85)
	for i in range(pts.size() - 1):
		_overlay.draw_line(pts[i], pts[i + 1], col, 1.0)


# Sample the AuthoredPath's own resolved polyline (dogfood) at the editor's anchor (lane 0 for
# relative, so relative paths show against the left; absolute paths ignore the anchor).
func _sample_polyline(mirror: bool) -> PackedVector2Array:
	var m := _build_pattern(mirror)
	# Drive on_start with a stub at the relative anchor to resolve pixel points.
	var stub := _make_stub(_rel_anchor_x())
	m.on_start(stub)
	# Walk the pattern in fine steps to trace the resolved curve (constant-speed, so uniform t).
	var out: PackedVector2Array = PackedVector2Array()
	out.append(stub.position)
	var guard := 0
	while guard < 4000:
		guard += 1
		var step: Vector2 = m.compute_step(stub, 1.0 / 60.0)
		stub.position += step
		out.append(stub.position)
		if stub.position.y >= Playfield.Y_MAX + 12.0:
			break
	return out


func _resolve(wp: Vector2, mirror: bool) -> Vector2:
	return AuthoredPath.resolve_point(wp, _rel_anchor_x(), bool(_cur().get("relative", true)), mirror)


func _rel_anchor_x() -> float:
	# Relative paths preview anchored on lane 3 (centre) so +/- offsets stay on the board.
	return Lanes.lane_center(3) if bool(_cur().get("relative", true)) else 0.0


# ---------------------------------------------------------------- ghost preview

func _build_pattern(mirror: bool) -> Resource:
	var def: Dictionary = _cur().duplicate(true)
	def["waypoints"] = _wps_as_arrays()
	def["dwell"] = _dwell.duplicate()
	var m = AuthoredPathLibrary.build_from_def(def)
	if mirror != bool(def.get("mirror", false)):
		m.mirrored = mirror
	return m


func _wps_as_arrays() -> Array:
	var out: Array = []
	for wp in _wps:
		out.append([(wp as Vector2).x, (wp as Vector2).y])
	return out


func _make_stub(anchor_x: float) -> Node2D:
	var s := Node2D.new()
	s.position = Vector2(anchor_x, 0.0)
	s.set("move_speed", SPEED_RUNGS[_speed_i])
	return s


func _rebuild_ghost() -> void:
	_ghost_mv = _build_pattern(_mirror_preview)
	_ghost_t = 0.0
	if _ghost != null:
		_ghost.position = Vector2(_rel_anchor_x(), 0.0)
		if _ghost_mv != null:
			_ghost.set("move_speed", SPEED_RUNGS[_speed_i])
			_ghost_mv.on_start(_ghost)


func _process(delta: float) -> void:
	if _preview_on and _ghost_mv != null and _ghost != null:
		var step: Vector2 = _ghost_mv.compute_step(_ghost, delta)
		_ghost.position += step
		if _ghost.position.y >= Playfield.Y_MAX + 16.0:
			_rebuild_ghost()   # loop the preview
	if _overlay:
		_overlay.queue_redraw()


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
		return
	if event is InputEventMouseButton and event.pressed:
		var pos: Vector2 = get_global_mouse_position()
		if not _in_band(pos):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			var hit: int = _pick_node(pos)
			if hit >= 0:
				_drag_i = hit
			else:
				_append_waypoint(pos)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var h: int = _pick_node(pos)
			if h >= 0:
				_delete_waypoint(h)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _drag_i >= 0:
			_drag_i = -1
			_after_edit()
	elif event is InputEventMouseMotion and _drag_i >= 0:
		var mp: Vector2 = get_global_mouse_position()
		_wps[_drag_i] = _to_authoring(mp)
		if _overlay:
			_overlay.queue_redraw()


func _in_band(pos: Vector2) -> bool:
	return pos.x >= Playfield.X_MIN and pos.x <= Playfield.X_MAX and pos.y >= Playfield.Y_MIN and pos.y <= Playfield.Y_MAX


func _pick_node(pos: Vector2) -> int:
	for i in _wps.size():
		if _resolve(_wps[i], false).distance_to(pos) <= NODE_GRAB:
			return i
	return -1


# Pixel -> authoring space (x lane units, y band progress). Relative x is offset from the anchor lane.
func _to_authoring(pos: Vector2) -> Vector2:
	var y: float = clampf((pos.y - Playfield.Y_MIN) / (Playfield.Y_MAX - Playfield.Y_MIN), 0.0, 1.0)
	var x: float
	if bool(_cur().get("relative", true)):
		x = (pos.x - _rel_anchor_x()) / Lanes.PITCH
	else:
		x = (pos.x - Lanes.FIRST_CENTER) / Lanes.PITCH
	return Vector2(x, y)


func _append_waypoint(pos: Vector2) -> void:
	_wps.append(_to_authoring(pos))
	_dwell.append(0.0)
	_after_edit()


func _delete_waypoint(i: int) -> void:
	if i < 0 or i >= _wps.size():
		return
	_wps.remove_at(i)
	if i < _dwell.size():
		_dwell.remove_at(i)
	_after_edit()


func _after_edit() -> void:
	_sync_current()
	_rebuild_ghost()
	if _overlay:
		_overlay.queue_redraw()
	_update_status()


# ---------------------------------------------------------------- knobs

func _cycle_speed(d: int) -> void:
	_speed_i = clampi(_speed_i + d, 0, SPEED_RUNGS.size() - 1)
	_rebuild_ghost()
	_refresh_labels()


func _cycle_scale(d: int) -> void:
	var s: float = clampf(float(_cur().get("speed_scale", 1.0)) + 0.1 * float(d), 0.3, 2.0)
	_cur()["speed_scale"] = snappedf(s, 0.05)
	_after_edit()
	_refresh_labels()


func _cycle_smooth(d: int) -> void:
	var s: float = clampf(float(_cur().get("smoothing", 1.0)) + 0.25 * float(d), 0.0, 1.0)
	_cur()["smoothing"] = s
	_after_edit()
	_refresh_labels()


func _toggle_relative() -> void:
	_cur()["relative"] = not bool(_cur().get("relative", true))
	# Re-anchor the on-screen preview but keep authored x values (they now mean offsets vs absolute).
	_after_edit()
	_refresh_labels()


func _toggle_mirror_flag() -> void:
	_cur()["mirror"] = not bool(_cur().get("mirror", false))
	_after_edit()
	_refresh_labels()


func _toggle_mirror_preview() -> void:
	_mirror_preview = not _mirror_preview
	_rebuild_ghost()
	_update_status()


func _toggle_preview() -> void:
	_preview_on = not _preview_on
	if _preview_on:
		_rebuild_ghost()


func _dwell_last(d: int) -> void:
	# Add/remove dwell on the LAST waypoint (quick per-waypoint hold authoring).
	if _wps.is_empty():
		return
	while _dwell.size() < _wps.size():
		_dwell.append(0.0)
	var i: int = _wps.size() - 1
	_dwell[i] = clampf(float(_dwell[i]) + 0.25 * float(d), 0.0, 4.0)
	_after_edit()


# ---------------------------------------------------------------- save / copy

func _save_json() -> void:
	_sync_current()
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_library, "\t"))
		f.close()
		_set_status("saved %d paths" % _library.size())
	else:
		_set_status("save failed")


func _copy_gdscript() -> void:
	_sync_current()
	# Emit a paste-ready DATA entry for authored_path_library.gd (JSON literal = valid GDScript).
	var nm: String = String(_cur().get("name", "path"))
	var text: String = '\t"%s": ' % nm + JSON.stringify(_cur(), "\t") + ",\n"
	DisplayServer.clipboard_set(text)
	_set_status("copied DATA[\"%s\"] → clipboard" % nm)


func _commit_name(t: String) -> void:
	var nm: String = t.strip_edges()
	if nm != "":
		_cur()["name"] = nm
		_update_status()


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var left := _make_panel(Vector2(0, 0), Vector2(128, 270))
	add_child(left)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 2)
	left.add_child(outer)
	_fill_panel(outer)
	var lsc := ScrollContainer.new()
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(lsc)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 2)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lsc.add_child(lv)

	lv.add_child(_new_label("PATH EDITOR", UiTheme.COLOR_ACCENT, SZ))

	# Path nav + name.
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 2)
	lv.add_child(pr)
	_add_fixed_button(pr, "<", func(): _select_path(_idx - 1), 14)
	_name_edit = LineEdit.new()
	_name_edit.add_theme_font_size_override("font_size", SZ)
	_name_edit.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.text_submitted.connect(_commit_name)
	_name_edit.focus_exited.connect(func(): _commit_name(_name_edit.text))
	pr.add_child(_name_edit)
	_add_fixed_button(pr, ">", func(): _select_path(_idx + 1), 14)
	var pr2 := HBoxContainer.new()
	pr2.add_theme_constant_override("separation", 2)
	lv.add_child(pr2)
	_add_button(pr2, "New", _new_path)
	_add_button(pr2, "Dup", _dup_path)
	_add_button(pr2, "Del", _del_path)

	lv.add_child(_sep())
	_add_caption(lv, "KNOBS")
	_speed_lbl = _knob_row(lv, "spd", func(): _cycle_speed(-1), func(): _cycle_speed(1))
	_scale_lbl = _knob_row(lv, "scale", func(): _cycle_scale(-1), func(): _cycle_scale(1))
	_smooth_lbl = _knob_row(lv, "smooth", func(): _cycle_smooth(-1), func(): _cycle_smooth(1))
	_rel_btn = _add_button(lv, "rel: on", _toggle_relative)
	_mir_btn = _add_button(lv, "mirror: off", _toggle_mirror_flag)
	# Per-waypoint dwell (last node).
	var dwr := HBoxContainer.new()
	dwr.add_theme_constant_override("separation", 2)
	lv.add_child(dwr)
	_add_fixed_button(dwr, "-", func(): _dwell_last(-1), 14)
	dwr.add_child(_new_label("dwell(last)", UiTheme.COLOR_TEXT, SZ))
	_add_fixed_button(dwr, "+", func(): _dwell_last(1), 14)

	lv.add_child(_sep())
	_add_caption(lv, "PREVIEW")
	_add_button(lv, "Preview: on/off", _toggle_preview)
	_add_button(lv, "Mirror preview", _toggle_mirror_preview)

	# Pinned action bar.
	outer.add_child(_sep())
	var a1 := HBoxContainer.new()
	a1.add_theme_constant_override("separation", 2)
	outer.add_child(a1)
	_add_button(a1, "Save", _save_json)
	_add_button(a1, "Copy GDScript", _copy_gdscript)
	var a2 := HBoxContainer.new()
	a2.add_theme_constant_override("separation", 2)
	outer.add_child(a2)
	_add_button(a2, "Clear", func(): _wps = []; _dwell = []; _after_edit())
	_add_button(a2, "Back", _on_back)
	_status_lbl = _new_label("", UiTheme.COLOR_FAINT, SZ)
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.custom_minimum_size = Vector2(120, 0)
	outer.add_child(_status_lbl)

	# Right gutter — help / path list.
	var right := _make_panel(Vector2(348, 0), Vector2(132, 270))
	add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 2)
	right.add_child(rv)
	_fill_panel(rv)
	_add_caption(rv, "HELP")
	rv.add_child(_new_label("L-click: add node", UiTheme.COLOR_TEXT, SZ))
	rv.add_child(_new_label("drag: move node", UiTheme.COLOR_TEXT, SZ))
	rv.add_child(_new_label("R-click: delete", UiTheme.COLOR_TEXT, SZ))
	rv.add_child(_new_label("x=lane, y=band", UiTheme.COLOR_FAINT, SZ))
	rv.add_child(_sep())
	_add_caption(rv, "PATHS")
	var lscroll := ScrollContainer.new()
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(lscroll)
	_path_list = VBoxContainer.new()
	_path_list.add_theme_constant_override("separation", 1)
	_path_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lscroll.add_child(_path_list)
	_rebuild_path_list()


func _rebuild_path_list() -> void:
	if _path_list == null:
		return
	for ch in _path_list.get_children():
		_path_list.remove_child(ch)
		ch.queue_free()
	for i in _library.size():
		var idx: int = i
		var b := _add_button(_path_list, String(_library[i].get("name", "path")), func(): _select_path(idx))
		b.custom_minimum_size = Vector2(0, 14)


func _refresh_labels() -> void:
	if _name_edit and not _name_edit.has_focus():
		_name_edit.text = String(_cur().get("name", "-"))
	if _speed_lbl:
		_speed_lbl.text = "spd: %s" % Clarity_label(SPEED_RUNGS[_speed_i])
	if _scale_lbl:
		_scale_lbl.text = "scale: %.2f" % float(_cur().get("speed_scale", 1.0))
	if _smooth_lbl:
		_smooth_lbl.text = "smooth: %.2f" % float(_cur().get("smoothing", 1.0))
	if _rel_btn:
		_rel_btn.text = "rel: on" if bool(_cur().get("relative", true)) else "rel: off"
	if _mir_btn:
		_mir_btn.text = "mirror: on" if bool(_cur().get("mirror", false)) else "mirror: off"
	if _path_list:
		_rebuild_path_list()


func Clarity_label(sp: float) -> String:
	var C = preload("res://scripts/systems/clarity.gd")
	return C.label_for_speed(sp)


func _update_status() -> void:
	if _status_lbl == null:
		return
	var mono: bool = AuthoredPath.is_monotone_y(_wps_as_arrays())
	_status_lbl.text = "%d nodes  %s" % [_wps.size(), "path-phase" if mono else "cadence (non-mono)"]


func _set_status(s: String) -> void:
	if _status_lbl:
		_status_lbl.text = s


func _on_back() -> void:
	_sync_current()
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


# ---------------------------------------------------------------- UI helpers

func _knob_row(parent: Node, name: String, dec: Callable, inc: Callable) -> Label:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 2)
	parent.add_child(r)
	_add_fixed_button(r, "<", dec, 14)
	var l := _new_label(name, UiTheme.COLOR_TEXT, SZ)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.add_child(l)
	_add_fixed_button(r, ">", inc, 14)
	return l


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
