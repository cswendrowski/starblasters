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
	# Cap the panel to fit the 480×270 viewport with a small margin even
	# when stacked over the sector map (which uses native res). Without
	# the cap the panel overflows vertically once the controls section
	# expands to 7 rebindable actions.
	panel.custom_minimum_size = Vector2(0, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.COLOR_PANEL_BG
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	# Scroll wrapper so the 7-action rebind list + sliders always fit
	# inside the 270 px tall viewport.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)

	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(240, 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	scroll.add_child(v)

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

	# Autofire is toggled in-game via the rebindable "autofire_toggle"
	# action (default R). The settings checkbox was removed 2026-05-24
	# per designer feedback — runtime toggle is friendlier and the
	# rebind row below exposes the keybinding.

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

	# Controls — display current keyboard bindings + click-to-rebind
	# (keyboard only for now; gamepad bindings stay defaults).
	var ctrl_lbl := Label.new()
	ctrl_lbl.text = "Controls"
	UiTheme.style_label(ctrl_lbl, UiTheme.LabelKind.HEADER)
	v.add_child(ctrl_lbl)
	for action_name in ["shoot", "shoot2", "shoot_nose", "focus", "weapon_previous", "weapon_next", "autofire_toggle"]:
		_add_rebind_row(v, action_name)

	v.add_child(_make_separator())

	# Return to Main Menu — available from any non-menu scene. From the
	# sector map there's nothing to lose (autosave already fired); inside a
	# level (combat/outpost/signal/hazard) we warn before bailing.
	if _show_menu_button():
		var menu := Button.new()
		menu.text = "Return to Main Menu"
		menu.custom_minimum_size = Vector2(180, 22)
		UiTheme.style_button(menu, true)
		menu.pressed.connect(_on_return_to_menu)
		var menu_center := CenterContainer.new()
		menu_center.add_child(menu)
		v.add_child(menu_center)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(140, 22)
	UiTheme.style_button(back, true)
	back.pressed.connect(_on_back)
	var back_center := CenterContainer.new()
	back_center.add_child(back)
	v.add_child(back_center)


# Rebind row for one input action. Shows the action's display label and
# the current primary keyboard binding (if any) as a clickable button.
# Clicking arms a one-shot key capture; the next keypress replaces the
# action's first keyboard event.
const _ACTION_LABELS := {
	"shoot": "Primary fire",
	"shoot2": "Secondary fire",
	"shoot_nose": "Super weapon",
	"focus": "Focus / Slow",
	"weapon_previous": "Previous weapon",
	"weapon_next": "Next weapon",
	"autofire_toggle": "Toggle autofire",
}

var _rebind_pending_action: String = ""
var _rebind_pending_button: Button = null


func _add_rebind_row(parent: VBoxContainer, action_name: String) -> void:
	if not InputMap.has_action(action_name):
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = _ACTION_LABELS.get(action_name, action_name)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(lbl, UiTheme.LabelKind.BODY)
	row.add_child(lbl)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(90, 18)
	btn.text = _key_label_for(action_name)
	UiTheme.style_button(btn)
	btn.pressed.connect(func(): _start_rebind(action_name, btn))
	row.add_child(btn)


# Returns a human-readable label for the action's first keyboard event,
# or "—" if no keyboard binding exists.
func _key_label_for(action_name: String) -> String:
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventKey:
			return OS.get_keycode_string(ev.physical_keycode) if ev.physical_keycode != 0 else OS.get_keycode_string(ev.keycode)
	return "—"


func _start_rebind(action_name: String, btn: Button) -> void:
	_rebind_pending_action = action_name
	_rebind_pending_button = btn
	btn.text = "Press a key…"


# Capture the next keypress and rebind the action's first keyboard event
# to it. Other events (gamepad buttons, the secondary keyboard binding)
# are left untouched.
func _unhandled_key_input(event: InputEvent) -> void:
	if _rebind_pending_action == "":
		return
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		# Cancel rebind silently.
		if _rebind_pending_button:
			_rebind_pending_button.text = _key_label_for(_rebind_pending_action)
		_rebind_pending_action = ""
		_rebind_pending_button = null
		get_viewport().set_input_as_handled()
		return
	# Find the existing first keyboard event and replace it.
	var existing_key: InputEventKey = null
	for e in InputMap.action_get_events(_rebind_pending_action):
		if e is InputEventKey:
			existing_key = e
			break
	# Persist via Settings.set_keybind — it both updates InputMap AND
	# writes the override to settings.cfg so the rebind survives a
	# restart.
	if _settings().has_method("set_keybind"):
		_settings().set_keybind(_rebind_pending_action, event.physical_keycode)
	elif existing_key:
		# Fallback for the unlikely case Settings is unavailable.
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


func _on_font_picked(idx: int) -> void:
	_settings().set_font_style("pixel" if idx == 0 else "ttf")
	# Rebuild the overlay so every existing Label/Button picks up the
	# new active_font() — UiTheme.style_*() reads font_style at apply
	# time and caches it on the node, so swapping requires a re-style.
	# Deferred to avoid mutating the tree while the OptionButton's
	# item_selected signal handler is still on the stack.
	call_deferred("_rebuild_ui")


func _rebuild_ui() -> void:
	for child in get_children():
		child.queue_free()
	_build_ui()


func _on_back() -> void:
	queue_free()


# Hide the menu button on the main menu itself — already there.
const _MAIN_MENU_PATH := "res://scenes/main_menu.tscn"
const _SECTOR_MAP_PATH := "res://scenes/sector_map_v3.tscn"

func _show_menu_button() -> bool:
	var scn = get_tree().current_scene
	if scn == null:
		return false
	return scn.scene_file_path != _MAIN_MENU_PATH


# True for any scene where leaving means scrapping current-level progress.
# Sector map is safe (autosaved on entry), so no warning there.
func _in_level() -> bool:
	var scn = get_tree().current_scene
	if scn == null:
		return false
	var p: String = scn.scene_file_path
	return p != _MAIN_MENU_PATH and p != _SECTOR_MAP_PATH


func _on_return_to_menu() -> void:
	if _in_level():
		_show_menu_warning()
	else:
		_go_to_menu()


func _go_to_menu() -> void:
	get_tree().paused = false
	var SceneTransition = load("res://scripts/scene_transition.gd")
	SceneTransition.change_scene(get_tree(), _MAIN_MENU_PATH)


func _show_menu_warning() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.name = "WarnDim"
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.COLOR_PANEL_BG
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.border_width_left = 2; sb.border_width_top = 2
	sb.border_width_right = 2; sb.border_width_bottom = 2
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(240, 0)
	panel.add_child(v)
	var head := Label.new()
	head.text = "Return to Main Menu?"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(head, UiTheme.LabelKind.HEADER)
	v.add_child(head)
	var body := Label.new()
	body.text = "Leaving this level will scrap your progress in it.\nYour patrol resumes from the sector map."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(220, 0)
	UiTheme.style_label(body, UiTheme.LabelKind.BODY)
	v.add_child(body)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	v.add_child(btn_row)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(96, 22)
	UiTheme.style_button(cancel, true)
	cancel.pressed.connect(func(): dim.queue_free())
	btn_row.add_child(cancel)
	var confirm := Button.new()
	confirm.text = "Leave"
	confirm.custom_minimum_size = Vector2(96, 22)
	UiTheme.style_button(confirm)
	confirm.pressed.connect(_go_to_menu)
	btn_row.add_child(confirm)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# Swallow the event so the pause menu underneath doesn't toggle when
		# the player closes Options with Escape.
		get_viewport().set_input_as_handled()
		queue_free()
