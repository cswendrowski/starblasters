extends Control

# Parallax Tuner — dev menu for inspecting and tweaking the procedural
# parallax stack (galaxy_backdrop). Layer-focused UI per Roman, 2026-05-17:
# pick the layer you want to tweak, see its brightness / contrast / speed
# on dedicated sliders. No global master controls.
#
# How each knob maps to the live backdrop:
#   Brightness — modulate.rgb scale around the layer's recorded base color.
#                A starfield's "modulate = (1.1, 1.1, 1.1, 1)" is preserved
#                as the base; the slider scales it.
#   Contrast   — pivots the effective modulate around 0.5 ((rgb - 0.5)*c
#                + 0.5). Approximation — true per-pixel contrast would
#                need a per-layer shader pass — but it's the right feel
#                for layers driven by additive shaders / dominant
#                modulate alpha. At 1.0 it's a no-op.
#   Speed      — overrides the `drift_mult` meta on the layer node. The
#                backdrop's _process loop reads that meta every frame, so
#                changes take effect immediately on the next tick.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const BACKDROP_V1 = preload("res://scripts/galaxy_backdrop.gd")
const BACKDROP_V2 = preload("res://scripts/parallax/galaxy_backdrop_v2.gd")

const CONFIG_PATH := "user://tuners/parallax.json"

const PLANET_NAMES := [
	"LavaWorld", "IceWorld", "DryTerran", "GasPlanet",
	"NoAtmosphere", "LandMasses", "BlackHole", "Galaxy", "Star",
]

var _backdrop: Node2D = null
var _info_label: Label = null
var _seed_label: Label = null
var _seed_value: int = 0
var _layer_picker: OptionButton = null
var _brightness_slider: HSlider = null
var _contrast_slider: HSlider = null
var _speed_slider: HSlider = null
# V2-only: RGBA sliders driving the selected layer's silhouette shader
# uniform. No-op when a V1 layer is selected (V1 doesn't have a
# silhouette pass).
var _silhouette_r_slider: HSlider = null
var _silhouette_g_slider: HSlider = null
var _silhouette_b_slider: HSlider = null
var _silhouette_a_slider: HSlider = null
var _selected_layer: CanvasItem = null
# Per-layer base modulate (captured at scan time so brightness/contrast
# computations don't accumulate). Keyed by node instance ID.
var _layer_base_modulate: Dictionary = {}
# Per-layer base drift_mult (used to display a "stock" value alongside the
# slider when the player has overridden it).
var _layer_base_drift: Dictionary = {}
# Per-layer cached brightness + contrast values so swapping selection
# remembers what the slider was set to.
var _layer_brightness: Dictionary = {}
var _layer_contrast: Dictionary = {}
var _use_v2: bool = false
var _version_label: Label = null
var _status_label: Label = null
# Per-layer silhouette RGBA cache so Copy GDScript can emit it even
# after the slider was last touched on a different layer.
var _layer_silhouette: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seed_value = randi()
	_rebuild_backdrop()
	_build_ui()
	# Wait a frame so the backdrop._ready spawns its children before we
	# enumerate them for the picker.
	await get_tree().process_frame
	_refresh_layer_picker()
	_capture_info()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")


# Spawn a fresh galaxy_backdrop instance using _seed_value. Roman wants
# "generate a random new background" as a discrete action — the seed
# changes only when Randomize is pressed.
func _rebuild_backdrop() -> void:
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	_backdrop = Node2D.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_script(BACKDROP_V2 if _use_v2 else BACKDROP_V1)
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.run_seed = _seed_value
		run.visited_nodes.clear()
		run.current_stellar = {}
		run.current_hazard_subtype = ""
	add_child(_backdrop)
	move_child(_backdrop, 0)


