extends Control

# UI Designer — dev tuner for HUD widget placement on the 480×270
# Starblaster viewport. Roman wants live control over the magic numbers
# currently baked into scripts/ui.gd::_ready and
# scripts/main.gd::_install_playfield_frame, plus a way to export the
# final values back into source.
#
# Layout follows scripts/dev/parallax_tuner.gd: left-side knob rail in a
# styled PanelContainer + ScrollContainer, live preview behind it,
# Esc to close, single-instance behaviour.
#
# Preview strategy: rather than mount main.tscn wholesale (which would
# spin up the wave director / player / enemies and fight us for input),
# we instance a galaxy_backdrop for atmosphere, recreate the playfield
# glass + outline panels exactly like main.gd::_install_playfield_frame,
# and mount scenes/ui.tscn under a CanvasLayer so the real HUD widgets
# render against the real backdrop. The HUD is bound to a lightweight
# MockPlayer object that emits hull_changed/shield_changed/ammo_changed
# so the bars carry meaningful values.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const BACKDROP_SCRIPT = preload("res://scripts/galaxy_backdrop.gd")
# Playfield is globally registered via `class_name Playfield` — no preload needed.
const UI_SCENE := preload("res://scenes/ui.tscn")

const CONFIG_PATH := "user://tuners/ui_designer.json"

# --- Knob registry --------------------------------------------------------
# Each row: key, label, kind ("int" | "float" | "color"), min, max, step,
# default. The order here drives the rail UI AND the snippet output.

const KNOBS := [
	# Playfield bounds — the 216×270 band the gameplay is constrained to.
	{"key": "playfield_x_min",        "label": "Playfield X",           "kind": "int",   "min": 0,   "max": 240, "step": 1,  "default": 132},
	{"key": "playfield_width",        "label": "Playfield W",           "kind": "int",   "min": 60,  "max": 480, "step": 1,  "default": 216},
	{"key": "playfield_y_min",        "label": "Playfield Y",           "kind": "int",   "min": 0,   "max": 200, "step": 1,  "default": 0},
	{"key": "playfield_height",       "label": "Playfield H",           "kind": "int",   "min": 60,  "max": 270, "step": 1,  "default": 270},
	# HUD widget placement.
	{"key": "hud_top_margin",         "label": "HUD top margin",        "kind": "int",   "min": 0,   "max": 40,  "step": 1,  "default": 6},
	{"key": "hull_bar_left_spacer",   "label": "Hull spacer (L)",       "kind": "int",   "min": 0,   "max": 320, "step": 1,  "default": 186},
	{"key": "hull_bar_width",         "label": "Hull bar W",            "kind": "int",   "min": 20,  "max": 200, "step": 1,  "default": 80},
	{"key": "hull_bar_height",        "label": "Hull bar H",            "kind": "int",   "min": 4,   "max": 32,  "step": 1,  "default": 12},
	{"key": "bounty_min_width",       "label": "Bounty min W",          "kind": "int",   "min": 20,  "max": 200, "step": 1,  "default": 80},
	{"key": "boxcontainer_min_width", "label": "BoxContainer W",        "kind": "int",   "min": 100, "max": 480, "step": 1,  "default": 452},
	{"key": "bounty_font_size",       "label": "Bounty font",           "kind": "int",   "min": 6,   "max": 24,  "step": 1,  "default": 10},
	{"key": "ammo_font_size",         "label": "Ammo font",             "kind": "int",   "min": 6,   "max": 24,  "step": 1,  "default": 10},
	{"key": "hull_warning_font_size", "label": "Warning font",          "kind": "int",   "min": 6,   "max": 24,  "step": 1,  "default": 11},
	{"key": "glass_bg_color",         "label": "Glass BG",              "kind": "color", "default": [0.04, 0.06, 0.10, 0.55]},
	{"key": "frame_border_color",     "label": "Frame border",          "kind": "color", "default": [0.32, 0.50, 0.72, 1.0]},
]

# Layer Z constants are documented but not exposed as knobs (Roman's note
# in the task brief: "leave fixed"). Snippet output mentions them as
# comments so they're still discoverable.
const GLASS_LAYER_Z := 1
const OUTLINE_LAYER_Z := 10

# --- State ----------------------------------------------------------------

var _backdrop: Node2D = null
var _glass_layer: CanvasLayer = null
var _frame_layer: CanvasLayer = null
var _hud_layer: CanvasLayer = null
var _hud_root = null  # MarginContainer (ui.tscn root)
var _mock_player: Node = null

