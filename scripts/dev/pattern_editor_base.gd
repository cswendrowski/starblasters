extends Control

# Shared base for the in-game pattern editors (movement, shoot).
# Subclasses set RESOURCE_DIR + supply a live-preview node in their .tscn;
# this base handles list management, reflection-driven field generation,
# save/dup/del, and the HD viewport swap.
#
# Editor layout contract (the .tscn must provide these node paths):
#   $Body/LeftRail/PatternList            ItemList
#   $Body/LeftRail/LeftButtons/NewBtn     Button
#   $Body/LeftRail/LeftButtons/DuplicateBtn Button
#   $Body/LeftRail/LeftButtons/DeleteBtn  Button
#   $Body/Center/Props                    GridContainer (cols=2) for fields
#   $Body/Center/Status                   Label (status line)
#   $FooterButtons/SaveBtn                Button
#   $FooterButtons/BackBtn                Button
# Subclasses with a preview pane add a $Body/Preview node tree of their own.

const SceneTransition = preload("res://scripts/scene_transition.gd")

const HD_VIEWPORT := Vector2i(1920, 1080)
var _prev_scale_size: Vector2i = Vector2i.ZERO

# Subclass overrides — directory of .tres files this editor manages and
# the script class new patterns instantiate.
var RESOURCE_DIR: String = ""
var DEFAULT_SCRIPT: Script = null

# Mirror of disk. key = basename, value = {"path": ..., "res": Resource}.
var _items: Dictionary = {}
var _current_key: String = ""
var _populating: bool = false

# Reflection-built field bindings. Built per-selection so we can rebuild
# when switching to a pattern with a different shape.
var _field_widgets: Array = []  # of {prop:String, node:Control, type:int}

@onready var _list: ItemList = $Body/LeftRail/PatternList
@onready var _new_btn: Button = $Body/LeftRail/LeftButtons/NewBtn
@onready var _dup_btn: Button = $Body/LeftRail/LeftButtons/DuplicateBtn
@onready var _del_btn: Button = $Body/LeftRail/LeftButtons/DeleteBtn
@onready var _props: GridContainer = $Body/Center/Props
@onready var _status: Label = $Body/Center/Status
@onready var _save_btn: Button = $FooterButtons/SaveBtn
@onready var _back_btn: Button = $FooterButtons/BackBtn
@onready var _name_edit: LineEdit = $Body/Center/NameRow/NameEdit


func _ready() -> void:
	_enter_hd_viewport()
	_configure()
	_wire_signals()
	_scan_items()
	if _list.item_count > 0:
		_list.select(0)
		_on_item_selected(0)
	else:
		_clear_form()


# Subclass hook: set RESOURCE_DIR + DEFAULT_SCRIPT before _ready continues.
func _configure() -> void:
	pass


# Subclass hook: filter which loaded Resources show in the list. Default
# includes everything; weapon_editor overrides to filter by slot_type.
func _should_include(_res: Resource) -> bool:
	return true


func _wire_signals() -> void:
	_list.item_selected.connect(_on_item_selected)
	_new_btn.pressed.connect(_on_new)
	_dup_btn.pressed.connect(_on_duplicate)
	_del_btn.pressed.connect(_on_delete)
	_save_btn.pressed.connect(_on_save)
	_back_btn.pressed.connect(_on_back)
	_name_edit.text_changed.connect(func(_t): _mark_dirty())


# ---- HD viewport swap (same trick as wave_editor) -----------------------

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


# ---- Disk scan ----------------------------------------------------------

func _scan_items() -> void:
	_items.clear()
	_list.clear()
	if RESOURCE_DIR == "":
		return
	var dir := DirAccess.open(RESOURCE_DIR)
	if dir == null:
		_set_status("Cannot read %s" % RESOURCE_DIR)
		return
	dir.list_dir_begin()
	var keys: Array = []
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var key := fname.get_basename()
			var path := RESOURCE_DIR + fname
			var res = load(path)
			if res != null and _should_include(res):
				_items[key] = {"path": path, "res": res}
				keys.append(key)
		fname = dir.get_next()
	dir.list_dir_end()
	keys.sort()
	for k in keys:
		_list.add_item(k)