func _build_ui() -> void:
	var header := Label.new()
	header.text = "PARALLAX TUNER"
	header.position = Vector2(8, 4)
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	add_child(header)

	var back_btn := Button.new()
	back_btn.text = "Back to Dev Menu"
	back_btn.position = Vector2(8, 380)
	back_btn.size = Vector2(80, 14)
	UiTheme.style_button(back_btn, true)
	back_btn.pressed.connect(_on_back)
	add_child(back_btn)

	var rail_bg := PanelContainer.new()
	rail_bg.position = Vector2(216, 24)
	rail_bg.size = Vector2(100, 350)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.84)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	rail_bg.add_theme_stylebox_override("panel", sb)
	add_child(rail_bg)

	# ScrollContainer so the rail's per-layer + silhouette sliders stay
	# reachable when the content grows taller than the panel (Roman,
	# 2026-05-17: "most of them are off screen and unusable").
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail_bg.add_child(scroll)

	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 10)
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rail)

	# V1/V2 toggle for A/B comparison (Roman, 2026-05-17). V1 = the hand-
	# rolled drift loop; V2 = partial migration using Godot's Parallax2D
	# for asteroid bands + planet drift.
	var version_row := HBoxContainer.new()
	rail.add_child(version_row)
	_version_label = Label.new()
	_version_label.text = "Parallax: V1"
	_version_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(_version_label, UiTheme.LabelKind.BODY)
	version_row.add_child(_version_label)
	var swap_btn := Button.new()
	swap_btn.text = "Swap V1/V2"
	UiTheme.style_button(swap_btn, true)
	swap_btn.pressed.connect(_on_swap_version)
	version_row.add_child(swap_btn)

	_seed_label = Label.new()
	_seed_label.text = "seed: %d" % _seed_value
	UiTheme.style_label(_seed_label, UiTheme.LabelKind.CAPTION)
	rail.add_child(_seed_label)

	var rnd_btn := Button.new()
	rnd_btn.text = "Generate New Background"
	rnd_btn.custom_minimum_size = Vector2(0, 16)
	UiTheme.style_button(rnd_btn, true)
	rnd_btn.pressed.connect(_on_randomize)
	rail.add_child(rnd_btn)

	rail.add_child(HSeparator.new())

	var info_header := Label.new()
	info_header.text = "Current Config"
	UiTheme.style_label(info_header, UiTheme.LabelKind.CAPTION)
	rail.add_child(info_header)

	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size = Vector2(94, 0)
	UiTheme.style_label(_info_label, UiTheme.LabelKind.BODY)
	rail.add_child(_info_label)

	rail.add_child(HSeparator.new())

	var pick_lbl := Label.new()
	pick_lbl.text = "Layer"
	UiTheme.style_label(pick_lbl, UiTheme.LabelKind.CAPTION)
	rail.add_child(pick_lbl)

	_layer_picker = OptionButton.new()
	_layer_picker.custom_minimum_size = Vector2(0, 14)
	_layer_picker.item_selected.connect(_on_layer_picked)
	rail.add_child(_layer_picker)

	# Three per-layer sliders. They drive whatever layer is currently
	# selected; the cache (_layer_brightness / _layer_contrast / drift_mult
	# meta) preserves the value across selection swaps.
	_brightness_slider = _add_slider_row(rail, "Brightness", 0.0, 2.5, 1.0, _on_brightness_changed)
	_contrast_slider = _add_slider_row(rail, "Contrast", 0.2, 2.5, 1.0, _on_contrast_changed)
	_speed_slider = _add_slider_row(rail, "Speed", 0.0, 3.0, 1.0, _on_speed_changed)

	rail.add_child(HSeparator.new())
	var sil_header := Label.new()
	sil_header.text = "Silhouette Color (V2)"
	UiTheme.style_label(sil_header, UiTheme.LabelKind.CAPTION)
	rail.add_child(sil_header)
	_silhouette_r_slider = _add_slider_row(rail, "R", 0.0, 1.0, 0.0, _on_silhouette_changed)
	_silhouette_g_slider = _add_slider_row(rail, "G", 0.0, 1.0, 0.0, _on_silhouette_changed)
	_silhouette_b_slider = _add_slider_row(rail, "B", 0.0, 1.0, 0.0, _on_silhouette_changed)
	_silhouette_a_slider = _add_slider_row(rail, "A", 0.0, 1.0, 1.0, _on_silhouette_changed)

	rail.add_child(HSeparator.new())
	# Handoff row: persist + copy a paste-ready snippet for Claude to
	# integrate. JSON lives at user://tuners/parallax.json; clipboard gets a
	# GDScript const dict keyed by layer name.
	var save_btn := Button.new()
	save_btn.text = "Save"
	UiTheme.style_button(save_btn, true)
	save_btn.pressed.connect(_on_save)
	rail.add_child(save_btn)
	var load_btn := Button.new()
	load_btn.text = "Load"
	UiTheme.style_button(load_btn, true)
	load_btn.pressed.connect(_on_load)
	rail.add_child(load_btn)
	var copy_btn := Button.new()
	copy_btn.text = "Copy GDScript"
	UiTheme.style_button(copy_btn, true)
	copy_btn.pressed.connect(_on_copy_snippet)
	rail.add_child(copy_btn)
	_status_label = Label.new()
	_status_label.text = ""
	UiTheme.style_label(_status_label, UiTheme.LabelKind.CAPTION)
	rail.add_child(_status_label)


