extends Control

# Parallax Tuner V4 — rewritten 2026-05-29 for the backdrop_coordinator.tscn
# (Parallax V4 only, no V1/V2/V3 cycling). Lets the designer:
#   - Generate a new coordinator instance
#   - Tune CanvasModulate color per layer (LayerStars, LayerPlanet, etc.)
#   - Save / Load / Copy GDScript export
#
# Layout mirrors scripts/dev/ui_designer.gd: full-rect Control, backdrop
# behind, translucent rail panel on the left at z=20.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const BACKDROP_COORDINATOR = preload("res://scenes/parallax/backdrop_coordinator.tscn")

const CONFIG_PATH := "user://tuners/parallax_v4.json"

const LAYER_NAMES := ["LayerStars", "LayerPlanet", "LayerStellarFar", "LayerStellarMid", "LayerStellarNear", "LayerStreaks", "LayerComposite"]

# Dev-tool viewport scale: the project ships at 480×270 for chunky-pixel
# gameplay, but this tuner needs HD real estate for the rail UI. We swap
# the window's content_scale_size to 1920×1080 for the scene's lifetime,
# then render the backdrop into a 480×270 SubViewport and upscale it with
# nearest-neighbour so the pixel-art look is preserved.
const HD_VIEWPORT := Vector2i(1920, 1080)
const BACKDROP_NATIVE := Vector2i(480, 270)
const BACKDROP_DISPLAY_SCALE := 4.0  # 1920 / 480

# ---- State ---------------------------------------------------------------

var _hd_scope: HdViewportScope = null
var _backdrop_layer: CanvasLayer = null
var _backdrop: Node2D = null

# Per-layer color cache, keyed by layer name. Persist across backdrop regens
# so the pickers recall the layer's last edited color.
var _layer_colors: Dictionary = {}

# ---- UI nodes ------------------------------------------------------------

var _status_label: Label
var _layer_rows: Array = []  # stores (layer_name, color_picker, reset_btn) tuples

# ---- Lifecycle -----------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hd_scope = HdViewportScope.attach(self, HD_VIEWPORT)
	_build_backdrop_pipeline()
	_rebuild_backdrop()
	_build_ui()
	# Defer a frame so the backdrop's _ready spawns children before we
	# enumerate them for the picker.
	await get_tree().process_frame
	_refresh_layers()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")


func _build_backdrop_pipeline() -> void:
	_backdrop_layer = CanvasLayer.new()
	_backdrop_layer.name = "BackdropLayer"
	_backdrop_layer.layer = -10  # below all UI canvas layers
	# CanvasLayer.transform scales its children without touching their
	# local transform — layers inside render at native, then the
	# CanvasLayer scales the result up.
	_backdrop_layer.transform = Transform2D.IDENTITY.scaled(Vector2(BACKDROP_DISPLAY_SCALE, BACKDROP_DISPLAY_SCALE))
	add_child(_backdrop_layer)


func _rebuild_backdrop() -> void:
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	_backdrop = BACKDROP_COORDINATOR.instantiate()
	if _backdrop_layer:
		_backdrop_layer.add_child(_backdrop)
	else:
		add_child(_backdrop)


# ---- UI build ------------------------------------------------------------

