extends Control

# Asteroid HDR Lab (Roman 2026-06-24) — verification bench for the asteroid-over-HDR-bright fix.
# A single HDR-2D play space (the real combat setup) with a bloom-bright planet + drifting
# gameplay-style asteroids + HDR-bright bullets. The asteroids USED to crush to black over the
# bright planet; the fix is in `Planets/Asteroids/Asteroids.gdshader` (opaque-or-discard instead of
# writing alpha-0 fragments — alpha-0 canvas pixels crush their opaque pixels over >1 content in
# use_hdr_2d; sprites/ColorRects don't). Crank Planet glow / pick BlackHole or Galaxy to stress it.
# See docs/asteroid_hdr_darkening_2026-06-23.md.

const HdScreen = preload("res://scripts/ui/hd_screen.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const LayerPlanetScene = preload("res://scenes/parallax/layers/layer_planet.tscn")
const LayerPlanetC = preload("res://scripts/parallax/layer_planet.gd")
const PlanetGlowC = preload("res://scripts/effects/planet_glow_config.gd")
const ASTEROID_SCENE := "res://Planets/Asteroids/Asteroid.tscn"

const PLANET_NAMES := ["LavaWorld", "IceWorld", "DryTerran", "GasPlanet", "NoAtmosphere", "LandMasses", "BlackHole", "Galaxy", "Star", "GasPlanetLayers", "Rivers"]
const VP := Vector2i(480, 270)
const PLANET_SIZE := 150.0
const DRIFT := 42.0
const ROCK_COUNT := 6

var _hd_scope = null
var _rng := RandomNumberGenerator.new()
var _planet_idx := 5
var _glow_mult := 1.75
var _vp: SubViewport = null
var _planet: Node = null
var _gameplay: Node2D = null
var _rocks: Array = []   # [{x,y,size,seed,spin,rot,node}]


func _ready() -> void:
	_rng.seed = 7
	PlanetGlowC.ensure_loaded()
	if get_parent() == get_tree().root:
		_hd_scope = HdViewportScope.attach(self)
	_build_ui()
	_rebuild()
	await get_tree().process_frame
	HdScreen.verify_native_subviewport(_vp, "Asteroid HDR Lab")


func _new_env_node() -> WorldEnvironment:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_strength = 0.75
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.5
	we.environment = env
	return we


func _spawn_planet() -> void:
	var lp = LayerPlanetScene.instantiate()
	_vp.add_child(lp)
	var prng := RandomNumberGenerator.new()
	prng.seed = 4242
	lp.spawn_planet(_planet_idx, PLANET_SIZE, prng, "", 4242, Color.WHITE)
	_planet = lp.get("_planet_node")
	if _planet != null and is_instance_valid(_planet):
		_planet.position = Vector2(VP) * 0.5 - Vector2(PLANET_SIZE, PLANET_SIZE) * 0.5
		LayerPlanetC.apply_palette_glow(_planet, _glow_mult)


func _make_rock(size: float, seed_i: int) -> Node:
	var v = load(ASTEROID_SCENE).instantiate()
	var inner = v.get_node_or_null("Asteroid")
	if inner != null and "material" in inner and inner.material != null:
		inner.material = inner.material.duplicate()
	if v.has_method("set_seed"):
		v.set_seed(seed_i)
	if v is Control:
		v.custom_minimum_size = Vector2(size, size)
		v.size = Vector2(size, size)
		v.pivot_offset = Vector2(size, size) * 0.5
	var base := Color(0.70, 0.66, 0.60)
	base = base * (0.82 / maxf(base.r, 0.01))
	if v.has_method("set_colors"):
		v.set_colors(PackedColorArray([base.lightened(0.22), base, base.darkened(0.4)]))
	if inner != null and "material" in inner and inner.material != null:
		inner.material.set_shader_parameter("roundness", 0.7)
		inner.material.set_shader_parameter("should_dither", false)
	if v.has_method("set_pixels"):
		v.set_pixels(size)
	return v


func _rebuild() -> void:
	if _vp != null and is_instance_valid(_vp):
		_vp.queue_free()
	_rocks.clear()
	_planet = null

	var sub := SubViewportContainer.new()
	sub.stretch = true
	sub.stretch_shrink = 2
	sub.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.position = Vector2(160, 90)
	sub.size = Vector2(1600, 900)
	add_child(sub)
	_vp = SubViewport.new()
	_vp.size = VP
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.handle_input_locally = false
	_vp.use_hdr_2d = true
	sub.add_child(_vp)
	_vp.add_child(_new_env_node())
	_spawn_planet()
	_gameplay = Node2D.new()
	_vp.add_child(_gameplay)
	for x in [150.0, 240.0, 330.0]:   # HDR-bright bullets
		var b := ColorRect.new()
		b.color = Color(2.0, 2.0, 2.2, 1.0)
		b.size = Vector2(5, 13)
		b.position = Vector2(x - 2.5, 150.0)
		_gameplay.add_child(b)
	for i in ROCK_COUNT:
		var size := _rng.randf_range(44.0, 60.0)
		var seed_i := _rng.randi()
		var node := _make_rock(size, seed_i)
		_gameplay.add_child(node)
		_rocks.append({
			"x": _rng.randf_range(120.0, 360.0), "y": _rng.randf_range(-60.0, 240.0),
			"size": size, "spin": _rng.randf_range(-0.6, 0.6), "rot": 0.0, "node": node,
		})


func _process(delta: float) -> void:
	for r in _rocks:
		r["y"] += DRIFT * delta
		if r["y"] > float(VP.y) + r["size"]:
			r["y"] = -r["size"]
		r["rot"] += r["spin"] * delta
		var n = r["node"]
		if is_instance_valid(n):
			n.position = Vector2(r["x"], r["y"]) - Vector2(r["size"], r["size"]) * 0.5
			n.rotation = r["rot"]


func _reapply_glow() -> void:
	if _planet != null and is_instance_valid(_planet):
		LayerPlanetC.apply_palette_glow(_planet, _glow_mult)


# ---- UI ---------------------------------------------------------------------

func _build_ui() -> void:
	var title := Label.new()
	title.text = "ASTEROID HDR LAB"
	title.position = Vector2(24, 16)
	title.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_HEADER)
	title.add_theme_color_override("font_color", Color(0.82, 0.90, 1.0))
	add_child(title)

	var bar := HBoxContainer.new()
	bar.position = Vector2(160, 40)
	bar.add_theme_constant_override("separation", 16)
	add_child(bar)

	var pl := Label.new(); pl.text = "Planet"; _cap(pl); bar.add_child(pl)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(220, 34)
	for n in PLANET_NAMES:
		picker.add_item(n)
	picker.select(_planet_idx)
	picker.item_selected.connect(func(i: int): _planet_idx = i; _rebuild())
	bar.add_child(picker)

	var gl := Label.new(); gl.text = "Planet glow x"; _cap(gl); bar.add_child(gl)
	var slider := HSlider.new()
	slider.min_value = 1.0; slider.max_value = 3.0; slider.step = 0.05; slider.value = _glow_mult
	slider.custom_minimum_size = Vector2(320, 30)
	bar.add_child(slider)
	var val := Label.new()
	val.text = "%.2f" % _glow_mult
	val.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	val.custom_minimum_size = Vector2(48, 0)
	bar.add_child(val)
	slider.value_changed.connect(func(v: float):
		_glow_mult = v
		val.text = "%.2f" % v
		_reapply_glow())

	var back := Button.new()
	back.text = "Back"; back.custom_minimum_size = Vector2(90, 34)
	back.pressed.connect(_on_back)
	bar.add_child(back)

	var note := Label.new()
	note.text = "Gameplay-style asteroids drift over a bloom-bright planet + 3 HDR bullets, in ONE HDR-2D viewport (the real play space). With the shader fix they render clean; bullets keep their glow. Crank Planet glow / pick BlackHole or Galaxy to stress it."
	note.position = Vector2(160, 1000)
	note.size = Vector2(1600, 0)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cap(note)
	add_child(note)


func _cap(l: Label) -> void:
	l.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 0.85))


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()
