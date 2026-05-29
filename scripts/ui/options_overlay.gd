extends CanvasLayer

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const NODE_NAME := "OptionsOverlay"


static func open(parent: Node) -> CanvasLayer:
	if parent == null:
		return null
	var root: Node = parent.get_tree().root if parent.is_inside_tree() else parent
	for n in root.get_children():
		if n.name == NODE_NAME and n is CanvasLayer:
			n.visible = true
			return n
	var overlay := load("res://scripts/ui/options_overlay.gd").new() as CanvasLayer
	overlay.name = NODE_NAME
	root.add_child(overlay)
	return overlay


var _master_slider: HSlider = null
var _music_slider: HSlider = null
var _shake_slider: HSlider = null
var _fullscreen_check: CheckButton = null

var _rebind_pending_action: String = ""
var _rebind_pending_button: Button = null


func _settings() -> Node:
	return get_node("/root/Settings")


func _init() -> void:
	layer = 91
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.70)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.COLOR_PANEL_BG
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	var header := Label.new()
	header.text = "OPTIONS"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	outer.add_child(header)

	outer.add_child(_make_separator())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	outer.add_child(columns)

	# --- Left column: Audio + Display ---
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(200, 0)
	left.add_theme_constant_override("separation", 6)
	columns.add_child(left)

	var audio_lbl := Label.new()
	audio_lbl.text = "Audio"
	UiTheme.style_label(audio_lbl, UiTheme.LabelKind.HEADER)
	left.add_child(audio_lbl)

	_master_slider = _add_slider_row(left, "Master Volume", _settings().master_volume, _on_master_changed)
	_music_slider  = _add_slider_row(left, "Music Volume",  _settings().music_volume,  _on_music_changed)
	_shake_slider  = _add_slider_row(left, "Screen Shake",  _settings().shake_scale,   _on_shake_changed)

	left.add_child(_make_separator())

	var display_lbl := Label.new()
	display_lbl.text = "Display"
	UiTheme.style_label(display_lbl, UiTheme.LabelKind.HEADER)
	left.add_child(display_lbl)

	var fs_row := HBoxContainer.new()
	fs_row.add_theme_constant_override("separation", 8)
	left.add_child(fs_row)
	var fs_label := Label.new()
	fs_label.text = "Fullscreen"
	fs_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(fs_label, UiTheme.LabelKind.BODY)
	fs_row.add_child(fs_label)
	_fullscreen_check = CheckButton.new()
	_fullscreen_check.button_pressed = _settings().fullscreen
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	fs_row.add_child(_fullscreen_check)

	var font_row := HBoxContainer.new()
	font_row.add_theme_constant_override("separation", 8)
	left.add_child(font_row)
	var font_label := Label.new()
	font_label.text = "Font"
	font_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(font_label, UiTheme.LabelKind.BODY)
	font_row.add_child(font_label)
	var font_btn := OptionButton.new()
	font_btn.add_item("Pixel Operator")
	font_btn.add_item("Pixelify Sans (TTF)")
	font_btn.select(0 if String(_settings().font_style) == "pixel" else 1)
	font_btn.item_selected.connect(_on_font_picked)
	font_row.add_child(font_btn)

	# --- Right column: Controls ---
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(200, 0)
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)

	var ctrl_lbl := Label.new()
	ctrl_lbl.text = "Controls"
	UiTheme.style_label(ctrl_lbl, UiTheme.LabelKind.HEADER)
	right.add_child(ctrl_lbl)

	for action_name in ["shoot", "shoot2", "shoot_nose", "focus", "primary_swap", "autofire_toggle"]:
		_add_rebind_row(right, action_name)

	outer.add_child(_make_separator())

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(120, 22)
	UiTheme.style_button(back, true)
	back.pressed.connect(_on_back)
	var back_center := CenterContainer.new()
	back_center.add_child(back)
	outer.add_child(back_center)


const _ACTION_LABELS := {
	"shoot": "Primary fire",
	"shoot2": "Secondary fire",
	"shoot_nose": "Super weapon",
	"focus": "Focus / Slow",
	"primary_swap": "Swap primary",
	"autofire_toggle": "Toggle autofire",
}


func _add_rebind_row(parent: VBoxContainer, action_name: String) -> void:
	if not InputMap.has_action(action_name):
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = _ACTION_LABELS.get(action_name, action_name)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(lbl, UiTheme.LabelKind.BODY)
	row.add_child(lbl)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(80, 18)
	btn.text = _key_label_for(action_name)
	UiTheme.style_button(btn)
	btn.pressed.connect(func(): _start_rebind(action_name, btn))
	row.add_child(btn)


func _key_label_for(action_name: String) -> String:
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventKey:
			return OS.get_keycode_string(ev.physical_keycode) if ev.physical_keycode != 0 else OS.get_keycode_string(ev.keycode)
	return "—"


func _start_rebind(action_name: String, btn: Button) -> void:
	_rebind_pending_action = action_name
	_rebind_pending_button = btn
	btn.text = "Press key…"


func _unhandled_key_input(event: InputEvent) -> void:
	if _rebind_pending_action == "":
		return
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		if _rebind_pending_button:
			_rebind_pending_button.text = _key_label_for(_rebind_pending_action)
		_rebind_pending_action = ""
		_rebind_pending_button = null
		get_viewport().set_input_as_handled()
		return
	if _settings().has_method("set_keybind"):
		_settings().set_keybind(_rebind_pending_action, event.physical_keycode)
	else:
		var existing_key: InputEventKey = null
		for e in InputMap.action_get_events(_rebind_pending_action):
			if e is InputEventKey:
				existing_key = e
				break
		if existing_key:
			InputMap.action_erase_event(_rebind_pending_action, existing_key)
		var new_ev := InputEventKey.new()
		new_ev.physical_keycode = event.physical_keycode
		new_ev.keycode = event.keycode
		InputMap.action_add_event(_rebind_pending_action, new_ev)
	if _rebind_pending_button:
		_rebind_pending_button.text = _key_label_for(_rebind_pending_action)
	_rebind_pending_action = ""
	_rebind_pending_button = null
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _rebind_pending_action != "":
			return
		get_viewport().set_input_as_handled()
		queue_free()


func _make_separator() -> Control:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	return sep


func _add_slider_row(parent: VBoxContainer, label_text: String, initial: float, on_changed: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(96, 0)
	UiTheme.style_label(lbl, UiTheme.LabelKind.BODY)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(80, 14)
	slider.value_changed.connect(on_changed)
	row.add_child(slider)
	var pct := Label.new()
	pct.custom_minimum_size = Vector2(32, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.text = "%d%%" % int(round(initial * 100.0))
	UiTheme.style_label(pct, UiTheme.LabelKind.CAPTION)
	row.add_child(pct)
	slider.value_changed.connect(func(v: float):
		pct.text = "%d%%" % int(round(v * 100.0))
	)
	return slider


func _on_master_changed(v: float) -> void:
	_settings().set_master_volume(v)


func _on_music_changed(v: float) -> void:
	_settings().set_music_volume(v)


func _on_shake_changed(v: float) -> void:
	_settings().set_shake_scale(v)


func _on_fullscreen_toggled(on: bool) -> void:
	_settings().set_fullscreen(on)


func _on_font_picked(idx: int) -> void:
	_settings().set_font_style("pixel" if idx == 0 else "ttf")
	call_deferred("_rebuild_ui")


func _rebuild_ui() -> void:
	for child in get_children():
		child.queue_free()
	_build_ui()


func _on_back() -> void:
	queue_free()