var _values: Dictionary = {}
var _editors: Dictionary = {}  # key -> control(s) per knob
var _readouts: Dictionary = {} # key -> Label

var _status_label: Label = null
var _live_preview_failed: bool = false
var _fallback_label: Label = null


# --- Mock player ---------------------------------------------------------
# Minimal stand-in so ui.tscn::bind_player has something to talk to. The
# HUD reads max_hull/hull/max_shield/shield/ammo/weapon_style + emits
# hull_changed/shield_changed/ammo_changed.

class MockPlayer extends Node:
	signal hull_changed(max_value, value)
	signal shield_changed(max_value, value)
	signal ammo_changed(value)

	var max_hull: int = 50
	var hull: int = 18  # 36% — well below the 50% threshold so HULL COMPROMISED is visible
	var max_shield: int = 3
	var shield: int = 2
	var ammo: int = 24
	var weapon_style: String = "machinegun"


# --- Lifecycle ------------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seed_defaults()
	_load_from_disk()
	_install_backdrop()
	if not _install_live_preview():
		_live_preview_failed = true
		_install_fallback_preview()
	_build_ui()
	_apply_all()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")


func _seed_defaults() -> void:
	for k in KNOBS:
		var dflt = k["default"]
		if k["kind"] == "color":
			_values[k["key"]] = Color(float(dflt[0]), float(dflt[1]), float(dflt[2]), float(dflt[3]))
		else:
			_values[k["key"]] = dflt


func _install_backdrop() -> void:
	_backdrop = Node2D.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_script(BACKDROP_SCRIPT)
	_backdrop.set("drift_speed", 10.0)
	_backdrop.set("starfield_density", 30.0)
	_backdrop.set("starfield_scroll", 5.0)
	_backdrop.set("warp_streak_count", 6)
	_backdrop.set("warp_streak_speed", 280.0)
	add_child(_backdrop)
	move_child(_backdrop, 0)

	# Glass gutters + frame outline. Mirrors main.gd::_install_playfield_frame
	# 1:1 — those panels are what we're tuning. Refreshed on every
	# color knob change via _refresh_frame().
	_glass_layer = CanvasLayer.new()
	_glass_layer.name = "PlayfieldGlass"
	_glass_layer.layer = GLASS_LAYER_Z
	add_child(_glass_layer)

	_frame_layer = CanvasLayer.new()
	_frame_layer.name = "PlayfieldFrame"
	_frame_layer.layer = OUTLINE_LAYER_Z
	add_child(_frame_layer)

	_refresh_frame()


func _install_live_preview() -> bool:
	# Mount ui.tscn under a CanvasLayer between glass and outline (the
	# HUD lives on layer 5 in production). Bind to a MockPlayer so the
	# bars / bounty / ammo carry sensible values. Returns true on
	# success, false if anything blows up — caller then falls back to
	# the hardcoded mock.
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "HUD"
	_hud_layer.layer = 5
	add_child(_hud_layer)

	var inst = UI_SCENE.instantiate()
	if inst == null:
		return false
	_hud_layer.add_child(inst)
	_hud_root = inst

	_mock_player = MockPlayer.new()
	add_child(_mock_player)
	# bind_player wires hull/shield/ammo signals + seeds initial values.
	if _hud_root.has_method("bind_player"):
		_hud_root.bind_player(_mock_player)
	# Re-emit so the seeded values flow through any late connections.
	_mock_player.emit_signal("hull_changed", _mock_player.max_hull, _mock_player.hull)
	_mock_player.emit_signal("shield_changed", _mock_player.max_shield, _mock_player.shield)
	_mock_player.emit_signal("ammo_changed", _mock_player.ammo)
	return true


func _install_fallback_preview() -> void:
	# Live HUD couldn't mount — drop a placard so it's obvious the
	# preview is degraded. Knobs still tweak _values + the snippet
	# output remains useful.
	_fallback_label = Label.new()
	_fallback_label.text = "[live HUD unavailable — knobs still drive snippet output]"
	_fallback_label.position = Vector2(140, 120)
	UiTheme.style_label(_fallback_label, UiTheme.LabelKind.CAPTION)
	_fallback_label.add_theme_color_override("font_color", Color(1, 0.7, 0.3))
	add_child(_fallback_label)


# --- UI rail --------------------------------------------------------------

func _build_ui() -> void:
	# Tuner rail sits on its own CanvasLayer ABOVE the glass + outline so
	# the controls always read on top of whatever HUD layout is being
	# previewed. Without this, glass (layer 1) and outline (layer 10)
	# overlay the tuner controls in the gutters / playfield edges.
	var rail_layer := CanvasLayer.new()
	rail_layer.name = "TunerRail"
	rail_layer.layer = 20
	add_child(rail_layer)

	var header := Label.new()
	header.text = "UI DESIGNER — Esc to close"
	header.position = Vector2(6, 4)
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	header.add_theme_font_size_override("font_size", 9)
	rail_layer.add_child(header)

	var rail_bg := PanelContainer.new()
	# Push the rail down past the top HUD strip so HULL COMPROMISED + the
	# hull bar are visible above it; left flush so the right gutter +
	# bounty / ammo also read.
	rail_bg.position = Vector2(6, 38)
	rail_bg.size = Vector2(158, 224)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.86)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	rail_bg.add_theme_stylebox_override("panel", sb)
	rail_layer.add_child(rail_bg)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail_bg.add_child(scroll)

	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 1)
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rail)

	for k in KNOBS:
		_add_knob_row(rail, k)

	rail.add_child(HSeparator.new())

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(130, 0)
	UiTheme.style_label(_status_label, UiTheme.LabelKind.CAPTION)
	_status_label.add_theme_font_size_override("font_size", 8)
	rail.add_child(_status_label)

	# Buttons row — Save / Load / Reset / Copy.
	_add_button(rail, "Save",                _on_save)
	_add_button(rail, "Load",                _on_load)
	_add_button(rail, "Reset Defaults",      _on_reset)
	_add_button(rail, "Copy GDScript",       _on_copy_snippet)
	rail.add_child(HSeparator.new())
	_add_button(rail, "Back to Dev Menu",    _on_back)


func _add_button(parent: Node, label: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 12)
	btn.add_theme_font_size_override("font_size", 8)
	UiTheme.style_button(btn, true)
	btn.pressed.connect(cb)
	parent.add_child(btn)


func _add_knob_row(parent: Node, k: Dictionary) -> void:
	var key: String = String(k["key"])
	var kind: String = String(k["kind"])

	# One-line row: [label][control(s)] so each knob takes ~10 px tall.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = String(k["label"])
	UiTheme.style_label(lbl, UiTheme.LabelKind.CAPTION)
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.custom_minimum_size = Vector2(58, 0)
	row.add_child(lbl)

	if kind == "color":
		var picker := ColorPickerButton.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.custom_minimum_size = Vector2(0, 10)
		picker.add_theme_font_size_override("font_size", 8)
		picker.color = _values[key]
		picker.edit_alpha = true
		picker.color_changed.connect(func(c: Color):
			_values[key] = c
			_apply_all()
		)
		row.add_child(picker)
		_editors[key] = picker
		return

	var slider := HSlider.new()
	slider.min_value = float(k["min"])
	slider.max_value = float(k["max"])
	slider.step = float(k["step"])
	slider.value = float(_values[key])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 8)
	# Shrink the grabber so the slider can actually compress vertically.
	slider.add_theme_constant_override("grabber_offset", 0)
	row.add_child(slider)

	var spin := SpinBox.new()
	spin.min_value = float(k["min"])
	spin.max_value = float(k["max"])
	spin.step = float(k["step"])
	spin.value = float(_values[key])
	spin.custom_minimum_size = Vector2(34, 10)
	spin.add_theme_font_size_override("font_size", 8)
	row.add_child(spin)

	var setter := func(v: float):
		var nv = int(v) if kind == "int" else v
		if _values.get(key) == nv:
			return
		_values[key] = nv
		# Sync the sibling input without re-firing.
		if slider.value != float(nv):
			slider.set_value_no_signal(float(nv))
		if spin.value != float(nv):
			spin.set_value_no_signal(float(nv))
		_apply_all()
	slider.value_changed.connect(setter)
	spin.value_changed.connect(setter)

	_editors[key] = slider


# --- Apply knobs to live preview -----------------------------------------

func _apply_all() -> void:
	_apply_to_hud()
	_refresh_frame()


