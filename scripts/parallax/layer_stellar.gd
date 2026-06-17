extends "res://scripts/parallax/layer_base.gd"

const RESET_THRESHOLD := 340.0

@export var asteroid_count: int = 4
@export var asteroid_min_size: float = 12.0
@export var asteroid_max_size: float = 24.0
# Power-curve exponent biasing the size roll toward the SMALL end (Roman 2026-06-15). 1.0 = uniform;
# higher = max-size rocks are rarer (a long tail). Per-layer so the NEAR band can keep a large max
# while making it rare; far/mid keep the gentle default.
@export var asteroid_size_pow: float = 1.286
@export var asteroid_tint: Color = Color(0.9, 0.88, 0.85, 1.0)
@export var mini_asteroid_count: int = 14
# When true, spawn asteroids spread across the FULL viewport height (already on-screen) instead of
# only above the top — so a static preview shows them immediately (Roman 2026-06-17). Combat keeps
# false so asteroids drift in from the top.
@export var asteroid_prefill: bool = false
@export var nebula_enabled: bool = false
@export var nebula_alpha: float = 0.18
@export var nebula_shader_path: String = "res://graphics/nebula2.gdshader"
@export var nebula_scale: float = 2.5
@export var nebula_octaves: int = 5
@export var nebula_density: float = 0.9
@export var nebula_edge: float = 0.4
@export var nebula_drift: float = 0.004
@export var nebula_chance: float = 0.7
@export var nebula_swirl: float = 0.0           # TIME-driven filament churn (0 = static); coordinator drives it
@export var nebula_tint: Color = Color(1, 1, 1, 1)  # multiplies the cloud colour (per-POI palette)
@export var pixel_density: float = 1.0
@export var mine_count: int = 0

# Use the actual ASTEROID_SCENE path from galaxy_backdrop.gd
const ASTEROID_SCENE = "res://Planets/Asteroids/Asteroid.tscn"
const SPACE_COLORSCHEME := "res://SpaceBG/Colorscheme.tres"
# Background mine decoration uses the NEW mine art (graphics/mines/, the live-mine
# sprites) — NOT the old graphics/enemy-mine*.png (Roman 2026-06-11).
const BG_MINE_TEX := "res://graphics/mines/enemy_mine.png"
const BG_BOMBLET_TEX := "res://graphics/mines/enemy_mine_bomblet.png"
const MineBlinker = preload("res://scripts/effects/mine_blinker.gd")

var _objects: Array = []
var _nebula_rect: ColorRect = null
var _local_rng: RandomNumberGenerator = null

const NEBULA_TILE: float = 270.0


func populate(rng: RandomNumberGenerator) -> void:
	_local_rng = rng
	_clear_content()
	for _i in asteroid_count:
		_spawn_asteroid()
	for _i in mini_asteroid_count:
		_spawn_mini_asteroid()
	if nebula_enabled and _local_rng != null and _local_rng.randf() < nebula_chance:
		_spawn_nebula()
	if mine_count > 0:
		_spawn_bg_mines()


func _clear_content() -> void:
	for entry in _objects:
		if is_instance_valid(entry.node):
			entry.node.queue_free()
	_objects.clear()
	if _nebula_rect and is_instance_valid(_nebula_rect):
		_nebula_rect.queue_free()
		_nebula_rect = null


