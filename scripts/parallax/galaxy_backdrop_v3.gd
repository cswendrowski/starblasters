extends Node2D

# Galaxy Backdrop V3 — five-layer architecture per Cobalt 2026-05-20.
#
# Bottom → top:
#   1. Stars       (anchor, nearly static — 1×1 / 2×2 ColorRects, no AA)
#   2. Planets     (anchor, very slow drift — ~4 min top→bottom)
#   3. Far         (content slot, empty by default)
#   4. Middle      (content slot, empty by default)
#   5. Near        (content slot, empty by default)
# Above all of it:
#   6. ColorCorrection — scene-wide tint + blend mode overlay
#
# Content slots accept a list of "fills" passed via populate_layer():
#   - "asteroid_few"  — sparse asteroid scatter
#   - "asteroid_many" — dense asteroid scatter
#   - "nebula"        — full-tile nebula at this layer's speed
#   - "debris"        — placeholder for ship-debris asset (no-op for now)
# The slot's scroll speed is layer-defined; content type doesn't pick its
# own depth. Same asteroid spawner can land in Far, Middle, or Near with
# the layer driving how fast it goes by.
#
# Pixel parity (1:1 with player) is enforced everywhere — see
# _apply_pixel_parity. Stars use ColorRects so the pixel grid is exact
# by construction (no AA halo around big stars).

const ASTEROID_SCENE = "res://Planets/Asteroids/Asteroid.tscn"
const NEBULA_SHADER = "res://graphics/nebula.gdshader"
const NEBULA2_SHADER = "res://graphics/nebula2.gdshader"
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

# Viewport-matched tile so a single tile fills the playfield and
# Parallax2D wraps cleanly on every screen of scroll.
const TILE_SIZE := Vector2(480.0, 270.0)

# ---- Tunable layer parameters --------------------------------------------

@export var drift_speed: float = 22.0
# Stars: nearly static — a hair of motion to sell depth.
@export_range(0.0, 0.2) var stars_scroll: float = 0.02
# Planets: ~4 min top→bottom at default drift (0.05 × 22 px/s ≈ 1.1 px/s →
# 270 / 1.1 ≈ 245s ≈ 4 min). Cobalt called for 3+ min, sitting comfortably above.
@export_range(0.0, 0.2) var planets_scroll: float = 0.05
@export_range(0.05, 1.0) var far_scroll: float = 0.25
@export_range(0.1, 1.5) var middle_scroll: float = 0.55
@export_range(0.2, 2.0) var near_scroll: float = 1.0

# Default slot fills — overridable via populate_layer() at runtime so
# different sectors / hazards can stuff different content in the same
# slot. By default Far + Middle are empty (pure void); Near gets a
# sparse asteroid scatter so the tuner has something to look at.
@export var default_far_fill: Array[String] = []
@export var default_middle_fill: Array[String] = []
@export var default_near_fill: Array[String] = ["asteroid_few"]

# ---- Pixel parity (matches galaxy_backdrop.gd V1) ------------------------

@export_range(0.5, 6.0) var pixel_density: float = 1.0
@export_range(8.0, 64.0) var pixels_floor: float = 16.0
@export_range(8.0, 48.0) var asteroid_min_size: float = 16.0

# ---- Color correction overlay --------------------------------------------

@export var color_correction_tint: Color = Color(1, 1, 1, 1)
# 0 = Mix (alpha-tint), 1 = Add, 2 = Multiply
@export_enum("Mix", "Add", "Multiply") var color_correction_blend: int = 0
@export_range(0.0, 1.0) var color_correction_intensity: float = 0.0

const COLORRECT_DEFAULT_CANONICAL := Vector2(100.0, 100.0)
const COLORRECT_CANONICAL_BY_NAME := {
	"Disk": Vector2(300.0, 300.0),
	"Ring": Vector2(300.0, 300.0),
}

# ---- Runtime state -------------------------------------------------------

