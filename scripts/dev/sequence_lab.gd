extends Control

# Sequence Lab (Roman 2026-06-12) — play back + tune death / wreck animation SEQUENCES on a live
# enemy ship in the native 480×270 SubViewport. Pick a sequence (left rail), pick / re-roll a ship,
# tune its timing + magnitude knobs (right rail), and Play (optionally Loop) to watch.
#   Slow Death  — big-hull slow death: slows, lists, lights-out, secondary blasts → hands to wreck
#   Bomber Death— the bomber slump/darken/shrink + blast cascade (lifted from the legacy wing)
#   Wreck       — the wreck-layer hull drift (descent → tumble → recede → fire/smoke → exit)
# Knobs persist to user://tuners/sequence_lab.json; Copy GDScript emits the tuned values. Esc = back.
#
# Mirrors the shader_lab dev-tool skeleton (HD scope, native SubViewport stage, mode rail, knob rail).

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const Playfield = preload("res://scripts/systems/playfield.gd")
const EnemyManifest = preload("res://scripts/dev/enemy_manifest.gd")

const SEQUENCES := [
	{"name": "Slow Death", "script": preload("res://scripts/effects/sequences/seq_slow_death.gd"), "ship": ""},
	{"name": "Bomber Death", "script": preload("res://scripts/effects/sequences/seq_bomber_death.gd"), "ship": "res://scenes/enemies/core/enemy_bomber.tscn"},
	{"name": "Wreck", "script": preload("res://scripts/effects/sequences/seq_wreck.gd"), "ship": ""},
	{"name": "Bombing Run", "script": preload("res://scripts/effects/sequences/seq_bombing_run.gd"), "ship": "res://scenes/enemies/core/enemy_bomber.tscn"},
]

const SAVE_PATH := "user://tuners/sequence_lab.json"

const FS_TITLE := 40
const FS_BODY := 18
const FS_CAPTION := 15
const RAIL_W := 280
const KNOB_W := 430
const MARGIN := 20
const HEADER_H := 56
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.6)
const PANEL_BORDER := Color(0.35, 0.55, 0.75, 0.85)

var _hd_scope: HdViewportScope = null
var _preview_vp: SubViewport = null
var _stage: Node2D = null
var _ui: CanvasLayer = null
var _mode_list: ItemList = null
var _knob_box: VBoxContainer = null
var _note: Label = null
var _ship_label: Label = null

var _mode: int = 0
var _values: Dictionary = {}     # seq name → {key: value}
var _ship: Node2D = null
var _ship_path: String = ""
var _seq: Node = null            # active SequencePlayer
var _looping: bool = false
var _spawn_pos := Vector2(240.0, 90.0)


func _ready() -> void:
	if get_parent() == get_tree().root:
		_hd_scope = HdViewportScope.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_spawn_pos = Vector2(Playfield.CENTER.x, 90.0)
	_init_values()
	_load_saved()
	_build_playspace()
	_build_overlay()
	_set_mode(0)


func _init_values() -> void:
	for seq in SEQUENCES:
		var d := {}
		for def in seq["script"].knob_schema():
			d[String(def["key"])] = float(def["def"])
		_values[String(seq["name"])] = d


# ---- Playspace (native 480×270 SubViewport, mirror of shader_lab) ----------

