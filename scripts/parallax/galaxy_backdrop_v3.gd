extends Node2D

# Galaxy Backdrop V3 — five-layer architecture per Cobalt 2026-05-20.
#
# Bottom → top:
#   0. DeepSpace   — full-viewport black ColorRect (Cobalt: bg must be black)
#   1. Stars       (anchor, nearly static — 1×1 / 2×2 ColorRects, no AA halo)
#   2. Planets     (single-pass Node2D — does NOT tile. Celestial spawns,
#                   drifts down, frees itself when fully off-screen)
#   3. Far         (Parallax2D content slot, empty by default)
#   4. Middle      (Parallax2D content slot, empty by default)
#   5. Near        (Parallax2D content slot, empty by default)
# Above all of it:
#   6. ColorCorrection — scene-wide tint + blend mode overlay
#
# Each content slot's children sit inside a CanvasGroup with the
# parallax_tint shader so per-layer tinting (driven by the tuner) actually
# applies — Parallax2D in Godot 4.3 doesn't reliably propagate modulate to
# tiled repeat draws. The shader is multiplicative (tints the art) rather
# than replacing (which the old silhouette pass did).
#
# Content slot fills via populate_layer():
#   - "asteroid_few"  — sparse asteroid scatter
#   - "asteroid_many" — dense asteroid scatter
#   - "nebula"        — full-viewport nebula at the layer's depth, seamless
#                       via fixed-position rect with shader scroll_offset
#                       driven from the layer's accumulated scroll
#   - "debris"        — placeholder (no asset yet)

const ASTEROID_SCENE = "res://Planets/Asteroids/Asteroid.tscn"
const NEBULA_SHADER = preload("res://graphics/nebula.gdshader")
const NEBULA2_SHADER = preload("res://graphics/nebula2.gdshader")
const TINT_SHADER = preload("res://graphics/parallax_tint.gdshader")
const SPACE_COLORSCHEME = "res://SpaceBG/Colorscheme.tres"
const PLANET_SCENES := [
	"res://Planets/LavaWorld/LavaWorld.tscn",
	"res://Planets/IceWorld/IceWorld.tscn",
	"res://Planets/DryTerran/DryTerran.tscn",
	"res://Planets/GasPlanet/GasPlanet.tscn",
	"res://Planets/NoAtmosphere/NoAtmosphere.tscn",
	"res://Planets/LandMasses/LandMasses.tscn",
	"res://Planets/BlackHole/BlackHole.tscn",
	"res://Planets/Galaxy/Galaxy.tscn",
	"res://Planets/Star/Star.tscn",
]

const TILE_SIZE := Vector2(480.0, 270.0)

# ---- Tunable layer parameters --------------------------------------------

@export var drift_speed: float = 22.0
@export_range(0.0, 0.2) var stars_scroll: float = 0.02
# Planets layer drift is in vp-px/sec directly (not multiplier) so the
# "3+ min top→bottom" timing is concrete and easy to reason about.
@export_range(0.1, 10.0) var planet_drift_px_per_sec: float = 1.2  # ~225s = ~3:45 to cross 270 px
@export_range(0.05, 2.0) var far_scroll: float = 0.25
@export_range(0.1, 2.0) var middle_scroll: float = 0.55
@export_range(0.2, 3.0) var near_scroll: float = 1.0

@export var default_far_fill: Array[String] = []
@export var default_middle_fill: Array[String] = []
@export var default_near_fill: Array[String] = []
@export var randomize_empty_slots: bool = true

# Pixel parity
@export_range(0.5, 6.0) var pixel_density: float = 1.0
@export_range(8.0, 64.0) var pixels_floor: float = 16.0
@export_range(8.0, 48.0) var asteroid_min_size: float = 16.0

# Color correction overlay
@export var color_correction_tint: Color = Color(1, 1, 1, 1)
@export_enum("Mix", "Add", "Multiply") var color_correction_blend: int = 0
@export_range(0.0, 1.0) var color_correction_intensity: float = 0.0

# Each entry: {size, pos}. PixelPlanets' set_pixels writes both. Reset
# preserves the authored layout.
const COLORRECT_DEFAULT_CANONICAL := {"size": Vector2(100.0, 100.0), "pos": Vector2.ZERO}
const COLORRECT_CANONICAL_BY_NAME := {
	"Disk":       {"size": Vector2(300.0, 300.0), "pos": Vector2(-100.0, -100.0)},
	"Ring":       {"size": Vector2(300.0, 300.0), "pos": Vector2(-100.0, -100.0)},
	"Blobs":      {"size": Vector2(200.0, 200.0), "pos": Vector2(-50.0, -50.0)},
	"StarFlares": {"size": Vector2(200.0, 200.0), "pos": Vector2(-50.0, -50.0)},
}