func _add_slider_row(parent: Node, label_text: String, min_v: float, max_v: float, initial: float, on_changed: Callable) -> HSlider:
	var lbl := Label.new()
	lbl.text = label_text
	UiTheme.style_label(lbl, UiTheme.LabelKind.BODY)
	parent.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = (max_v - min_v) / 100.0
	slider.value = initial
	slider.custom_minimum_size = Vector2(0, 10)
	slider.value_changed.connect(on_changed)
	parent.add_child(slider)
	var val_lbl := Label.new()
	val_lbl.text = "%.2f" % initial
	UiTheme.style_label(val_lbl, UiTheme.LabelKind.CAPTION)
	parent.add_child(val_lbl)
	slider.value_changed.connect(func(v: float):
		val_lbl.text = "%.2f" % v
	)
	return slider


# Walk the backdrop and populate the picker with every CanvasItem layer.
# Records each layer's stock modulate + drift_mult so per-layer sliders
# can compute relative changes without losing the layer's authored hue.
func _refresh_layer_picker() -> void:
	_layer_picker.clear()
	_layer_base_modulate.clear()
	_layer_base_drift.clear()
	_layer_brightness.clear()
	_layer_contrast.clear()
	_selected_layer = null
	if _backdrop == null or not is_instance_valid(_backdrop):
		return
	var first: CanvasItem = null
	for child in _backdrop.get_children():
		if not (child is CanvasItem):
			continue
		var id := child.get_instance_id()
		_layer_base_modulate[id] = child.modulate
		# Base drift / speed knob — for V1 layers this is the drift_mult
		# meta tag; for V2 Parallax2D layers it's scroll_scale.y. Default
		# to 1.0 if neither is set so the slider midpoint is "stock".
		var dm: float = 1.0
		if child is Parallax2D:
			dm = (child as Parallax2D).scroll_scale.y
		elif child.has_meta("drift_mult"):
			dm = float(child.get_meta("drift_mult"))
		_layer_base_drift[id] = dm
		_layer_brightness[id] = 1.0
		_layer_contrast[id] = 1.0
		_layer_picker.add_item(String(child.name))
		if first == null:
			first = child
	if first != null:
		_select_layer(first)


func _select_layer(layer: CanvasItem) -> void:
	_selected_layer = layer
	if layer == null:
		return
	# Find the picker index that matches this layer's name.
	for i in _layer_picker.item_count:
		if _layer_picker.get_item_text(i) == String(layer.name):
			_layer_picker.select(i)
			break
	# Resync the sliders to whatever was last applied to this layer.
	var id := layer.get_instance_id()
	_brightness_slider.set_value_no_signal(_layer_brightness.get(id, 1.0))
	_contrast_slider.set_value_no_signal(_layer_contrast.get(id, 1.0))
	# Resync the RGBA silhouette sliders to the selected V2 layer's
	# shader uniform. V1 layers have no silhouette material — leave the
	# sliders at their last values; they won't do anything.
	if _use_v2 and layer is Parallax2D and _backdrop and _backdrop.has_method("silhouette_material_for"):
		var sm: ShaderMaterial = _backdrop.silhouette_material_for(layer)
		if sm:
			var c: Color = sm.get_shader_parameter("silhouette_color")
			_silhouette_r_slider.set_value_no_signal(c.r)
			_silhouette_g_slider.set_value_no_signal(c.g)
			_silhouette_b_slider.set_value_no_signal(c.b)
			_silhouette_a_slider.set_value_no_signal(c.a)
	# Speed slider source depends on whether this is a V1 meta-tagged
	# layer or a V2 Parallax2D. V2 layers drive scroll_scale.y; V1 uses
	# the drift_mult meta on the layer node directly.
	var dm_now: float = _layer_base_drift.get(id, 1.0)
	if layer is Parallax2D:
		dm_now = (layer as Parallax2D).scroll_scale.y
	elif layer.has_meta("drift_mult"):
		dm_now = float(layer.get_meta("drift_mult"))
	_speed_slider.set_value_no_signal(dm_now)