func _build_playspace() -> void:
	var sub_container := SubViewportContainer.new()
	sub_container.stretch = true
	sub_container.stretch_shrink = 4
	sub_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sub_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub_container)

	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(480, 270)
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_vp.handle_input_locally = false
	_preview_vp.use_hdr_2d = true
	sub_container.add_child(_preview_vp)

	var gutter := ColorRect.new()
	gutter.color = Color(0.04, 0.05, 0.08, 1.0)
	gutter.size = Vector2(480, 270)
	gutter.z_index = -101
	_preview_vp.add_child(gutter)
	var band := ColorRect.new()
	band.color = Color(0.07, 0.09, 0.13, 1.0)
	band.position = Vector2(Playfield.X_MIN, 0)
	band.size = Vector2(Playfield.W, Playfield.H)
	band.z_index = -100
	_preview_vp.add_child(band)

	# Faint 7-lane grid so bombing-run placement reads against the lanes.
	for i in Lanes.COUNT:
		var col := ColorRect.new()
		col.color = Color(0.30, 0.42, 0.55, 0.10)
		col.position = Vector2(Lanes.lane_left(i), 0)
		col.size = Vector2(Lanes.WIDTH, Playfield.H)
		col.z_index = -99
		_preview_vp.add_child(col)

	_stage = Node2D.new()
	_stage.name = "Stage"
	_preview_vp.add_child(_stage)


# ---- Overlay UI -----------------------------------------------------------

func _build_overlay() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)

	var header := _label("SEQUENCE LAB", FS_TITLE, UiTheme.COLOR_ACCENT)
	header.position = Vector2(MARGIN, 12)
	header.add_theme_constant_override("outline_size", 6)
	_ui.add_child(header)

	_note = _label("", FS_CAPTION, UiTheme.COLOR_FAINT)
	_note.position = Vector2(MARGIN + 380, 28)
	_ui.add_child(_note)

	var back := Button.new()
	back.text = "Back"
	back.position = Vector2(1920 - MARGIN - 120, 16)
	back.size = Vector2(120, 40)
	UiTheme.style_button(back, true)
	back.add_theme_font_size_override("font_size", FS_BODY)
	back.pressed.connect(_on_back)
	_ui.add_child(back)

	# Left rail: sequence list.
	var ly := HEADER_H + MARGIN + 24
	var lh := SEQUENCES.size() * 52 + 60
	_ui.add_child(_panel(Vector2(MARGIN, ly), Vector2(RAIL_W, lh)))
	var lbl := _label("Sequence", FS_CAPTION, UiTheme.COLOR_FAINT)
	lbl.position = Vector2(MARGIN + 14, ly + 10)
	_ui.add_child(lbl)
	_mode_list = ItemList.new()
	_mode_list.position = Vector2(MARGIN + 14, ly + 36)
	_mode_list.size = Vector2(RAIL_W - 28, lh - 50)
	_mode_list.add_theme_font_override("font", UiTheme.active_font())
	_mode_list.add_theme_font_size_override("font_size", FS_BODY)
	for s in SEQUENCES:
		_mode_list.add_item(String(s["name"]))
	_mode_list.item_selected.connect(_set_mode)
	_ui.add_child(_mode_list)

	# Right rail: knobs + actions in a scroll, Save/Copy fixed below.
	var rx := 1920 - MARGIN - KNOB_W
	var ry := HEADER_H + MARGIN + 24
	var rh := int((1080.0 - ry - MARGIN) * 0.9)
	_ui.add_child(_panel(Vector2(rx, ry), Vector2(KNOB_W, rh)))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(rx + 16, ry + 14)
	scroll.size = Vector2(KNOB_W - 32, rh - 92)
	_ui.add_child(scroll)
	_knob_box = VBoxContainer.new()
	_knob_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_knob_box.custom_minimum_size = Vector2(KNOB_W - 56, 0)
	_knob_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_knob_box)

	var row := HBoxContainer.new()
	row.position = Vector2(rx + 16, ry + rh - 64)
	row.add_theme_constant_override("separation", 10)
	_ui.add_child(row)
	var save_btn := Button.new()
	save_btn.text = "Save"
	UiTheme.style_button(save_btn, true)
	save_btn.add_theme_font_size_override("font_size", FS_BODY)
	save_btn.custom_minimum_size = Vector2(120, 40)
	save_btn.pressed.connect(_on_save)
	row.add_child(save_btn)
	var copy_btn := Button.new()
	copy_btn.text = "Copy GDScript"
	UiTheme.style_button(copy_btn, false)
	copy_btn.add_theme_font_size_override("font_size", FS_BODY)
	copy_btn.custom_minimum_size = Vector2(200, 40)
	copy_btn.pressed.connect(_on_copy)
	row.add_child(copy_btn)


