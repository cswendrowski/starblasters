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
# Nebula silhouette tint — magenta-ish gas by default so the layer reads
# as celestial cloud rather than a flat white veil. Tunable in-tuner.
@export var nebula_tint: Color = Color(0.55, 0.30, 0.65, 1.0)
# Pixel parity (Cobalt 2026-05-20) — same rule as galaxy_backdrop V1.
# shader_pixels = display_size_vp / pixel_density keeps each cell at
# `pixel_density` viewport-px per art-pixel regardless of body size.
# 1.0 matches the player's 1 vp-px per art-pixel.
@export_range(0.5, 6.0) var pixel_density: float = 1.0
@export_range(8.0, 64.0) var pixels_floor: float = 16.0
# Minimum decorative asteroid size in viewport pixels (legibility floor —
# below ~16 vp-px the procgen rock can't form a readable silhouette at
# 1:1 pixel parity).
@export_range(8.0, 48.0) var asteroid_min_size: float = 16.0
const COLORRECT_DEFAULT_CANONICAL_V2 := Vector2(100.0, 100.0)
const COLORRECT_CANONICAL_BY_NAME_V2 := {
	"Disk": Vector2(300.0, 300.0),
	"Ring": Vector2(300.0, 300.0),
}

var _parallax_layers: Array = []           # Parallax2D nodes — driven each frame
var _spinning: Array = []                  # {node, spin} entries
var _layer_time_updaters: Array = []       # asteroid Controls with update_time(t)
var _shader_time: float = 0.0


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
	# Layer 1 — base stars: small, dim, dense. Cool white reads well as
	# distant pinpricks against the dark deep.
	_spawn_stars_layer("BaseStars", base_stars_scroll, rng,
		160, 1.0, 1.5, Color(0.85, 0.92, 1.00, 0.85))
	# Layer 2 — big stars: fewer, brighter, slightly larger. Slightly
	# warmer than base stars so depth reads (warm pop in front of cool
	# pinpricks).
	_spawn_stars_layer("BigStars", big_stars_scroll, rng,
		55, 2.0, 3.0, Color(1.00, 0.96, 0.86, 1.00))
	# Layer 3 — small spinning asteroids, silhouette-darkened blue-gray.
	# Lower bound clamps to `asteroid_min_size` for 1:1 legibility.
	_spawn_asteroid_layer("SmallAsteroids", small_asteroid_scroll, rng,
		small_asteroid_count, max(18.0, asteroid_min_size), max(42.0, asteroid_min_size + 26.0), small_asteroid_tint)
	# Layer 4 — nebula clouds. Default to a deep magenta so the layer reads
	# as gas instead of a flat white wash. Tuner Colorization knob is the
	# primary way to retune this per scene.
	_spawn_nebula_layer(rng)
	# Layer 5 — large close asteroids. Default to a warm mid-gray so the
	# close band reads as illuminated rock, not a featureless white sheet.
	_spawn_asteroid_layer("LargeAsteroids", large_asteroid_scroll, rng,
		large_asteroid_count, 100.0, 200.0, Color(0.58, 0.55, 0.50, 1.0))


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
	# Pixel parity — shader cells track displayed size so a tiny asteroid
	# and a giant one both render at the target density.
	_apply_pixel_parity_v2(a, sz)
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


# Pixel parity helper for V2 — mirrors galaxy_backdrop.gd's _apply_pixel_parity.
# Drives shader.pixels = displayed_size_vp / density, then resets internal
# ColorRects to their authored canonical size so the shader cell count is
# independent of the layer's scale.
func _apply_pixel_parity_v2(p: Node, displayed_size: float) -> void:
	var px: float = max(displayed_size / max(pixel_density, 0.01), pixels_floor)
	if p.has_method("set_pixels"):
		p.set_pixels(px)
	else:
		_apply_pixels_only_v2(p, px)
	_reset_colorrect_sizes_v2(p)


func _apply_pixels_only_v2(root: Node, value: float) -> void:
	for child in root.get_children():
		if child is ColorRect and child.material is ShaderMaterial:
			child.material.set_shader_parameter("pixels", value)
		_apply_pixels_only_v2(child, value)


func _reset_colorrect_sizes_v2(root: Node) -> void:
	for child in root.get_children():
		if child is ColorRect:
			var canon: Vector2 = COLORRECT_CANONICAL_BY_NAME_V2.get(String(child.name), COLORRECT_DEFAULT_CANONICAL_V2)
			(child as ColorRect).size = canon
		_reset_colorrect_sizes_v2(child)


func _spawn_nebula_layer(rng: RandomNumberGenerator) -> void:
	var par := _make_parallax("Nebula", nebula_scroll)
	var canvas := _make_canvas_group_child(par, Color(nebula_tint.r, nebula_tint.g, nebula_tint.b, nebula_alpha))
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
	# Pixel parity — TILE_SIZE.x is the larger axis (320 vs 400-y but
	# in 480×270 viewport the rect is full-width; use the longer of the
	# two to keep cells ≤ density viewport-px in either dimension).
	mat.set_shader_parameter("pixels", max(TILE_SIZE.x, TILE_SIZE.y) / max(pixel_density, 0.01))
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


# Apply the per-layer tint to the Parallax2D directly via modulate. No
# CanvasGroup / silhouette compositing — the natural art of the layer
# (star ColorRects, asteroid sprites, nebula shader) reads through, with
# the tint as a simple cascading multiplier. Cobalt 2026-05-20: the
# previous silhouette pass (flat-fill the whole band with one color) hid
# the actual layer art, defeating the V1/V2 comparison.
#
# Returns the Parallax2D itself so callers can add children to it as
# they did to the old CanvasGroup wrapper.
func _make_canvas_group_child(par: Parallax2D, initial_tint: Color) -> Parallax2D:
	par.modulate = initial_tint
	return par


# Back-compat shim — silhouette pass no longer exists, but the tuner
# still calls this. Returns null now; the tuner falls back to reading
# Parallax2D.modulate as the per-layer tint (same path V1 uses).
func silhouette_material_for(_par: Parallax2D) -> ShaderMaterial:
	return null


# Seed off Run's run_seed so visits look the same on a retry — falls back
# to randomize when no Run exists (e.g. Tuner usage).
func _seed_value() -> int:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		var step: int = max(run.visited_nodes.size() - 1, 0)
		return run.run_seed + step * 1009 + run.sectors_cleared * 9973
	return randi()
