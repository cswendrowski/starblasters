extends CanvasLayer

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const NODE_NAME := "OptionsOverlay"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

# Set true by callers that want an "Exit to Main Menu" button in the overlay —
# currently only the sector map, which has no separate pause menu of its own.
# Must be set BEFORE the overlay enters the tree (before _ready builds the UI).
var _show_exit_to_menu: bool = false


static func open(parent: Node, show_exit_to_menu: bool = false) -> CanvasLayer:
	if parent == null:
		return null
	var root: Node = parent.get_tree().root if parent.is_inside_tree() else parent
	for n in root.get_children():
		if n.name == NODE_NAME and n is CanvasLayer:
			n.visible = true
			return n
	var overlay := load("res://scripts/ui/options_overlay.gd").new() as CanvasLayer
	overlay.name = NODE_NAME
	overlay._show_exit_to_menu = show_exit_to_menu
	root.add_child(overlay)
	return overlay


var _options_panel: PanelContainer = null

var _master_slider: HSlider = null
var _music_slider: HSlider = null
var _sfx_slider: HSlider = null
var _shake_slider: HSlider = null
var _fullscreen_check: CheckButton = null
var _damage_tells_check: CheckButton = null

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
	# Near-opaque: the overlay can sit over the live (paused) game, and Roman
	# wants menus to read as solid HD screens rather than see-through.
	dim.color = Color(0.02, 0.03, 0.06, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Panel parented directly to the CanvasLayer so _fit_panel() can size +
	# center it manually. We do NOT scale the panel (scaling a Control desyncs
	# its child click rects from the visual). The overlay renders at HD
	# (1920×1080) — it inherits the content scale of whatever opened it (every
	# caller is an HD screen), so there's ample room and no scrolling needed.
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.COLOR_PANEL_BG
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(2)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	_options_panel = panel

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	panel.add_child(outer)

	var header := Label.new()
	header.text = "OPTIONS"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(header, UiTheme.LabelKind.TITLE)
	outer.add_child(header)

	outer.add_child(_make_separator())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 48)
	outer.add_child(columns)

	# --- Left column: Audio + Display ---
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(460, 0)
	left.add_theme_constant_override("separation", 12)
	columns.add_child(left)

	var audio_lbl := Label.new()
	audio_lbl.text = "Audio"
	UiTheme.style_label(audio_lbl, UiTheme.LabelKind.HEADER)
	left.add_child(audio_lbl)

	_master_slider = _add_slider_row(left, "Master Volume", _settings().master_volume, _on_master_changed)
	_music_slider  = _add_slider_row(left, "Music Volume",  _settings().music_volume,  _on_music_changed)
	_sfx_slider    = _add_slider_row(left, "Sound Volume",  _settings().sfx_volume,    _on_sfx_changed)
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

	var tells_row := HBoxContainer.new()
	tells_row.add_theme_constant_override("separation", 8)
	left.add_child(tells_row)
	var tells_label := Label.new()
	tells_label.text = "Damage Tells"
	tells_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(tells_label, UiTheme.LabelKind.BODY)
	tells_row.add_child(tells_label)
	_damage_tells_check = CheckButton.new()
	_damage_tells_check.button_pressed = _settings().damage_tells
	_damage_tells_check.toggled.connect(_on_damage_tells_toggled)
	tells_row.add_child(_damage_tells_check)

	var font_row := HBoxContainer.new()
	font_row.add_theme_constant_override("separation", 8)
	left.add_child(font_row)
	var font_label := Label.new()
	font_label.text = "Font"
	font_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(font_label, UiTheme.LabelKind.BODY)
	font_row.add_child(font_label)
	var font_btn := OptionButton.new()
	font_btn.add_theme_font_override("font", UiTheme.menu_font())
	font_btn.add_item("Pixel Operator")
	font_btn.add_item("Pixelify Sans (TTF)")
	font_btn.select(0 if String(_settings().font_style) == "pixel" else 1)
	font_btn.item_selected.connect(_on_font_picked)
	font_row.add_child(font_btn)

	# How often the outpost docking cinematic plays (Roman 2026-06-27).
	var dock_row := HBoxContainer.new()
	dock_row.add_theme_constant_override("separation", 8)
	left.add_child(dock_row)
	var dock_label := Label.new()
	dock_label.text = "Dock cinematic"
	dock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(dock_label, UiTheme.LabelKind.BODY)
	dock_row.add_child(dock_label)
	var dock_btn := OptionButton.new()
	dock_btn.add_theme_font_override("font", UiTheme.menu_font())
	dock_btn.add_item("Always")
	dock_btn.add_item("Once per boss")
	dock_btn.add_item("Once per patrol")
	dock_btn.add_item("Never")
	dock_btn.select(clampi(int(_settings().outpost_dock_anim), 0, 3))
	dock_btn.item_selected.connect(_on_dock_anim_picked)
	dock_row.add_child(dock_btn)

	# --- Right column: Controls ---
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(460, 0)
	right.add_theme_constant_override("separation", 12)
	columns.add_child(right)

	var ctrl_lbl := Label.new()
	ctrl_lbl.text = "Controls"
	UiTheme.style_label(ctrl_lbl, UiTheme.LabelKind.HEADER)
	right.add_child(ctrl_lbl)

	for action_name in ["shoot", "shoot2", "shoot_nose", "focus", "primary_swap", "autofire_toggle", "smart_mount_toggle"]:
		_add_rebind_row(right, action_name)

	outer.add_child(_make_separator())

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	if _show_exit_to_menu:
		var exit_btn := Button.new()
		exit_btn.text = "Exit to Main Menu"
		exit_btn.custom_minimum_size = Vector2(300, 60)
		UiTheme.style_button(exit_btn)
		exit_btn.pressed.connect(_on_exit_to_menu)
		btn_row.add_child(exit_btn)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(260, 60)
	UiTheme.style_button(back)
	back.pressed.connect(_on_back)
	btn_row.add_child(back)
	var back_center := CenterContainer.new()
	back_center.add_child(btn_row)
	outer.add_child(back_center)

	# Containers report their final size only after a layout pass, so defer
	# the fit-and-center until the panel has resolved its natural size.
	call_deferred("_fit_panel")


