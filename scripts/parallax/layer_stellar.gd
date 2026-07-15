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
# ── Nebula Lab port (WP10, Roman 2026-07-12) ───────────────────────────────
# The Nebula Lab (scripts/dev/nebula_lab.gd) evolved past the old hardcoded
# warp_strength 0.8 / wisp 0.2 / opacity 1.0 literals. These per-layer exports
# carry the lab's tuned Neb2 config into production; authored per-layer in the
# layer_stellar_{far,mid,near}.tscn overrides (same mechanism as nebula_alpha).
# nebula2.gdshader only — consumed in _spawn_nebula's nebula2 branch.
@export var nebula_warp_strength: float = 0.8   # domain-warp curl amount (was hardcoded 0.8)
@export var nebula_warp_scale: float = 1.0      # domain-warp frequency; per-layer for variety (was 1.0)
@export var nebula_wisp_strength: float = 0.2   # filament wisp band (was hardcoded 0.2)
# Density + opacity BREATHE together over time (lab convention): higher opacity <-> higher density,
# phase-offset per layer so bands don't pulse in lockstep. breathe_speed 0 = frozen at the phase value.
@export var nebula_breathe_speed: float = 0.0   # 0 = static (frozen density/opacity at nebula_phase)
@export var nebula_phase: float = 0.0           # per-layer breathe phase offset (radians)
@export var pixel_density: float = 1.0
@export var mine_count: int = 0
# Per-rock lateral drift (Parallax V4 showcase). 0 = today's lockstep conveyor.
# When > 0 each rock gets a persistent vx of ±drift_variance px/s scaled by the
# layer's scroll_rate (far rocks drift less), applied in _process with an X-wrap
# at the screen edge + margin, mirroring the Y wrap. Default 0 = inert.
@export var drift_variance: float = 0.0

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
# Density/opacity breathe ranges (Nebula Lab port). density high <-> opacity high opens breaks +
# texture in the cloud; floor > 0 so a layer never fully vanishes. Matched to nebula_lab.gd.
const NEBULA_DENSITY_RANGE := Vector2(0.75, 1.4)
const NEBULA_OPACITY_RANGE := Vector2(0.4, 1.0)

var _nebula_time: float = 0.0


func populate(rng: RandomNumberGenerator) -> void:
	_local_rng = rng
	_clear_content()
	# Flagged baked-asteroid path (crash test): when enabled + the shared atlas is baked,
	# spawn cheap Sprite2D rocks (no per-rock shader) instead of live procedural ones. The
	# live path below is unchanged when the flag is off. See AsteroidBakeCache.
	var use_baked := AsteroidBakeCache.enabled and AsteroidBakeCache.is_ready()
	for _i in asteroid_count:
		if use_baked:
			_spawn_baked_asteroid()
		else:
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
	a.position = Vector2(_local_rng.randf_range(16, 464), -sz - _local_rng.randf_range(0, 270))
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
			(inner.material as ShaderMaterial).set_shader_parameter("draw_outline", false)
			_apply_shadow_params(inner.material as ShaderMaterial)
	var spin: float = 0.0
	if _local_rng.randf() < 0.35:
		spin = _local_rng.randf_range(0.05, 0.25)
		if _local_rng.randf() < 0.5:
			spin = -spin
	var base_rot: float = 0.0
	if inner != null and inner.material is ShaderMaterial:
		base_rot = float((inner.material as ShaderMaterial).get_shader_parameter("rotation"))
	_objects.append({"node": a, "size": sz, "spin": spin, "rot": base_rot, "mini": false, "asteroid": inner, "vx": _roll_drift_vx()})