# ---- Sequence switching ---------------------------------------------------

func _set_mode(idx: int) -> void:
	_mode = idx
	if _mode_list.item_count > idx and not _mode_list.is_selected(idx):
		_mode_list.select(idx)
	_clear_stage()
	for c in _knob_box.get_children():
		c.queue_free()
	var seq: Dictionary = SEQUENCES[_mode]
	_knob_box.add_child(_label(String(seq["name"]), FS_BODY, UiTheme.COLOR_ACCENT))
	_knob_box.add_child(_label("Adjust the knobs, then Play to apply.\n(Knobs read at play start.)", FS_CAPTION, UiTheme.COLOR_FAINT))
	_ship_label = _label("", FS_CAPTION, UiTheme.COLOR_BOUNTY)
	_knob_box.add_child(_ship_label)
	# Action buttons.
	_add_action("▶ Play", _play)
	_add_action("New Ship", _on_new_ship)
	var loop := CheckButton.new()
	loop.text = "Loop"
	loop.button_pressed = _looping
	loop.add_theme_font_override("font", UiTheme.active_font())
	loop.add_theme_font_size_override("font_size", FS_BODY)
	loop.toggled.connect(func(on: bool): _looping = on)
	_knob_box.add_child(loop)
	_knob_box.add_child(HSeparator.new())
	# Knobs.
	for def in seq["script"].knob_schema():
		_add_knob(def, String(seq["name"]))
	# Spawn an idle ship to preview.
	_ship_path = _pick_ship_path()
	_spawn_idle()


# ---- Playback -------------------------------------------------------------

func _play() -> void:
	if _ship_path == "":
		_ship_path = _pick_ship_path()
	_spawn_idle()   # fresh ship every play (the sequence consumes / moves it)
	if _ship == null or not is_instance_valid(_ship):
		return
	var seq_cfg: Dictionary = SEQUENCES[_mode]
	var sprite: Sprite2D = _find_body_sprite(_ship)
	_seq = seq_cfg["script"].new()
	_stage.add_child(_seq)   # sibling of the ship (survives sprite reparenting)
	_seq.finished.connect(_on_seq_finished)
	_seq.play(_ship, sprite, _values[String(seq_cfg["name"])])


func _on_seq_finished() -> void:
	if _looping:
		# Brief beat, then replay with the same ship type. Guard so a queued loop callback after a
		# mode-switch / Back doesn't fire into a dead lab.
		get_tree().create_timer(0.6).timeout.connect(func():
			if _looping and is_instance_valid(self) and _stage != null and is_instance_valid(_stage):
				_play())


func _on_new_ship() -> void:
	_ship_path = _pick_ship_path()
	_spawn_idle()


func _spawn_idle() -> void:
	_clear_stage()
	if _ship_path == "" or not ResourceLoader.exists(_ship_path):
		return
	var ship: Node2D = load(_ship_path).instantiate()
	ship.position = _spawn_pos
	_stage.add_child(ship)
	_freeze_node(ship)
	if ship.is_in_group("enemies"):
		ship.remove_from_group("enemies")
	_ship = ship
	if _ship_label != null and is_instance_valid(_ship_label):
		_ship_label.text = "Ship: %s" % _ship_path.get_file().get_basename()


func _clear_stage() -> void:
	_seq = null
	_ship = null
	if _stage != null and is_instance_valid(_stage):
		for c in _stage.get_children():
			c.queue_free()