func _spawn_asteroid() -> void:
	if _local_rng == null:
		return
	var ps := load(ASTEROID_SCENE) as PackedScene
	if ps == null:
		return
	var a := ps.instantiate()
	# Size selection (Roman 2026-05-30): reduce how often a decorative asteroid
	# lands at the top of the size range by ~20%, so max-size asteroids are a bit
	# less frequent. Previously this was a flat uniform pick:
	#     randf_range(min, max)  -> top 20% bucket hit 20% of the time.
	# Now we power-curve the [0,1] roll toward the small end. With exponent 1.286
	# the probability the roll lands in the top 20% of the range becomes
	# 1 - 0.8^(1/1.286) = 1 - 0.838 = 0.162, i.e. ~16.2% vs 20% before — a 20%
	# relative reduction in max-size frequency, redistributed to smaller sizes.
	# (Mini asteroids in _spawn_mini_asteroid keep their own sizing, untouched.)
	var size_t: float = pow(_local_rng.randf(), asteroid_size_pow)
	var sz := asteroid_min_size + (asteroid_max_size - asteroid_min_size) * size_t
	# Reset Control anchors to a clean top-left 100×100 box — PlanetKit scenes
	# ship full-rect anchors that collapse under a CanvasLayer (Node-type) parent.
	if a is Control:
		a.anchor_left = 0.0; a.anchor_top = 0.0
		a.anchor_right = 0.0; a.anchor_bottom = 0.0
		a.offset_left = 0.0; a.offset_top = 0.0
		a.offset_right = 100.0; a.offset_bottom = 100.0
		a.size = Vector2(100, 100)
		a.custom_minimum_size = Vector2(100, 100)
		a.pivot_offset = Vector2.ZERO
	var sf := sz / 100.0
	a.scale = Vector2(sf, sf)
	# Recolor the rock to the POI's asteroid color. modulate alone can't do this:
	# it MULTIPLIES the shader's blue-gray default palette, so the rock always
	# reads blue-gray. Driving the shader `colors` ramp (light→mid→dark derived
	# from asteroid_tint) makes the asteroid genuinely that color. The layer's
	# CanvasModulate still handles per-depth dimming. (Roman 2026-06-02)
	a.modulate = Color.WHITE
	# Spawn fully above the top so it drifts in (body spans [pos.y, pos.y+sz]).
	var spawn_y: float = -sz - _local_rng.randf_range(0, 270)
	if asteroid_prefill:
		spawn_y = _local_rng.randf_range(-sz, 270.0)   # already on-screen for static previews
	a.position = Vector2(_local_rng.randf_range(16, 464), spawn_y)
	add_child(a)
	# Each Asteroid.tscn instance shares one inline ShaderMaterial — duplicate
	# it per-instance so set_seed/set_pixels/set_rotates don't all write to the
	# same material (which made every asteroid identical — last-write-wins).
	var _inner_mat := a.get_node_or_null("Asteroid")
	if _inner_mat != null and _inner_mat is CanvasItem and _inner_mat.material != null:
		_inner_mat.material = _inner_mat.material.duplicate()
	# Unique shape + rotation per asteroid.
	if a.has_method("set_seed"):
		a.set_seed(_local_rng.randi())
	if a.has_method("set_rotates"):
		a.set_rotates(_local_rng.randf() < 0.7)
	# Recolor to the POI hue via the shader palette (see modulate note above).
	if a.has_method("set_colors"):
		a.set_colors(_tint_ramp(asteroid_tint))
	# Pixel parity: set_pixels resizes the inner Asteroid ColorRect to sz×sz;
	# reset it to 100×100 so node scale alone controls footprint (otherwise
	# footprint = sz²/100, quadratic).
	if a.has_method("set_pixels"):
		a.set_pixels(maxf(sz, 16.0))
	var inner := a.get_node_or_null("Asteroid")
	if inner is Control:
		inner.size = Vector2(100, 100)
		inner.position = Vector2.ZERO
		if inner.material is ShaderMaterial:
			var amat := inner.material as ShaderMaterial
			amat.set_shader_parameter("draw_outline", false)
			# Rounder, lower-detail silhouettes read better as drifting rocks than the jagged
			# default (roundness 0). Per-instance random within the tuned ranges (Roman 2026-06-17).
			amat.set_shader_parameter("roundness", _local_rng.randf_range(0.4, 0.75))
			amat.set_shader_parameter("octaves", _local_rng.randi_range(0, 5))
	var spin: float = 0.0
	if _local_rng.randf() < 0.35:
		spin = _local_rng.randf_range(0.05, 0.25)
		if _local_rng.randf() < 0.5:
			spin = -spin
	var base_rot: float = 0.0
	if inner != null and inner.material is ShaderMaterial:
		base_rot = float((inner.material as ShaderMaterial).get_shader_parameter("rotation"))
	_objects.append({"node": a, "size": sz, "spin": spin, "rot": base_rot, "mini": false, "asteroid": inner})


# Build the Asteroids.gdshader `colors` ramp (light → mid → dark) from a single
# base hue, matching the spread of the shader's default blue-gray palette.
func _tint_ramp(base: Color) -> PackedColorArray:
	return PackedColorArray([
		base.lightened(0.35),
		base,
		base.darkened(0.45),
	])


func _spawn_mini_asteroid() -> void:
	if _local_rng == null:
		return
	var r := ColorRect.new()
	var px: float = 2.0 if _local_rng.randf() < 0.4 else 1.0
	r.size = Vector2(px, px)
	r.color = asteroid_tint
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = Vector2(_local_rng.randf_range(0, 480), -_local_rng.randf_range(0, 270))
	add_child(r)
	_objects.append({"node": r, "size": px, "spin": 0.0, "rot": 0.0, "mini": true})


