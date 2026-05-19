extends Node2D

# Parallax v2 — basic 5-layer parallax stack per Roman, 2026-05-17.
# Stripped down from the previous V2 attempt; the goal is a clean
# foundation we can compare against V1 and grow once it looks right.
#
# Layers (bottom → top):
#   1. BaseStars      — small starfield, distant
#   2. BigStars       — bigger pop stars
#   3. SmallAsteroids — small, rotating, silhouette-tinted
#   4. Nebula         — repeating cloud at 40% alpha
#   5. LargeAsteroids — close, rotating, full brightness
#
# Every layer is a Parallax2D so Godot's engine owns the wrap math. The
# only manual work in _process is advancing scroll_offset (scaled per
# layer) and rotating individual asteroids (rotation isn't a Parallax2D
# concern; spins live on the child sprites themselves).

const ASTEROID_SCENE = "res://Planets/Asteroids/Asteroid.tscn"
const NEBULA_SHADER = "res://graphics/nebula.gdshader"
const SPACE_COLORSCHEME = "res://SpaceBG/Colorscheme.tres"
const SILHOUETTE_SHADER = preload("res://graphics/parallax_silhouette.gdshader")
# 320×400 res rework — tile matches the new internal viewport so layers
# wrap every screen of scroll.
const TILE_SIZE := Vector2(320.0, 400.0)

@export var drift_speed: float = 22.0
# Per-layer multipliers — far layers move slow, near layers fast.
@export var base_stars_scroll: float = 0.10
@export var big_stars_scroll: float = 0.18
@export var small_asteroid_scroll: float = 0.40
@export var nebula_scroll: float = 0.65
@export var large_asteroid_scroll: float = 1.00
# Counts per layer.
@export var small_asteroid_count: int = 7
@export var large_asteroid_count: int = 4
# Silhouette modulate for the small-asteroid band (distant darkening).
@export var small_asteroid_tint: Color = Color(0.45, 0.55, 0.75, 1.0)
# Nebula final alpha (Roman wants ~40%).
@export var nebula_alpha: float = 0.40

var _parallax_layers: Array = []           # Parallax2D nodes — driven each frame
var _spinning: Array = []                  # {node, spin} entries
var _layer_time_updaters: Array = []       # asteroid Controls with update_time(t)
var _shader_time: float = 0.0
# Each Parallax2D gets a CanvasGroup wrapper so the silhouette shader
# can sample the layer's composited render rather than each individual
# sprite. The tuner uses this dict to find the layer's ShaderMaterial
# when the player adjusts the RGBA color sliders.
var _layer_silhouette_mat: Dictionary = {}  # Parallax2D instance_id -> ShaderMaterial


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_value()
	# Solid backdrop so the stars don't show through to a transparent
	# scene root.
	var deep := ColorRect.new()
	deep.color = Color(0.04, 0.05, 0.08, 1.0)
	deep.size = TILE_SIZE
	deep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(deep)
	# Layer 1 — base stars: small, dim, dense.
	_spawn_stars_layer("BaseStars", base_stars_scroll, rng,
		160, 1.0, 1.5, Color(0.85, 0.92, 1.00, 0.85))
	# Layer 2 — big stars: fewer, brighter, slightly larger.
	_spawn_stars_layer("BigStars", big_stars_scroll, rng,
		55, 2.0, 3.0, Color(1.00, 0.98, 0.92, 1.00))
	# Layer 3 — small spinning asteroids, silhouette-darkened.
	_spawn_asteroid_layer("SmallAsteroids", small_asteroid_scroll, rng,
		small_asteroid_count, 18.0, 42.0, small_asteroid_tint)
	# Layer 4 — nebula clouds.
	_spawn_nebula_layer(rng)
	# Layer 5 — large close asteroids.
	_spawn_asteroid_layer("LargeAsteroids", large_asteroid_scroll, rng,
		large_asteroid_count, 100.0, 200.0, Color(1.0, 1.0, 1.0, 1.0))


# ---- Master scroll driver -------------------------------------------------

# scroll_scale on Parallax2D only kicks in when the layer follows a
# camera — our camera is static, so we apply the per-layer scale here.
# Direction: += scroll_offset.y produces visual DOWN motion of children.
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
	for n in _layer_time_updaters:
		if is_instance_valid(n) and n.has_method("update_time"):
			n.update_time(_shader_time)


# ---- Layer builders -------------------------------------------------------

func _spawn_stars_layer(layer_name: String, scroll: float, rng: RandomNumberGenerator,
		count: int, size_min: float, size_max: float, color: Color) -> void:
	var par := _make_parallax(layer_name, scroll)
	var canvas := _make_canvas_group_child(par, color)
	# Scatter `count` pinpricks across one tile. The Parallax2D tiles
	# them with repeat_size so the scatter loops seamlessly.
	for i in count:
		var dot := ColorRect.new()
		var sz: float = rng.randf_range(size_min, size_max)
		dot.size = Vector2(sz, sz)
		dot.position = Vector2(
			rng.randf_range(0.0, TILE_SIZE.x - sz),
			rng.randf_range(0.0, TILE_SIZE.y - sz)
		)
		# Soft per-star alpha variance so the field doesn't look uniform.
		var a: float = color.a * rng.randf_range(0.55, 1.0)
		dot.color = Color(color.r, color.g, color.b, a)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.add_child(dot)


