extends Control

# Nebula Lab (Roman 2026-07-04) — see the two liked nebula styles (Neb2 / AltB) in the FULL live
# parallax stack. Renders the real backdrop_coordinator at 480x270 x4, then overlays a tunable nebula
# on any of the Far / Mid / Near stellar layers so a dense nebula reads WITH depth. Both styles scroll
# DOWNWARD with the parallax (per-layer rate). Colours randomise from a realistic-nebula palette.
# Knobs persist to user://tuners/nebula_lab.json; Copy GDScript emits a paste-ready block.

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const BackdropCoordinatorScene = preload("res://scenes/parallax/backdrop_coordinator.tscn")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const NEB2_SHADER := preload("res://graphics/nebula2.gdshader")
const ALTB_SHADER := preload("res://graphics/nebula_alt2.gdshader")

const CONFIG_PATH := "user://tuners/nebula_lab.json"

enum Style { NEB2, ALTB }
const STYLE_NAMES := ["Neb2 (filament)", "AltB (stars+clouds)"]

const LAYERS := ["Far", "Mid", "Near"]
const LAYER_NODE := {"Far": "LayerStellarFar", "Mid": "LayerStellarMid", "Near": "LayerStellarNear"}
# Parallax scroll rate per depth (far drifts slowest) + a per-depth brightness (atmospheric perspective).
const LAYER_RATE := {"Far": 0.35, "Mid": 0.65, "Near": 1.0}
const LAYER_DIM := {"Far": 0.55, "Mid": 0.78, "Near": 1.0}
# Downward scroll sign — both shaders sample uv+offset, so -y moves content DOWN. Flip if it drifts up.
const SCROLL_DIR := -1.0

# Realistic nebula hues: emission Hα reds/pinks, reflection blues, OIII teal/green, gold, violet.
const NEBULA_PALETTE := [
	Color(0.86, 0.22, 0.30),  # crimson (Halpha)
	Color(0.92, 0.48, 0.56),  # rose
	Color(0.30, 0.46, 0.86),  # reflection blue
	Color(0.22, 0.34, 0.62),  # deep blue
	Color(0.24, 0.70, 0.72),  # teal (OIII)
	Color(0.34, 0.66, 0.48),  # green
	Color(0.86, 0.66, 0.36),  # gold
	Color(0.56, 0.36, 0.76),  # violet
	Color(0.78, 0.30, 0.66),  # magenta
]

# Neb2 defaults = Roman's saved shader-lab config; AltB = shader defaults (its knobs weren't persisted).
var _neb2 := {
	"scale": 2.0, "octaves": 8.0, "density": 0.95, "edge": 0.5,
	"warp_strength": 1.2, "warp_scale": 2.25, "swirl": 0.16, "drift": 0.02,
	"opacity": 1.0, "max_alpha": 1.0,
}
var _altb := {
	"brightness": 1.0, "clouds_resolution": 3.0, "waveyness": 0.5,
	"fragmentation": 7.0, "distortion": 0.5, "blur": 1.4, "alpha": 1.0,
}
# Slider specs per style: [param, label, min, max, step]
const NEB2_KNOBS := [
	["scale", "Scale", 0.5, 6.0, 0.1], ["octaves", "Octaves", 1.0, 8.0, 1.0],
	["density", "Density", 0.0, 2.0, 0.05], ["edge", "Edge sharp", 0.0, 1.0, 0.02],
	["warp_strength", "Warp str", 0.0, 4.0, 0.05], ["warp_scale", "Warp scale", 0.2, 4.0, 0.05],
	["swirl", "Swirl", 0.0, 2.0, 0.02], ["drift", "Drift", 0.0, 0.5, 0.005],
	["opacity", "Opacity", 0.0, 1.0, 0.02], ["max_alpha", "Max alpha", 0.0, 1.0, 0.02],
]
const ALTB_KNOBS := [
	["brightness", "Brightness", 0.0, 3.0, 0.05], ["clouds_resolution", "Cloud zoom", 0.5, 10.0, 0.1],
	["waveyness", "Waveyness", 0.0, 5.0, 0.05], ["fragmentation", "Fragment", 0.0, 100.0, 1.0],
	["distortion", "Distortion", 0.0, 10.0, 0.1], ["blur", "Blur", 0.5, 5.0, 0.05],
	["alpha", "Opacity", 0.0, 1.0, 0.02],
]

