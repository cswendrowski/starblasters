extends Control

# Parallax Tuner V4 — rewritten 2026-05-29 for the backdrop_coordinator.tscn
# (Parallax V4 only, no V1/V2/V3 cycling). Lets the designer:
#   - Generate a new coordinator instance
#   - Tune CanvasModulate color per layer (LayerStars, LayerPlanet, etc.)
#   - Save / Load / Copy GDScript export
#
# Layout mirrors scripts/dev/ui_designer.gd: full-rect Control, backdrop
# behind, translucent rail panel on the left at z=20.

const SceneTransition = preload("res://scripts/scene_transition.gd")
const BACKDROP_COORDINATOR = preload("res://scenes/parallax/backdrop_coordinator.tscn")

const CONFIG_PATH := "user://tuners/parallax_v4.json"

const LAYER_NAMES := ["LayerStars", "LayerPlanet", "LayerStellarFar", "LayerStellarMid", "LayerStellarNear", "LayerStreaks", "LayerComposite"]

const LAYER_SHORT_NAMES := {
	"LayerStars":       "Stars",
	"LayerPlanet":      "Planet",
	"LayerStellarFar":  "Far",
	"LayerStellarMid":  "Mid",
	"LayerStellarNear": "Near",
	"LayerStreaks":     "Streaks",
	"LayerComposite":   "Grade",
}

# ---- State ---------------------------------------------------------------

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
	_rebuild_backdrop()
	_build_ui()
	# Defer a frame so the backdrop's _ready spawns children before we
	# enumerate them for the picker.
	await get_tree().process_frame
	_refresh_layers()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")


func _rebuild_backdrop() -> void:
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	_backdrop = BACKDROP_COORDINATOR.instantiate()
	add_child(_backdrop)


# ---- UI build ------------------------------------------------------------

func _build_ui() -> void:
	# Rail above everything — backdrop + any glass/outline siblings.
	var rail_layer := CanvasLayer.new()
	rail_layer.name = "TunerRail"
	rail_layer.layer = 20
	add_child(rail_layer)

	# Rail panel — left gutter at position (2, 2), size (128, 266).
	var rail_bg := PanelContainer.new()
	rail_bg.position = Vector2(2, 2)
	rail_bg.size = Vector2(128, 266)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.88)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	rail_bg.add_theme_stylebox_override("panel", sb)
	rail_layer.add_child(rail_bg)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail_bg.add_child(scroll)

	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 4)
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rail)

	# ---- Top: Title ----
	var title := Label.new()
	title.text = "TUNER V4"
	title.custom_minimum_size = Vector2(0, 16)
	title.add_theme_font_size_override("font_size", 8)
	_style_caption(title)
	rail.add_child(title)

	# ---- Generate button ----
	var gen_btn := _add_button(rail, "Generate New", _on_generate_new)
	gen_btn.custom_minimum_size = Vector2(0, 18)

	# ---- First separator ----
	rail.add_child(HSeparator.new())

	# ---- Layer rows container ----
	# This will be filled in by _refresh_layers()
	var layers_container := VBoxContainer.new()
	layers_container.name = "LayersContainer"
	layers_container.add_theme_constant_override("separation", 4)
	layers_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail.add_child(layers_container)

	# ---- Second separator ----
	rail.add_child(HSeparator.new())

	# ---- Bottom buttons ----
	_add_button(rail, "Save", _on_save).custom_minimum_size = Vector2(0, 14)
	_add_button(rail, "Load", _on_load).custom_minimum_size = Vector2(0, 14)
	_add_button(rail, "Copy GDScript", _on_copy_snippet).custom_minimum_size = Vector2(0, 14)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(120, 0)
	_style_caption(_status_label)
	rail.add_child(_status_label)


func _style_caption(lbl: Label) -> void:
	if lbl == null:
		return
	var font_color := Color(0.70, 0.78, 0.88, 0.70)  # COLOR_FAINT
	lbl.add_theme_color_override("font_color", font_color)


func _add_button(parent: Node, text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 16)
	# Light blue accent text
	btn.add_theme_color_override("font_color", Color(0.62, 0.82, 1.00, 1.0))
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
		var short_name = LAYER_SHORT_NAMES.get(layer_name, layer_name)
		var layer_node = _backdrop.get_node_or_null(layer_name)
		if layer_node == null:
			continue

		var cm: CanvasModulate = layer_node.get_node_or_null("CanvasModulate")
		if cm == null:
			continue

		# Initialize color cache with the current CanvasModulate color
		if not _layer_colors.has(layer_name):
			_layer_colors[layer_name] = cm.color

		# Create a row: short label + color picker
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		layers_container.add_child(row)

		var lbl := Label.new()
		lbl.text = short_name
		lbl.custom_minimum_size = Vector2(52, 0)
		lbl.add_theme_font_size_override("font_size", 7)
		_style_caption(lbl)
		row.add_child(lbl)

		var color_picker := ColorPickerButton.new()
		color_picker.color = _layer_colors[layer_name]
		color_picker.edit_alpha = true
		color_picker.custom_minimum_size = Vector2(60, 16)
		row.add_child(color_picker)

		# Store the tuple and bind signals
		_layer_rows.append({
			"layer_name": layer_name,
			"layer_node": layer_node,
			"canvas_modulate": cm,
			"color_picker": color_picker,
		})

		# Connect color change signal
		color_picker.color_changed.connect(func(c: Color):
			_on_layer_color_changed(layer_name, c)
		)


func _on_layer_color_changed(layer_name: String, c: Color) -> void:
	_layer_colors[layer_name] = c
	for row in _layer_rows:
		if row["layer_name"] == layer_name:
			var cm: CanvasModulate = row["canvas_modulate"]
			if cm and is_instance_valid(cm):
				cm.color = c
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