func _spawn_asteroid_layer(layer_name: String, scroll: float, rng: RandomNumberGenerator,
		count: int, size_min: float, size_max: float, tint: Color) -> void:
	var par := _make_parallax(layer_name, scroll)
	var canvas := _make_canvas_group_child(par, tint)
	for i in count:
		var a := _spawn_one_asteroid(rng, size_min, size_max)
		if a == null:
			continue
		canvas.add_child(a)
		# Per-asteroid spin so the field doesn't look frozen.
		var spin_rate: float = rng.randf_range(0.04, 0.12)
		if rng.randi() % 2 == 0:
			spin_rate = -spin_rate
		_spinning.append({"node": a, "spin": spin_rate})
		_layer_time_updaters.append(a)


func _spawn_one_asteroid(rng: RandomNumberGenerator, size_min: float, size_max: float) -> Node:
	var ps = load(ASTEROID_SCENE)
	if ps == null:
		return null
	var a = ps.instantiate()
	# Duplicate the shader material so each asteroid gets its own seed
	# and looks distinct.
	var inner: Node = a.get_node_or_null("Asteroid")
	if inner and "material" in inner and inner.material != null:
		inner.material = inner.material.duplicate()
	var sz: float = rng.randf_range(size_min, size_max)
	var sf: float = sz / 100.0
	a.scale = Vector2(sf, sf)
	if a.has_method("set_seed"):
		a.set_seed(rng.randi() % 100000)
	if "override_time" in a:
		a.override_time = true
	# Place anywhere inside a tile; Parallax2D wraps the whole layer when
	# it scrolls off the bottom.
	a.position = Vector2(
		rng.randf_range(20.0, TILE_SIZE.x - sz - 20.0),
		rng.randf_range(20.0, TILE_SIZE.y - sz - 20.0)
	)
	if a is Control:
		a.pivot_offset = Vector2(50, 50)
	return a


func _spawn_nebula_layer(rng: RandomNumberGenerator) -> void:
	var par := _make_parallax("Nebula", nebula_scroll)
	var canvas := _make_canvas_group_child(par, Color(1, 1, 1, nebula_alpha))
	var shader = load(NEBULA_SHADER)
	if shader == null:
		return
	var cs = load(SPACE_COLORSCHEME)
	var r := ColorRect.new()
	r.name = "NebulaRect"
	r.size = TILE_SIZE
	r.color = Color(0, 0, 0, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("scale", 2.6)
	mat.set_shader_parameter("octaves", 5)
	mat.set_shader_parameter("seed", 1.0 + (float(rng.seed % 900) / 100.0))
	mat.set_shader_parameter("pixels", 200.0)
	mat.set_shader_parameter("drift_speed", 0.0)
	mat.set_shader_parameter("max_alpha", 1.0)
	mat.set_shader_parameter("density", 0.9)
	mat.set_shader_parameter("edge_sharpness", 0.4)
	mat.set_shader_parameter("uv_correct", Vector2(1.0, 1.0))
	if cs != null:
		mat.set_shader_parameter("colorscheme", cs)
	r.material = mat
	canvas.add_child(r)


# ---- Plumbing -------------------------------------------------------------

# Create a Parallax2D with the canonical setup: full-tile repeat on Y,
# no x scroll, named so the Tuner picker shows it cleanly. `repeat_times`
# of 2 keeps coverage in case the camera ever zooms (it doesn't today,
# but it's free insurance).
func _make_parallax(layer_name: String, scroll: float) -> Parallax2D:
	var par := Parallax2D.new()
	par.name = layer_name
	par.scroll_scale = Vector2(0.0, scroll)
	par.repeat_size = Vector2(0.0, TILE_SIZE.y)
	par.repeat_times = 2
	add_child(par)
	_parallax_layers.append(par)
	return par


# Wrap a Parallax2D's content inside a CanvasGroup with the silhouette
# shader attached. CanvasGroup composites its children into one off-
# screen texture; the shader then samples that texture per fragment so
# the per-layer silhouette color applies uniformly to the whole layer
# (stars, asteroids, nebula clouds) while still respecting per-child
# alpha cutouts (Roman, 2026-05-17). Initial silhouette color comes
# from the layer's "natural" tint so a fresh roll matches what V1's
# palette wanted.
func _make_canvas_group_child(par: Parallax2D, initial_color: Color) -> CanvasGroup:
	var cg := CanvasGroup.new()
	cg.name = "Silhouette"
	# Fit margin extends the offscreen render rect by N pixels so child
	# content drawing past the layer bounds doesn't get clipped (e.g. a
	# spinning asteroid rotating past its placement). 64 px is a soft
	# buffer that costs basically nothing.
	cg.fit_margin = 64.0
	var mat := ShaderMaterial.new()
	mat.shader = SILHOUETTE_SHADER
	mat.set_shader_parameter("silhouette_color", initial_color)
	cg.material = mat
	par.add_child(cg)
	_layer_silhouette_mat[par.get_instance_id()] = mat
	return cg


# Public accessor used by the Tuner — given a Parallax2D layer, return
# the ShaderMaterial driving its silhouette so the RGBA sliders can
# update silhouette_color without grovelling through children.
func silhouette_material_for(par: Parallax2D) -> ShaderMaterial:
	return _layer_silhouette_mat.get(par.get_instance_id(), null)


# Seed off Run's run_seed so visits look the same on a retry — falls back
# to randomize when no Run exists (e.g. Tuner usage).
func _seed_value() -> int:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		var step: int = max(run.visited_nodes.size() - 1, 0)
		return run.run_seed + step * 1009 + run.sectors_cleared * 9973
	return randi()