func _apply_to_hud() -> void:
	if _hud_root == null or not is_instance_valid(_hud_root):
		return
	# Top margin on the UI MarginContainer.
	_hud_root.add_theme_constant_override("margin_top", int(_values["hud_top_margin"]))

	var spacer_left = _find_descendant(_hud_root, "SpacerLeft")
	if spacer_left:
		spacer_left.custom_minimum_size = Vector2(int(_values["hull_bar_left_spacer"]), 0)

	var hull_sprite = _find_descendant(_hud_root, "HullBarSprite")
	if hull_sprite:
		hull_sprite.custom_minimum_size = Vector2(int(_values["hull_bar_width"]), int(_values["hull_bar_height"]))

	# BoxContainer is a direct child of the UI root.
	var box = _hud_root.get_node_or_null("BoxContainer")
	if box:
		box.custom_minimum_size = Vector2(int(_values["boxcontainer_min_width"]), 0)

	var bounty = _find_descendant(_hud_root, "BountyLabel")
	if bounty:
		bounty.custom_minimum_size = Vector2(int(_values["bounty_min_width"]), 0)
		bounty.add_theme_font_size_override("font_size", int(_values["bounty_font_size"]))

	var ammo = _find_descendant(_hud_root, "AmmoLabel")
	if ammo:
		ammo.add_theme_font_size_override("font_size", int(_values["ammo_font_size"]))

	var warn = _find_descendant(_hud_root, "HullWarning")
	if warn:
		warn.add_theme_font_size_override("font_size", int(_values["hull_warning_font_size"]))


func _refresh_frame() -> void:
	if _glass_layer == null or not is_instance_valid(_glass_layer):
		return
	# Playfield bounds come from the knobs, not the const Playfield class —
	# so dragging the playspace sliders moves the live preview.
	var px: float = float(_values["playfield_x_min"])
	var pw: float = float(_values["playfield_width"])
	var py: float = float(_values["playfield_y_min"])
	var ph: float = float(_values["playfield_height"])
	var x_max: float = px + pw
	# Wipe + rebuild glass panels with the current color.
	for c in _glass_layer.get_children():
		c.queue_free()
	var glass_bg: Color = _values["glass_bg_color"]
	var glass_edge: Color = _values["frame_border_color"]
	for spec in [
		{"name": "GutterLeft",  "x": 0.0,   "w": px,            "edge": "right"},
		{"name": "GutterRight", "x": x_max, "w": 480.0 - x_max, "edge": "left"},
	]:
		var panel := Panel.new()
		panel.name = String(spec["name"])
		panel.position = Vector2(float(spec["x"]), 0.0)
		panel.size = Vector2(float(spec["w"]), 270.0)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gsb := StyleBoxFlat.new()
		gsb.bg_color = glass_bg
		gsb.border_color = glass_edge
		if String(spec["edge"]) == "right":
			gsb.border_width_right = 1
		else:
			gsb.border_width_left = 1
		panel.add_theme_stylebox_override("panel", gsb)
		_glass_layer.add_child(panel)

	# Rebuild frame outline.
	for c in _frame_layer.get_children():
		c.queue_free()
	var frame := Panel.new()
	frame.name = "Frame"
	frame.position = Vector2(px, py)
	frame.size = Vector2(pw, ph)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = glass_edge
	# Left + right edges only — Roman doesn't want a top/bottom cap on
	# the playfield outline (the band reads as an open vertical column).
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 0
	sb.border_width_bottom = 0
	frame.add_theme_stylebox_override("panel", sb)
	_frame_layer.add_child(frame)


func _find_descendant(root: Node, node_name: String) -> Node:
	if root == null:
		return null
	if String(root.name) == node_name:
		return root
	for c in root.get_children():
		var hit = _find_descendant(c, node_name)
		if hit:
			return hit
	return null


# --- Persistence ---------------------------------------------------------

func _save_to_disk() -> bool:
	var dir := DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("tuners"):
			dir.make_dir("tuners")
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		return false
	var out := {}
	for k in _values.keys():
		var v = _values[k]
		if v is Color:
			out[k] = [v.r, v.g, v.b, v.a]
		else:
			out[k] = v
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	return true


func _load_from_disk() -> bool:
	if not FileAccess.file_exists(CONFIG_PATH):
		return false
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return false
	# Merge into defaults — don't replace, so a missing key keeps its
	# default rather than going null.
	for k in KNOBS:
		var key: String = String(k["key"])
		if not parsed.has(key):
			continue
		if k["kind"] == "color":
			var arr = parsed[key]
			if arr is Array and arr.size() >= 4:
				_values[key] = Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
		elif k["kind"] == "int":
			_values[key] = int(parsed[key])
		else:
			_values[key] = float(parsed[key])
	return true