func _spawn_nebula() -> void:
	var shader := load(nebula_shader_path) as Shader
	if shader == null:
		return
	var cs = load(SPACE_COLORSCHEME)  # gradient texture — required for color
	_nebula_rect = ColorRect.new()
	_nebula_rect.name = "Nebula"
	_nebula_rect.size = Vector2(480, 270)
	_nebula_rect.color = Color(0, 0, 0, 0)
	_nebula_rect.modulate = nebula_tint   # per-POI palette tint multiplies the cloud colour
	_nebula_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var nebula_px: float = 480.0 / max(pixel_density, 0.01)
	var sd: float = 1.0
	if _local_rng:
		sd = 1.0 + float(_local_rng.randi() % 900) / 100.0   # fresh draw → unique per band
	mat.set_shader_parameter("scale", nebula_scale)
	mat.set_shader_parameter("octaves", nebula_octaves)
	mat.set_shader_parameter("seed", sd)
	mat.set_shader_parameter("pixels", nebula_px)
	mat.set_shader_parameter("drift_speed", nebula_drift)
	var alpha_mult: float = _local_rng.randf_range(1.0, 1.5) if _local_rng else 1.0
	mat.set_shader_parameter("max_alpha", nebula_alpha * alpha_mult)
	mat.set_shader_parameter("density", nebula_density)
	mat.set_shader_parameter("edge_sharpness", nebula_edge)
	mat.set_shader_parameter("uv_correct", Vector2(1.0, 1.0))
	if cs != null:
		mat.set_shader_parameter("colorscheme", cs)
	# nebula2-only knobs — gentle swirl/filaments per V1's live near pass.
	if nebula_shader_path.ends_with("nebula2.gdshader"):
		mat.set_shader_parameter("warp_strength", 0.8)
		mat.set_shader_parameter("warp_scale", 1.0)
		mat.set_shader_parameter("wisp_strength", 0.2)
		mat.set_shader_parameter("swirl_speed", nebula_swirl)   # dynamic filament churn
		mat.set_shader_parameter("opacity", 1.0)
		mat.set_shader_parameter("scroll_offset", Vector2.ZERO)
		mat.set_shader_parameter("rect_size", _nebula_rect.size)   # square, native-aligned pixelation
	_nebula_rect.material = mat
	add_child(_nebula_rect)


func _spawn_bg_mines() -> void:
	if _local_rng == null:
		return
	var mine_tex = load(BG_MINE_TEX)
	var bomblet_tex = load(BG_BOMBLET_TEX)
	for _i in mine_count:
		var s := Sprite2D.new()
		# New mine art (a clean transparent sprite — no black box / pixel outline).
		s.texture = bomblet_tex if (_local_rng.randf() < 0.35) else mine_tex
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.position = Vector2(_local_rng.randf_range(80, 400), _local_rng.randf_range(-270, 0))
		s.scale = Vector2(0.7, 0.7)
		s.modulate = Color(0.62, 0.62, 0.66, 0.7)   # dimmed — decoration, not a live mine
		add_child(s)
		# Dimmed pixel pulse light so the field reads as live-but-distant (round-1
		# worklist: "their pixel pulse light as well, albeit dimmed"). Not an enemy.
		var blink = MineBlinker.new()
		blink.modulate = Color(1, 1, 1, 0.4)
		s.add_child(blink)
		_objects.append({"node": s, "size": 8.0})


func _on_scrolled() -> void:
	for entry in _objects:
		var n: Node = entry.node
		if not is_instance_valid(n):
			continue
		var sz: float = entry.size
		# Wrap only when FULLY below the screen (top edge past the bottom),
		# and respawn FULLY above the top so it drifts in with no pop.
		if offset.y + n.position.y > 270.0 + 16.0:
			if _local_rng:
				n.position.x = _local_rng.randf_range(16, 464)
				n.position.y = (-sz - _local_rng.randf_range(8, 220)) - offset.y
	if _nebula_rect and is_instance_valid(_nebula_rect):
		# Keep the nebula screen-fixed (counter the layer's offset.y) so it
		# doesn't scroll off and leave a gap; drift comes from the shader.
		_nebula_rect.position.y = -offset.y
		if _nebula_rect.material is ShaderMaterial:
			(_nebula_rect.material as ShaderMaterial).set_shader_parameter(
				"scroll_offset", Vector2(0, offset.y / NEBULA_TILE)
			)


func _process(delta: float) -> void:
	for entry in _objects:
		var sp: float = float(entry.get("spin", 0.0))
		if sp == 0.0:
			continue
		var n: Node = entry.node
		if not is_instance_valid(n):
			continue
		var inner: Node = entry.get("asteroid")
		if inner != null and is_instance_valid(inner) and inner.material is ShaderMaterial:
			entry.rot = float(entry.get("rot", 0.0)) + sp * delta
			(inner.material as ShaderMaterial).set_shader_parameter("rotation", entry.rot)


func _on_reset() -> void:
	_clear_content()