func _build_ui() -> void:
	# Rail above everything — backdrop + any glass/outline siblings.
	var rail_layer := CanvasLayer.new()
	rail_layer.name = "TunerRail"
	rail_layer.layer = 20
	add_child(rail_layer)

	# Header strip.
	var header := Label.new()
	header.text = "PARALLAX TUNER V4 — Esc closes"
	header.position = Vector2(24, 16)
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	rail_layer.add_child(header)

	# Rail panel — sized for the HD viewport (1920×1080 logical). Sits
	# along the left edge so the backdrop preview reads behind + to the right.
	var rail_bg := PanelContainer.new()
	rail_bg.position = Vector2(24, 56)
	rail_bg.size = Vector2(520, 980)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.86)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	rail_bg.add_theme_stylebox_override("panel", sb)
	rail_layer.add_child(rail_bg)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail_bg.add_child(scroll)

	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 8)
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rail)

	# ---- Top: Generate New button ----
	var gen_btn := _add_button(rail, "Generate New", _on_generate_new)
	gen_btn.custom_minimum_size = Vector2(0, 14)

	rail.add_child(HSeparator.new())

	# ---- Layer rows container ----
	# This will be filled in by _refresh_layers()
	var layers_container := VBoxContainer.new()
	layers_container.name = "LayersContainer"
	layers_container.add_theme_constant_override("separation", 8)
	layers_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail.add_child(layers_container)

	rail.add_child(HSeparator.new())

	# ---- Persistence + handoff ----
	_add_button(rail, "Save", _on_save)
	_add_button(rail, "Load", _on_load)
	_add_button(rail, "Copy GDScript", _on_copy_snippet)
	rail.add_child(HSeparator.new())
	_add_button(rail, "Back to Dev Menu", _on_back)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(440, 0)
	_style_caption(_status_label)
	rail.add_child(_status_label)


func _style_caption(lbl: Label) -> void:
	UiTheme.style_label(lbl, UiTheme.LabelKind.CAPTION)


func _add_button(parent: Node, text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 28)
	UiTheme.style_button(btn, true)
	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn


# ---- Layer enumeration + UI rows -----------------------------------------------

func _refresh_layers() -> void:
	# Find the LayersContainer and clear it
	var rail_layer = get_node_or_null("TunerRail")
	if rail_layer == null:
		return
	var layers_container = null
	for child in rail_layer.get_children():
		if child is PanelContainer:
			for panel_child in child.get_children():
				if panel_child is ScrollContainer:
					for scroll_child in panel_child.get_children():
						if scroll_child is VBoxContainer and scroll_child.name == "LayersContainer":
							layers_container = scroll_child
						break
			break

	if layers_container == null:
		return

	# Clear existing layer rows
	for child in layers_container.get_children():
		child.queue_free()
	_layer_rows.clear()

	# Build UI for each layer
	if _backdrop == null or not is_instance_valid(_backdrop):
		return

	for layer_name in LAYER_NAMES:
		var layer_node = _backdrop.get_node_or_null(layer_name)
		if layer_node == null:
			continue

		var cm: CanvasModulate = layer_node.get_node_or_null("CanvasModulate")
		if cm == null:
			continue

		# Initialize color cache with the current CanvasModulate color
		if not _layer_colors.has(layer_name):
			_layer_colors[layer_name] = cm.color

		# Create a row: label + color picker + reset button
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		layers_container.add_child(row)

		var lbl := Label.new()
		lbl.text = layer_name
		lbl.custom_minimum_size = Vector2(120, 0)
		_style_caption(lbl)
		row.add_child(lbl)

		var color_picker := ColorPickerButton.new()
		color_picker.color = _layer_colors[layer_name]
		color_picker.edit_alpha = true
		color_picker.custom_minimum_size = Vector2(80, 28)
		row.add_child(color_picker)

		var reset_btn := Button.new()
		reset_btn.text = "Reset"
		reset_btn.custom_minimum_size = Vector2(60, 28)
		UiTheme.style_button(reset_btn, true)
		row.add_child(reset_btn)

		# Make row fill horizontally
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Store the tuple and bind signals
		_layer_rows.append({
			"layer_name": layer_name,
			"layer_node": layer_node,
			"canvas_modulate": cm,
			"color_picker": color_picker,
			"reset_btn": reset_btn,
		})

		# Connect color change signal
		color_picker.color_changed.connect(func(c: Color):
			_on_layer_color_changed(layer_name, c)
		)

		# Connect reset button
		reset_btn.pressed.connect(func():
			_on_reset_layer(layer_name)
		)


