extends Control

# Parallax Tuner V4 — rewritten 2026-05-29 with SubViewport rendering + brightness/contrast
# Full 1920×1080 HD viewport showing 480×270 backdrop at 4× scale in a SubViewportContainer,
# overlaid with UI panel on the right side. Layers can be individually tuned by:
#   - Color picker
#   - Brightness multiplier (0.0–2.0)
#   - Contrast curve (0.5–2.0)
# Persistence: save/load/copy-snippet for all three dicts (colors, brightness, contrast).

const SceneTransition = preload("res://scripts/scene_transition.gd")
const BackdropCoordinatorScene = preload("res://scenes/parallax/backdrop_coordinator.tscn")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

const CONFIG_PATH := "user://tuners/parallax_v4.json"

const LAYER_NAMES := ["LayerStars", "LayerPlanet", "LayerStellarFar", "LayerStellarMid", "LayerStellarNear", "LayerStreaks", "LayerComposite"]

const LAYER_SHORT_NAMES := {
	"LayerStars":       "Stars",
	"LayerPlanet":      "Planet",
	"LayerStellarFar":  "Stellar Far",
	"LayerStellarMid":  "Stellar Mid",
	"LayerStellarNear": "Stellar Near",
	"LayerStreaks":     "Streaks",
	"LayerComposite":   "Composite",
}

# ---- State ---------------------------------------------------------------

var _sub_viewport: SubViewport = null
var _backdrop: Node2D = null

# Per-layer caches, keyed by layer name
var _layer_colors: Dictionary = {}
var _layer_brightness: Dictionary = {}
var _layer_contrast: Dictionary = {}

# ---- UI nodes ------------------------------------------------------------

var _status_label: Label
var _layer_controls: Dictionary = {}  # layer_name -> {color_picker, brightness_slider, contrast_slider}
var _brightness_value_lbl: Label = null
var _contrast_value_lbl: Label = null
var _layer_buttons: Dictionary = {}  # layer_name -> Button

# ---- Lifecycle -----------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	HdViewportScope.attach(self)   # 1920×1080 so UI panel coordinates work
	_build_backdrop_subviewport()
	_build_ui()
	# Defer a frame so the backdrop's _ready spawns children before we enumerate them.
	await get_tree().process_frame
	_refresh_layers()
	if not LAYER_NAMES.is_empty():
		_on_layer_selected(LAYER_NAMES[0])
		_refresh_layer_button_selection()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")


func _build_backdrop_subviewport() -> void:
	_sub_viewport = SubViewport.new()
	_sub_viewport.size = Vector2i(480, 270)
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_viewport.transparent_bg = false

	var container := SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = 4  # 1920/4 = 480 → SubViewport renders at 480×270, upscaled 4×
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixel-art upscale
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.add_child(_sub_viewport)
	add_child(container)

	_rebuild_backdrop()


func _rebuild_backdrop() -> void:
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	_backdrop = BackdropCoordinatorScene.instantiate()
	_sub_viewport.add_child(_backdrop)


# ---- UI build (right panel at CanvasLayer 20) ----------------------------