var _sub_viewport: SubViewport = null
var _backdrop: Node2D = null
var _noise_tex: NoiseTexture2D = null

var _style: int = Style.NEB2
var _layer_on := {"Far": true, "Mid": true, "Near": true}
var _flight: float = 0.4
var _layer_colors := {}              # layer -> [primary, secondary]
var _nebula_rects := {}              # layer -> ColorRect
var _scroll := {"Far": 0.0, "Mid": 0.0, "Near": 0.0}

var _knob_box: VBoxContainer = null
var _status: Label = null


func _cur() -> Dictionary:
	return _neb2 if _style == Style.NEB2 else _altb


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	HdViewportScope.attach(self)
	_load()   # before _build_ui so saved style/flight/layers/knobs seed the UI
	_randomize_colors(false)
	_build_backdrop()
	_build_ui()
	# Defer so the coordinator's _ready spawns its layer children before we parent nebula into them.
	await get_tree().process_frame
	await get_tree().process_frame
	_rebuild_nebula()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")


func _process(delta: float) -> void:
	for layer in LAYERS:
		if not _layer_on[layer]:
			continue
		_scroll[layer] += delta * _flight * float(LAYER_RATE[layer])
		var rect = _nebula_rects.get(layer)
		if rect == null or not is_instance_valid(rect):
			continue
		# The stellar layers are CanvasLayers that scroll by accumulating `offset.y` (their stars get
		# re-wrapped in _on_scrolled). A full-screen nebula quad would just slide off with that offset,
		# so cancel it here — the quad stays screen-fixed and the SHADER's scroll_offset does the drift.
		var host := _layer_node(layer) as CanvasLayer
		if host != null and is_instance_valid(host):
			rect.position = Vector2(0.0, -host.offset.y)
		if rect.material:
			rect.material.set_shader_parameter("scroll_offset", Vector2(0.0, SCROLL_DIR * _scroll[layer]))


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()


# ---- Backdrop + nebula ----------------------------------------------------

func _build_backdrop() -> void:
	_sub_viewport = SubViewport.new()
	_sub_viewport.size = Vector2i(480, 270)
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_viewport.transparent_bg = false
	var container := SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = 4   # 1920/4 = 480 → renders 480x270 upscaled 4x
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.add_child(_sub_viewport)
	add_child(container)
	_backdrop = BackdropCoordinatorScene.instantiate()
	_sub_viewport.add_child(_backdrop)
	# Seamless noise for AltB clouds.
	_noise_tex = NoiseTexture2D.new()
	_noise_tex.seamless = true
	_noise_tex.width = 256
	_noise_tex.height = 256
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.015
	_noise_tex.noise = n


func _regenerate_backdrop() -> void:
	if _backdrop and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	_nebula_rects.clear()
	_backdrop = BackdropCoordinatorScene.instantiate()
	_sub_viewport.add_child(_backdrop)
	await get_tree().process_frame
	await get_tree().process_frame
	_rebuild_nebula()
	_set_status("Regenerated backdrop.")


func _layer_node(layer: String) -> Node:
	if _backdrop == null or not is_instance_valid(_backdrop):
		return null
	return _backdrop.get_node_or_null(LAYER_NODE[layer])


func _rebuild_nebula() -> void:
	for layer in _nebula_rects.keys():
		var r = _nebula_rects[layer]
		if r and is_instance_valid(r):
			r.queue_free()
	_nebula_rects.clear()
	for layer in LAYERS:
		if not _layer_on[layer]:
			continue
		var host := _layer_node(layer)
		if host == null:
			continue
		var rect := ColorRect.new()
		rect.name = "Nebula_" + layer
		rect.size = Vector2(480, 270)
		rect.color = Color(0, 0, 0, 0)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = NEB2_SHADER if _style == Style.NEB2 else ALTB_SHADER
		rect.material = mat
		host.add_child(rect)
		host.move_child(rect, 0)   # behind this layer's own stars
		_nebula_rects[layer] = rect
	_apply_params()