# Size the panel to fit inside the viewport (capped, never scaled) and center
# it. Done after layout because a PanelContainer's size is unknown until its
# children are measured. Capping never scales, so click rects stay 1:1 with
# the visuals. Re-run safe (idempotent).
func _fit_panel() -> void:
	if _options_panel == null or not is_instance_valid(_options_panel):
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# Margin so the panel border doesn't kiss the screen edge.
	var avail: Vector2 = vp - Vector2(16, 16)
	_options_panel.scale = Vector2.ONE
	var natural: Vector2 = _options_panel.get_combined_minimum_size()
	if natural.x <= 0.0 or natural.y <= 0.0:
		natural = _options_panel.size
	_options_panel.size = Vector2(minf(natural.x, avail.x), minf(natural.y, avail.y))
	_options_panel.position = ((vp - _options_panel.size) * 0.5).round()
	UiTheme.assert_inside_viewport(self)


const _ACTION_LABELS := {
	"shoot": "Primary fire",
	"shoot2": "Secondary fire",
	"shoot_nose": "Super weapon",
	"focus": "Focus / Slow",
	"primary_swap": "Swap primary",
	"autofire_toggle": "Toggle autofire",
	"smart_mount_toggle": "Toggle smart mount",
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
	btn.custom_minimum_size = Vector2(180, 48)
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
	_settings().set_keybind(_rebind_pending_action, event.physical_keycode)
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
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(200, 0)
	UiTheme.style_label(lbl, UiTheme.LabelKind.BODY)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(180, 28)
	slider.value_changed.connect(on_changed)
	row.add_child(slider)
	var pct := Label.new()
	pct.custom_minimum_size = Vector2(64, 0)
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


func _on_sfx_changed(v: float) -> void:
	_settings().set_sfx_volume(v)


func _on_shake_changed(v: float) -> void:
	_settings().set_shake_scale(v)


func _on_fullscreen_toggled(on: bool) -> void:
	_settings().set_fullscreen(on)


func _on_damage_tells_toggled(on: bool) -> void:
	_settings().set_damage_tells(on)


func _on_font_picked(idx: int) -> void:
	_settings().set_font_style("pixel" if idx == 0 else "ttf")
	call_deferred("_rebuild_ui")


func _on_dock_anim_picked(idx: int) -> void:
	_settings().set_outpost_dock_anim(idx)


func _rebuild_ui() -> void:
	for child in get_children():
		child.queue_free()
	_build_ui()


func _on_back() -> void:
	queue_free()


func _on_exit_to_menu() -> void:
	# Tear down this overlay first — it's parented to the tree root (a sibling of
	# the scene), so a scene swap wouldn't free it otherwise and it'd linger over
	# the main menu. The transition's black cover hides the teardown.
	queue_free()
	SceneTransition.change_scene(get_tree(), MAIN_MENU_SCENE)