var _layers: Dictionary = {}             # slot name → Parallax2D
var _parallax_layers: Array = []         # iteration order for scroll
var _spinning: Array = []                # {node, spin}
var _time_updaters: Array = []           # asteroid Controls + planets w/ update_time
var _shader_time: float = 0.0
var _last_planet_idx: int = -1
var _color_correction_rect: ColorRect = null


# ---- Lifecycle -----------------------------------------------------------

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_value()
	_build_layers(rng)
	populate_layer("far", default_far_fill, rng)
	populate_layer("middle", default_middle_fill, rng)
	populate_layer("near", default_near_fill, rng)
	_build_color_correction()


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

func _build_layers(rng: RandomNumberGenerator) -> void:
	_spawn_stars_layer(rng)
	_spawn_planets_layer(rng)
	_layers["far"] = _make_parallax("Far", far_scroll)
	_layers["middle"] = _make_parallax("Middle", middle_scroll)
	_layers["near"] = _make_parallax("Near", near_scroll)


# Pixel-perfect ColorRect starfield. Two populations: dense 1×1
# pinpricks (small distant stars) + sparse 2×2 brighter pops (closer or
# bigger stars). No anti-aliasing, no shader — every star sits on the
# viewport pixel grid by construction.
func _spawn_stars_layer(rng: RandomNumberGenerator) -> void:
	var par := _make_parallax("Stars", stars_scroll)
	_layers["stars"] = par
	# Pinpricks
	for i in 220:
		var dot := ColorRect.new()
		dot.size = Vector2(1, 1)
		dot.position = Vector2(
			floor(rng.randf() * TILE_SIZE.x),
			floor(rng.randf() * TILE_SIZE.y)
		)
		var bright: float = 0.55 + rng.randf() * 0.45
		dot.color = Color(bright * 0.95, bright * 0.97, bright * 1.0, 1.0)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		par.add_child(dot)
	# Bigger pops
	for i in 40:
		var big := ColorRect.new()
		big.size = Vector2(2, 2)
		big.position = Vector2(
			floor(rng.randf() * (TILE_SIZE.x - 2.0)),
			floor(rng.randf() * (TILE_SIZE.y - 2.0))
		)
		# Mix warm + cool stars for variety.
		var col: Color
		if rng.randf() < 0.5:
			col = Color(1.00, 0.97, 0.92, 1.0)
		else:
			col = Color(0.92, 0.95, 1.00, 1.0)
		big.color = col
		big.mouse_filter = Control.MOUSE_FILTER_IGNORE
		par.add_child(big)


# Planets layer: 60% chance to spawn one celestial body. Weighted pick
# matches V1's distribution (mostly planets/stars, rare BlackHole/Galaxy).
func _spawn_planets_layer(rng: RandomNumberGenerator) -> void:
	var par := _make_parallax("Planets", planets_scroll)
	_layers["planets"] = par
	if rng.randf() < 0.4:
		return  # Pure deep-space level
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
	# Position so the body peeks from the top edge — feels distant and
	# anchors the scene without dominating the playfield.
	var x: float = rng.randf_range(0.0, max(0.0, TILE_SIZE.x - size_vp))
	var y: float = rng.randf_range(-size_vp * 0.4, -size_vp * 0.15)
	p.position = Vector2(x, y)
	if "override_time" in p:
		p.override_time = true
	_time_updaters.append(p)
	par.add_child(p)


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


func _make_parallax(layer_name: String, scroll: float) -> Parallax2D:
	var par := Parallax2D.new()
	par.name = layer_name
	par.scroll_scale = Vector2(0.0, scroll)
	par.repeat_size = Vector2(0.0, TILE_SIZE.y)
	par.repeat_times = 2
	add_child(par)
	_parallax_layers.append(par)
	return par


# ---- Content slot population --------------------------------------------