func _on_layer_color_changed(layer_name: String, c: Color) -> void:
	_layer_colors[layer_name] = c
	for row in _layer_rows:
		if row["layer_name"] == layer_name:
			var cm: CanvasModulate = row["canvas_modulate"]
			if cm and is_instance_valid(cm):
				cm.color = c
			break


func _on_reset_layer(layer_name: String) -> void:
	_layer_colors[layer_name] = Color.WHITE
	for row in _layer_rows:
		if row["layer_name"] == layer_name:
			var cm: CanvasModulate = row["canvas_modulate"]
			if cm and is_instance_valid(cm):
				cm.color = Color.WHITE
			var picker: ColorPickerButton = row["color_picker"]
			if picker and is_instance_valid(picker):
				picker.color = Color.WHITE
			_set_status("Reset %s" % layer_name)
			break


# ---- Buttons ---------------------------------------------------------------

func _on_generate_new() -> void:
	_rebuild_backdrop()
	# Two-frame defer: backdrop spawns children in _ready; one process_frame
	# isn't always enough for them all to settle.
	await get_tree().process_frame
	await get_tree().process_frame
	_refresh_layers()
	_set_status("Generated new backdrop")


func _on_back() -> void:
	# Restore native scale *before* change_scene so the next scene doesn't
	# render at HD between its _ready and our _exit_tree.
	if _hd_scope != null and is_instance_valid(_hd_scope):
		_hd_scope.free()
		_hd_scope = null
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()


# ---- Persistence + snippet -----------------------------------------------

func _current_config() -> Dictionary:
	var out: Dictionary = {}
	out["_version"] = "V4"
	var layers := {}
	for layer_name in LAYER_NAMES:
		var c: Color = _layer_colors.get(layer_name, Color.WHITE)
		layers[layer_name] = {
			"color": [c.r, c.g, c.b, c.a],
		}
	out["layers"] = layers
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
	var layers: Dictionary = cfg.get("layers", {})
	for layer_name in LAYER_NAMES:
		if not layers.has(layer_name):
			continue
		var entry: Dictionary = layers[layer_name]
		var arr = entry.get("color", [1.0, 1.0, 1.0, 1.0])
		if arr is Array and arr.size() >= 4:
			var c := Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
			_layer_colors[layer_name] = c

			# Find and update the corresponding row's color picker and canvas modulate
			for row in _layer_rows:
				if row["layer_name"] == layer_name:
					var picker: ColorPickerButton = row["color_picker"]
					var cm: CanvasModulate = row["canvas_modulate"]
					if picker and is_instance_valid(picker):
						picker.color = c
					if cm and is_instance_valid(cm):
						cm.color = c
					break


func _build_snippet() -> String:
	var cfg := _current_config()
	var lines: PackedStringArray = []
	lines.append("# Parallax V4 layer tints")
	lines.append("var LAYER_TINTS := {")
	var layers: Dictionary = cfg.get("layers", {})
	var names: Array = layers.keys()
	names.sort()
	for nm in names:
		var e: Dictionary = layers[nm]
		var s: Array = e.get("color", [1.0, 1.0, 1.0, 1.0])
		lines.append("\t\"%s\": Color(%.3f, %.3f, %.3f, %.3f)," % [
			nm, float(s[0]), float(s[1]), float(s[2]), float(s[3]),
		])
	lines.append("}")
	return "\n".join(lines)


func _on_save() -> void:
	if _save_to_disk():
		_set_status("Saved to %s" % CONFIG_PATH)
	else:
		_set_status("Save FAILED")


func _on_load() -> void:
	var cfg := _load_from_disk()
	if cfg.is_empty():
		_set_status("No saved config")
		return
	_apply_config(cfg)
	_set_status("Loaded from %s" % CONFIG_PATH)


func _on_copy_snippet() -> void:
	var s := _build_snippet()
	DisplayServer.clipboard_set(s)
	_set_status("Snippet copied (%d chars)" % s.length())


func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg
