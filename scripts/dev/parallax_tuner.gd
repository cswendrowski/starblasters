extends Control

# Parallax Tuner — rebuilt 2026-05-20 for the 480×270 viewport + modern dev
# menu standards. Lets the designer:
#   - Generate a new random backdrop (re-seed)
#   - Swap V1 (galaxy_backdrop.gd) vs V2 (parallax/galaxy_backdrop_v2.gd)
#   - Pick a layer
#   - Tune Brightness, Contrast, Colorization (a tint color) per layer
#   - Save / Load / Copy GDScript export
#
# Per-layer composition (V1 and V2 alike):
#   modulate = (base.rgb * tint.rgb * brightness - 0.5) * contrast + 0.5
#   alpha    = base.a * tint.a
#
# For V2 layers, the colorization tint ALSO drives the silhouette shader's
# `silhouette_color` uniform — so a Parallax2D's whole band shifts hue
# together. V1 layers fall back to modulate-only.
#
# Layout mirrors scripts/dev/ui_designer.gd: full-rect Control, backdrop
# behind, translucent rail panel on the left at z=20.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const BACKDROP_V1 = preload("res://scripts/galaxy_backdrop.gd")
const BACKDROP_V2 = preload("res://scripts/parallax/galaxy_backdrop_v2.gd")
const BACKDROP_V3 = preload("res://scripts/parallax/galaxy_backdrop_v3.gd")
# Backdrop variant cycle — Swap button rotates V1 → V2 → V3 → V1.
const VARIANTS := ["V1", "V2", "V3"]

const CONFIG_PATH := "user://tuners/parallax.json"

const PLANET_NAMES := [
	"LavaWorld", "IceWorld", "DryTerran", "GasPlanet",
	"NoAtmosphere", "LandMasses", "BlackHole", "Galaxy", "Star",
]

# Dev-tool viewport scale: the project ships at 480×270 for chunky-pixel
# gameplay, but this tuner needs HD real estate for the rail UI. We swap
# the window's content_scale_size to 1920×1080 for the scene's lifetime,
# then render the backdrop into a 480×270 SubViewport and upscale it with
# nearest-neighbour so the pixel-art look is preserved.
const HD_VIEWPORT := Vector2i(1920, 1080)
const BACKDROP_NATIVE := Vector2i(480, 270)

# ---- State ---------------------------------------------------------------

var _hd_scope: HdViewportScope = null
var _backdrop_viewport: SubViewport = null
var _backdrop_display: TextureRect = null
var _backdrop: Node2D = null
var _variant_idx: int = 0   # index into VARIANTS — 0:V1, 1:V2, 2:V3
var _seed_value: int = 0
var _selected_layer: CanvasItem = null

# Per-layer caches keyed by instance_id. Persist across selection swaps so
# the sliders / picker recall the layer's last edited values.
var _layer_base_modulate: Dictionary = {}
var _layer_base_drift: Dictionary = {}
var _layer_brightness: Dictionary = {}
var _layer_contrast: Dictionary = {}
var _layer_color: Dictionary = {}        # Color picker tint (default white)

# ---- UI nodes ------------------------------------------------------------

var _seed_label: Label
var _version_label: Label
var _info_label: Label
var _layer_picker: OptionButton
var _brightness_slider: HSlider
var _brightness_value: Label
var _contrast_slider: HSlider
var _contrast_value: Label
var _color_picker: ColorPickerButton
var _status_label: Label
var _grabber_tex: ImageTexture = null


# ---- Lifecycle -----------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hd_scope = HdViewportScope.attach(self, HD_VIEWPORT)
	_seed_value = randi()
	_build_backdrop_pipeline()
	_rebuild_backdrop()
	_build_ui()
	# Defer a frame so the backdrop's _ready spawns children before we
	# enumerate them for the picker.
	await get_tree().process_frame
	_refresh_layer_picker()
	_refresh_info()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")


# SubViewport pipeline was dropped (Cobalt 2026-05-20) — V3 didn't
# render reliably through it. Backdrop now mounts directly under a
# CanvasLayer so the scaling transform isn't applied to the Parallax2D
# layers (whose tiled draws don't play nice with parent Node2D scale).
const BACKDROP_DISPLAY_SCALE := 4.0  # 1920 / 480
var _backdrop_layer: CanvasLayer = null