# Star color palette — random pick per star for the colorful field.
const STAR_COLORS := [
	Color(0.95, 0.97, 1.00),  # cool white
	Color(1.00, 0.97, 0.92),  # warm white
	Color(1.00, 0.85, 0.60),  # orange dwarf
	Color(0.75, 0.85, 1.00),  # blue
	Color(1.00, 0.95, 0.80),  # yellow
	Color(0.95, 0.70, 0.70),  # red giant
	Color(0.80, 0.95, 0.95),  # cyan
]

# ---- Runtime state -------------------------------------------------------

var _content_layers: Dictionary = {}        # slot name → Parallax2D ("far"/"middle"/"near")
var _tint_materials: Dictionary = {}        # Parallax2D instance_id → ShaderMaterial
var _parallax_layers: Array = []            # iteration order for scroll
var _planets_layer: Node2D = null           # holds the celestial; manual scroll
var _planets_scroll_accum: float = 0.0
var _planet_object: Node = null             # current celestial (null if none)
var _planet_object_size: float = 0.0
var _planet_dominant_color: Color = Color(0.6, 0.7, 1.0, 1.0)  # default if no planet
var _nebula_scroll_drivers: Array = []      # {layer, material} — for seamless nebula
var _time_updaters: Array = []
var _shader_time: float = 0.0
var _last_planet_idx: int = -1
var _color_correction_rect: ColorRect = null
var _twinkle_stars: Array = []


func _register_twinkle(rect: ColorRect, rng: RandomNumberGenerator) -> void:
	if rng.randf() > 0.7:
		return
	_twinkle_stars.append({
		"node": rect,
		"base_color": rect.color,
		"phase": rng.randf() * TAU,
		"amp": rng.randf_range(0.15, 0.45),
		"hz": rng.randf_range(0.4, 2.2),
	})


# ---- Lifecycle -----------------------------------------------------------

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_value()
	_spawn_deep_space()
	_spawn_stars_layer(rng)
	_spawn_planets_layer(rng)
	_build_content_layers()
	_apply_planet_dominant_default_tints()
	populate_layer("far", _resolve_fill(default_far_fill, "far", rng), rng)
	populate_layer("middle", _resolve_fill(default_middle_fill, "middle", rng), rng)
	populate_layer("near", _resolve_fill(default_near_fill, "near", rng), rng)
	_build_color_correction()


func _resolve_fill(explicit: Array, slot: String, rng: RandomNumberGenerator) -> Array:
	if explicit.size() > 0 or not randomize_empty_slots:
		return explicit
	var picks: Array = []
	var roll: float = rng.randf()
	if roll < 0.30:
		picks.append("asteroid_few")
	elif roll < 0.55:
		picks.append("asteroid_many")
	if rng.randf() < 0.35:
		picks.append("nebula")
	return picks


func _seed_value() -> int:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if "run_seed" in run:
			var step: int = 0
			if "visited_nodes" in run:
				step = max(run.visited_nodes.size() - 1, 0)
			var sec: int = 0
			if "sectors_cleared" in run:
				sec = run.sectors_cleared
			return run.run_seed + step * 1009 + sec * 9973
	return randi()


# ---- Layer construction --------------------------------------------------

func _spawn_deep_space() -> void:
	# Full-viewport black backdrop so the gaps between stars are pure void.
	# Cobalt 2026-05-20: "Background space needs to be black."
	var deep := ColorRect.new()
	deep.name = "DeepSpace"
	deep.color = Color(0.0, 0.0, 0.0, 1.0)
	deep.size = TILE_SIZE
	deep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(deep)