func _on_layer_picked(idx: int) -> void:
	var nm := _layer_picker.get_item_text(idx)
	if _backdrop == null or not is_instance_valid(_backdrop):
		return
	for child in _backdrop.get_children():
		if child is CanvasItem and String(child.name) == nm:
			_select_layer(child)
			return


# ---- Slider handlers ------------------------------------------------------

func _on_brightness_changed(v: float) -> void:
	if _selected_layer == null or not is_instance_valid(_selected_layer):
		return
	_layer_brightness[_selected_layer.get_instance_id()] = v
	_apply_layer_modulate(_selected_layer)


func _on_contrast_changed(v: float) -> void:
	if _selected_layer == null or not is_instance_valid(_selected_layer):
		return
	_layer_contrast[_selected_layer.get_instance_id()] = v
	_apply_layer_modulate(_selected_layer)


# Compose brightness + contrast onto the layer's stock modulate.
# Brightness multiplies; contrast pivots around 0.5 so >1 spreads and
# <1 compresses the color range. Alpha is preserved.
func _apply_layer_modulate(layer: CanvasItem) -> void:
	var id := layer.get_instance_id()
	var base: Color = _layer_base_modulate.get(id, Color(1, 1, 1, 1))
	var b: float = _layer_brightness.get(id, 1.0)
	var c: float = _layer_contrast.get(id, 1.0)
	var r: float = (base.r * b - 0.5) * c + 0.5
	var g: float = (base.g * b - 0.5) * c + 0.5
	var bl: float = (base.b * b - 0.5) * c + 0.5
	layer.modulate = Color(r, g, bl, base.a)


func _on_silhouette_changed(_v: float) -> void:
	if _selected_layer == null or not is_instance_valid(_selected_layer):
		return
	if not (_selected_layer is Parallax2D):
		return
	if _backdrop == null or not _backdrop.has_method("silhouette_material_for"):
		return
	var sm: ShaderMaterial = _backdrop.silhouette_material_for(_selected_layer)
	if sm == null:
		return
	var c := Color(
		_silhouette_r_slider.value,
		_silhouette_g_slider.value,
		_silhouette_b_slider.value,
		_silhouette_a_slider.value,
	)
	sm.set_shader_parameter("silhouette_color", c)
	_layer_silhouette[_selected_layer.get_instance_id()] = c


func _on_speed_changed(v: float) -> void:
	if _selected_layer == null or not is_instance_valid(_selected_layer):
		return
	# V2 layers are Parallax2D nodes — their speed knob is the y
	# component of scroll_scale. V1 layers use the meta-tag dispatch in
	# galaxy_backdrop.gd's _process loop.
	if _selected_layer is Parallax2D:
		var par := _selected_layer as Parallax2D
		par.scroll_scale = Vector2(par.scroll_scale.x, v)
	else:
		_selected_layer.set_meta("drift_mult", v)


# ---- Buttons --------------------------------------------------------------

func _on_randomize() -> void:
	_seed_value = randi()
	if _seed_label:
		_seed_label.text = "seed: %d" % _seed_value
	_rebuild_backdrop()
	await get_tree().process_frame
	_refresh_layer_picker()
	_capture_info()


func _on_swap_version() -> void:
	_use_v2 = not _use_v2
	if _version_label:
		_version_label.text = "Parallax: %s" % ("V2" if _use_v2 else "V1")
	_rebuild_backdrop()
	await get_tree().process_frame
	_refresh_layer_picker()
	_capture_info()