# Public API. `slot_name` is "far" | "middle" | "near".
# `fills` is an Array of strings naming content types (see header doc).
# Pass an `rng` for deterministic seeding; nil means derive from Run seed.
func populate_layer(slot_name: String, fills, rng: RandomNumberGenerator = null) -> void:
	if not _layers.has(slot_name):
		return
	var par: Parallax2D = _layers[slot_name]
	var actual_rng: RandomNumberGenerator = rng
	if actual_rng == null:
		actual_rng = RandomNumberGenerator.new()
		actual_rng.seed = _seed_value() + slot_name.hash()
	for item in fills:
		match String(item):
			"asteroid_few":
				_spawn_asteroids_in(par, 3, actual_rng)
			"asteroid_many":
				_spawn_asteroids_in(par, 8, actual_rng)
			"nebula":
				_spawn_nebula_in(par, actual_rng)
			"debris":
				# TODO — needs a debris sprite. No-op for now so callers
				# can request it without crashing.
				pass


func _spawn_asteroids_in(par: Parallax2D, count: int, rng: RandomNumberGenerator) -> void:
	for i in count:
		var sz: float = rng.randf_range(
			max(16.0, asteroid_min_size),
			max(48.0, asteroid_min_size + 32.0)
		)
		var a := _spawn_one_asteroid(sz, rng)
		if a == null:
			continue
		par.add_child(a)
		var spin_rate: float = rng.randf_range(0.04, 0.12)
		if rng.randi() % 2 == 0:
			spin_rate = -spin_rate
		_spinning.append({"node": a, "spin": spin_rate})
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


# Full-tile nebula at the layer's depth. Uses NEBULA2_SHADER (domain-
# warped + filaments). Tinting comes from the layer's modulate so the
# colorization picker in the tuner drives it without touching shader
# uniforms.
func _spawn_nebula_in(par: Parallax2D, rng: RandomNumberGenerator) -> void:
	var shader = load(NEBULA2_SHADER)
	if shader == null:
		return
	var cs = load(SPACE_COLORSCHEME)
	var r := ColorRect.new()
	r.name = "Nebula"
	r.size = TILE_SIZE
	r.color = Color(0, 0, 0, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("scale", 2.4)
	mat.set_shader_parameter("octaves", 5)
	mat.set_shader_parameter("seed", 1.0 + (float(rng.seed % 900) / 100.0))
	mat.set_shader_parameter("pixels", TILE_SIZE.x / max(pixel_density, 0.01))
	mat.set_shader_parameter("drift_speed", 0.0)
	mat.set_shader_parameter("max_alpha", 0.7)
	mat.set_shader_parameter("opacity", 0.85)
	mat.set_shader_parameter("density", 0.95)
	mat.set_shader_parameter("edge_sharpness", 0.42)
	mat.set_shader_parameter("warp_strength", 1.2)
	mat.set_shader_parameter("wisp_strength", 0.3)
	mat.set_shader_parameter("uv_correct", Vector2(TILE_SIZE.x / TILE_SIZE.y, 1.0))
	if cs != null:
		mat.set_shader_parameter("colorscheme", cs)
	r.material = mat
	par.add_child(r)


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
			var canon: Vector2 = COLORRECT_CANONICAL_BY_NAME.get(String(child.name), COLORRECT_DEFAULT_CANONICAL)
			(child as ColorRect).size = canon
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
	for entry in _spinning:
		var node: Node = entry["node"]
		if is_instance_valid(node) and node is Node2D:
			(node as Node2D).rotation += float(entry["spin"]) * delta
	for n in _time_updaters:
		if is_instance_valid(n) and n.has_method("update_time"):
			n.update_time(_shader_time)


# Back-compat shim — the tuner still calls this on any backdrop; V3
# has no silhouette pass, so return null and let the tuner fall through
# to modulate-based color seeding.
func silhouette_material_for(_par: Parallax2D) -> ShaderMaterial:
	return null
