extends Control

# Planet Flyover Lab (Roman 2026-07-11) — tunes the Planet Flyover combat backdrop: flying
# straight down over a planet's surface (scrolling ground + atmosphere haze + gray/white cloud
# layers). The world itself is built by scripts/parallax/flyover_backdrop.gd (FlyoverBackdrop);
# this lab HOSTS one inside a native 480×270 play SubViewport (4× nearest upscale so it matches
# combat's pixel-art look), drives it through apply_settings(), and adds demo ships + the
# recycle choreography as shadow casters via the public register_caster() API.
#
# Knobs persist to user://tuners/planet_flyover.json (the planner overlays that same file in
# production); Copy GDScript emits a paste-ready block (tuner contract).

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const HdScreen = preload("res://scripts/ui/hd_screen.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
# Preload (not the global class_name) so the lab loads clean under headless --script before the
# class cache regenerates — matches the factions/lane_traffic preload convention.
const Backdrop = preload("res://scripts/parallax/flyover_backdrop.gd")
const SHIP_TEX := preload("res://graphics/player/player_ship_a_body.png")
# Demo enemy ships (single-frame sprites) that travel DOWN-screen under the Near layer.
const ENEMY_TEXES: Array = [
	preload("res://graphics/enemies/enemy_core_s_jet.png"),
	preload("res://graphics/enemies/enemy_c_s_skirmisher.png"),
	preload("res://graphics/enemies/enemy_core_s_flechette.png"),
]

const CONFIG_PATH := "user://tuners/planet_flyover.json"
# Demo z-band, above the hosted backdrop's Near cloud (base_z 0 → Near at z 24). A recycled
# ship drops just UNDER the Near layer to sink away through the cloud deck, then respawns above.
const DEMO_LIVE_Z := 35
const DEMO_RECYCLE_Z := 22
const SHIP_Z := 40

# ---- Tunable state (persisted) -------------------------------------------
var _flight: float = 0.35        # ground scroll speed, screen-heights / second
var _feature_scale: float = 8.0  # noise cells across the screen (feature size)
var _loop_size: int = 32         # tiling period (integer) — bigger = longer loop
var _octaves: int = 5
var _relief: float = 0.35
var _pixels: float = 160.0
var _river_cutoff: float = 0.5   # water/lava/rock coverage threshold (per preset, tunable)
var _cloud_opacity: float = 0.6  # master multiplier over each layer's opacity
var _cloud_coverage: float = 0.55  # generated-cloud style: how much sky is covered
var _preset: int = 0
var _atmo_color: Color = Color(0.45, 0.65, 0.95)
var _atmo_opacity: float = 0.18
# Demo ship + its cloud shadow.
var _ship_on: bool = true
var _ship_shadow: float = 0.35
# Per-decorative-layer knobs: style (Nebula=nebula2 / Clouds=cloud_layer), opacity, colour.
var _layer_style := {"Far": 0, "Mid": 0, "Near": 0}
var _layer_opacity := {"Far": 1.0, "Mid": 1.0, "Near": 1.0}
var _layer_color := {"Far": Color(0.75, 0.78, 0.83), "Mid": Color(0.82, 0.84, 0.88), "Near": Color(0.90, 0.91, 0.94)}
# Randomize Look state: shader noise seed (new terrain layout) + per-preset hue-rolled
# palettes (one hue rotation shared by all slots keeps the ramp coherent while the hue family
# goes anywhere, like the kit's randomize_colors schemes).
var _rand_seed: float = 1.0
var _rand_palettes := {}         # preset name -> Array[Color] override (not persisted)
var _cloud_on := {"Far": true, "Mid": true, "Near": true}
# Night knobs (persisted). The Night preview toggle itself is NOT persisted.
var _night_darkness: float = 0.45
var _night_color: Color = Color(0.25, 0.31, 0.53)
var _night_preview: bool = false

# ---- Runtime -------------------------------------------------------------
var _sub: SubViewport = null
var _backdrop: Backdrop = null
var _ship: Sprite2D = null
var _ship_time: float = 0.0
# Demo caster bookkeeping (movement + recycle state); the shadow masks live in the backdrop.
var _demo: Array = []            # [{node: Sprite2D, speed: float, recycled: bool}]
var _status: Label = null
var _atmo_picker: ColorPickerButton = null


func _ready() -> void:
	HdScreen.enter(self)
	_load()
	_build_scene()
	_build_ui()
	_push()
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")


func _process(delta: float) -> void:
	# Demo ships: the player hover-bobs; enemies travel down-screen and respawn above. The
	# hosted backdrop tracks every registered caster's transform into its shadow masks.
	_ship_time += delta
	if _ship != null and is_instance_valid(_ship):
		_ship.position = Vector2(240.0 + sin(_ship_time * 0.7) * 4.0, 195.0 + sin(_ship_time * 1.3) * 2.0)
	for c in _demo:
		var n: Sprite2D = c["node"]
		if n == null or not is_instance_valid(n):
			continue
		if float(c["speed"]) > 0.0:
			n.position.y += float(c["speed"]) * delta
			# Bottom zone → RECYCLE: drop under the Near cloud layer with the depth-tint ghost,
			# so the exit reads as sinking away through the cloud deck.
			if not bool(c["recycled"]) and n.position.y > 235.0:
				c["recycled"] = true
				n.z_index = DEMO_RECYCLE_Z
				n.modulate = Color(0.62, 0.66, 0.76, 0.95)
			if n.position.y > 310.0:
				c["recycled"] = false
				n.z_index = DEMO_LIVE_Z
				n.modulate = Color.WHITE
				n.position = Vector2(randf_range(60.0, 420.0), -40.0)
				c["speed"] = randf_range(30.0, 70.0)
		n.visible = _ship_on


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()


# ---- Scene ---------------------------------------------------------------

func _build_scene() -> void:
	_sub = HdScreen.make_play_subviewport(self)
	# The world builder. base_z 0 slots the whole flyover stack at z 0..24; demo ships sit above.
	_backdrop = Backdrop.new()
	_backdrop.name = "Flyover"
	_backdrop.base_z = 0
	_backdrop.track_combat_casters = false   # the lab registers its demo casters explicitly
	_sub.add_child(_backdrop)
	# Demo player ship above everything — a COMPOSED single frame (the sheet is a 3-hframe
	# banking strip; frame 1 = level flight), casts on all three layers.
	_ship = Sprite2D.new()
	_ship.name = "Ship"
	_ship.texture = _single_frame(SHIP_TEX, 1)
	_ship.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ship.position = Vector2(240.0, 195.0)
	_ship.z_index = SHIP_Z
	_sub.add_child(_ship)
	_backdrop.register_caster(_ship, _ship.texture)
	_demo.append({"node": _ship, "speed": 0.0, "recycled": false})
	# Demo enemy ships: LIVE they travel down-screen ABOVE the Near layer casting on all three
	# masks. Reaching the bottom zone they RECYCLE — drop under the Near clouds, take the
	# depth-tint ghost — and sink off through the cloud deck, then respawn.
	for i in 3:
		var e := Sprite2D.new()
		e.name = "Enemy%d" % i
		# Enemy sheets are 3-hframe strips too (body/glow/livery); frame 0 = the body.
		e.texture = _single_frame(ENEMY_TEXES[i % ENEMY_TEXES.size()], 0)
		e.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		e.rotation = PI   # art faces up; these fly down
		e.z_index = DEMO_LIVE_Z
		e.position = Vector2(randf_range(60.0, 420.0), randf_range(-260.0, -20.0))
		_sub.add_child(e)
		_backdrop.register_caster(e, e.texture)
		_demo.append({"node": e, "speed": randf_range(30.0, 70.0), "recycled": false})


# One frame of a 3-hframe sprite strip as a standalone texture.
func _single_frame(tex: Texture2D, frame: int) -> AtlasTexture:
	var fw: float = tex.get_width() / 3.0
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(fw * float(frame), 0.0, fw, tex.get_height())
	return at


# Build the full settings dict from lab state and push it to the hosted backdrop.
func _push() -> void:
	if _backdrop == null or not is_instance_valid(_backdrop):
		return
	_backdrop.apply_settings(_settings_dict())


func _settings_dict() -> Dictionary:
	var pname: String = Backdrop.PRESET_NAMES[_preset]
	var preset: Dictionary = Backdrop.PRESETS[pname]
	var colors: Array = _rand_palettes.get(pname, preset["colors"])
	return {
		"flyover": true,
		"preset": _preset,
		"surface_type": int(preset["type"]),
		"colors": colors,
		"emissive": float(preset["emissive"]),
		"seed": _rand_seed,
		"flight": _flight, "feature_scale": _feature_scale, "loop_size": _loop_size,
		"octaves": _octaves, "pixels": _pixels, "relief": _relief, "river_cutoff": _river_cutoff,
		"atmo": bool(preset["atmo"]), "atmo_color": _atmo_color, "atmo_opacity": _atmo_opacity,
		"cloud_opacity": _cloud_opacity, "cloud_coverage": _cloud_coverage,
		"cloud_on": _cloud_on, "layer_style": _layer_style,
		"layer_opacity": _layer_opacity, "layer_color": _layer_color,
		"ship_shadow": _ship_shadow,
		"night": _night_preview, "night_darkness": _night_darkness, "night_color": _night_color,
	}


# ---- UI ------------------------------------------------------------------

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

	v.add_child(_label("PLANET FLYOVER LAB", UiTheme.FONT_SIZE_TITLE, UiTheme.COLOR_ACCENT))
	v.add_child(_label("Scrolling ground from the PixelPlanets land-mass noise + gray/white cloud layers.\nSeamless vertical loop.", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))

	# Planet surface preset.
	v.add_child(_label("SURFACE", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	var dd := OptionButton.new()
	for n in Backdrop.PRESET_NAMES:
		dd.add_item(n)
	dd.select(_preset)
	dd.item_selected.connect(_on_preset_changed)
	v.add_child(dd)

	# Randomize Look: new noise seed + kit-style hue-rolled palette for this preset.
	var rrow := HBoxContainer.new()
	var rand_b := UiTheme.make_button("Randomize Look", true)
	rand_b.pressed.connect(_on_randomize_look)
	rrow.add_child(rand_b)
	var auth_b := UiTheme.make_button("Authored Look", true)
	auth_b.pressed.connect(_on_authored_look)
	rrow.add_child(auth_b)
	v.add_child(rrow)

	# Atmosphere: gated by the preset's atmo flag; colour + opacity free knobs.
	v.add_child(_label("ATMOSPHERE", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	var arow := HBoxContainer.new()
	_atmo_picker = ColorPickerButton.new()
	_atmo_picker.color = _atmo_color
	_atmo_picker.custom_minimum_size = Vector2(56, 26)
	_atmo_picker.color_changed.connect(func(c): _atmo_color = c; _push())
	arow.add_child(_atmo_picker)
	var aslider := _slider("Opacity", _atmo_opacity, 0.0, 0.6, 0.01, func(x): _atmo_opacity = x; _push())
	aslider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arow.add_child(aslider)
	v.add_child(arow)

	# Cloud layer toggles.
	v.add_child(_label("CLOUD LAYERS (depth)", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	var lrow := HBoxContainer.new()
	for layer in Backdrop.CLOUD_LAYERS:
		var cb := CheckButton.new()
		cb.text = layer
		cb.button_pressed = _cloud_on[layer]
		cb.toggled.connect(_on_cloud_toggled.bind(layer))
		lrow.add_child(cb)
	v.add_child(lrow)

	# Per-layer style / colour / opacity — max parallax cloud/dust tunability.
	for layer in Backdrop.CLOUD_LAYERS:
		var row := HBoxContainer.new()
		var name_l := _label(layer, UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_TEXT)
		name_l.custom_minimum_size = Vector2(38, 0)
		row.add_child(name_l)
		var style_dd := OptionButton.new()
		for s in Backdrop.LAYER_STYLE_NAMES:
			style_dd.add_item(s)
		style_dd.select(int(_layer_style[layer]))
		style_dd.item_selected.connect(func(idx): _layer_style[layer] = idx; _push())
		row.add_child(style_dd)
		var pick := ColorPickerButton.new()
		pick.color = _layer_color[layer]
		pick.custom_minimum_size = Vector2(44, 26)
		pick.color_changed.connect(func(c): _layer_color[layer] = c; _push())
		row.add_child(pick)
		var op := HSlider.new()
		op.min_value = 0.0
		op.max_value = 1.0
		op.step = 0.02
		op.value = float(_layer_opacity[layer])
		op.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		op.custom_minimum_size = Vector2(0, 16)
		op.value_changed.connect(func(x): _layer_opacity[layer] = x; _push())
		row.add_child(op)
		v.add_child(row)

	v.add_child(HSeparator.new())
	v.add_child(_label("GROUND", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	v.add_child(_slider("Flight speed", _flight, 0.0, 2.0, 0.01, func(x): _flight = x; _push()))
	v.add_child(_slider("Feature scale", _feature_scale, 3.0, 24.0, 0.5, func(x): _feature_scale = x; _push()))
	v.add_child(_slider("Loop size (period)", float(_loop_size), 12.0, 96.0, 1.0, func(x): _loop_size = int(x); _push()))
	v.add_child(_slider("Octaves", float(_octaves), 1.0, 8.0, 1.0, func(x): _octaves = int(x); _push()))
	v.add_child(_slider("Relief (sun)", _relief, 0.0, 1.0, 0.02, func(x): _relief = x; _push()))
	v.add_child(_slider("Water / lava level", _river_cutoff, 0.2, 0.8, 0.01, func(x): _river_cutoff = x; _push()))
	v.add_child(_slider("Pixelation", _pixels, 40.0, 480.0, 5.0, func(x): _pixels = x; _push()))

	v.add_child(HSeparator.new())
	v.add_child(_label("CLOUDS", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	v.add_child(_slider("Cloud opacity", _cloud_opacity, 0.0, 1.0, 0.02, func(x): _cloud_opacity = x; _push()))
	v.add_child(_slider("Cloud coverage", _cloud_coverage, 0.0, 1.0, 0.02, func(x): _cloud_coverage = x; _push()))
	var srow := HBoxContainer.new()
	var ship_cb := CheckButton.new()
	ship_cb.text = "Ships"
	ship_cb.button_pressed = _ship_on
	ship_cb.toggled.connect(func(p): _ship_on = p)
	srow.add_child(ship_cb)
	var sshadow := _slider("Cloud shadow", _ship_shadow, 0.0, 1.0, 0.02, func(x): _ship_shadow = x; _push())
	sshadow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(sshadow)
	v.add_child(srow)

	# Day/Night: preview toggle (not persisted) + persisted darkness + colour knobs.
	v.add_child(HSeparator.new())
	v.add_child(_label("NIGHT", UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT))
	var nrow := HBoxContainer.new()
	var night_cb := CheckButton.new()
	night_cb.text = "Night preview"
	night_cb.button_pressed = _night_preview
	night_cb.toggled.connect(func(p): _night_preview = p; _push())
	nrow.add_child(night_cb)
	var ncolor := ColorPickerButton.new()
	ncolor.color = _night_color
	ncolor.custom_minimum_size = Vector2(56, 26)
	ncolor.color_changed.connect(func(c): _night_color = c; _push())
	nrow.add_child(ncolor)
	v.add_child(nrow)
	var ndark := _slider("Night darkness", _night_darkness, 0.0, 0.8, 0.01, func(x): _night_darkness = x; _push())
	ndark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(ndark)

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


func _on_preset_changed(idx: int) -> void:
	_preset = idx
	# Atmosphere colour defaults from the preset on switch (then stays user-tunable).
	_atmo_color = Backdrop.PRESETS[Backdrop.PRESET_NAMES[idx]]["atmo_color"]
	if _atmo_picker != null and is_instance_valid(_atmo_picker):
		_atmo_picker.color = _atmo_color
	_push()
	_set_status("Surface: %s" % Backdrop.PRESET_NAMES[idx])


# New shader seed (fresh terrain layout) + a hue-rolled palette for the current preset — one
# random hue rotation shared across all slots (ramps stay coherent, hue family goes anywhere)
# with slight per-slot sat/val jitter. Reuses FlyoverBackdrop.shift_color.
func _on_randomize_look() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_rand_seed = rng.randf_range(1.0, 10.0)
	var pname: String = Backdrop.PRESET_NAMES[_preset]
	var dh := rng.randf()
	var out: Array = []
	for c in Backdrop.PRESETS[pname]["colors"]:
		out.append(Backdrop.shift_color(c, dh, rng))
	_rand_palettes[pname] = out
	_push()
	_set_status("Randomized %s look (seed %.2f)." % [pname, _rand_seed])


func _on_authored_look() -> void:
	_rand_palettes.erase(Backdrop.PRESET_NAMES[_preset])
	_rand_seed = 1.0
	_push()
	_set_status("Authored look restored.")


func _on_cloud_toggled(pressed: bool, layer: String) -> void:
	_cloud_on[layer] = pressed
	_push()


# ---- Persistence ---------------------------------------------------------

func _save() -> void:
	DirAccess.make_dir_recursive_absolute("user://tuners")
	var lc := {}
	for layer in Backdrop.CLOUD_LAYERS:
		lc[layer] = (_layer_color[layer] as Color).to_html(false)
	var data := {
		"flight": _flight, "feature_scale": _feature_scale, "loop_size": _loop_size,
		"octaves": _octaves, "relief": _relief, "pixels": _pixels, "river_cutoff": _river_cutoff,
		"cloud_opacity": _cloud_opacity, "cloud_coverage": _cloud_coverage,
		"preset": _preset, "cloud_on": _cloud_on,
		"atmo_color": _atmo_color.to_html(false), "atmo_opacity": _atmo_opacity,
		"layer_style": _layer_style, "layer_opacity": _layer_opacity, "layer_color": lc,
		"ship_on": _ship_on, "ship_shadow": _ship_shadow,
		"night_darkness": _night_darkness, "night_color": _night_color.to_html(false),
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
		_flight = float(d.get("flight", _flight))
		_feature_scale = float(d.get("feature_scale", _feature_scale))
		_loop_size = int(d.get("loop_size", _loop_size))
		_octaves = int(d.get("octaves", _octaves))
		_relief = float(d.get("relief", _relief))
		_pixels = float(d.get("pixels", _pixels))
		_river_cutoff = float(d.get("river_cutoff", _river_cutoff))
		_cloud_opacity = float(d.get("cloud_opacity", _cloud_opacity))
		_cloud_coverage = float(d.get("cloud_coverage", _cloud_coverage))
		_atmo_opacity = float(d.get("atmo_opacity", _atmo_opacity))
		_ship_on = bool(d.get("ship_on", _ship_on))
		_ship_shadow = float(d.get("ship_shadow", _ship_shadow))
		_night_darkness = float(d.get("night_darkness", _night_darkness))
		if d.has("atmo_color"):
			_atmo_color = Color.from_string(String(d["atmo_color"]), _atmo_color)
		if d.has("night_color"):
			_night_color = Color.from_string(String(d["night_color"]), _night_color)
		# Clamp: a saved index can outlive a removed preset.
		_preset = clampi(int(d.get("preset", _preset)), 0, Backdrop.PRESET_NAMES.size() - 1)
		if d.has("cloud_on"):
			for layer in Backdrop.CLOUD_LAYERS:
				_cloud_on[layer] = bool(d["cloud_on"].get(layer, true))
		if d.has("layer_style"):
			for layer in Backdrop.CLOUD_LAYERS:
				_layer_style[layer] = int(d["layer_style"].get(layer, 0))
		if d.has("layer_opacity"):
			for layer in Backdrop.CLOUD_LAYERS:
				_layer_opacity[layer] = float(d["layer_opacity"].get(layer, 1.0))
		if d.has("layer_color"):
			for layer in Backdrop.CLOUD_LAYERS:
				if d["layer_color"].has(layer):
					_layer_color[layer] = Color.from_string(String(d["layer_color"][layer]), _layer_color[layer])


func _copy_snippet() -> void:
	var pname: String = Backdrop.PRESET_NAMES[_preset]
	var t := "# Planet Flyover — tuned ground config.\n"
	t += "const GROUND_PRESET := \"%s\"  # surface_type %d\n" % [pname, int(Backdrop.PRESETS[pname]["type"])]
	t += "const GROUND_FLIGHT := %s        # screen-heights / second\n" % _fmt(_flight)
	t += "const GROUND_FEATURE_SCALE := %s # noise cells across the screen\n" % _fmt(_feature_scale)
	t += "const GROUND_LOOP_SIZE := %d      # tiling period (integer, seamless)\n" % _loop_size
	t += "const GROUND_OCTAVES := %d\n" % _octaves
	t += "const GROUND_RELIEF := %s\n" % _fmt(_relief)
	t += "const GROUND_RIVER_CUTOFF := %s  # water/lava/rock coverage\n" % _fmt(_river_cutoff)
	t += "const GROUND_SEED := %s\n" % _fmt(_rand_seed)
	t += "const GROUND_PIXELS := %s\n" % _fmt(_pixels)
	t += "const ATMOSPHERE := %s  # colour #%s, opacity %s\n" % [str(Backdrop.PRESETS[pname]["atmo"]), _atmo_color.to_html(false), _fmt(_atmo_opacity)]
	t += "const CLOUD_OPACITY := %s\n" % _fmt(_cloud_opacity)
	t += "const CLOUD_COVERAGE := %s\n" % _fmt(_cloud_coverage)
	t += "const SHIP_CLOUD_SHADOW := %s\n" % _fmt(_ship_shadow)
	t += "const NIGHT_DARKNESS := %s  # CanvasModulate lerp amount\n" % _fmt(_night_darkness)
	t += "const NIGHT_COLOR := \"#%s\"\n" % _night_color.to_html(false)
	for layer in Backdrop.CLOUD_LAYERS:
		t += "# %s: style=%s colour=#%s opacity=%s\n" % [layer, Backdrop.LAYER_STYLE_NAMES[int(_layer_style[layer])], (_layer_color[layer] as Color).to_html(false), _fmt(_layer_opacity[layer])]
	DisplayServer.clipboard_set(t)
	_set_status("Copied GDScript to clipboard.")


func _fmt(x) -> String:
	return "%.3f" % float(x)


func _on_close() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


# ---- Small helpers -------------------------------------------------------

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
	s.value_changed.connect(func(x):
		val_l.text = "%.2f" % x
		on_change.call(x))
	row.add_child(s)
	row.add_child(val_l)
	return row


func _set_status(msg: String) -> void:
	if _status:
		_status.text = msg