func _apply_params() -> void:
	var p := _cur()
	for layer in LAYERS:
		var rect = _nebula_rects.get(layer)
		if rect == null or not is_instance_valid(rect):
			continue
		var mat: ShaderMaterial = rect.material
		var cols: Array = _layer_colors[layer]
		var dim: float = float(LAYER_DIM[layer])
		if _style == Style.NEB2:
			mat.set_shader_parameter("scale", p["scale"])
			mat.set_shader_parameter("octaves", int(p["octaves"]))
			mat.set_shader_parameter("density", p["density"])
			mat.set_shader_parameter("edge_sharpness", p["edge"])
			mat.set_shader_parameter("warp_strength", p["warp_strength"])
			mat.set_shader_parameter("warp_scale", p["warp_scale"])
			mat.set_shader_parameter("swirl_speed", p["swirl"])
			mat.set_shader_parameter("drift_speed", p["drift"])
			mat.set_shader_parameter("opacity", p["opacity"])
			mat.set_shader_parameter("max_alpha", float(p["max_alpha"]) * dim)
			mat.set_shader_parameter("pixels", 480.0)
			mat.set_shader_parameter("rect_size", Vector2(480, 270))
			mat.set_shader_parameter("uv_correct", Vector2(1, 1))
			mat.set_shader_parameter("wisp_strength", 0.2)
			mat.set_shader_parameter("seed", float(abs(hash(layer)) % 900) / 100.0)
			mat.set_shader_parameter("colorscheme", _make_gradient(cols[0], cols[1]))
		else:
			mat.set_shader_parameter("noise_texture", _noise_tex)
			mat.set_shader_parameter("brightness", p["brightness"])
			mat.set_shader_parameter("clouds_resolution", p["clouds_resolution"])
			mat.set_shader_parameter("waveyness", p["waveyness"])
			mat.set_shader_parameter("fragmentation", p["fragmentation"])
			mat.set_shader_parameter("distortion", p["distortion"])
			mat.set_shader_parameter("blur", p["blur"])
			mat.set_shader_parameter("alpha", float(p["alpha"]) * dim)
			mat.set_shader_parameter("stars_on", true)
			mat.set_shader_parameter("colour_muiltiplier", cols[0])
			mat.set_shader_parameter("colour_muiltiplier2", cols[1])


