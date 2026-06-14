extends Control

# Maneuver Sim — dev tool for sketching enemy movement splines on a
# mockup of the playfield, naming them, saving to disk, and playing them
# back with a placeholder ship so behavior can be inspected.
#
# Save format: user://maneuvers/<name>.json
#   { "name": "...", "points": [[x,y], [x,y], ...] }
#
# Existing parametric movement patterns (StraightDown, SCurve, Loiter) are
# listed in the preview rail — clicking "Preview" runs that pattern on a
# dummy ship without converting it to a spline.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const MANEUVER_DIR := "user://maneuvers"

# Playfield mockup occupies the left chunk of the screen; the right rail is
# the editor UI (name field, save/load list, pattern previews).
# 320×400 res rework: field occupies the left ~200px, rail goes right.
const FIELD_RECT := Rect2(8, 24, 180, 350)
const POINT_RADIUS := 3.0
const POINT_HIT_RADIUS := 6.0
const SHIP_SIZE := Vector2(8, 8)

var _points: Array[Vector2] = []
var _dragging_idx: int = -1
var _current_name: String = "Untitled"

var _field: Control = null
var _name_edit: LineEdit = null
var _list: ItemList = null
var _ship_preview: ColorRect = null
var _playback_tween: Tween = null
var _status: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_dir()
	_build_ui()
	_refresh_save_list()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(MANEUVER_DIR)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MANEUVER_DIR))


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.11, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Header strip
	var header := Label.new()
	header.text = "MANEUVER SIM"
	header.position = Vector2(8, 4)
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	add_child(header)

	var back_btn := Button.new()
	back_btn.text = "Back to Dev Menu"
	back_btn.position = Vector2(8, 380)
	back_btn.size = Vector2(80, 14)
	UiTheme.style_button(back_btn, true)
	back_btn.pressed.connect(_on_back)
	add_child(back_btn)

	_status = Label.new()
	_status.position = Vector2(96, 382)
	_status.size = Vector2(220, 12)
	_status.text = "Left-click to add point. Drag to move. Right-click to remove. Shift+click to clear."
	UiTheme.style_label(_status, UiTheme.LabelKind.CAPTION)
	add_child(_status)

	# Playfield mockup
	_field = Control.new()
	_field.position = FIELD_RECT.position
	_field.size = FIELD_RECT.size
	_field.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_field)

	var field_bg := ColorRect.new()
	field_bg.color = Color(0.12, 0.15, 0.20, 1.0)
	field_bg.size = FIELD_RECT.size
	field_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(field_bg)

	# Grid overlay (drawn via _draw on a Node2D child)
	var grid := Node2D.new()
	grid.draw.connect(_draw_grid.bind(grid))
	_field.add_child(grid)
	grid.queue_redraw()

	# Spline overlay
	var spline_layer := Node2D.new()
	spline_layer.name = "SplineLayer"
	spline_layer.draw.connect(_draw_spline.bind(spline_layer))
	_field.add_child(spline_layer)

	# Ship preview (visible during playback)
	_ship_preview = ColorRect.new()
	_ship_preview.color = Color(0.6, 1.0, 0.6, 1.0)
	_ship_preview.size = SHIP_SIZE
	_ship_preview.visible = false
	_ship_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(_ship_preview)

	_field.gui_input.connect(_on_field_gui_input)

	# Right rail — wrap the VBox in a ScrollContainer so a tall list of
	# saved maneuvers + preview buttons stays reachable (Roman,
	# 2026-05-17: dev rails were getting clipped off-screen).
	var rail_scroll := ScrollContainer.new()
	rail_scroll.position = Vector2(192, 24)
	rail_scroll.size = Vector2(124, 350)
	add_child(rail_scroll)
	var rail := VBoxContainer.new()
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail.add_theme_constant_override("separation", 8)
	rail_scroll.add_child(rail)

	var name_lbl := Label.new()
	name_lbl.text = "Name"
	UiTheme.style_label(name_lbl, UiTheme.LabelKind.CAPTION)
	rail.add_child(name_lbl)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "diving_arc"
	_name_edit.text = _current_name
	_name_edit.custom_minimum_size = Vector2(0, 14)
	rail.add_child(_name_edit)

	_add_rail_button(rail, "Save", _on_save)
	_add_rail_button(rail, "Play", _on_play)
	_add_rail_button(rail, "Clear Points", _on_clear)

	rail.add_child(HSeparator.new())

	var saved_lbl := Label.new()
	saved_lbl.text = "Saved Maneuvers"
	UiTheme.style_label(saved_lbl, UiTheme.LabelKind.CAPTION)
	rail.add_child(saved_lbl)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 80)
	_list.item_selected.connect(_on_list_select)
	rail.add_child(_list)

	_add_rail_button(rail, "Delete Selected", _on_delete_selected)

	rail.add_child(HSeparator.new())

	var ptn_lbl := Label.new()
	ptn_lbl.text = "Preview Built-in"
	UiTheme.style_label(ptn_lbl, UiTheme.LabelKind.CAPTION)
	rail.add_child(ptn_lbl)

	_add_rail_button(rail, "Straight Down", _preview_straight)
	_add_rail_button(rail, "S-Curve", _preview_scurve)
	_add_rail_button(rail, "Loiter", _preview_loiter)