# Baked-asteroid spawn (flagged crash-test path). A Sprite2D reading one frame cell from
# the shared baked atlas — no per-rock ShaderMaterial, so it does not add the live
# Asteroids.gdshader to the combat-load pipeline burst. Scrolls/wraps via _objects like
# the live rocks; its rotation frame is ticked in _process.
func _spawn_baked_asteroid() -> void:
	if _local_rng == null:
		return
	var size_t: float = pow(_local_rng.randf(), asteroid_size_pow)
	var sz := asteroid_min_size + (asteroid_max_size - asteroid_min_size) * size_t
	# Above the top bucket the rock stays LIVE — a procedural rock renders at pixels=size, so
	# it's inherently 1:1, and it doubles as the LOD "hero" tier for the big rare rocks.
	if sz > float(AsteroidBakeCache.max_bucket()) + 6.0:
		_spawn_asteroid()
		return
	var atlas := AsteroidBakeCache.get_atlas_for_size(sz)
	var tex = atlas.get("texture")
	if tex == null:
		_spawn_asteroid()
		return
	var fpx: int = int(atlas.get("frame_px", 32))
	var frames: int = maxi(int(atlas.get("frames", 1)), 1)
	var variants: int = maxi(int(atlas.get("variants", 1)), 1)
	var variant := _local_rng.randi() % variants
	var s := Sprite2D.new()
	s.texture = tex
	s.region_enabled = true
	s.region_rect = Rect2(0, variant * fpx, fpx, fpx)
	s.centered = true
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Tint the neutral baked rock to the POI asteroid colour. asteroid_tint is the sector map's
	# per-POI colour (realistic palette), shunted here by the coordinator, so baked backdrop
	# rocks match the gameplay rocks. Brightened to roughly the live backdrop's tint level.
	s.modulate = Color(asteroid_tint.r * 1.4, asteroid_tint.g * 1.4, asteroid_tint.b * 1.4, 1.0)
	# 1:1 — render at the bucket's native px (scale 1.0); the rock size snaps to the bucket.
	s.position = Vector2(_local_rng.randf_range(16, 464), -float(fpx) - _local_rng.randf_range(0, 270))
	add_child(s)
	# ~50% static; the rest drift slowly CW or CCW (signed).
	var bspin: float = 0.0
	if _local_rng.randf() < 0.5:
		bspin = _local_rng.randf_range(0.03, 0.08) * (1.0 if _local_rng.randf() < 0.5 else -1.0)
	# "spin": 0.0 so the live rotation tick in _process skips it; "baked" routes it to the
	# baked frame tick instead. "size" = the bucket px (drives the scroll-wrap threshold).
	_objects.append({
		"node": s, "size": float(fpx), "spin": 0.0, "rot": 0.0, "mini": false,
		"baked": true, "variant": variant, "fpx": fpx, "frames": frames,
		"phase": _local_rng.randf(), "bspin": bspin, "vx": _roll_drift_vx(),
	})


# Persistent per-rock lateral velocity (px/s). ±drift_variance scaled by this
# layer's scroll_rate so far bands drift slower than near ones. Zero when the
# knob is off (default) — the drift branch in _process then short-circuits.
func _roll_drift_vx() -> float:
	if drift_variance <= 0.0 or _local_rng == null:
		return 0.0
	return _local_rng.randf_range(-drift_variance, drift_variance) * scroll_rate


# Ship drop shadows (asteroid_shadow_rig): bind this band's screen-space caster
# mask + strength into the rock's (already per-instance) material. No rig in the
# tree — menus, labs, coordinator flag off — leaves the params untouched, and the
# shader's shadow_strength default of 0 keeps the rock byte-identical to today.
func _apply_shadow_params(mat: ShaderMaterial) -> void:
	var rig: Node = get_tree().get_first_node_in_group("asteroid_shadow_rig")
	if rig == null or rig.is_queued_for_deletion() or not rig.has_method("mask_texture"):
		return
	var band := _shadow_band()
	mat.set_shader_parameter("shadow_mask", rig.mask_texture(band))
	mat.set_shader_parameter("shadow_strength", rig.band_strength(band))


# Which shadow band this layer is, derived from the scene root name
# (LayerStellarFar/Mid/Near) so the band needs no .tscn edit. Unknown → mid.
func _shadow_band() -> String:
	var n := String(name).to_lower()
	if n.contains("far"):
		return "far"
	if n.contains("near"):
		return "near"
	return "mid"


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
	_objects.append({"node": r, "size": px, "spin": 0.0, "rot": 0.0, "mini": true, "vx": _roll_drift_vx()})


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
	# max_alpha IS the lab's per-layer max_alpha now (nebula_alpha). The old random
	# alpha_mult was dropped in the WP10 lab port — the lab's config is deterministic
	# per layer, so band brightness comes straight from the authored nebula_alpha.
	mat.set_shader_parameter("max_alpha", nebula_alpha)
	mat.set_shader_parameter("density", nebula_density)
	mat.set_shader_parameter("edge_sharpness", nebula_edge)
	mat.set_shader_parameter("uv_correct", Vector2(1.0, 1.0))
	if cs != null:
		mat.set_shader_parameter("colorscheme", cs)
	# nebula2-only knobs — tuned in the Nebula Lab, carried by the per-layer exports.
	if nebula_shader_path.ends_with("nebula2.gdshader"):
		mat.set_shader_parameter("warp_strength", nebula_warp_strength)
		mat.set_shader_parameter("warp_scale", nebula_warp_scale)   # per-depth curl variety
		mat.set_shader_parameter("wisp_strength", nebula_wisp_strength)
		mat.set_shader_parameter("swirl_speed", nebula_swirl)   # dynamic filament churn (coordinator-driven)
		mat.set_shader_parameter("scroll_offset", Vector2.ZERO)
		mat.set_shader_parameter("rect_size", _nebula_rect.size)   # square, native-aligned pixelation
		# density + opacity breathe together (frozen at nebula_phase when breathe_speed == 0).
		_nebula_time = 0.0
		_apply_nebula_breathe(mat)
	_nebula_rect.material = mat
	add_child(_nebula_rect)


