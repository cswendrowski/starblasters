extends Control

# Nebula Lab (Roman 2026-07-04) — see the two liked nebula styles (Neb2 / AltB) in the FULL live
# parallax stack. Renders the real backdrop_coordinator at 480x270 x4, then overlays a tunable nebula
# on any of the Far / Mid / Near stellar layers so a dense nebula reads WITH depth. Both styles scroll
# DOWNWARD with the parallax (per-layer rate). Colours randomise from a realistic-nebula palette.
# Knobs persist to user://tuners/nebula_lab.json; Copy GDScript emits a paste-ready block.

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const MenuBackdrop = preload("res://scripts/ui/menu_backdrop.gd")
const HdScreen = preload("res://scripts/ui/hd_screen.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const NEB2_SHADER := preload("res://graphics/nebula2.gdshader")
const ALTB_SHADER := preload("res://graphics/nebula_alt2.gdshader")

const CONFIG_PATH := "user://tuners/nebula_lab.json"

enum Style { NEB2, ALTB }
const STYLE_NAMES := ["Neb2 (filament)", "AltB (stars+clouds)"]

const LAYERS := ["Far", "Mid", "Near"]
const LAYER_NODE := {"Far": "LayerStellarFar", "Mid": "LayerStellarMid", "Near": "LayerStellarNear"}
const STREAK_SPEED := {"Far": 130.0, "Mid": 230.0, "Near": 380.0}
const STREAK_COUNT := 7
# Per-depth streak SIZE — distant (Far) streaks smaller, near ones larger (parallax perspective).
const STREAK_SCALE := {"Far": 0.5, "Mid": 0.9, "Near": 1.5}
# The nebula is a CHILD of each stellar CanvasLayer, so it rides that layer's REAL parallax scroll
# (the layer accumulates offset.y → we feed it to the shader) AND its colour grade (the layer's
# CanvasModulate multiplies the nebula too). No separate per-depth rate/dim of our own. nebula2 does
# `nuv -= scroll_offset`, so +offset.y scrolls content DOWN in lockstep with that layer's stars.
const RECT_H := 270.0   # nebula quad height; layer offset (px) / this = the shader's UV scroll
# Neb2 density + opacity BREATHE together over time (higher opacity <-> higher density) to open breaks
# + texture in the clouds; each layer is phase-offset so they don't pulse in lockstep.
const DENSITY_RANGE := Vector2(0.75, 1.4)
const OPACITY_RANGE := Vector2(0.4, 1.0)   # floor > 0 so a layer never fully vanishes (stays tunable)
const LAYER_PHASE := {"Far": 0.0, "Mid": 2.1, "Near": 4.2}

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

# Neb2 = Roman's tuned config, per-layer (Far/Mid/Near tune independently).
# density/opacity BREATHE per-layer, warp_scale is per-layer (below), drift defaults to 0.05 for visibility.
var _neb2 := {
	"Far": {"scale": 2.0, "octaves": 8.0, "edge": 0.5, "warp_strength": 1.2, "swirl": 0.16, "drift": 0.05, "max_alpha": 1.0},
	"Mid": {"scale": 2.0, "octaves": 8.0, "edge": 0.5, "warp_strength": 1.2, "swirl": 0.16, "drift": 0.05, "max_alpha": 1.0},
	"Near": {"scale": 2.0, "octaves": 8.0, "edge": 0.5, "warp_strength": 1.2, "swirl": 0.16, "drift": 0.05, "max_alpha": 1.0},
}
# Per-depth warp_scale (0.2..4.0) — each layer curls differently for variety; re-rolled on Randomize.
var _layer_warp := {"Far": 0.8, "Mid": 2.0, "Near": 3.4}
var _breathe_speed: float = 0.15
var _time: float = 0.0
var _altb := {
	"Far": {"brightness": 1.0, "clouds_resolution": 3.0, "waveyness": 0.5, "fragmentation": 7.0, "distortion": 0.5, "blur": 1.4, "alpha": 1.0},
	"Mid": {"brightness": 1.0, "clouds_resolution": 3.0, "waveyness": 0.5, "fragmentation": 7.0, "distortion": 0.5, "blur": 1.4, "alpha": 1.0},
	"Near": {"brightness": 1.0, "clouds_resolution": 3.0, "waveyness": 0.5, "fragmentation": 7.0, "distortion": 0.5, "blur": 1.4, "alpha": 1.0},
}
# Slider specs per style: [param, label, min, max, step]
# density/opacity/warp_scale are NOT sliders here — they breathe (density/opacity) or vary per-layer (warp).
const NEB2_KNOBS := [
	["scale", "Scale", 0.5, 6.0, 0.1], ["octaves", "Octaves", 1.0, 8.0, 1.0],
	["edge", "Edge sharp", 0.0, 1.0, 0.02], ["warp_strength", "Warp str", 0.0, 4.0, 0.05],
	["swirl", "Swirl", 0.0, 2.0, 0.02], ["drift", "Drift", 0.0, 0.5, 0.005],
	["max_alpha", "Max alpha", 0.0, 1.0, 0.02],
]
const ALTB_KNOBS := [
	["brightness", "Brightness", 0.0, 3.0, 0.05], ["clouds_resolution", "Cloud zoom", 0.5, 10.0, 0.1],
	["waveyness", "Waveyness", 0.0, 5.0, 0.05], ["fragmentation", "Fragment", 0.0, 100.0, 1.0],
	["distortion", "Distortion", 0.0, 10.0, 0.1], ["blur", "Blur", 0.5, 5.0, 0.05],
	["alpha", "Opacity", 0.0, 1.0, 0.02],
]

var _backdrop_sub: SubViewport = null
var _backdrop: Node2D = null
var _noise_tex: NoiseTexture2D = null
var _asteroids_on: bool = true
var _streaks_all: bool = false
var _edit_layer: String = "Near"

var _style: int = Style.NEB2
var _layer_on := {"Far": true, "Mid": true, "Near": true}
var _flight: float = 22.0             # drives the coordinator drift_speed = the whole parallax speed
var _layer_colors := {}              # layer -> [primary, secondary]
var _nebula_rects := {}              # layer -> ColorRect
var _layer_rate := {"Far": 0.2, "Mid": 0.5, "Near": 1.2}
var _layer_streaks := {}             # layer -> GPUParticles2D

var _knob_box: VBoxContainer = null
var _status: Label = null


func _cur() -> Dictionary:
	return (_neb2 if _style == Style.NEB2 else _altb)[_edit_layer]


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
	MenuBackdrop.drop_celestials(_backdrop)
	_apply_layer_rates()
	_build_layer_streaks()
	_rebuild_nebula()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")


func _process(_delta: float) -> void:
	_time += _delta
	# Flight slider = the coordinator's drift_speed, so the WHOLE parallax (stars, planet, nebula)
	# scrolls together at one rate.
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.drift_speed = _flight
	for layer in LAYERS:
		var host := _layer_node(layer) as CanvasLayer
		if host == null or not is_instance_valid(host):
			continue
		# Streaks: keep screen-fixed by counteracting the layer's offset (independent of nebula toggle).
		var streak = _layer_streaks.get(layer)
		if streak != null and is_instance_valid(streak):
			streak.position = Vector2(240.0, -10.0 - host.offset.y)
		# Nebula handling (gated by _layer_on).
		if not _layer_on[layer]:
			continue
		var rect = _nebula_rects.get(layer)
		if rect == null or not is_instance_valid(rect):
			continue
		var mat: ShaderMaterial = rect.material
		if mat == null:
			continue
		# The nebula is a child of this stellar CanvasLayer (so it already gets the layer's colour grade
		# + depth dim via the layer CanvasModulate). The layer scrolls by accumulating offset.y — keep the
		# quad screen-fixed (cancel it) and feed the SAME offset to the shader so the nebula drifts in
		# lockstep with THIS layer's stars: the real per-depth parallax speed, not a fabricated one.
		rect.position = Vector2(0.0, -host.offset.y)
		mat.set_shader_parameter("scroll_offset", Vector2(0.0, host.offset.y / RECT_H))
		if _style == Style.NEB2:
			# Breathe: density + opacity rise/fall together (phase-offset per layer) → slow breaks + texture.
			var o: float = 0.5 + 0.5 * sin(_time * _breathe_speed + float(LAYER_PHASE[layer]))
			mat.set_shader_parameter("density", lerpf(DENSITY_RANGE.x, DENSITY_RANGE.y, o))
			mat.set_shader_parameter("opacity", lerpf(OPACITY_RANGE.x, OPACITY_RANGE.y, o))


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()


# ---- Backdrop + nebula ----------------------------------------------------

func _build_backdrop() -> void:
	_backdrop = MenuBackdrop.make()
	_backdrop.set("force_asteroids", _asteroids_on)
	_backdrop.set("drift_speed", _flight)
	_backdrop_sub = HdScreen.add_upscaled_backdrop(self, _backdrop)
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
	if _backdrop_sub and is_instance_valid(_backdrop_sub):
		_backdrop_sub.queue_free()
	var bv := get_node_or_null("BackdropView")
	if bv:
		bv.queue_free()
	_nebula_rects.clear()
	var run := get_node_or_null("/root/Run")
	if run != null and "run_seed" in run:
		run.set("run_seed", randi())
	_backdrop = MenuBackdrop.make()
	_backdrop.set("force_asteroids", _asteroids_on)
	_backdrop.set("drift_speed", _flight)
	_backdrop_sub = HdScreen.add_upscaled_backdrop(self, _backdrop)
	await get_tree().process_frame
	await get_tree().process_frame
	MenuBackdrop.drop_celestials(_backdrop)
	_apply_layer_rates()
	_build_layer_streaks()
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


func _apply_layer_rates() -> void:
	for layer in LAYERS:
		var cl := _layer_node(layer) as CanvasLayer
		if cl != null:
			cl.set("scroll_rate", float(_layer_rate[layer]))


func _make_streaks(speed: float, count: int, scale: float) -> GPUParticles2D:
	# Build a warp-streak emitter like layer_streaks, but with local_coords = true so we can screen-fix it.
	var p := GPUParticles2D.new()
	p.name = "LayerStreaks"
	p.amount = count
	p.lifetime = 1000.0 / max(speed, 1.0)
	p.preprocess = p.lifetime  # populate the field on spawn rather than empty
	p.one_shot = false
	p.explosiveness = 0.0
	p.local_coords = true
	p.position = Vector2(240, -10)
	p.texture = _build_streak_texture()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(260, 6, 0)
	m.direction = Vector3(0, 1, 0)
	m.spread = 0.0
	m.initial_velocity_min = speed * 0.8
	m.initial_velocity_max = speed * 1.2
	m.gravity = Vector3.ZERO
	m.scale_min = 0.7 * scale
	m.scale_max = 1.6 * scale
	var grad = Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.6),
		Color(0.55, 0.7, 1.0, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	var ramp = GradientTexture1D.new()
	ramp.gradient = grad
	ramp.width = 32
	m.color_ramp = ramp
	p.process_material = m
	# Additive blend so streaks add light over the scene.
	var canvas_mat := CanvasItemMaterial.new()
	canvas_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = canvas_mat
	return p


static func _build_streak_texture() -> Texture2D:
	# Tall thin gradient: faint at the tips, bright in the middle (copied from layer_streaks).
	var g = Gradient.new()
	g.colors = PackedColorArray([
		Color(1, 1, 1, 0),
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var t = GradientTexture2D.new()
	t.gradient = g
	t.width = 2
	t.height = 28
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0.5, 0.0)
	t.fill_to = Vector2(0.5, 1.0)
	return t


func _build_layer_streaks() -> void:
	# Free any existing emitters and clear the dict.
	for layer in _layer_streaks.keys():
		var s = _layer_streaks[layer]
		if s and is_instance_valid(s):
			s.queue_free()
	_layer_streaks.clear()
	# Build new streaks if enabled.
	if _streaks_all:
		for layer in LAYERS:
			var host := _layer_node(layer)
			if host != null:
				var streak = _make_streaks(STREAK_SPEED[layer], STREAK_COUNT, float(STREAK_SCALE[layer]))
				host.add_child(streak)
				_layer_streaks[layer] = streak


func _apply_params() -> void:
	for layer in LAYERS:
		var rect = _nebula_rects.get(layer)
		if rect == null or not is_instance_valid(rect):
			continue
		var p: Dictionary = (_neb2 if _style == Style.NEB2 else _altb)[layer]
		var mat: ShaderMaterial = rect.material
		var cols: Array = _layer_colors[layer]
		if _style == Style.NEB2:
			mat.set_shader_parameter("scale", p["scale"])
			mat.set_shader_parameter("octaves", int(p["octaves"]))
			mat.set_shader_parameter("edge_sharpness", p["edge"])
			mat.set_shader_parameter("warp_strength", p["warp_strength"])
			mat.set_shader_parameter("warp_scale", float(_layer_warp[layer]))   # per-depth variety
			mat.set_shader_parameter("swirl_speed", p["swirl"])
			mat.set_shader_parameter("drift_speed", p["drift"])
			mat.set_shader_parameter("max_alpha", float(p["max_alpha"]))
			# density + opacity are driven per-frame in _process (breathe).
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
			mat.set_shader_parameter("alpha", float(p["alpha"]))   # per-depth dim comes from the layer grade
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
	# Distinct per-depth warp_scale (low/mid/high bands, shuffled) so each layer curls differently.
	var warps := [rng.randf_range(0.3, 1.3), rng.randf_range(1.4, 2.6), rng.randf_range(2.7, 3.9)]
	warps.shuffle()
	_layer_warp["Far"] = warps[0]
	_layer_warp["Mid"] = warps[1]
	_layer_warp["Near"] = warps[2]
	if reapply:
		_apply_params()
		_set_status("Randomized colours + per-layer warp.")


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

	# Buttons row 1 (large buttons).
	var brow1 := HBoxContainer.new()
	var rc := UiTheme.make_button("Randomize Colours", true)
	rc.pressed.connect(_randomize_colors.bind(true))
	brow1.add_child(rc)
	var rg := UiTheme.make_button("New Backdrop", true)
	rg.pressed.connect(_regenerate_backdrop)
	brow1.add_child(rg)
	v.add_child(brow1)

	# Buttons row 2 (toggle checkboxes).
	var brow2 := HBoxContainer.new()
	var ast := CheckButton.new()
	ast.text = "Asteroids"
	ast.button_pressed = _asteroids_on
	ast.toggled.connect(_on_asteroids_toggled)
	brow2.add_child(ast)
	var str := CheckButton.new()
	str.text = "Streaks"
	str.button_pressed = _streaks_all
	str.toggled.connect(_on_streaks_toggled)
	brow2.add_child(str)
	v.add_child(brow2)

	# Parallax speed (drives the coordinator drift_speed — moves the whole stack) + breathe rate.
	v.add_child(_slider("Parallax speed (drift)", _flight, 0.0, 60.0, 1.0, func(val): _flight = val))
	v.add_child(_slider("Breathe speed (density/opacity)", _breathe_speed, 0.0, 1.0, 0.01, func(val): _breathe_speed = val))

	v.add_child(HSeparator.new())
	v.add_child(_label("PARALLAX LAYER SPEED", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	for layer in LAYERS:
		var title = layer + " speed"
		v.add_child(_slider(title, _layer_rate[layer], 0.0, 2.0, 0.05, func(v): _layer_rate[layer] = v; _apply_layer_rates()))

	v.add_child(HSeparator.new())
	v.add_child(_label("EDIT LAYER", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	var layer_row := HBoxContainer.new()
	for layer in LAYERS:
		var layer_btn := UiTheme.make_button(layer, true)
		layer_btn.pressed.connect(_on_edit_layer_selected.bind(layer))
		layer_row.add_child(layer_btn)
	v.add_child(layer_row)

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


func _on_asteroids_toggled(pressed: bool) -> void:
	_asteroids_on = pressed
	_regenerate_backdrop()


func _on_streaks_toggled(pressed: bool) -> void:
	_streaks_all = pressed
	_build_layer_streaks()


func _on_edit_layer_selected(layer: String) -> void:
	_edit_layer = layer
	_rebuild_knobs()


# ---- Persistence ----------------------------------------------------------

func _save() -> void:
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var data := {
		"style": _style, "flight": _flight, "layers": _layer_on,
		"breathe_speed": _breathe_speed, "layer_warp": _layer_warp,
		"layer_rate": _layer_rate, "asteroids_on": _asteroids_on, "streaks_all": _streaks_all,
		"edit_layer": _edit_layer, "neb2": _neb2, "altb": _altb,
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
		_breathe_speed = float(d.get("breathe_speed", _breathe_speed))
		_asteroids_on = bool(d.get("asteroids_on", _asteroids_on))
		_streaks_all = bool(d.get("streaks_all", _streaks_all))
		_edit_layer = d.get("edit_layer", _edit_layer)
		if d.has("layer_warp"):
			for layer in LAYERS:
				_layer_warp[layer] = float(d["layer_warp"].get(layer, _layer_warp[layer]))
		if d.has("layer_rate"):
			for layer in LAYERS:
				_layer_rate[layer] = float(d["layer_rate"].get(layer, _layer_rate[layer]))
		if d.has("layers"):
			for layer in LAYERS:
				_layer_on[layer] = bool(d["layers"].get(layer, true))
		# Load per-layer neb2 dicts.
		if d.has("neb2"):
			for layer in LAYERS:
				if d["neb2"].has(layer):
					for key in _neb2[layer].keys():
						if d["neb2"][layer].has(key):
							_neb2[layer][key] = float(d["neb2"][layer][key])
		# Load per-layer altb dicts.
		if d.has("altb"):
			for layer in LAYERS:
				if d["altb"].has(layer):
					for key in _altb[layer].keys():
						if d["altb"][layer].has(key):
							_altb[layer][key] = float(d["altb"][layer][key])


func _copy_snippet() -> void:
	var t := "# Nebula Lab — tuned Neb2 per-layer configs (density/opacity breathe over time; warp is per-layer).\n"
	# Output per-layer Neb2 configs.
	for layer in LAYERS:
		t += "const NEB2_%s := {\n" % layer.to_upper()
		for key in _neb2[layer].keys():
			t += "\t\"%s\": %s,\n" % [key, _fmt(_neb2[layer][key])]
		t += "}\n"
	t += "const NEB2_WARP_SCALE := { \"Far\": %s, \"Mid\": %s, \"Near\": %s }\n" % [_fmt(_layer_warp["Far"]), _fmt(_layer_warp["Mid"]), _fmt(_layer_warp["Near"])]
	t += "const NEB2_DENSITY_RANGE := Vector2(%s, %s)\n" % [_fmt(DENSITY_RANGE.x), _fmt(DENSITY_RANGE.y)]
	t += "const NEB2_OPACITY_RANGE := Vector2(%s, %s)  # breathes with density\n" % [_fmt(OPACITY_RANGE.x), _fmt(OPACITY_RANGE.y)]
	t += "const NEB2_BREATHE_SPEED := %s\n" % _fmt(_breathe_speed)
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
	var row := HBoxContainer.new()
	var name_l := _label(title, UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_TEXT)
	name_l.custom_minimum_size = Vector2(150, 0)
	row.add_child(name_l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 16)
	var val_l := _label("%.2f" % value, UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_ACCENT)
	val_l.custom_minimum_size = Vector2(52, 0)
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(v):
		val_l.text = "%.2f" % v
		on_change.call(v))
	row.add_child(s)
	row.add_child(val_l)
	return row


func _set_status(msg: String) -> void:
	if _status:
		_status.text = msg