func _add_rail_button(rail: Node, text: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 14)
	UiTheme.style_button(btn, true)
	btn.pressed.connect(cb)
	rail.add_child(btn)


# ---- Field input -----------------------------------------------------------

func _on_field_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var local: Vector2 = mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.shift_pressed:
					_points.clear()
					_redraw_spline()
					_status.text = "Points cleared."
					return
				# Try to grab an existing point first.
				var idx := _hit_point(local)
				if idx >= 0:
					_dragging_idx = idx
				else:
					_points.append(local)
					_redraw_spline()
			else:
				_dragging_idx = -1
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var idx := _hit_point(local)
			if idx >= 0:
				_points.remove_at(idx)
				_redraw_spline()
	elif event is InputEventMouseMotion and _dragging_idx >= 0:
		var mm := event as InputEventMouseMotion
		_points[_dragging_idx] = mm.position
		_redraw_spline()


func _hit_point(pos: Vector2) -> int:
	for i in range(_points.size()):
		if _points[i].distance_to(pos) <= POINT_HIT_RADIUS:
			return i
	return -1


func _redraw_spline() -> void:
	var layer: Node2D = _field.get_node_or_null("SplineLayer")
	if layer:
		layer.queue_redraw()


# ---- Drawing ---------------------------------------------------------------

func _draw_grid(canvas: Node2D) -> void:
	var c := Color(1, 1, 1, 0.05)
	for x in range(0, int(FIELD_RECT.size.x), 16):
		canvas.draw_line(Vector2(x, 0), Vector2(x, FIELD_RECT.size.y), c, 1.0)
	for y in range(0, int(FIELD_RECT.size.y), 16):
		canvas.draw_line(Vector2(0, y), Vector2(FIELD_RECT.size.x, y), c, 1.0)
	# "Top of playfield" marker (where enemies typically spawn) — top edge.
	canvas.draw_line(Vector2(0, 0), Vector2(FIELD_RECT.size.x, 0), Color(0.6, 0.82, 1.0, 0.55), 2.0)
	# "Bottom of playfield" marker (where the player sits) — bottom edge.
	canvas.draw_line(Vector2(0, FIELD_RECT.size.y), Vector2(FIELD_RECT.size.x, FIELD_RECT.size.y), Color(1.0, 0.6, 0.5, 0.55), 2.0)


func _draw_spline(canvas: Node2D) -> void:
	if _points.size() >= 2:
		var curve := _build_curve()
		var pts: PackedVector2Array = curve.tessellate(5, 3.0)
		canvas.draw_polyline(pts, Color(0.62, 0.82, 1.0, 0.95), 2.0)
	# Control point handles.
	for i in range(_points.size()):
		var p: Vector2 = _points[i]
		canvas.draw_circle(p, POINT_RADIUS, Color(0.62, 0.82, 1.0, 0.95))
		canvas.draw_arc(p, POINT_RADIUS + 2.0, 0.0, TAU, 24, Color(1, 1, 1, 0.5), 1.5)
		var n := Label.new()
		# Numbered labels could go here; skipped for simplicity.


# Build a Curve2D from the current control points. Uses default tangents
# (Catmull-Rom-ish via tessellate's stages parameter).
func _build_curve() -> Curve2D:
	var c := Curve2D.new()
	for p in _points:
		c.add_point(p)
	return c


# ---- Save / Load -----------------------------------------------------------