func _build_backdrop_pipeline() -> void:
	_backdrop_layer = CanvasLayer.new()
	_backdrop_layer.name = "BackdropLayer"
	_backdrop_layer.layer = -10  # below all UI canvas layers
	# CanvasLayer.transform scales its children without touching their
	# local transform — Parallax2D inside renders at native, then the
	# CanvasLayer scales the result up.
	_backdrop_layer.transform = Transform2D.IDENTITY.scaled(Vector2(BACKDROP_DISPLAY_SCALE, BACKDROP_DISPLAY_SCALE))
	add_child(_backdrop_layer)


func _rebuild_backdrop() -> void:
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	_backdrop = Node2D.new()
	_backdrop.name = "Backdrop"
	match VARIANTS[_variant_idx]:
		"V2":
			_backdrop.set_script(BACKDROP_V2)
		"V3":
			_backdrop.set_script(BACKDROP_V3)
		_:
			_backdrop.set_script(BACKDROP_V1)
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.run_seed = _seed_value
		if "visited_nodes" in run:
			run.visited_nodes.clear()
		if "current_stellar" in run:
			run.current_stellar = {}
		if "current_hazard_subtype" in run:
			run.current_hazard_subtype = ""
	if _backdrop_layer:
		_backdrop_layer.add_child(_backdrop)
	else:
		add_child(_backdrop)


# ---- UI build ------------------------------------------------------------

func _make_grabber_texture() -> ImageTexture:
	if _grabber_tex != null:
		return _grabber_tex
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for y in 14:
		for x in 14:
			var dx := float(x) - 6.5
			var dy := float(y) - 6.5
			if dx * dx + dy * dy <= 36.0:
				img.set_pixel(x, y, Color(0.85, 0.92, 1.0, 1.0))
	_grabber_tex = ImageTexture.create_from_image(img)
	return _grabber_tex


func _build_ui() -> void:
	# Rail above everything — backdrop + any glass/outline siblings.
	var rail_layer := CanvasLayer.new()
	rail_layer.name = "TunerRail"
	rail_layer.layer = 20
	add_child(rail_layer)

	# Header strip.
	var header := Label.new()
	header.text = "PARALLAX TUNER — Esc closes"
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

	# ---- Top: seed + randomize + V1/V2 toggle -----------------------------
	_seed_label = Label.new()
	_seed_label.text = "seed: %d" % _seed_value
	_style_caption(_seed_label)
	rail.add_child(_seed_label)

	# Generate + Swap are the "half-size" buttons per Cobalt — 14 px min
	# height vs the 28 used elsewhere on the rail.
	var gen_btn := _add_button(rail, "Generate New Layer", _on_randomize)
	gen_btn.custom_minimum_size = Vector2(0, 14)

	var version_row := HBoxContainer.new()
	version_row.add_theme_constant_override("separation", 8)
	rail.add_child(version_row)
	_version_label = Label.new()
	_version_label.text = "V1"
	_version_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_caption(_version_label)
	version_row.add_child(_version_label)
	var swap_btn := Button.new()
	swap_btn.text = "Cycle V1/V2/V3"
	swap_btn.custom_minimum_size = Vector2(0, 14)
	UiTheme.style_button(swap_btn, true)
	swap_btn.pressed.connect(_on_swap_version)
	version_row.add_child(swap_btn)

	rail.add_child(HSeparator.new())

	# ---- Info ----
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size = Vector2(440, 0)
	_style_caption(_info_label)
	rail.add_child(_info_label)

	rail.add_child(HSeparator.new())

	# ---- Layer picker ----
	var pick_lbl := Label.new()
	pick_lbl.text = "Layer"
	_style_caption(pick_lbl)
	rail.add_child(pick_lbl)

	_layer_picker = OptionButton.new()
	_layer_picker.custom_minimum_size = Vector2(0, 28)
	_layer_picker.item_selected.connect(_on_layer_picked)
	rail.add_child(_layer_picker)

	# ---- Per-layer sliders ----
	_brightness_slider = _add_slider(rail, "Brightness", 0.0, 2.5, 1.0, _on_brightness_changed)
	_brightness_value = rail.get_child(rail.get_child_count() - 1) as Label
	_contrast_slider = _add_slider(rail, "Contrast", 0.2, 2.5, 1.0, _on_contrast_changed)
	_contrast_value = rail.get_child(rail.get_child_count() - 1) as Label

	# ---- Colorization color picker ----
	var color_lbl := Label.new()
	color_lbl.text = "Colorization"
	_style_caption(color_lbl)
	rail.add_child(color_lbl)
	_color_picker = ColorPickerButton.new()
	_color_picker.custom_minimum_size = Vector2(0, 36)
	_color_picker.edit_alpha = true
	_color_picker.color = Color(1, 1, 1, 1)
	_color_picker.color_changed.connect(_on_color_changed)
	rail.add_child(_color_picker)

	rail.add_child(HSeparator.new())

	# ---- Persistence + handoff ----
	_add_button(rail, "Save", _on_save)
	_add_button(rail, "Load", _on_load)
	_add_button(rail, "Copy GDScript", _on_copy_snippet)
	_add_button(rail, "Reset Layer", _on_reset_layer)
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