# Drive the nebula2 density/opacity breathe from _nebula_time + nebula_phase. At
# breathe_speed 0 the value is frozen (constant per layer); > 0 it slowly pulses.
# Set once at spawn (initial frame) and re-applied per-frame in _process while
# breathe_speed > 0. No-op for non-nebula2 shaders.
func _apply_nebula_breathe(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	var o: float = 0.5 + 0.5 * sin(_nebula_time * nebula_breathe_speed + nebula_phase)
	mat.set_shader_parameter("density", lerpf(NEBULA_DENSITY_RANGE.x, NEBULA_DENSITY_RANGE.y, o))
	mat.set_shader_parameter("opacity", lerpf(NEBULA_OPACITY_RANGE.x, NEBULA_OPACITY_RANGE.y, o))


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
		# Keep the nebula screen-fixed (counter the layer's offset.y AND offset.x)
		# so it doesn't scroll off and leave a gap; drift comes from the shader.
		# Countering offset.x is what stops lateral-parallax input from sliding
		# the nebula ColorRect across the band (Parallax V4 showcase).
		_nebula_rect.position.y = -offset.y
		_nebula_rect.position.x = -offset.x
		if _nebula_rect.material is ShaderMaterial:
			(_nebula_rect.material as ShaderMaterial).set_shader_parameter(
				"scroll_offset", Vector2(0, offset.y / NEBULA_TILE)
			)


func _process(delta: float) -> void:
	# Nebula density/opacity breathe (Nebula Lab port). Only ticks when a nebula is
	# live AND breathe_speed > 0 — at 0 the value stays frozen at its spawn (phase) value.
	if nebula_breathe_speed > 0.0 and _nebula_rect != null and is_instance_valid(_nebula_rect) \
			and _nebula_rect.material is ShaderMaterial \
			and nebula_shader_path.ends_with("nebula2.gdshader"):
		_nebula_time += delta
		_apply_nebula_breathe(_nebula_rect.material as ShaderMaterial)
	if drift_variance > 0.0:
		_apply_lateral_drift(delta)
	for entry in _objects:
		# Baked rocks: advance the rotation frame (region_rect) from their own signed spin.
		if entry.get("baked", false):
			var bn: Node = entry.node
			if not is_instance_valid(bn):
				continue
			var bspin: float = float(entry.get("bspin", 0.0))
			var frames: int = maxi(int(entry.get("frames", 1)), 1)
			var fpx: int = int(entry.get("fpx", 96))
			var variant: int = int(entry.get("variant", 0))
			var phase: float = float(entry.get("phase", 0.0))
			var t := Time.get_ticks_msec() / 1000.0
			var cyc := fmod(t * bspin + phase, 1.0)
			if cyc < 0.0:
				cyc += 1.0
			var fidx := int(cyc * float(frames)) % frames
			(bn as Sprite2D).region_rect = Rect2(fidx * fpx, variant * fpx, fpx, fpx)
			continue
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


# Advance each rock's persistent lateral drift and wrap at the screen edges
# (+16px margin, mirroring the Y wrap in _on_scrolled). Only runs when
# drift_variance > 0 so the default conveyor is untouched.
func _apply_lateral_drift(delta: float) -> void:
	for entry in _objects:
		var vx: float = float(entry.get("vx", 0.0))
		if vx == 0.0:
			continue
		var n: Node = entry.node
		if not is_instance_valid(n):
			continue
		n.position.x += vx * delta
		if n.position.x < -16.0:
			n.position.x = 496.0
		elif n.position.x > 496.0:
			n.position.x = -16.0


func _on_reset() -> void:
	_clear_content()