func _capture_info() -> void:
	if _backdrop == null or not is_instance_valid(_backdrop):
		return
	var lines: PackedStringArray = []
	var planet_idx: int = -1
	if "_last_planet_idx" in _backdrop:
		planet_idx = int(_backdrop._last_planet_idx)
	if planet_idx >= 0 and planet_idx < PLANET_NAMES.size():
		lines.append("Planet: %s (%d)" % [PLANET_NAMES[planet_idx], planet_idx])
	else:
		lines.append("Planet: ?")
	lines.append("Layers: %d" % _backdrop.get_child_count())
	if "drift_speed" in _backdrop:
		lines.append("Drift: %.1f px/s" % float(_backdrop.drift_speed))
	if _info_label:
		_info_label.text = "\n".join(lines)


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()


# ---- Handoff: persist + emit snippet --------------------------------------

# Build a per-layer-name dict of {brightness, contrast, speed, silhouette}
# from the current sliders/caches. Used by both save and copy.
func _current_config() -> Dictionary:
	var out: Dictionary = {}
	if _backdrop == null or not is_instance_valid(_backdrop):
		return out
	for child in _backdrop.get_children():
		if not (child is CanvasItem):
			continue
		var id := child.get_instance_id()
		var entry: Dictionary = {
			"brightness": float(_layer_brightness.get(id, 1.0)),
			"contrast": float(_layer_contrast.get(id, 1.0)),
		}
		var dm: float = 1.0
		if child is Parallax2D:
			dm = (child as Parallax2D).scroll_scale.y
		elif child.has_meta("drift_mult"):
			dm = float(child.get_meta("drift_mult"))
		entry["speed"] = dm
		if _layer_silhouette.has(id):
			var c: Color = _layer_silhouette[id]
			entry["silhouette"] = [c.r, c.g, c.b, c.a]
		out[String(child.name)] = entry
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
	if _backdrop == null or not is_instance_valid(_backdrop):
		return
	for child in _backdrop.get_children():
		if not (child is CanvasItem):
			continue
		var nm := String(child.name)
		if not cfg.has(nm):
			continue
		var entry: Dictionary = cfg[nm]
		var id := child.get_instance_id()
		_layer_brightness[id] = float(entry.get("brightness", 1.0))
		_layer_contrast[id] = float(entry.get("contrast", 1.0))
		_apply_layer_modulate(child)
		var speed: float = float(entry.get("speed", 1.0))
		if child is Parallax2D:
			var p := child as Parallax2D
			p.scroll_scale = Vector2(p.scroll_scale.x, speed)
		else:
			child.set_meta("drift_mult", speed)
		if entry.has("silhouette") and child is Parallax2D \
				and _backdrop.has_method("silhouette_material_for"):
			var arr: Array = entry["silhouette"]
			if arr.size() >= 4:
				var sm: ShaderMaterial = _backdrop.silhouette_material_for(child)
				if sm:
					var c := Color(arr[0], arr[1], arr[2], arr[3])
					sm.set_shader_parameter("silhouette_color", c)
					_layer_silhouette[id] = c
	# Resync the visible sliders to whatever the currently-selected layer now holds.
	if _selected_layer:
		_select_layer(_selected_layer)


func _build_snippet() -> String:
	var cfg := _current_config()
	var lines: PackedStringArray = []
	lines.append("# Parallax tuner export — paste into galaxy_backdrop.gd or a config Resource.")
	lines.append("# Per-layer overrides keyed by node name. Drop unused entries.")
	lines.append("const PARALLAX_OVERRIDES := {")
	var names := cfg.keys()
	names.sort()
	for nm in names:
		var e: Dictionary = cfg[nm]
		var parts: PackedStringArray = []
		parts.append("\"brightness\": %.3f" % float(e.get("brightness", 1.0)))
		parts.append("\"contrast\": %.3f" % float(e.get("contrast", 1.0)))
		parts.append("\"speed\": %.3f" % float(e.get("speed", 1.0)))
		if e.has("silhouette"):
			var s: Array = e["silhouette"]
			parts.append("\"silhouette\": Color(%.3f, %.3f, %.3f, %.3f)" % [s[0], s[1], s[2], s[3]])
		lines.append("\t\"%s\": {%s}," % [nm, ", ".join(parts)])
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
		_set_status("No saved config (or load failed)")
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