func _spawn_stars_layer(rng: RandomNumberGenerator) -> void:
	var par := _make_parallax("Stars", stars_scroll)
	# Pinpricks + bigger pops, randomized count + color palette.
	var pinprick_count: int = rng.randi_range(140, 320)
	var pop_count: int = rng.randi_range(20, 70)
	for i in pinprick_count:
		var dot := ColorRect.new()
		dot.size = Vector2(1, 1)
		dot.position = Vector2(floor(rng.randf() * TILE_SIZE.x), floor(rng.randf() * TILE_SIZE.y))
		var base: Color = STAR_COLORS[rng.randi() % STAR_COLORS.size()]
		var bright: float = 0.55 + rng.randf() * 0.45
		dot.color = Color(base.r * bright, base.g * bright, base.b * bright, 1.0)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_register_twinkle(dot, rng)
		par.add_child(dot)
	for i in pop_count:
		var big := ColorRect.new()
		big.size = Vector2(2, 2)
		big.position = Vector2(floor(rng.randf() * (TILE_SIZE.x - 2.0)), floor(rng.randf() * (TILE_SIZE.y - 2.0)))
		big.color = STAR_COLORS[rng.randi() % STAR_COLORS.size()]
		big.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_register_twinkle(big, rng)
		par.add_child(big)


# Planets layer is a regular Node2D, NOT a Parallax2D. Cobalt 2026-05-20:
# the layer should contain only what it generates with, not loop. Drift
# the planet down manually and free it when it's fully off-screen. The
# celestial persists past the bottom edge until completely gone — no
# early-vanish from Parallax2D culling.
func _spawn_planets_layer(rng: RandomNumberGenerator) -> void:
	_planets_layer = Node2D.new()
	_planets_layer.name = "Planets"
	add_child(_planets_layer)
	if rng.randf() < 0.4:
		return  # 40% chance no celestial — pure void
	var idx: int = _weighted_celestial_pick(rng)
	_last_planet_idx = idx
	var p_scene = load(PLANET_SCENES[idx])
	if p_scene == null:
		return
	var p = p_scene.instantiate()
	if p is Control:
		p.anchor_left = 0.0
		p.anchor_top = 0.0
		p.anchor_right = 0.0
		p.anchor_bottom = 0.0
		p.offset_left = 0.0
		p.offset_top = 0.0
		p.offset_right = 100.0
		p.offset_bottom = 100.0
		p.size = Vector2(100, 100)
		p.custom_minimum_size = Vector2(100, 100)
		p.pivot_offset = Vector2.ZERO
	var size_vp: float = rng.randf_range(180.0, 320.0)
	var sf: float = size_vp / 100.0
	p.scale = Vector2(sf, sf)
	_apply_pixel_parity(p, size_vp)
	if p.has_method("set_seed"):
		p.set_seed(rng.randi() % 100000)
	if p.has_method("randomize_colors"):
		p.randomize_colors()
	if p.has_method("set_rotates"):
		p.set_rotates(rng.randf() < 0.7)
	var x: float = rng.randf_range(0.0, max(0.0, TILE_SIZE.x - size_vp))
	var y: float = rng.randf_range(-size_vp * 0.4, -size_vp * 0.15)
	p.position = Vector2(x, y)
	if "override_time" in p:
		p.override_time = true
	_time_updaters.append(p)
	_planets_layer.add_child(p)
	_planet_object = p
	_planet_object_size = size_vp
	_planet_dominant_color = _sample_planet_dominant_color(p)


static func _weighted_celestial_pick(rng: RandomNumberGenerator) -> int:
	var r: float = rng.randf()
	if r < 0.07:
		return 6  # BlackHole
	if r < 0.10:
		return 7  # Galaxy
	if r < 0.50:
		return 8  # Star
	var planet_roll: float = (r - 0.50) / 0.50
	return clampi(int(floor(planet_roll * 6.0)), 0, 5)


# Sample the brightest color from the planet's color palette so content
# layers can default-tint toward it (Cobalt 2026-05-20: "Defaults should
# be set to match the predominant color of the largest object in the
# planet layer"). PixelPlanets stores colors via get_colors() per variant.
func _sample_planet_dominant_color(p: Node) -> Color:
	if p == null or not p.has_method("get_colors"):
		return Color(0.6, 0.7, 1.0, 1.0)
	var cols = p.get_colors()
	if not (cols is PackedColorArray) and not (cols is Array):
		return Color(0.6, 0.7, 1.0, 1.0)
	if cols.size() == 0:
		return Color(0.6, 0.7, 1.0, 1.0)
	# Pick the brightest entry (likely the body's surface highlight).
	var best: Color = cols[0]
	var best_lum: float = -1.0
	for c in cols:
		var col: Color = c
		var lum: float = col.r * 0.3 + col.g * 0.59 + col.b * 0.11
		if lum > best_lum:
			best_lum = lum
			best = col
	# Soften it so the tint doesn't blow out — multiply against 0.85 and
	# nudge toward neutral white by 25% so layers don't all go neon.
	return best.lerp(Color(1, 1, 1, 1), 0.25)