func _on_save() -> void:
	var nm: String = _name_edit.text.strip_edges()
	if nm == "":
		_status.text = "Name required."
		return
	if _points.is_empty():
		_status.text = "Add some points before saving."
		return
	var path := "%s/%s.json" % [MANEUVER_DIR, nm]
	var data := {
		"name": nm,
		"points": _points_to_array(),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_status.text = "Save failed: %s" % path
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	_current_name = nm
	_status.text = "Saved: %s" % nm
	_refresh_save_list()


func _points_to_array() -> Array:
	var out: Array = []
	for p in _points:
		out.append([p.x, p.y])
	return out


func _refresh_save_list() -> void:
	_list.clear()
	var dir := DirAccess.open(MANEUVER_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var fn := dir.get_next()
		if fn == "":
			break
		if fn.ends_with(".json"):
			_list.add_item(fn.get_basename())
	dir.list_dir_end()


func _on_list_select(idx: int) -> void:
	var nm: String = _list.get_item_text(idx)
	var path := "%s/%s.json" % [MANEUVER_DIR, nm]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_status.text = "Load failed: %s" % nm
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		_status.text = "Bad save: %s" % nm
		return
	_points.clear()
	for entry in (parsed.get("points", []) as Array):
		_points.append(Vector2(float(entry[0]), float(entry[1])))
	_current_name = String(parsed.get("name", nm))
	_name_edit.text = _current_name
	_redraw_spline()
	_status.text = "Loaded: %s (%d pts)" % [_current_name, _points.size()]


func _on_delete_selected() -> void:
	var sel: PackedInt32Array = _list.get_selected_items()
	if sel.is_empty():
		return
	var nm: String = _list.get_item_text(sel[0])
	var path := "%s/%s.json" % [MANEUVER_DIR, nm]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_refresh_save_list()
	_status.text = "Deleted: %s" % nm


func _on_clear() -> void:
	_points.clear()
	_redraw_spline()


# ---- Playback --------------------------------------------------------------

func _on_play() -> void:
	if _points.size() < 2:
		_status.text = "Need at least 2 points."
		return
	_play_along_curve(_build_curve())


func _play_along_curve(curve: Curve2D) -> void:
	if _playback_tween and _playback_tween.is_valid():
		_playback_tween.kill()
	_ship_preview.visible = true
	var length: float = curve.get_baked_length()
	if length <= 0.0:
		return
	var duration: float = clamp(length / 90.0, 0.6, 8.0)
	_playback_tween = create_tween()
	_playback_tween.tween_method(func(t: float):
		var p: Vector2 = curve.sample_baked(t * length)
		_ship_preview.position = p - SHIP_SIZE * 0.5
	, 0.0, 1.0, duration)
	_playback_tween.tween_callback(func():
		_ship_preview.visible = false
	)
	_status.text = "Playing... (%.1fs)" % duration


# ---- Built-in pattern previews --------------------------------------------

func _preview_straight() -> void:
	var c := Curve2D.new()
	c.add_point(Vector2(FIELD_RECT.size.x * 0.5, 0))
	c.add_point(Vector2(FIELD_RECT.size.x * 0.5, FIELD_RECT.size.y))
	_play_along_curve(c)
	_status.text = "Preview: Straight Down"


func _preview_scurve() -> void:
	var c := Curve2D.new()
	var w: float = FIELD_RECT.size.x
	var h: float = FIELD_RECT.size.y
	for i in range(7):
		var t: float = float(i) / 6.0
		var x: float = w * 0.5 + sin(t * TAU) * (w * 0.35)
		var y: float = t * h
		c.add_point(Vector2(x, y))
	_play_along_curve(c)
	_status.text = "Preview: S-Curve"


func _preview_loiter() -> void:
	var c := Curve2D.new()
	var w: float = FIELD_RECT.size.x
	var h: float = FIELD_RECT.size.y
	c.add_point(Vector2(w * 0.5, 0))
	c.add_point(Vector2(w * 0.5, h * 0.4))
	# Loiter back-and-forth
	for i in range(4):
		var x_off: float = (w * 0.18) * (1 if i % 2 == 0 else -1)
		c.add_point(Vector2(w * 0.5 + x_off, h * 0.4 + (i + 1) * 30.0))
	c.add_point(Vector2(w * 0.5, h))
	_play_along_curve(c)
	_status.text = "Preview: Loiter"


# ---- Navigation ------------------------------------------------------------

func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