# The sequence's preferred ship (a fixed path), else a random live enemy (excl. bosses, mines,
# asteroids, supremacy frigate — same filter as the Ship-Damage panel).
func _pick_ship_path() -> String:
	var fixed: String = String(SEQUENCES[_mode].get("ship", ""))
	if fixed != "" and ResourceLoader.exists(fixed):
		return fixed
	var pool: Array = []
	for p in EnemyManifest.all_enemies(false):   # full dev roster (zealots included), bosses already out
		var path: String = String(p)
		if path.contains("boss") or path.contains("asteroid") or path.contains("frigate"):
			continue
		if path.contains("enemy_mine") and not path.contains("minelayer"):
			continue
		pool.append(p)
	if pool.is_empty():
		return ""
	return String(pool[randi() % pool.size()])


# ---- Knobs / persistence --------------------------------------------------

func _add_knob(def: Dictionary, seq_name: String) -> void:
	var key := String(def["key"])
	var row_lbl := _label("%s: %s" % [def["label"], _fmt(float(_values[seq_name][key]), float(def["step"]))], FS_CAPTION, UiTheme.COLOR_FAINT)
	_knob_box.add_child(row_lbl)
	var sl := HSlider.new()
	sl.min_value = float(def["min"])
	sl.max_value = float(def["max"])
	sl.step = float(def["step"])
	sl.value = float(_values[seq_name][key])
	sl.custom_minimum_size = Vector2(0, 26)
	sl.value_changed.connect(func(v: float):
		_values[seq_name][key] = v
		row_lbl.text = "%s: %s" % [def["label"], _fmt(v, float(def["step"]))])
	_knob_box.add_child(sl)


func _add_action(text: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	UiTheme.style_button(btn, true)
	btn.add_theme_font_size_override("font_size", FS_BODY)
	btn.custom_minimum_size = Vector2(0, 36)
	btn.pressed.connect(cb)
	_knob_box.add_child(btn)


func _fmt(v: float, step: float) -> String:
	if step >= 1.0:
		return str(int(v))
	return "%.3f" % v if step < 0.01 else "%.2f" % v


func _on_save() -> void:
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_values, "\t"))
		f.close()
	if _note != null:
		_note.text = "Saved %s" % SAVE_PATH


func _load_saved() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		for seq_name in _values:
			var saved: Dictionary = data.get(seq_name, {})
			for key in _values[seq_name]:
				if saved.has(key):
					_values[seq_name][key] = float(saved[key])


func _on_copy() -> void:
	var seq_name := String(SEQUENCES[_mode]["name"])
	var v: Dictionary = _values[seq_name]
	var t := "# Sequence Lab — %s (tuned knobs). Paste the values into the sequence's\n" % seq_name
	t += "# knob_schema() defaults, or pass as the knobs dict to <SeqScript>.new().play(ship, sprite, {...}).\n"
	t += "var knobs := {\n"
	for def in SEQUENCES[_mode]["script"].knob_schema():
		var key := String(def["key"])
		t += "\t\"%s\": %s,\n" % [key, _fmt(float(v[key]), float(def["step"]))]
	t += "}\n"
	DisplayServer.clipboard_set(t)
	if _note != null:
		_note.text = "Copied GDScript to clipboard"


# ---- Frozen-enemy helpers (mirror of shader_lab) --------------------------

func _freeze_node(n: Node) -> void:
	n.set_process(false)
	n.set_physics_process(false)
	if n is Timer:
		(n as Timer).stop()
	for c in n.get_children():
		_freeze_node(c)


func _find_body_sprite(ship: Node) -> Sprite2D:
	var s := ship.get_node_or_null("Sprite2D")
	if s is Sprite2D:
		return s
	for c in ship.find_children("*", "Sprite2D", true, false):
		if c is Sprite2D:
			return c as Sprite2D
	return null


# ---- Input + back ---------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()


func _on_back() -> void:
	if _hd_scope != null and is_instance_valid(_hd_scope):
		_hd_scope.free()
		_hd_scope = null
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


# ---- UI helpers -----------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.active_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	l.add_theme_constant_override("outline_size", 3)
	return l


func _panel(pos: Vector2, sz: Vector2) -> Panel:
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = pos
	panel.size = sz
	return panel