func _make_gradient(c0: Color, c1: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([
		Color(0.02, 0.02, 0.05, 1.0), Color(c0.r, c0.g, c0.b, 1.0),
		Color(c1.r, c1.g, c1.b, 1.0), Color(1.0, 1.0, 1.0, 1.0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.4, 0.72, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 128
	t.height = 4
	return t


func _randomize_colors(reapply: bool = true) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# One cohesive scheme: a primary + a secondary from a different hue family, jittered per layer.
	var i0 := rng.randi() % NEBULA_PALETTE.size()
	var i1 := (i0 + 3 + rng.randi() % (NEBULA_PALETTE.size() - 4)) % NEBULA_PALETTE.size()
	var base0: Color = NEBULA_PALETTE[i0]
	var base1: Color = NEBULA_PALETTE[i1]
	for layer in LAYERS:
		var dh := rng.randf_range(-0.05, 0.05)
		_layer_colors[layer] = [_jitter(base0, dh, rng), _jitter(base1, dh, rng)]
	if reapply:
		_apply_params()
		_set_status("Randomized nebula colours.")


func _jitter(c: Color, dh: float, rng: RandomNumberGenerator) -> Color:
	return Color.from_hsv(
		fposmod(c.h + dh, 1.0),
		clampf(c.s + rng.randf_range(-0.05, 0.05), 0.0, 1.0),
		clampf(c.v + rng.randf_range(-0.05, 0.05), 0.0, 1.0))


# ---- UI -------------------------------------------------------------------

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -430
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.92)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(398, 0)
	scroll.add_child(v)

	v.add_child(_label("NEBULA LAB", UiTheme.FONT_SIZE_TITLE, UiTheme.COLOR_ACCENT))
	v.add_child(_label("Full parallax stack + tunable nebula on Far/Mid/Near.\nScrolls with the flight; colours from a realistic palette.", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))

	# Style selector.
	v.add_child(_label("STYLE", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	var style_dd := OptionButton.new()
	for s in STYLE_NAMES:
		style_dd.add_item(s)
	style_dd.select(_style)
	style_dd.item_selected.connect(_on_style_changed)
	v.add_child(style_dd)

	# Layer toggles.
	v.add_child(_label("LAYERS (depth)", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	var lrow := HBoxContainer.new()
	for layer in LAYERS:
		var cb := CheckButton.new()
		cb.text = layer
		cb.button_pressed = _layer_on[layer]
		cb.toggled.connect(_on_layer_toggled.bind(layer))
		lrow.add_child(cb)
	v.add_child(lrow)

	# Buttons row.
	var brow := HBoxContainer.new()
	var rc := UiTheme.make_button("Randomize Colours", true)
	rc.pressed.connect(_randomize_colors.bind(true))
	brow.add_child(rc)
	var rg := UiTheme.make_button("New Backdrop", true)
	rg.pressed.connect(_regenerate_backdrop)
	brow.add_child(rg)
	v.add_child(brow)

	# Flight speed.
	v.add_child(_slider("Flight speed", _flight, 0.0, 2.0, 0.05, func(val): _flight = val))

	v.add_child(HSeparator.new())
	v.add_child(_label("SHADER KNOBS", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	_knob_box = VBoxContainer.new()
	_knob_box.add_theme_constant_override("separation", 4)
	v.add_child(_knob_box)
	_rebuild_knobs()

	v.add_child(HSeparator.new())
	var frow := HBoxContainer.new()
	var save_b := UiTheme.make_button("Save", true)
	save_b.pressed.connect(_save)
	frow.add_child(save_b)
	var copy_b := UiTheme.make_button("Copy GDScript", true)
	copy_b.pressed.connect(_copy_snippet)
	frow.add_child(copy_b)
	var close_b := UiTheme.make_button("Close", true)
	close_b.pressed.connect(_on_close)
	frow.add_child(close_b)
	v.add_child(frow)

	_status = _label("", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT)
	v.add_child(_status)


func _rebuild_knobs() -> void:
	for c in _knob_box.get_children():
		c.queue_free()
	var p := _cur()
	var knobs: Array = NEB2_KNOBS if _style == Style.NEB2 else ALTB_KNOBS
	for k in knobs:
		var param: String = k[0]
		var s := _slider(k[1], float(p[param]), k[2], k[3], k[4], func(val): _on_knob(param, val))
		_knob_box.add_child(s)


func _on_knob(param: String, val: float) -> void:
	_cur()[param] = val
	_apply_params()


func _on_style_changed(idx: int) -> void:
	_style = idx
	_rebuild_knobs()
	_rebuild_nebula()
	_set_status("Style: %s" % STYLE_NAMES[idx])


func _on_layer_toggled(pressed: bool, layer: String) -> void:
	_layer_on[layer] = pressed
	_rebuild_nebula()


# ---- Persistence ----------------------------------------------------------

func _save() -> void:
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var data := {
		"style": _style, "flight": _flight, "layers": _layer_on,
		"neb2": _neb2, "altb": _altb,
	}
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
		_set_status("Saved to %s" % CONFIG_PATH)


func _load() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		_style = int(d.get("style", _style))
		_flight = float(d.get("flight", _flight))
		if d.has("layers"):
			for layer in LAYERS:
				_layer_on[layer] = bool(d["layers"].get(layer, true))
		for key in _neb2.keys():
			if d.has("neb2") and d["neb2"].has(key):
				_neb2[key] = float(d["neb2"][key])
		for key in _altb.keys():
			if d.has("altb") and d["altb"].has(key):
				_altb[key] = float(d["altb"][key])


func _copy_snippet() -> void:
	var t := "# Nebula Lab — tuned nebula config (Neb2 + AltB).\n"
	t += "const NEBULA_STYLE := \"%s\"\n" % STYLE_NAMES[_style]
	t += "const NEB2_PARAMS := {\n"
	for key in _neb2:
		t += "\t\"%s\": %s,\n" % [key, _fmt(_neb2[key])]
	t += "}\n"
	t += "const ALTB_PARAMS := {\n"
	for key in _altb:
		t += "\t\"%s\": %s,\n" % [key, _fmt(_altb[key])]
	t += "}\n"
	DisplayServer.clipboard_set(t)
	_set_status("Copied GDScript to clipboard.")


func _fmt(v) -> String:
	return "%.3f" % float(v)


func _on_close() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


# ---- Small helpers --------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.active_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _slider(title: String, value: float, lo: float, hi: float, step: float, on_change: Callable) -> Control:
	var box := VBoxContainer.new()
	var head := HBoxContainer.new()
	var name_l := _label(title, UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_TEXT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_l)
	var val_l := _label("%.3f" % value, UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_ACCENT)
	head.add_child(val_l)
	box.add_child(head)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(0, 18)
	s.value_changed.connect(func(v):
		val_l.text = "%.3f" % v
		on_change.call(v))
	box.add_child(s)
	return box


func _set_status(msg: String) -> void:
	if _status:
		_status.text = msg