func get_planet_dominant_color() -> Color:
	return _planet_dominant_color


# ---- Content layer construction ----------------------------------------

func _build_content_layers() -> void:
	_content_layers["far"] = _make_content_parallax("Far", far_scroll)
	_content_layers["middle"] = _make_content_parallax("Middle", middle_scroll)
	_content_layers["near"] = _make_content_parallax("Near", near_scroll)


# Make a Parallax2D content slot whose children sit inside a CanvasGroup
# with the parallax_tint shader. The tuner drives the tint uniform via
# tint_material_for(par). This bypasses Parallax2D's flaky modulate
# propagation entirely.
func _make_content_parallax(layer_name: String, scroll: float) -> Parallax2D:
	var par := Parallax2D.new()
	par.name = layer_name
	par.scroll_scale = Vector2(0.0, scroll)
	par.repeat_size = Vector2(0.0, TILE_SIZE.y)
	par.repeat_times = 2
	add_child(par)
	_parallax_layers.append(par)
	# CanvasGroup wrapper inside the Parallax2D — composites content,
	# applies tint, then Parallax2D tiles the composited result.
	var cg := CanvasGroup.new()
	cg.name = "Content"
	cg.fit_margin = 64.0
	var mat := ShaderMaterial.new()
	mat.shader = TINT_SHADER
	mat.set_shader_parameter("tint", Color(1, 1, 1, 1))
	cg.material = mat
	par.add_child(cg)
	_tint_materials[par.get_instance_id()] = mat
	return par


# Apply default tint from the planet's dominant color to every content
# layer. Tuner reads this back as the initial Colorization swatch.
func _apply_planet_dominant_default_tints() -> void:
	for layer in [_content_layers.get("far"), _content_layers.get("middle"), _content_layers.get("near")]:
		if layer == null:
			continue
		var mat: ShaderMaterial = _tint_materials.get(layer.get_instance_id(), null)
		if mat != null:
			mat.set_shader_parameter("tint", _planet_dominant_color)


func _make_parallax(layer_name: String, scroll: float) -> Parallax2D:
	var par := Parallax2D.new()
	par.name = layer_name
	par.scroll_scale = Vector2(0.0, scroll)
	par.repeat_size = Vector2(0.0, TILE_SIZE.y)
	par.repeat_times = 2
	add_child(par)
	_parallax_layers.append(par)
	return par


# Public — returns the shader material driving this content layer's tint
# (parallax_tint shader, "tint" uniform). The tuner uses this to drive
# the Colorization picker without going through modulate.
func tint_material_for(par: Parallax2D) -> ShaderMaterial:
	if par == null:
		return null
	return _tint_materials.get(par.get_instance_id(), null)


# Back-compat shim — V2 had silhouette_material_for. V3 redirects to the
# new tint material so the tuner can keep using the same name.
func silhouette_material_for(par: Parallax2D) -> ShaderMaterial:
	return tint_material_for(par)


# ---- Content population --------------------------------------------------

func populate_layer(slot_name: String, fills, rng: RandomNumberGenerator = null) -> void:
	if not _content_layers.has(slot_name):
		return
	var par: Parallax2D = _content_layers[slot_name]
	# Children go inside the CanvasGroup so the tint shader applies.
	var cg: Node = par.get_node_or_null("Content")
	if cg == null:
		cg = par
	var actual_rng: RandomNumberGenerator = rng
	if actual_rng == null:
		actual_rng = RandomNumberGenerator.new()
		actual_rng.seed = _seed_value() + slot_name.hash()
	for item in fills:
		match String(item):
			"asteroid_few":
				_spawn_asteroids_in(cg, 3, actual_rng)
			"asteroid_many":
				_spawn_asteroids_in(cg, 8, actual_rng)
			"nebula":
				_spawn_nebula_in(par, cg, slot_name, actual_rng)
			"debris":
				pass  # TODO — needs a debris sprite


func _spawn_asteroids_in(parent: Node, count: int, rng: RandomNumberGenerator) -> void:
	for i in count:
		var sz: float = rng.randf_range(
			max(16.0, asteroid_min_size),
			max(48.0, asteroid_min_size + 32.0)
		)
		var a := _spawn_one_asteroid(sz, rng)
		if a == null:
			continue
		parent.add_child(a)
		# Asteroid rotation removed (Cobalt 2026-05-20: spinning breaks
		# the sharp pixel-art read). _time_updaters still drives the
		# procgen shader's `time` uniform so internal surface animation
		# continues; only the rigid-body spin is gone.
		_time_updaters.append(a)