# ---- Selection / reflection form ----------------------------------------

func _on_item_selected(idx: int) -> void:
	if idx < 0 or idx >= _list.item_count:
		return
	_current_key = _list.get_item_text(idx)
	if not _items.has(_current_key):
		return
	var res = _items[_current_key]["res"]
	_populating = true
	_name_edit.text = _current_key
	_build_fields_for(res)
	_populating = false
	_on_pattern_loaded(res)
	_set_status("Loaded %s" % _current_key)


func _clear_form() -> void:
	for child in _props.get_children():
		child.queue_free()
	_field_widgets.clear()
	_name_edit.text = ""


# Walk the Resource's property list and emit one row per @export-able
# property. Type-driven control selection: float/int -> SpinBox,
# bool -> CheckBox, String -> LineEdit. Anything else gets a read-only
# label (Resource refs etc — those have their own pickers in the wave
# editor; patterns don't typically reference other Resources).
func _build_fields_for(res: Resource) -> void:
	for child in _props.get_children():
		child.queue_free()
	_field_widgets.clear()
	if res == null:
		return
	for prop in res.get_property_list():
		# Filter to @export script-visible props. Engine adds a bunch of
		# internal props (script, resource_path, resource_name, etc.) that
		# we don't want to show.
		var usage: int = int(prop.get("usage", 0))
		if not (usage & PROPERTY_USAGE_EDITOR):
			continue
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var name: String = String(prop["name"])
		if name in ["script", "resource_path", "resource_name", "resource_local_to_scene"]:
			continue
		var type: int = int(prop["type"])
		_add_field_row(res, name, type, prop)


func _add_field_row(res: Resource, prop_name: String, type: int, _prop: Dictionary) -> void:
	var lbl := Label.new()
	lbl.text = _humanize(prop_name)
	lbl.add_theme_font_size_override("font_size", 20)
	_props.add_child(lbl)
	var widget: Control = null
	match type:
		TYPE_FLOAT:
			var sb := SpinBox.new()
			sb.min_value = -10000.0
			sb.max_value = 10000.0
			sb.step = 0.05
			sb.value = float(res.get(prop_name))
			sb.custom_minimum_size = Vector2(0, 44)
			sb.value_changed.connect(func(v: float):
				if _populating: return
				res.set(prop_name, v)
				_mark_dirty()
				_on_field_changed(res, prop_name)
			)
			widget = sb
		TYPE_INT:
			var sb := SpinBox.new()
			sb.min_value = -10000.0
			sb.max_value = 10000.0
			sb.step = 1.0
			sb.value = int(res.get(prop_name))
			sb.custom_minimum_size = Vector2(0, 44)
			sb.value_changed.connect(func(v: float):
				if _populating: return
				res.set(prop_name, int(v))
				_mark_dirty()
				_on_field_changed(res, prop_name)
			)
			widget = sb
		TYPE_BOOL:
			var cb := CheckBox.new()
			cb.button_pressed = bool(res.get(prop_name))
			cb.toggled.connect(func(pressed: bool):
				if _populating: return
				res.set(prop_name, pressed)
				_mark_dirty()
				_on_field_changed(res, prop_name)
			)
			widget = cb
		TYPE_STRING:
			var le := LineEdit.new()
			le.text = String(res.get(prop_name))
			le.custom_minimum_size = Vector2(0, 44)
			le.add_theme_font_size_override("font_size", 20)
			le.text_changed.connect(func(t: String):
				if _populating: return
				res.set(prop_name, t)
				_mark_dirty()
				_on_field_changed(res, prop_name)
			)
			widget = le
		_:
			# Unsupported type — show a read-only label as a placeholder.
			var v := Label.new()
			v.text = "(%s — edit in Godot inspector)" % type_string(type)
			v.add_theme_font_size_override("font_size", 18)
			v.modulate = Color(0.7, 0.7, 0.7, 1)
			widget = v
	if widget:
		_props.add_child(widget)
		_field_widgets.append({"prop": prop_name, "node": widget, "type": type})