# Adds a "label, slider, value-readout" trio to `parent`. Returns the
# slider. The value Label is the very next child after.
func _add_slider(parent: Node, label_text: String, min_v: float, max_v: float, initial: float, on_changed: Callable) -> HSlider:
	var lbl := Label.new()
	lbl.text = label_text
	_style_caption(lbl)
	parent.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = (max_v - min_v) / 100.0
	slider.value = initial
	slider.custom_minimum_size = Vector2(0, 24)
	var grab := _make_grabber_texture()
	if grab:
		slider.add_theme_icon_override("grabber", grab)
		slider.add_theme_icon_override("grabber_highlight", grab)
		slider.add_theme_icon_override("grabber_disabled", grab)
	slider.value_changed.connect(on_changed)
	parent.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.text = "%.2f" % initial
	_style_caption(val_lbl)
	parent.add_child(val_lbl)
	slider.value_changed.connect(func(v: float):
		val_lbl.text = "%.2f" % v
	)
	return slider


# ---- Layer enumeration + selection --------------------------------------

func _refresh_layer_picker() -> void:
	_layer_picker.clear()
	_layer_base_modulate.clear()
	_layer_base_drift.clear()
	_layer_brightness.clear()
	_layer_contrast.clear()
	_layer_color.clear()
	_selected_layer = null
	if _backdrop == null or not is_instance_valid(_backdrop):
		return
	var first: CanvasItem = null
	for child in _backdrop.get_children():
		if not (child is CanvasItem):
			continue
		var id := child.get_instance_id()
		# base_modulate is held at white so the Colorization picker is the
		# single source of truth for tint. (Otherwise the authored layer
		# tint would double up: base × tint × brightness × contrast.)
		_layer_base_modulate[id] = Color(1, 1, 1, 1)
		var dm: float = 1.0
		if child is Parallax2D:
			dm = (child as Parallax2D).scroll_scale.y
		elif child.has_meta("drift_mult"):
			dm = float(child.get_meta("drift_mult"))
		_layer_base_drift[id] = dm
		_layer_brightness[id] = 1.0
		_layer_contrast[id] = 1.0
		# Seed the Colorization picker. V3 exposes a tint shader uniform
		# per content layer (planet's dominant color is the default);
		# fall back to layer.modulate for V1/V2 + overlays.
		var seed_color: Color = child.modulate
		if child is Parallax2D and _backdrop and _backdrop.has_method("tint_material_for"):
			var mat: ShaderMaterial = _backdrop.tint_material_for(child)
			if mat != null:
				var c = mat.get_shader_parameter("tint")
				if c is Color:
					seed_color = c
		_layer_color[id] = seed_color
		_layer_picker.add_item(String(child.name))
		if first == null:
			first = child
	if first != null:
		_select_layer(first)


func _select_layer(layer: CanvasItem) -> void:
	_selected_layer = layer
	if layer == null:
		return
	for i in _layer_picker.item_count:
		if _layer_picker.get_item_text(i) == String(layer.name):
			_layer_picker.select(i)
			break
	var id := layer.get_instance_id()
	_brightness_slider.set_value_no_signal(_layer_brightness.get(id, 1.0))
	_contrast_slider.set_value_no_signal(_layer_contrast.get(id, 1.0))
	_color_picker.color = _layer_color.get(id, Color(1, 1, 1, 1))
	if _brightness_value:
		_brightness_value.text = "%.2f" % float(_layer_brightness.get(id, 1.0))
	if _contrast_value:
		_contrast_value.text = "%.2f" % float(_layer_contrast.get(id, 1.0))