func _build_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "TunerUI"
	ui_layer.layer = 20
	add_child(ui_layer)

	# Panel: right side 560×1080 at x=1360
	var panel := PanelContainer.new()
	panel.position = Vector2(1360, 0)
	panel.size = Vector2(560, 1080)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.88)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	ui_layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# ---- Title ----
	var title := Label.new()
	title.text = "PARALLAX TUNER V4"
	title.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_HEADER)
	title.add_theme_color_override("font_color", Color(0.82, 0.90, 1.0, 1.0))
	vbox.add_child(title)

	# ---- Layer picker ----
	var layer_label := Label.new()
	layer_label.text = "Layers"
	layer_label.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	_style_caption(layer_label)
	vbox.add_child(layer_label)

	var layer_grid := GridContainer.new()
	layer_grid.columns = 2
	layer_grid.add_theme_constant_override("h_separation", 4)
	layer_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(layer_grid)

	for layer_name in LAYER_NAMES:
		var short_name = LAYER_SHORT_NAMES.get(layer_name, layer_name)
		var btn := Button.new()
		btn.text = short_name
		btn.custom_minimum_size = Vector2(120, 28)
		btn.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BUTTON)
		btn.add_theme_color_override("font_color", Color(0.62, 0.82, 1.00, 1.0))
		btn.pressed.connect(func(): _on_layer_selected(layer_name))
		layer_grid.add_child(btn)
		_layer_buttons[layer_name] = btn

	vbox.add_child(HSeparator.new())

	# ---- Color section (will populate on layer select) ----
	var color_label := Label.new()
	color_label.text = "Color"
	color_label.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	_style_caption(color_label)
	vbox.add_child(color_label)

	var color_picker := ColorPickerButton.new()
	color_picker.name = "LayerColorPicker"
	color_picker.edit_alpha = true
	color_picker.custom_minimum_size = Vector2(0, 32)
	color_picker.color_changed.connect(func(c: Color): _on_layer_color_changed(c))
	vbox.add_child(color_picker)
	_layer_controls["color_picker"] = color_picker

	vbox.add_child(HSeparator.new())

	# ---- Brightness slider ----
	var brightness_label := Label.new()
	brightness_label.text = "Brightness"
	brightness_label.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	_style_caption(brightness_label)
	vbox.add_child(brightness_label)

	var brightness_hbox := HBoxContainer.new()
	brightness_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(brightness_hbox)

	var brightness_slider := HSlider.new()
	brightness_slider.name = "BrightnessSlider"
	brightness_slider.min_value = 0.0
	brightness_slider.max_value = 2.0
	brightness_slider.value = 1.0
	brightness_slider.step = 0.05
	brightness_slider.custom_minimum_size = Vector2(0, 24)
	brightness_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brightness_slider.value_changed.connect(func(v: float): _on_brightness_changed(v))
	brightness_hbox.add_child(brightness_slider)

	_brightness_value_lbl = Label.new()
	_brightness_value_lbl.text = "1.00"
	_brightness_value_lbl.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	_brightness_value_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	_brightness_value_lbl.custom_minimum_size = Vector2(32, 0)
	brightness_hbox.add_child(_brightness_value_lbl)

	_layer_controls["brightness_slider"] = brightness_slider

	# ---- Contrast slider ----
	var contrast_label := Label.new()
	contrast_label.text = "Contrast"
	contrast_label.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	_style_caption(contrast_label)
	vbox.add_child(contrast_label)

	var contrast_hbox := HBoxContainer.new()
	contrast_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(contrast_hbox)

	var contrast_slider := HSlider.new()
	contrast_slider.name = "ContrastSlider"
	contrast_slider.min_value = 0.5
	contrast_slider.max_value = 2.0
	contrast_slider.value = 1.0
	contrast_slider.step = 0.05
	contrast_slider.custom_minimum_size = Vector2(0, 24)
	contrast_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contrast_slider.value_changed.connect(func(v: float): _on_contrast_changed(v))
	contrast_hbox.add_child(contrast_slider)

	_contrast_value_lbl = Label.new()
	_contrast_value_lbl.text = "1.00"
	_contrast_value_lbl.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	_contrast_value_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	_contrast_value_lbl.custom_minimum_size = Vector2(32, 0)
	contrast_hbox.add_child(_contrast_value_lbl)

	_layer_controls["contrast_slider"] = contrast_slider

	vbox.add_child(HSeparator.new())

	# ---- Generate button ----
	var gen_btn = _add_button(vbox, "Generate New", _on_generate_new)

	vbox.add_child(HSeparator.new())

	# ---- Bottom buttons ----
	var save_btn = _add_button(vbox, "Save JSON", _on_save)
	var load_btn = _add_button(vbox, "Load JSON", _on_load)
	var copy_btn = _add_button(vbox, "Copy GDScript", _on_copy_snippet)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(540, 0)
	_status_label.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	_style_caption(_status_label)
	vbox.add_child(_status_label)


func _style_caption(lbl: Label) -> void:
	if lbl == null:
		return
	var font_color := Color(0.70, 0.78, 0.88, 0.70)
	lbl.add_theme_color_override("font_color", font_color)


func _add_button(parent: Node, text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 28)
	btn.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BUTTON)
	btn.add_theme_color_override("font_color", Color(0.62, 0.82, 1.00, 1.0))
	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn


# ---- Layer enumeration + selection -----------------------------------------------

var _current_layer: String = ""


func _refresh_layer_button_selection() -> void:
	for ln in _layer_buttons:
		var b: Button = _layer_buttons[ln]
		if b == null:
			continue
		if ln == _current_layer:
			b.add_theme_color_override("font_color", UiTheme.COLOR_WHITE)
			b.modulate = Color(1.0, 1.0, 1.0, 1.0)
			# selected: bright accent background via a stylebox
			var sb := StyleBoxFlat.new()
			sb.bg_color = UiTheme.COLOR_ACCENT
			sb.corner_radius_top_left = 2
			sb.corner_radius_top_right = 2
			sb.corner_radius_bottom_left = 2
			sb.corner_radius_bottom_right = 2
			b.add_theme_stylebox_override("normal", sb)
		else:
			b.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
			b.remove_theme_stylebox_override("normal")

func _refresh_layers() -> void:
	if _backdrop == null or not is_instance_valid(_backdrop):
		return

	# Initialize each layer's color, brightness, contrast from the backdrop
	for layer_name in LAYER_NAMES:
		var layer_node = _backdrop.get_node_or_null(layer_name)
		if layer_node == null:
			continue

		var cm: CanvasModulate = layer_node.get_node_or_null("CanvasModulate")
		if cm == null:
			continue

		if not _layer_colors.has(layer_name):
			_layer_colors[layer_name] = cm.color
		if not _layer_brightness.has(layer_name):
			_layer_brightness[layer_name] = 1.0
		if not _layer_contrast.has(layer_name):
			_layer_contrast[layer_name] = 1.0


func _on_layer_selected(layer_name: String) -> void:
	_current_layer = layer_name
	var color_picker: ColorPickerButton = _layer_controls.get("color_picker")
	var brightness_slider: HSlider = _layer_controls.get("brightness_slider")
	var contrast_slider: HSlider = _layer_controls.get("contrast_slider")

	if color_picker:
		color_picker.color = _layer_colors.get(layer_name, Color.WHITE)
	if brightness_slider:
		brightness_slider.value = _layer_brightness.get(layer_name, 1.0)
	if contrast_slider:
		contrast_slider.value = _layer_contrast.get(layer_name, 1.0)

	# Update value labels
	if _brightness_value_lbl:
		_brightness_value_lbl.text = "%.2f" % _layer_brightness.get(layer_name, 1.0)
	if _contrast_value_lbl:
		_contrast_value_lbl.text = "%.2f" % _layer_contrast.get(layer_name, 1.0)

	_refresh_layer_button_selection()


func _on_layer_color_changed(c: Color) -> void:
	if _current_layer.is_empty():
		return
	_layer_colors[_current_layer] = c
	_apply_grade(_current_layer)


func _on_brightness_changed(v: float) -> void:
	if _current_layer.is_empty():
		return
	_layer_brightness[_current_layer] = v
	_apply_grade(_current_layer)
	if _brightness_value_lbl:
		_brightness_value_lbl.text = "%.2f" % v


func _on_contrast_changed(v: float) -> void:
	if _current_layer.is_empty():
		return
	_layer_contrast[_current_layer] = v
	_apply_grade(_current_layer)
	if _contrast_value_lbl:
		_contrast_value_lbl.text = "%.2f" % v


func _apply_grade(layer_name: String) -> void:
	var layer := _backdrop.get_node_or_null(layer_name)
	if layer == null:
		return
	var cm := layer.get_node_or_null("CanvasModulate") as CanvasModulate
	if cm == null:
		return

	var base: Color = _layer_colors.get(layer_name, Color.WHITE)
	var b: float = _layer_brightness.get(layer_name, 1.0)
	var c: float = _layer_contrast.get(layer_name, 1.0)

	# Apply contrast: (color - 0.5) * contrast + 0.5, then multiply by brightness
	var r := clampf((base.r - 0.5) * c + 0.5, 0, 1) * b
	var g := clampf((base.g - 0.5) * c + 0.5, 0, 1) * b
	var bv := clampf((base.b - 0.5) * c + 0.5, 0, 1) * b
	cm.color = Color(r, g, bv, base.a)