# Subclass override hook — called after a pattern is loaded into the form,
# and again whenever a field changes. Use to refresh the live preview.
func _on_pattern_loaded(_res: Resource) -> void:
	pass


func _on_field_changed(_res: Resource, _prop_name: String) -> void:
	pass


func _humanize(prop: String) -> String:
	# "down_speed" -> "Down speed".
	var parts := prop.split("_")
	if parts.is_empty():
		return prop
	var first := String(parts[0])
	var rest_arr: PackedStringArray = parts.slice(1)
	var rest_joined := " ".join(rest_arr)
	if rest_joined != "":
		return first.capitalize() + " " + rest_joined
	return first.capitalize()


func _current_resource() -> Resource:
	if _current_key == "" or not _items.has(_current_key):
		return null
	return _items[_current_key]["res"]


func _mark_dirty() -> void:
	if _populating:
		return
	_set_status("Unsaved changes")


# ---- Actions ------------------------------------------------------------

func _on_save() -> void:
	var res := _current_resource()
	if res == null:
		_set_status("Nothing to save")
		return
	var new_key := _name_edit.text.strip_edges()
	if new_key == "":
		_set_status("Name required")
		return
	var new_path := RESOURCE_DIR + new_key + ".tres"
	var old_path: String = _items[_current_key]["path"]
	var err := ResourceSaver.save(res, new_path)
	if err != OK:
		_set_status("Save FAILED (%d)" % err)
		return
	if new_key != _current_key and FileAccess.file_exists(old_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))
	_set_status("Saved %s" % new_key)
	_scan_items()
	_select_by_key(new_key)


func _on_new() -> void:
	if DEFAULT_SCRIPT == null:
		_set_status("New: no default script configured")
		return
	var base := "new_pattern"
	var i := 1
	var key := base if i == 1 else "%s_%d" % [base, i]
	while _items.has(key):
		i += 1
		key = "%s_%d" % [base, i]
	var res = Resource.new()
	res.set_script(DEFAULT_SCRIPT)
	var path := RESOURCE_DIR + key + ".tres"
	var err := ResourceSaver.save(res, path)
	if err != OK:
		_set_status("New FAILED (%d)" % err)
		return
	_scan_items()
	_select_by_key(key)
	_set_status("Created %s" % key)


func _on_duplicate() -> void:
	var res := _current_resource()
	if res == null:
		return
	var key := _current_key + "_copy"
	var i := 1
	var final_key := key if i == 1 else "%s%d" % [key, i]
	while _items.has(final_key):
		i += 1
		final_key = "%s%d" % [key, i]
	var dup: Resource = res.duplicate(true)
	var path := RESOURCE_DIR + final_key + ".tres"
	var err := ResourceSaver.save(dup, path)
	if err != OK:
		_set_status("Duplicate FAILED (%d)" % err)
		return
	_scan_items()
	_select_by_key(final_key)
	_set_status("Duplicated to %s" % final_key)


func _on_delete() -> void:
	if _current_key == "":
		return
	var path: String = _items[_current_key]["path"]
	var abs_path := ProjectSettings.globalize_path(path)
	var err := DirAccess.remove_absolute(abs_path)
	if err != OK:
		_set_status("Delete FAILED (%d)" % err)
		return
	var dropped := _current_key
	_current_key = ""
	_scan_items()
	if _list.item_count > 0:
		_list.select(0)
		_on_item_selected(0)
	else:
		_clear_form()
	_set_status("Deleted %s" % dropped)


func _on_back() -> void:
	# Honor a return-to override (e.g. wave editor → pattern editor → back
	# to wave editor with the picker re-selected on the just-edited file).
	var target := "res://scenes/dev_menu.tscn"
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if run.has_meta("pattern_editor_return_scene"):
			target = String(run.get_meta("pattern_editor_return_scene", target))
			run.remove_meta("pattern_editor_return_scene")
	_exit_hd_viewport()
	SceneTransition.change_scene(get_tree(), target)


func _select_by_key(key: String) -> void:
	for i in _list.item_count:
		if _list.get_item_text(i) == key:
			_list.select(i)
			_on_item_selected(i)
			return


func _set_status(msg: String) -> void:
	if _status:
		_status.text = msg


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