func _on_layer_picked(idx: int) -> void:
	var nm := _layer_picker.get_item_text(idx)
	if _backdrop == null or not is_instance_valid(_backdrop):
		return
	for child in _backdrop.get_children():
		if child is CanvasItem and String(child.name) == nm:
			_select_layer(child)
			return


# ---- Slider / picker handlers -------------------------------------------

func _on_brightness_changed(v: float) -> void:
	if _selected_layer == null or not is_instance_valid(_selected_layer):
		return
	_layer_brightness[_selected_layer.get_instance_id()] = v
	_apply_layer_visual(_selected_layer)


func _on_contrast_changed(v: float) -> void:
	if _selected_layer == null or not is_instance_valid(_selected_layer):
		return
	_layer_contrast[_selected_layer.get_instance_id()] = v
	_apply_layer_visual(_selected_layer)


func _on_color_changed(c: Color) -> void:
	if _selected_layer == null or not is_instance_valid(_selected_layer):
		return
	_layer_color[_selected_layer.get_instance_id()] = c
	_apply_layer_visual(_selected_layer)


func _apply_layer_visual(layer: CanvasItem) -> void:
	var id := layer.get_instance_id()
	var base: Color = _layer_base_modulate.get(id, Color(1, 1, 1, 1))
	var b: float = _layer_brightness.get(id, 1.0)
	var c: float = _layer_contrast.get(id, 1.0)
	var tint: Color = _layer_color.get(id, Color(1, 1, 1, 1))
	# Compose: tint multiplies into base, then brightness scales, then
	# contrast pivots around 0.5. Alpha is base.a * tint.a so the picker
	# can also fade the layer.
	var r: float = ((base.r * tint.r) * b - 0.5) * c + 0.5
	var g: float = ((base.g * tint.g) * b - 0.5) * c + 0.5
	var bl: float = ((base.b * tint.b) * b - 0.5) * c + 0.5
	var modulate_color := Color(r, g, bl, base.a * tint.a)
	# Preferred path (V3): backdrop exposes a tint ShaderMaterial per
	# layer; the parallax_tint shader multiplies the layer's composited
	# texture by `tint`. This bypasses Parallax2D's flaky modulate
	# propagation entirely.
	if layer is Parallax2D and _backdrop and _backdrop.has_method("tint_material_for"):
		var mat: ShaderMaterial = _backdrop.tint_material_for(layer)
		if mat != null:
			mat.set_shader_parameter("tint", modulate_color)
			return
	# Fallback (V1/V2 + non-Parallax2D layers like the ColorCorrection
	# overlay) — set modulate directly; for Parallax2D layers in V1/V2
	# also push modulate to direct children to cover the propagation gap.
	if layer is Parallax2D:
		for child in layer.get_children():
			if child is CanvasItem:
				(child as CanvasItem).modulate = modulate_color
	else:
		layer.modulate = modulate_color


# ---- Buttons -------------------------------------------------------------

func _on_randomize() -> void:
	_seed_value = randi()
	if _seed_label:
		_seed_label.text = "seed: %d" % _seed_value
	_rebuild_backdrop()
	# Two-frame defer: V3 in particular spawns children across several
	# add_child calls in _ready; one process_frame isn't always enough
	# for them all to settle before the picker enumerates direct children.
	await get_tree().process_frame
	await get_tree().process_frame
	_refresh_layer_picker()
	_refresh_info()


func _on_swap_version() -> void:
	_variant_idx = (_variant_idx + 1) % VARIANTS.size()
	if _version_label:
		_version_label.text = VARIANTS[_variant_idx]
	_rebuild_backdrop()
	# Two-frame defer: V3 in particular spawns children across several
	# add_child calls in _ready; one process_frame isn't always enough
	# for them all to settle before the picker enumerates direct children.
	await get_tree().process_frame
	await get_tree().process_frame
	_refresh_layer_picker()
	_refresh_info()