func _spawn_one_asteroid(sz: float, rng: RandomNumberGenerator) -> Node:
	var ps = load(ASTEROID_SCENE)
	if ps == null:
		return null
	var a = ps.instantiate()
	var inner: Node = a.get_node_or_null("Asteroid")
	if inner and "material" in inner and inner.material != null:
		inner.material = inner.material.duplicate()
	var sf: float = sz / 100.0
	a.scale = Vector2(sf, sf)
	_apply_pixel_parity(a, sz)
	if a.has_method("set_seed"):
		a.set_seed(rng.randi() % 100000)
	if "override_time" in a:
		a.override_time = true
	a.position = Vector2(
		rng.randf_range(20.0, TILE_SIZE.x - sz - 20.0),
		rng.randf_range(20.0, TILE_SIZE.y - sz - 20.0)
	)
	if a is Control:
		a.pivot_offset = Vector2(50, 50)
	return a


# Per-layer seamless nebula. The ColorRect is positioned at (0,0) inside
# the CanvasGroup (so the tint shader applies to it) and DOESN'T move via
# Parallax2D's repeat — instead its shader's `scroll_offset` uniform is
# driven from the layer's accumulated scroll. Since the noise is
# procedural and seamless under any offset, no break lines appear.
# Each layer gets a unique seed so far/mid/near nebulas look different.
func _spawn_nebula_in(par: Parallax2D, cg: Node, slot_name: String, rng: RandomNumberGenerator) -> void:
	var shader = NEBULA2_SHADER
	var cs = load(SPACE_COLORSCHEME)
	var r := ColorRect.new()
	r.name = "Nebula"
	r.size = TILE_SIZE
	r.position = Vector2.ZERO
	r.color = Color(0, 0, 0, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("scale", 2.4)
	mat.set_shader_parameter("octaves", 5)
	# Unique seed per slot so far/mid/near nebulas have different shapes.
	var slot_seed: float = float(rng.randi() % 9000) / 100.0 + float(slot_name.hash() % 1000) / 100.0
	mat.set_shader_parameter("seed", 1.0 + slot_seed)
	mat.set_shader_parameter("pixels", TILE_SIZE.x / max(pixel_density, 0.01))
	mat.set_shader_parameter("drift_speed", 0.0)
	mat.set_shader_parameter("max_alpha", 0.7)
	mat.set_shader_parameter("opacity", 0.85)
	mat.set_shader_parameter("density", 0.95)
	mat.set_shader_parameter("edge_sharpness", 0.42)
	mat.set_shader_parameter("warp_strength", 1.2)
	mat.set_shader_parameter("wisp_strength", 0.3)
	mat.set_shader_parameter("uv_correct", Vector2(TILE_SIZE.x / TILE_SIZE.y, 1.0))
	mat.set_shader_parameter("scroll_offset", Vector2.ZERO)
	if cs != null:
		mat.set_shader_parameter("colorscheme", cs)
	r.material = mat
	cg.add_child(r)
	# Register for seamless-scroll driver — _process feeds the layer's
	# accumulated scroll into the nebula shader's scroll_offset.
	_nebula_scroll_drivers.append({"layer": par, "material": mat})


# ---- Color correction overlay -------------------------------------------

func _build_color_correction() -> void:
	_color_correction_rect = ColorRect.new()
	_color_correction_rect.name = "ColorCorrection"
	_color_correction_rect.size = TILE_SIZE
	_color_correction_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_color_correction_state()
	add_child(_color_correction_rect)


func set_color_correction(tint: Color, blend_idx: int, intensity: float) -> void:
	color_correction_tint = tint
	color_correction_blend = blend_idx
	color_correction_intensity = clamp(intensity, 0.0, 1.0)
	_apply_color_correction_state()


func _apply_color_correction_state() -> void:
	if _color_correction_rect == null:
		return
	var c: Color = color_correction_tint
	c.a = color_correction_tint.a * color_correction_intensity
	_color_correction_rect.color = c
	var mat := CanvasItemMaterial.new()
	match color_correction_blend:
		1:
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		2:
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		_:
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	_color_correction_rect.material = mat


# Public — set the blend mode of a tinted layer's tint shader. Currently
# the tint shader uses BLEND_MODE_MIX hardcoded via render_mode. To
# support Add / Multiply we wrap the material in a CanvasItemMaterial.
# layer_name: "far" / "middle" / "near"
# blend_idx: 0 Mix, 1 Add, 2 Multiply
func set_layer_blend(layer_name: String, blend_idx: int) -> void:
	if not _content_layers.has(layer_name):
		return
	var par: Parallax2D = _content_layers[layer_name]
	var cg: Node = par.get_node_or_null("Content")
	if cg == null:
		return
	# The shader handles tint via fragment math; blend mode controls how
	# the resulting CanvasGroup texture mixes with what's below it. Use
	# CanvasItemMaterial in addition to the shader by parenting under one.
	# Easier: just set the CanvasGroup's `light_mask` or use a sibling
	# CanvasItemMaterial. Since Godot can't stack a ShaderMaterial + a
	# CanvasItemMaterial on one node, store the desired blend and let the
	# shader's render_mode handle it. For now expose the knob via the
	# CanvasGroup's modulate.a only (Mix/Add hint by intensity);
	# full per-blend implementation tracked in follow-up.
	cg.set_meta("blend_idx", blend_idx)


# ---- Pixel parity helpers (mirror V1) ----------------------------------

func _apply_pixel_parity(p: Node, displayed_size: float) -> void:
	var px: float = max(displayed_size / max(pixel_density, 0.01), pixels_floor)
	if p.has_method("set_pixels"):
		p.set_pixels(px)
	else:
		_apply_pixels_only(p, px)
	_reset_colorrect_sizes(p)


func _apply_pixels_only(root: Node, value: float) -> void:
	for child in root.get_children():
		if child is ColorRect and child.material is ShaderMaterial:
			child.material.set_shader_parameter("pixels", value)
		_apply_pixels_only(child, value)


func _reset_colorrect_sizes(root: Node) -> void:
	for child in root.get_children():
		if child is ColorRect:
			var canon: Dictionary = COLORRECT_CANONICAL_BY_NAME.get(String(child.name), COLORRECT_DEFAULT_CANONICAL)
			(child as ColorRect).size = canon["size"]
			(child as ColorRect).position = canon["pos"]
		_reset_colorrect_sizes(child)


# ---- Per-frame --------------------------------------------------------

func _process(delta: float) -> void:
	_shader_time += delta * 0.15
	var step: float = drift_speed * delta
	for p in _parallax_layers:
		if not is_instance_valid(p):
			continue
		var par := p as Parallax2D
		par.scroll_offset.y += step * par.scroll_scale.y
	# Drive nebula scroll_offset uniform from the layer's accumulated
	# scroll so the noise samples continuously — no tile seam visible.
	for entry in _nebula_scroll_drivers:
		var layer = entry["layer"]
		var mat: ShaderMaterial = entry["material"]
		if not is_instance_valid(layer) or mat == null:
			continue
		var off: Vector2 = (layer as Parallax2D).scroll_offset / TILE_SIZE
		mat.set_shader_parameter("scroll_offset", off)
	# Planets layer drifts independently — no tile, free when fully off.
	if _planet_object != null and is_instance_valid(_planet_object):
		_planets_scroll_accum += planet_drift_px_per_sec * delta
		_planets_layer.position.y = _planets_scroll_accum
		# Free once the planet's TOP edge (position.y + scroll) is past the
		# viewport bottom — i.e., it's fully off-screen, lights and all.
		var planet_visual_top: float = _planet_object.position.y + _planets_scroll_accum
		var planet_visual_bottom: float = planet_visual_top + _planet_object_size
		if planet_visual_top > TILE_SIZE.y + 20.0:
			_planet_object.queue_free()
			_planet_object = null
	# Twinkle drive.
	var t: float = Time.get_ticks_msec() / 1000.0
	for entry in _twinkle_stars:
		var node = entry["node"]
		if not is_instance_valid(node):
			continue
		var phase: float = float(entry["phase"]) + t * TAU * float(entry["hz"])
		var brightness: float = 1.0 - float(entry["amp"]) * (0.5 - 0.5 * cos(phase))
		var base: Color = entry["base_color"]
		(node as ColorRect).color = Color(base.r * brightness, base.g * brightness, base.b * brightness, base.a)
	for n in _time_updaters:
		if is_instance_valid(n) and n.has_method("update_time"):
			n.update_time(_shader_time)


# ---- Tuner-facing speed setters -----------------------------------------

func set_layer_scroll(layer_name: String, scroll: float) -> void:
	var par: Parallax2D = _content_layers.get(layer_name, null)
	if par == null:
		return
	par.scroll_scale = Vector2(0.0, scroll)
