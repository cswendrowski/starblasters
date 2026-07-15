extends Control

# Asteroid Lab — single procgen asteroid with sliders for every generation knob.
# HD-rebuilt 2026-06-17: the preview now renders in a native-480 SubViewport (4×
# upscale, crisp pixel-art) inside an HD 1920×1080 shell, mirroring the Parallax
# Tuner / Enemy Bench pattern — the old native-480 Control stretched on the HD window.
#
# Knob surface follows the real Asteroids.gdshader uniforms: size (noise freq),
# octaves (detail), roundness, time_speed (surface churn), light angle, outline
# toggle + colour, dither, plus the lab's footprint size + spin + RGB tint.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const PROCGEN_ASTEROID = "res://Planets/Asteroids/Asteroid.tscn"

# Ship drop-shadow demo (asteroid_shadow_rig): demo ships fly over the rock and
# cast band-scaled shadows on it — the same rig + settings production combat uses.
const AsteroidShadowRig = preload("res://scripts/parallax/asteroid_shadow_rig.gd")
const SHIP_TEX := preload("res://graphics/player/player_ship_a_body.png")
const DEMO_ENEMY_TEXES: Array = [
	preload("res://graphics/enemies/enemy_core_s_jet.png"),
	preload("res://graphics/enemies/enemy_c_s_skirmisher.png"),
]
# Band order matches the OptionButton below (near = full-size shadow, 8px offset).
const SHADOW_BANDS := ["near", "mid", "far"]
const SHADOW_BAND_LABELS := ["Near band (1.0×, 8 px)", "Mid band (0.5×, 16 px)", "Far band (0.25×, 26 px)"]

# Native-viewport centre the asteroid sits at (preview SubViewport is 480×270).
const ASTEROID_CENTER := Vector2(240.0, 135.0)
const PIXEL_DENSITY := 1.0
const PIXELS_FLOOR := 16.0
const COLORRECT_CANONICAL := Vector2(100.0, 100.0)

# Slider schema — key/label/min/max/step/default/fmt. Driven into the shader in _regenerate.
const KNOBS := [
	{"key": "size_px",    "label": "Footprint (px)",   "min": 30.0, "max": 160.0, "step": 1.0,  "def": 60.0,  "fmt": "%d px"},
	{"key": "roundness",  "label": "Roundness",         "min": 0.0,  "max": 1.0,   "step": 0.05, "def": 0.6,   "fmt": "%.2f"},
	{"key": "octaves",    "label": "Detail (octaves)",  "min": 0.0,  "max": 5.0,   "step": 1.0,  "def": 3.0,   "fmt": "%d"},
	{"key": "churn",      "label": "Surface churn",     "min": 0.0,  "max": 1.0,   "step": 0.02, "def": 0.40,  "fmt": "%.2f"},
	{"key": "light_ang",  "label": "Light angle",       "min": 0.0,  "max": 360.0, "step": 5.0,  "def": 225.0, "fmt": "%d°"},
	{"key": "spin",       "label": "Spin",              "min": -3.0, "max": 3.0,   "step": 0.1,  "def": 0.0,   "fmt": "%.1f rad/s"},
	{"key": "tint_r",     "label": "Tint R",            "min": 0.3,  "max": 1.7,   "step": 0.05, "def": 1.20,  "fmt": "%.2f"},
	{"key": "tint_g",     "label": "Tint G",            "min": 0.3,  "max": 1.7,   "step": 0.05, "def": 1.05,  "fmt": "%.2f"},
	{"key": "tint_b",     "label": "Tint B",            "min": 0.3,  "max": 1.7,   "step": 0.05, "def": 0.85,  "fmt": "%.2f"},
]

var _hd_scope: HdViewportScope = null
var _world: SubViewport = null
var _visual: Control = null
var _seed: int = 12345
var _vals: Dictionary = {}
var _draw_outline: bool = true
var _dither: bool = true
var _readout: Label = null
# Ship drop-shadow demo state.
var _rig: Node = null
var _ships_on: bool = true
var _shadow_strength: float = 0.35
var _shadow_band: int = 0   # index into SHADOW_BANDS
var _demo_ship: Sprite2D = null
var _demo_enemies: Array = []
var _demo_time: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hd_scope = HdViewportScope.attach(self)
	for d in KNOBS:
		_vals[d["key"]] = float(d["def"])
	_build_preview_subviewport()
	_build_demo_ships()
	_build_ui()
	_regenerate()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("silent")


func _build_preview_subviewport() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_world = SubViewport.new()
	_world.size = Vector2i(480, 270)
	_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_world.transparent_bg = true
	var container := SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = 4   # 1920/4 = 480 → renders native, upscaled 4×
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_world)
	add_child(container)