func _on_reset_layer() -> void:
	if _selected_layer == null or not is_instance_valid(_selected_layer):
		return
	var id := _selected_layer.get_instance_id()
	_layer_brightness[id] = 1.0
	_layer_contrast[id] = 1.0
	_layer_color[id] = Color(1, 1, 1, 1)
	_apply_layer_visual(_selected_layer)
	_select_layer(_selected_layer)
	_set_status("Reset %s" % String(_selected_layer.name))


func _refresh_info() -> void:
	if _backdrop == null or not is_instance_valid(_backdrop):
		return
	var lines: PackedStringArray = []
	lines.append("Version: %s" % VARIANTS[_variant_idx])
	var planet_idx: int = -1
	if "_last_planet_idx" in _backdrop:
		planet_idx = int(_backdrop._last_planet_idx)
	if planet_idx >= 0 and planet_idx < PLANET_NAMES.size():
		lines.append("Celestial: %s" % PLANET_NAMES[planet_idx])
	var n_layers: int = 0
	for child in _backdrop.get_children():
		if child is CanvasItem:
			n_layers += 1
	lines.append("Layers: %d" % n_layers)
	if _info_label:
		_info_label.text = "\n".join(lines)


func _on_back() -> void:
	# Restore native scale *before* change_scene so the next scene doesn't
	# render at HD between its _ready and our _exit_tree. See
	# wave_editor._restore_hd_now for the timing rationale.
	if _hd_scope != null and is_instance_valid(_hd_scope):
		_hd_scope.free()
		_hd_scope = null
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()


# ---- Persistence + snippet ----------------------------------------------

func _current_config() -> Dictionary:
	var out: Dictionary = {}
	if _backdrop == null or not is_instance_valid(_backdrop):
		return out
	out["_version"] = VARIANTS[_variant_idx]
	out["_seed"] = _seed_value
	var layers := {}
	for child in _backdrop.get_children():
		if not (child is CanvasItem):
			continue
		var id := child.get_instance_id()
		var c: Color = _layer_color.get(id, Color(1, 1, 1, 1))
		layers[String(child.name)] = {
			"brightness": float(_layer_brightness.get(id, 1.0)),
			"contrast": float(_layer_contrast.get(id, 1.0)),
			"colorization": [c.r, c.g, c.b, c.a],
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
	if _backdrop == null or not is_instance_valid(_backdrop):
		return
	var layers: Dictionary = cfg.get("layers", {})
	for child in _backdrop.get_children():
		if not (child is CanvasItem):
			continue
		var nm := String(child.name)
		if not layers.has(nm):
			continue
		var entry: Dictionary = layers[nm]
		var id := child.get_instance_id()
		_layer_brightness[id] = float(entry.get("brightness", 1.0))
		_layer_contrast[id] = float(entry.get("contrast", 1.0))
		var arr = entry.get("colorization", [1.0, 1.0, 1.0, 1.0])
		if arr is Array and arr.size() >= 4:
			_layer_color[id] = Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
		_apply_layer_visual(child)
	if _selected_layer and is_instance_valid(_selected_layer):
		_select_layer(_selected_layer)


func _build_snippet() -> String:
	var cfg := _current_config()
	var lines: PackedStringArray = []
	lines.append("# Parallax tuner export — paste per-layer overrides into")
	lines.append("# galaxy_backdrop.gd (V1) or parallax/galaxy_backdrop_v2.gd (V2).")
	lines.append("# Active version: %s, seed: %d" % [String(cfg.get("_version", "?")), int(cfg.get("_seed", 0))])
	lines.append("const PARALLAX_OVERRIDES := {")
	var layers: Dictionary = cfg.get("layers", {})
	var names: Array = layers.keys()
	names.sort()
	for nm in names:
		var e: Dictionary = layers[nm]
		var s: Array = e.get("colorization", [1.0, 1.0, 1.0, 1.0])
		lines.append("\t\"%s\": {\"brightness\": %.3f, \"contrast\": %.3f, \"colorization\": Color(%.3f, %.3f, %.3f, %.3f)}," % [
			nm, float(e.get("brightness", 1.0)), float(e.get("contrast", 1.0)),
			float(s[0]), float(s[1]), float(s[2]), float(s[3]),
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
