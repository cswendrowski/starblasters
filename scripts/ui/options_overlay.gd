extends CanvasLayer

# Shared Options menu, openable from the main menu and from the in-game
# pause menu. Single-instance: `open(parent)` is a no-op if an instance is
# already in the tree. Reads/writes Settings (autoload) so values persist
# across scenes and re-launches.
#
# Why CanvasLayer-based instead of a packed .tscn:
# - Caller-agnostic: the main menu is a Control, the pause menu is a
#   CanvasLayer. A CanvasLayer overlay sits on top of either without
#   inheriting weird parent transforms.
# - No .tscn cache-bind churn when we tweak widget layout.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const NODE_NAME := "OptionsOverlay"


# Returns the live overlay node (existing or freshly created). Callers can
# ignore the return value; the overlay manages its own lifecycle.
static func open(parent: Node) -> CanvasLayer:
	if parent == null:
		return null
	var root: Node = parent.get_tree().root if parent.is_inside_tree() else parent
	# Single-instance guard. If one is already mounted on this scene's
	# root, surface it again instead of stacking a second copy.
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


func _settings() -> Node:
	return get_node("/root/Settings")


func _init() -> void:
	layer = 90  # above pause menu (which doesn't set a layer; defaults to 1)
	# CanvasLayer doesn't have process_mode? It does — inherits from Node.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.COLOR_PANEL_BG
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(280, 0)
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)

	var header := Label.new()
	header.text = "OPTIONS"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	v.add_child(header)

	v.add_child(_make_separator())

	_master_slider = _add_slider_row(v, "Master Volume", _settings().master_volume, _on_master_changed)
	_music_slider = _add_slider_row(v, "Music Volume", _settings().music_volume, _on_music_changed)
	_shake_slider = _add_slider_row(v, "Screen Shake", _settings().shake_scale, _on_shake_changed)

	# Fullscreen toggle row
	var fs_row := HBoxContainer.new()
	fs_row.add_theme_constant_override("separation", 12)
	v.add_child(fs_row)
	var fs_label := Label.new()
	fs_label.text = "Fullscreen"
	fs_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(fs_label, UiTheme.LabelKind.BODY)
	fs_row.add_child(fs_label)
	_fullscreen_check = CheckButton.new()
	_fullscreen_check.button_pressed = _settings().fullscreen
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	fs_row.add_child(_fullscreen_check)

	# Autofire toggle row — when on, primary fire latches without
	# holding the button. Cave/Touhou tradition for marathon sessions.
	var af_row := HBoxContainer.new()
	af_row.add_theme_constant_override("separation", 12)
	v.add_child(af_row)
	var af_label := Label.new()
	af_label.text = "Autofire"
	af_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(af_label, UiTheme.LabelKind.BODY)
	af_row.add_child(af_label)
	var af_check := CheckButton.new()
	af_check.button_pressed = bool(_settings().get("autofire") if "autofire" in _settings() else false)
	af_check.toggled.connect(_on_autofire_toggled)
	af_row.add_child(af_check)

	# Font face row — "Pixel" (Pixel Operator, default) vs "TTF" (Pixelify
	# Sans). Re-opening menus after a swap shows the new face.
	var font_row := HBoxContainer.new()
	font_row.add_theme_constant_override("separation", 12)
	v.add_child(font_row)
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

	v.add_child(_make_separator())

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(140, 22)
	UiTheme.style_button(back, true)
	back.pressed.connect(_on_back)
	var back_center := CenterContainer.new()
	back_center.add_child(back)
	v.add_child(back_center)


func _make_separator() -> Control:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	return sep


func _add_slider_row(parent: VBoxContainer, label_text: String, initial: float, on_changed: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(110, 0)
	UiTheme.style_label(lbl, UiTheme.LabelKind.BODY)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(140, 14)
	slider.value_changed.connect(on_changed)
	row.add_child(slider)
	var pct := Label.new()
	pct.custom_minimum_size = Vector2(38, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.text = "%d%%" % int(round(initial * 100.0))
	UiTheme.style_label(pct, UiTheme.LabelKind.CAPTION)
	row.add_child(pct)
	# Bind the % label to live updates via the slider's signal.
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


func _on_autofire_toggled(on: bool) -> void:
	if _settings().has_method("set_autofire"):
		_settings().set_autofire(on)


func _on_font_picked(idx: int) -> void:
	_settings().set_font_style("pixel" if idx == 0 else "ttf")


func _on_back() -> void:
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# Swallow the event so the pause menu underneath doesn't toggle when
		# the player closes Options with Escape.
		get_viewport().set_input_as_handled()
		queue_free()