# Demo ships flying over the rock, exercising the PRODUCTION shadow path: the rig
# auto-tracks the "player"/"enemies" groups, so the demo sprites just join those
# groups (safe in a lab — no director/bullets alive to react to them).
func _build_demo_ships() -> void:
	_rig = AsteroidShadowRig.new()
	_rig.strength = _shadow_strength
	add_child(_rig)
	_demo_ship = Sprite2D.new()
	_demo_ship.name = "DemoShip"
	_demo_ship.texture = SHIP_TEX
	_demo_ship.hframes = 3   # banking strip; frame 1 = level flight
	_demo_ship.frame = 1
	_demo_ship.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_demo_ship.position = Vector2(240.0, 130.0)
	_demo_ship.z_index = 40
	_demo_ship.add_to_group("player")
	_world.add_child(_demo_ship)
	for i in 2:
		var e := Sprite2D.new()
		e.name = "DemoEnemy%d" % i
		e.texture = DEMO_ENEMY_TEXES[i % DEMO_ENEMY_TEXES.size()]
		e.hframes = 3   # body/glow/livery strip; frame 0 = the body
		e.frame = 0
		e.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		e.rotation = PI   # art faces up; these fly down
		e.z_index = 40
		e.position = Vector2(randf_range(140.0, 340.0), randf_range(-200.0, -20.0))
		e.set_meta("speed", randf_range(30.0, 60.0))
		e.add_to_group("enemies")
		_world.add_child(e)
		_demo_enemies.append(e)


func _build_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 20
	add_child(ui_layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(1430, 0)
	panel.size = Vector2(490, 1080)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.9)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	ui_layer.add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	var hdr := Label.new()
	hdr.text = "ASTEROID LAB"
	hdr.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_HEADER)
	hdr.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
	v.add_child(hdr)
	var sub := Label.new()
	sub.text = "Tune the procgen asteroid shader."
	sub.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	sub.add_theme_color_override("font_color", UiTheme.COLOR_FAINT)
	v.add_child(sub)
	v.add_child(HSeparator.new())

	for d in KNOBS:
		_add_slider(v, d)

	v.add_child(HSeparator.new())
	# Toggles: outline + dither.
	_add_toggle(v, "Draw outline", _draw_outline, func(on: bool): _draw_outline = on; _regenerate())
	_add_toggle(v, "Dither", _dither, func(on: bool): _dither = on; _regenerate())

	v.add_child(HSeparator.new())
	# Ship drop shadows — the asteroid_shadow_rig ported from the Flyover cloud
	# shadows. Band picks which depth's offset/scale/weight the rock samples.
	var shdr := Label.new()
	shdr.text = "SHIP SHADOWS"
	shdr.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	shdr.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
	v.add_child(shdr)
	_add_toggle(v, "Demo ships", _ships_on, func(on: bool): _ships_on = on)
	var band_dd := OptionButton.new()
	for n in SHADOW_BAND_LABELS:
		band_dd.add_item(n)
	band_dd.select(_shadow_band)
	band_dd.item_selected.connect(func(idx: int): _shadow_band = idx; _apply_shadow_params())
	v.add_child(band_dd)
	_add_shadow_slider(v)

	v.add_child(HSeparator.new())
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	_readout.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	v.add_child(_readout)

	v.add_child(HSeparator.new())
	_add_button(v, "Generate New Asteroid", _on_new_asteroid)
	_add_button(v, "Back", _on_back)