func _sync_editors_from_values() -> void:
	for k in KNOBS:
		var key: String = String(k["key"])
		var ed = _editors.get(key)
		if ed == null:
			continue
		if k["kind"] == "color":
			(ed as ColorPickerButton).color = _values[key]
		else:
			(ed as HSlider).set_value_no_signal(float(_values[key]))
			# Sibling spinbox lives in the same HBoxContainer.
			var parent_row = (ed as Control).get_parent()
			if parent_row:
				for c in parent_row.get_children():
					if c is SpinBox:
						(c as SpinBox).set_value_no_signal(float(_values[key]))


# --- Snippet output ------------------------------------------------------

func _build_snippet() -> String:
	var lines: PackedStringArray = []
	lines.append("# UI Designer export — paste into scripts/playfield.gd,")
	lines.append("# scripts/ui.gd::_ready, and scripts/main.gd::_install_playfield_frame.")
	lines.append("")
	lines.append("# --- scripts/playfield.gd ---")
	var px: int = int(_values["playfield_x_min"])
	var pw: int = int(_values["playfield_width"])
	var py: int = int(_values["playfield_y_min"])
	var ph: int = int(_values["playfield_height"])
	lines.append("const W: float = %d.0" % pw)
	lines.append("const H: float = %d.0" % ph)
	lines.append("const X_MIN: float = %d.0" % px)
	lines.append("const X_MAX: float = %d.0  # X_MIN + W" % (px + pw))
	lines.append("const Y_MIN: float = %d.0" % py)
	lines.append("const Y_MAX: float = %d.0" % (py + ph))
	lines.append("const CENTER := Vector2(%.1f, %.1f)" % [float(px) + float(pw) * 0.5, float(py) + float(ph) * 0.5])
	lines.append("")
	lines.append("# --- scripts/ui.gd::_ready ---")
	lines.append("add_theme_constant_override(\"margin_top\", %d)" % int(_values["hud_top_margin"]))
	lines.append("# SpacerLeft inside HullShieldRow:")
	lines.append("spacer_left.custom_minimum_size = Vector2(%d, 0)" % int(_values["hull_bar_left_spacer"]))
	lines.append("# HullBarSprite (TextureProgressBar):")
	lines.append("hull_tpb.custom_minimum_size = Vector2(%d, %d)" % [int(_values["hull_bar_width"]), int(_values["hull_bar_height"])])
	lines.append("# Bounty label:")
	lines.append("bounty_label.custom_minimum_size = Vector2(%d, 0)" % int(_values["bounty_min_width"]))
	lines.append("bounty_label.add_theme_font_size_override(\"font_size\", %d)" % int(_values["bounty_font_size"]))
	lines.append("# BoxContainer:")
	lines.append("$BoxContainer.custom_minimum_size = Vector2(%d, 0)" % int(_values["boxcontainer_min_width"]))
	lines.append("# Ammo label:")
	lines.append("ammo_label.add_theme_font_size_override(\"font_size\", %d)" % int(_values["ammo_font_size"]))
	lines.append("# Hull warning label:")
	lines.append("hull_warning.add_theme_font_size_override(\"font_size\", %d)" % int(_values["hull_warning_font_size"]))
	lines.append("")
	lines.append("# --- scripts/main.gd::_install_playfield_frame ---")
	var gbg: Color = _values["glass_bg_color"]
	var fbc: Color = _values["frame_border_color"]
	lines.append("var glass_bg := Color(%.3f, %.3f, %.3f, %.3f)" % [gbg.r, gbg.g, gbg.b, gbg.a])
	lines.append("var glass_edge := Color(%.3f, %.3f, %.3f, %.3f)" % [fbc.r, fbc.g, fbc.b, fbc.a])
	lines.append("# Layer Z values (fixed): glass=%d, outline=%d" % [GLASS_LAYER_Z, OUTLINE_LAYER_Z])
	return "\n".join(lines)


# --- Buttons -------------------------------------------------------------

func _on_save() -> void:
	if _save_to_disk():
		_set_status("Saved to %s" % CONFIG_PATH)
	else:
		_set_status("Save FAILED")


func _on_load() -> void:
	if _load_from_disk():
		_sync_editors_from_values()
		_apply_all()
		_set_status("Loaded from %s" % CONFIG_PATH)
	else:
		_set_status("No saved config (or load failed)")


func _on_reset() -> void:
	_seed_defaults()
	_sync_editors_from_values()
	_apply_all()
	_set_status("Reset to defaults")


func _on_copy_snippet() -> void:
	var s := _build_snippet()
	DisplayServer.clipboard_set(s)
	_set_status("Snippet copied to clipboard (%d chars)" % s.length())


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
