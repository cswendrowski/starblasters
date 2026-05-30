# Pause Menu Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the oversized pause overlay and single-column options panel with a slim 3-button pause overlay and a 2-column HD options screen.

**Architecture:** Two tasks — (1) slim the pause_menu scene/script to 3 buttons with no header/status, (2) replace the options_overlay.gd single-column scroll with a 2-column layout. The `static func open(parent)` API on options_overlay.gd is preserved so all 4 callers work unchanged.

**Tech Stack:** Godot 4.6.3 GDScript, `scripts/ui/ui_theme.gd` for all styling, no new scenes needed.

---

### Task 1: Slim the Pause Overlay

**Files:**
- Modify: `scenes/pause_menu.tscn`
- Modify: `scripts/pause_menu.gd`

- [ ] **Step 1: Rewrite `scenes/pause_menu.tscn`**

Replace the entire file contents with a minimal 3-button scene. The existing scene has `ResumeBtn`, `MenuBtn`, `QuitBtn`, a header Label and `StatusLabel`. We need to keep only Dim + Center + VBox with 3 buttons: MenuBtn, OptionsBtn, BackBtn.

```
[gd_scene load_steps=2 format=3 uid="uid://b2t4ltiewu7fw"]

[ext_resource type="Script" path="res://scripts/pause_menu.gd" id="1_5lpsx"]

[node name="PauseMenu" type="CanvasLayer"]
layer = 10
script = ExtResource("1_5lpsx")

[node name="Dim" type="ColorRect" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0, 0, 0, 0.7)
mouse_filter = 1

[node name="Center" type="CenterContainer" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0

[node name="VBox" type="VBoxContainer" parent="Center"]
custom_minimum_size = Vector2(160, 0)
layout_mode = 2
theme_override_constants/separation = 6

[node name="MenuBtn" type="Button" parent="Center/VBox"]
custom_minimum_size = Vector2(160, 22)
layout_mode = 2
text = "Main Menu"

[node name="OptionsBtn" type="Button" parent="Center/VBox"]
custom_minimum_size = Vector2(160, 22)
layout_mode = 2
text = "Options"

[node name="BackBtn" type="Button" parent="Center/VBox"]
custom_minimum_size = Vector2(160, 22)
layout_mode = 2
text = "Back"
```

- [ ] **Step 2: Rewrite `scripts/pause_menu.gd`**

Replace entirely:

```gdscript
extends CanvasLayer

const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

@onready var _menu_btn: Button = $Center/VBox/MenuBtn
@onready var _opts_btn: Button = $Center/VBox/OptionsBtn
@onready var _back_btn: Button = $Center/VBox/BackBtn

var _paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	for b in [_menu_btn, _opts_btn, _back_btn]:
		UiTheme.style_button(b, true)
	_menu_btn.pressed.connect(_to_menu)
	_opts_btn.pressed.connect(_open_options)
	_back_btn.pressed.connect(_resume)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_toggle()


func _toggle() -> void:
	_paused = not _paused
	visible = _paused
	get_tree().paused = _paused
	if has_node("/root/Music"):
		get_node("/root/Music").set_walk_frozen(_paused)


func _resume() -> void:
	_toggle()


func _open_options() -> void:
	var OptionsOverlay = load("res://scripts/ui/options_overlay.gd")
	OptionsOverlay.open(self)


func _to_menu() -> void:
	_show_menu_warning()


func _show_menu_warning() -> void:
	var m := UiTheme.make_modal(95, Vector2(240, 0))
	add_child(m.layer)
	var head := Label.new()
	head.text = "Return to Main Menu?"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(head, UiTheme.LabelKind.HEADER)
	m.vbox.add_child(head)
	var body := Label.new()
	body.text = "Leaving this level will scrap your progress in it.\nYour patrol resumes from the sector map."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(220, 0)
	UiTheme.style_label(body, UiTheme.LabelKind.BODY)
	m.vbox.add_child(body)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	m.vbox.add_child(btn_row)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(96, 22)
	UiTheme.style_button(cancel, true)
	cancel.pressed.connect(func(): m.layer.queue_free())
	btn_row.add_child(cancel)
	var confirm := Button.new()
	confirm.text = "Leave"
	confirm.custom_minimum_size = Vector2(96, 22)
	UiTheme.style_button(confirm)
	confirm.pressed.connect(func():
		get_tree().paused = false
		SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")
	)
	btn_row.add_child(confirm)
```

- [ ] **Step 3: Verify parse — run headless smoke**

```powershell
& "C:\Users\Cody\AppData\Local\Programs\Godot\Godot_v4.6.3-stable_win64.exe" --path . --headless --quit-after 2 2>&1
```

Expected: no parse errors, exits cleanly.

- [ ] **Step 4: Commit**

```
git add scenes/pause_menu.tscn scripts/pause_menu.gd
git commit -m "feat: slim pause menu to 3-button overlay (no quit, no status header)"
```

---

### Task 2: 2-Column Options Screen

**Files:**
- Modify: `scripts/ui/options_overlay.gd`

Preserve the `static func open(parent) -> CanvasLayer` API and all Settings.* calls. Replace the single-column scroll layout with a 2-column HBox: Audio+Display on the left, Controls on the right.

- [ ] **Step 1: Rewrite `scripts/ui/options_overlay.gd`**

Replace entirely (keep the file at the same path so all `load()` calls continue to work):

```gdscript
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

	# Header
	var header := Label.new()
	header.text = "OPTIONS"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	outer.add_child(header)

	outer.add_child(_make_separator())

	# Two-column body
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

	# Fullscreen toggle row
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

	# Font row
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

	# Back button
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
```

- [ ] **Step 2: Run headless smoke**

```powershell
& "C:\Users\Cody\AppData\Local\Programs\Godot\Godot_v4.6.3-stable_win64.exe" --path . --headless --quit-after 2 2>&1
```

Expected: exits cleanly, no parse errors.

- [ ] **Step 3: Commit**

```
git add scripts/ui/options_overlay.gd
git commit -m "feat: replace options overlay with 2-column HD layout (audio+display / controls)"
```

---

## Self-Review

**Spec coverage:**
- ✅ Slim 3-button pause overlay (Main Menu, Options, Back)
- ✅ No Quit button
- ✅ Mid-level warning on Main Menu (uses `UiTheme.make_modal`)
- ✅ Options screen is 2-column (audio+display left, controls right)
- ✅ `static func open(parent)` API preserved — all 4 callers unaffected
- ✅ ESC closes options screen
- ✅ Back button in options = queue_free()
- ✅ All Settings.* calls (master_volume, music_volume, shake_scale, fullscreen, font_style) present
- ✅ All 6 rebind actions included

**Placeholder scan:** No TBD, no "similar to above", all code is complete.

**Type consistency:** `_add_slider_row` returns `HSlider` and is stored in `HSlider` vars. `_add_rebind_row` takes `VBoxContainer` (not generic `Node`) matching the `left`/`right` column type. `UiTheme.make_modal` returns `{layer, dim, panel, vbox}` — Task 1 uses `m.layer`, `m.vbox` matching the dict keys defined in `ui_theme.gd:243`.

**Note on `_rebuild_ui` in options:** The font swap rebuild in options_overlay now calls `_rebuild_ui()` which clears all children including the outer CanvasLayer children (dim + center). This matches the existing behavior. ✅