func _add_slider(parent: Container, d: Dictionary) -> void:
	var key: String = d["key"]
	var fmt: String = d["fmt"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = d["label"]
	l.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var val := Label.new()
	val.text = fmt % float(_vals[key])
	val.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	val.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.custom_minimum_size = Vector2(90, 0)
	row.add_child(val)
	var s := HSlider.new()
	s.min_value = float(d["min"])
	s.max_value = float(d["max"])
	s.step = float(d["step"])
	s.value = float(_vals[key])
	s.custom_minimum_size = Vector2(0, 24)
	s.value_changed.connect(func(v: float):
		_vals[key] = v
		val.text = fmt % v
		_regenerate())
	parent.add_child(s)


func _add_toggle(parent: Container, text: String, on: bool, cb: Callable) -> void:
	var b := CheckButton.new()
	b.text = text
	b.button_pressed = on
	b.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	b.toggled.connect(cb)
	parent.add_child(b)


func _add_button(parent: Container, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	b.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BUTTON)
	UiTheme.style_button(b, true)
	b.pressed.connect(cb)
	parent.add_child(b)


func _on_new_asteroid() -> void:
	_seed = randi()
	_regenerate()


func _regenerate() -> void:
	if _world == null:
		return
	if _visual and is_instance_valid(_visual):
		_visual.queue_free()
		_visual = null
	var ps = load(PROCGEN_ASTEROID)
	if ps == null:
		return
	var v = ps.instantiate()
	# Per-instance shader material so each seed/knob set produces a distinct rock.
	var inner: Control = v.get_node_or_null("Asteroid") as Control
	if inner and inner.material != null:
		inner.material = inner.material.duplicate()
	if v.has_method("set_seed"):
		v.set_seed(_seed)
	# 1:1 pixel parity: scale the outer Control, keep the inner 100×100 ColorRect canonical.
	var size_px: float = float(_vals["size_px"])
	var sf: float = size_px / 100.0
	if v is Control:
		v.custom_minimum_size = COLORRECT_CANONICAL
		v.size = COLORRECT_CANONICAL
		v.scale = Vector2(sf, sf)
		v.position = ASTEROID_CENTER - COLORRECT_CANONICAL * 0.5 * sf
		v.pivot_offset = COLORRECT_CANONICAL * 0.5
	var shader_pixels: float = max(size_px / PIXEL_DENSITY, PIXELS_FLOOR)
	if v.has_method("set_pixels"):
		v.set_pixels(shader_pixels)
	# Apply the shader knobs. Roundness drives noise frequency (`size`); octaves is now its
	# OWN knob (was coupled to roundness); churn = time_speed; light angle → light_origin.
	if inner and inner.material is ShaderMaterial:
		var mat: ShaderMaterial = inner.material
		var roundness: float = float(_vals["roundness"])
		mat.set_shader_parameter("size", lerp(8.0, 1.5, roundness))
		mat.set_shader_parameter("roundness", roundness)
		mat.set_shader_parameter("octaves", int(round(float(_vals["octaves"]))))
		mat.set_shader_parameter("time_speed", float(_vals["churn"]))
		var ang: float = deg_to_rad(float(_vals["light_ang"]))
		mat.set_shader_parameter("light_origin", Vector2(0.5 + 0.45 * cos(ang), 0.5 + 0.45 * sin(ang)))
		mat.set_shader_parameter("draw_outline", _draw_outline)
		mat.set_shader_parameter("should_dither", _dither)
	if inner:
		inner.size = COLORRECT_CANONICAL
		inner.position = Vector2.ZERO
		inner.pivot_offset = COLORRECT_CANONICAL * 0.5
		inner.modulate = Color(float(_vals["tint_r"]), float(_vals["tint_g"]), float(_vals["tint_b"]), 1.0)
	v.set_meta("spin", float(_vals["spin"]))
	_world.add_child(v)
	_visual = v
	_apply_shadow_params()
	_update_readout()


# Bind the selected band's mask + strength into the current rock's material —
# the exact params layer_stellar sets at production rock spawn.
func _apply_shadow_params() -> void:
	if _rig == null or _visual == null or not is_instance_valid(_visual):
		return
	var inner := _visual.get_node_or_null("Asteroid")
	if inner == null or not (inner.material is ShaderMaterial):
		return
	_rig.strength = _shadow_strength
	var band: String = SHADOW_BANDS[_shadow_band]
	var mat: ShaderMaterial = inner.material
	mat.set_shader_parameter("shadow_mask", _rig.mask_texture(band))
	mat.set_shader_parameter("shadow_strength", _rig.band_strength(band))


# Strength slider — separate from KNOBS so tuning it doesn't regenerate the rock.
func _add_shadow_slider(parent: Container) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = "Shadow strength"
	l.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var val := Label.new()
	val.text = "%.2f" % _shadow_strength
	val.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_BODY)
	val.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.custom_minimum_size = Vector2(90, 0)
	row.add_child(val)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.02
	s.value = _shadow_strength
	s.custom_minimum_size = Vector2(0, 24)
	s.value_changed.connect(func(x: float):
		_shadow_strength = x
		val.text = "%.2f" % x
		_apply_shadow_params())
	parent.add_child(s)


func _process(delta: float) -> void:
	if _visual and is_instance_valid(_visual):
		var spin: float = float(_visual.get_meta("spin", 0.0))
		if abs(spin) > 0.001 and _visual is Control:
			_visual.rotation += spin * delta
	# Demo ships: player sweeps across the rock so the shadow visibly crosses it;
	# enemies travel down-screen and respawn above. Mask sync is the rig's job.
	_demo_time += delta
	if _demo_ship != null and is_instance_valid(_demo_ship):
		_demo_ship.visible = _ships_on
		# y ≈ rock centre so the offset shadow lands ON the rock, not under it.
		_demo_ship.position = Vector2(240.0 + sin(_demo_time * 0.4) * 110.0, 130.0 + sin(_demo_time * 1.3) * 4.0)
	for e in _demo_enemies:
		if e == null or not is_instance_valid(e):
			continue
		e.visible = _ships_on
		if _ships_on:
			e.position.y += float(e.get_meta("speed", 40.0)) * delta
			if e.position.y > 300.0:
				e.position = Vector2(randf_range(140.0, 340.0), -randf_range(20.0, 160.0))
				e.set_meta("speed", randf_range(30.0, 60.0))


func _update_readout() -> void:
	if _readout == null:
		return
	_readout.text = "Seed: %d   octaves: %d" % [_seed, int(round(float(_vals["octaves"])))]


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