# ---- Buttons ---------------------------------------------------------------

func _on_generate_new() -> void:
	_rebuild_backdrop()
	await get_tree().process_frame
	await get_tree().process_frame
	# Clear caches so the sliders re-read the freshly generated backdrop's
	# tints instead of showing stale values from the previous backdrop.
	_layer_colors.clear()
	_layer_brightness.clear()
	_layer_contrast.clear()
	_refresh_layers()
	if not _current_layer.is_empty():
		_on_layer_selected(_current_layer)
	_set_status("Generated new backdrop")


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()


# ---- Persistence + snippet -----------------------------------------------

func _current_config() -> Dictionary:
	var out: Dictionary = {}
	out["_version"] = "V4"
	var colors := {}
	var brightness := {}
	var contrast := {}
	for layer_name in LAYER_NAMES:
		var c: Color = _layer_colors.get(layer_name, Color.WHITE)
		colors[layer_name] = [c.r, c.g, c.b, c.a]
		brightness[layer_name] = _layer_brightness.get(layer_name, 1.0)
		contrast[layer_name] = _layer_contrast.get(layer_name, 1.0)
	out["colors"] = colors
	out["brightness"] = brightness
	out["contrast"] = contrast
	return out


func _save_to_disk() -> bool:
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(_current_config(), "  "))
	f.close()
	return true


func _load_from_disk() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return {}
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _apply_config(cfg: Dictionary) -> void:
	var colors: Dictionary = cfg.get("colors", {})
	var brightness: Dictionary = cfg.get("brightness", {})
	var contrast: Dictionary = cfg.get("contrast", {})

	for layer_name in LAYER_NAMES:
		if colors.has(layer_name):
			var arr = colors[layer_name]
			if arr is Array and arr.size() >= 4:
				var c := Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
				_layer_colors[layer_name] = c

		if brightness.has(layer_name):
			_layer_brightness[layer_name] = float(brightness[layer_name])

		if contrast.has(layer_name):
			_layer_contrast[layer_name] = float(contrast[layer_name])

	# Refresh UI to reflect loaded values
	if not _current_layer.is_empty():
		_on_layer_selected(_current_layer)

	# Apply grades to all layers
	for layer_name in LAYER_NAMES:
		_apply_grade(layer_name)


func _build_snippet() -> String:
	var cfg := _current_config()
	var lines: PackedStringArray = []
	lines.append("# Parallax V4 layer tuning (colors, brightness, contrast)")
	lines.append("")

	lines.append("var LAYER_COLORS := {")
	var colors: Dictionary = cfg.get("colors", {})
	var names: Array = colors.keys()
	names.sort()
	for nm in names:
		var s: Array = colors[nm]
		lines.append("\t\"%s\": Color(%.3f, %.3f, %.3f, %.3f)," % [
			nm, float(s[0]), float(s[1]), float(s[2]), float(s[3]),
		])
	lines.append("}")
	lines.append("")

	lines.append("var LAYER_BRIGHTNESS := {")
	var brightness: Dictionary = cfg.get("brightness", {})
	names = brightness.keys()
	names.sort()
	for nm in names:
		lines.append("\t\"%s\": %.3f," % [nm, float(brightness[nm])])
	lines.append("}")
	lines.append("")

	lines.append("var LAYER_CONTRAST := {")
	var contrast: Dictionary = cfg.get("contrast", {})
	names = contrast.keys()
	names.sort()
	for nm in names:
		lines.append("\t\"%s\": %.3f," % [nm, float(contrast[nm])])
	lines.append("}")

	return "\n".join(lines)


func _on_save() -> void:
	if _save_to_disk():
		_set_status("Saved to user://tuners/parallax_v4.json")
	else:
		_set_status("Save FAILED")


func _on_load() -> void:
	var cfg := _load_from_disk()
	if cfg.is_empty():
		_set_status("No saved config")
		return
	_apply_config(cfg)
	_set_status("Loaded from user://tuners/parallax_v4.json")


func _on_copy_snippet() -> void:
	var s := _build_snippet()
	DisplayServer.clipboard_set(s)
	_set_status("Snippet copied (%d chars)" % s.length())


func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg
