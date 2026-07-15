extends "res://scripts/parallax/layer_base.gd"

@export var pixel_density: float = 1.0
@export var pixels_floor: float = 16.0
@export var planet_size: float = 240.0
# Planet body lateral wander amplitude (px), Parallax V4 showcase. 0 = static
# (today). When > 0 the main planet drifts sinusoidally ±lateral_wander px around
# its spawn X, period ~40s — "a massive body we're passing", not a sticker.
@export var lateral_wander: float = 0.0
# Per-body parallax (Parallax V4 showcase, item 6). 0 = today: the whole layer scrolls
# as one rigid plate. When > 0 each spawned body (main planet, system bodies, companions —
# NOT moons, they orbit their parent) drifts on TOP of the layer scroll by its own
# depth_mult (bigger/nearer = faster), star_mode-aware. 1.0 = full depth spread.
@export var body_parallax: float = 0.0
# Star-mode from the composition (item 5/6). Set by the coordinator before spawn. Weights
# the per-body depth: near_star bodies read CLOSE (fast), distant_star ≈ static, "" = moderate.
var star_mode: String = ""

# ── Star FX tiers (Parallax V4 showcase, WP8) ────────────────────────────────
# Size-tiered rendering for star bodies (hero planet idx 8 + system star entries). OFF (default)
# = byte-identical: the PixelPlanets Star kit + WP5's glow_boost bloom halo, untouched. ON:
#   < star_sparkle_max px → sparkle ColorRect (diffraction twinkle) + white HDR center dot, NO kit;
#   star_sparkle_max..star_clamp_max → kit + pixel_halo_glow ring (size lerps on the star px);
#   > star_clamp_max → clamped to star_clamp_max at spawn (then it lands in the halo tier).
# The new tiers REPLACE glow_boost when on (no double-halo — a distant small star lands in the
# strictly-brighter sparkle tier). All thresholds are lab-tunable (WP9 drives these exports).
@export var star_fx: bool = false
# Below this display px a star renders as the sparkle tier (no PixelPlanets kit).
@export var star_sparkle_max: float = 32.0
# Star display size is capped here when star_fx is on (the halo stops reading past it, and a
# 120px star is bright enough to carry the scene). Composer near_star sizes hit this cap.
@export var star_clamp_max: float = 120.0
# Multiplier on the lerped halo size (WP9 tuner knob). 1.0 = the raw 64→240 lerp.
@export var halo_scale_mult: float = 1.0
# Halo brightness levers (Roman 2026-07-08 — the two knobs that run hot when the halo,
# HDR kit palette, and WorldEnv bloom stack): the gradient's mid-stop alpha, and the
# shader's core_intensity (1.5 sits exactly at the bloom threshold).
@export var halo_mid_alpha: float = 0.75
@export var halo_core_intensity: float = 1.5
# Sparkle-tier levers (Roman 2026-07-08 "giant central dot" round 2). The sparkle shader's
# gaussian envelope M = exp(-L²·decay²/scale) paints a FULL-brightness core ≈40% of the star
# diameter at the Shader-Lab decay 0.12 — fine there (it sat BEHIND a textured kit star),
# a featureless blob here where the dot replaces the kit. 0.30 → core ≈17% of the star.
@export var sparkle_decay: float = 0.3
# Multiplier on the reference shader `scale` (4300 @ 32px). Higher = tighter core + spikes.
@export var sparkle_scale_mult: float = 1.0
# Glint energy — scales the star point's core heat + cross-ray length (0.45 = reference).
@export var dot_size_frac: float = 0.45
# The glint's HDR boost (bloom threshold is 1.5).
@export var dot_hdr: float = 2.5

const STAR_HALO_SHADER := preload("res://graphics/pixel_halo_glow.gdshader")
const STAR_SPARKLE_SHADER := preload("res://graphics/sparkle_star.gdshader")
const STAR_GLINT_SHADER := preload("res://graphics/star_glint.gdshader")
# Halo size lerp anchors: ≈ star×2.8. History: Roman's first-pass ×3 (98/360) read enormous,
# the Shader-Lab ×2 (64/240) read too tight in the showcase — settled at ×2 + 40%
# (Roman 2026-07-08 after driving the glint build). Fixed anchors (the sparkle/clamp EXPORTS
# move the tier boundaries; these stay put; halo_scale_mult scales the result).
const STAR_HALO_ANCHOR_LO := 32.0
const STAR_HALO_ANCHOR_HI := 120.0
const STAR_HALO_PX_LO := 90.0
const STAR_HALO_PX_HI := 336.0
# Sparkle sizing reference (Roman's Shader Lab block, tuned at star size 32): the sparkle ColorRect
# is 2× the star (lab "Star Sparkle" default halo_px 220 / star 110 = 2:1) and the shader `scale`
# param is 4300 at that 32px reference. Both shrink proportionally with the star (rect & scale).
const SPARKLE_REF_STAR := 32.0
const SPARKLE_REF_SCALE := 4300.0
const SPARKLE_RECT_RATIO := 2.0

# Reference display size for depth weighting — a body at this size sits at ~unit depth. Roughly
# the main planet's footprint (planet_size default 240); larger bodies read as nearer (faster).
const BODY_DEPTH_REF := 240.0
# Bodies under per-body parallax: [{node, depth_mult}]. Parallel to _animated, cleared with it.
# Empty (and never appended to) while body_parallax is 0, so scroll()/apply_lateral short-circuit.
var _parallax_bodies: Array = []
# Previous applied lateral shift, so apply_lateral's per-body drift can advance incrementally
# (apply_lateral SETS offset.x absolutely). Reset with the layer.
var _prev_lateral_x: float = 0.0

const PLANETS := {
	0: "res://Planets/LavaWorld/LavaWorld.tscn",
	1: "res://Planets/IceWorld/IceWorld.tscn",
	2: "res://Planets/DryTerran/DryTerran.tscn",
	3: "res://Planets/GasPlanet/GasPlanet.tscn",
	4: "res://Planets/NoAtmosphere/NoAtmosphere.tscn",
	5: "res://Planets/LandMasses/LandMasses.tscn",
	6: "res://Planets/BlackHole/BlackHole.tscn",
	7: "res://Planets/Galaxy/Galaxy.tscn",
	8: "res://Planets/Star/Star.tscn",
	9: "res://Planets/GasPlanetLayers/GasPlanetLayers.tscn",   # ringed gas giant (set_pixels handles the Ring)
	10: "res://Planets/Rivers/Rivers.tscn",
}

const COLORRECT_DEFAULT_CANONICAL := {"size": Vector2(100.0, 100.0), "pos": Vector2.ZERO}
const COLORRECT_CANONICAL_BY_NAME := {
	"Disk":       {"size": Vector2(300.0, 300.0), "pos": Vector2(-100.0, -100.0)},
	"Ring":       {"size": Vector2(300.0, 300.0), "pos": Vector2(-100.0, -100.0)},
	"Blobs":      {"size": Vector2(200.0, 200.0), "pos": Vector2(-50.0, -50.0)},
	"StarFlares": {"size": Vector2(200.0, 200.0), "pos": Vector2(-50.0, -50.0)},
}

const PULSE_GLOW_SHADER = preload("res://graphics/pulse_glow.gdshader")
const POI_MOON_SCENE := "res://Planets/NoAtmosphere/NoAtmosphere.tscn"
const PlanetGlow = preload("res://scripts/effects/planet_glow_config.gd")

# Cap on the baked halo-gradient resolution. Halos pick a power-of-two texture
# >= their displayed diameter (see _halo_res_for) so the radial falloff maps at
# (or above) 1:1 to viewport pixels — a fixed 64² texture nearest-upscaled to a
# big planet's ~560–730px bloom (9–11×) is what made large glows read as chunky
# concentric blocks. Pow2 bucketing bounds the shared cache to ~5 textures total.
const HALO_TEX_MAX := 1024

var _planet_node: Node = null
var _planet_actual_size: float = 0.0
var _planet_spawn_x: float = 0.0        # main planet's authored X, for lateral_wander
var _dominant_color: Color = Color.WHITE  # cached per spawn (get_dominant_color)

const ANIM_SPEED: float = 0.30   # 70% slower than real-time
var _anim_time: float = 0.0
var _animated: Array = []   # planet nodes to drive update_time on


func _duplicate_materials(root: Node) -> void:
	for child in root.get_children():
		if child is ColorRect and child.material is ShaderMaterial:
			(child as ColorRect).material = (child.material as ShaderMaterial).duplicate()
		_duplicate_materials(child)


# Scale a planet body's palette by M (uniform, per-channel) via the kit's own get_colors/set_colors,
# so its brightest colours clear the HDR bloom threshold and glow in the body's OWN hue. Snapshots
# the authored palette to "base_palette" meta once, so re-applying a different M never compounds.
# Static so both production (layer_planet spawn) and the Parallax Tuner can call it on any body.
static func apply_palette_glow(p: Node, m: float) -> void:
	if p == null or not (p.has_method("get_colors") and p.has_method("set_colors")):
		return
	var base: Array
	if p.has_meta("base_palette"):
		base = p.get_meta("base_palette")
	else:
		base = p.get_colors()
		p.set_meta("base_palette", base)
	var out: Array = []
	for c in base:
		out.append(Color(c.r * m, c.g * m, c.b * m, c.a))
	p.set_colors(out)


# ── Per-body parallax (item 6) ──────────────────────────────────────────────
# depth_mult for a body of `actual_size`: 1.0 = moves exactly with the layer (static
# relative to it); > 1.0 = drifts faster (nearer). Bigger bodies + near_star mode push it up.
func _depth_mult_for(actual_size: float) -> float:
	var size_factor: float = clampf(actual_size / BODY_DEPTH_REF, 0.0, 1.5)
	var mode_factor: float = 0.5   # "" / single-planet / sector-map default
	match star_mode:
		"near_star":    mode_factor = 1.0    # the star is CLOSE — bodies swing
		"distant_star": mode_factor = 0.15   # far system — barely any spread
	return 1.0 + size_factor * mode_factor


# Register a spawned body for per-body parallax. No-op (and no list growth) when the knob
# is off, so body_parallax = 0 stays byte-identical (scroll()/apply_lateral short-circuit).
func _register_parallax_body(node: Node, actual_size: float) -> void:
	if body_parallax <= 0.0 or node == null:
		return
	_parallax_bodies.append({"node": node, "depth_mult": _depth_mult_for(actual_size)})


# Scroll override: layer moves as one via offset.y, THEN each registered body gets an extra
# (depth_mult - 1) × delta × body_parallax on its position.y so nearer bodies outrun the plate.
# Short-circuits to the base behavior when the knob is off. Bodies that drift off the bottom just
# leave (planet-layer bodies have never wrapped — they historically scroll off and are gone), which
# is the intended "we flew past it" read; nothing accumulates since clear_planet resets the list.
func scroll(delta_y: float) -> void:
	offset.y += delta_y
	if body_parallax > 0.0 and not _parallax_bodies.is_empty():
		for b in _parallax_bodies:
			var n: Node = b["node"]
			if is_instance_valid(n):
				n.position.y += (float(b["depth_mult"]) - 1.0) * delta_y * body_parallax
	_on_scrolled()


# Lateral override: same per-body depth scaling on X. apply_lateral SETS offset.x absolutely,
# so advance each body by the DELTA of the applied shift (incremental, composes additively).
func apply_lateral(px: float) -> void:
	var new_x: float = px * scroll_rate
	if body_parallax > 0.0 and not _parallax_bodies.is_empty():
		var dx: float = new_x - _prev_lateral_x
		for b in _parallax_bodies:
			var n: Node = b["node"]
			if is_instance_valid(n):
				n.position.x += (float(b["depth_mult"]) - 1.0) * dx * body_parallax
	_prev_lateral_x = new_x
	offset.x = new_x
	_on_scrolled()


func spawn_planet(planet_idx: int, actual_size: float, rng: RandomNumberGenerator, poi_id: String = "", planet_seed: int = -1, star_color: Color = Color.WHITE) -> void:
	clear_planet()
	# WP8 star FX: a hero star (idx 8) reroutes to the tiered sparkle/halo renderer. Companions
	# (binary star) still spawn from the shared path — they're a separate, rarer site.
	if star_fx and planet_idx == 8:
		_spawn_star_planet(actual_size, rng, planet_seed, star_color)
		_spawn_companions(rng, planet_idx, _planet_spawn_x, -_planet_actual_size * 0.78, _planet_actual_size)
		return
	var scene_path: String = PLANETS.get(planet_idx, PLANETS[2])
	var ps := load(scene_path) as PackedScene
	if ps == null:
		return
	var p := ps.instantiate()
	# Set up Control anchors (same as galaxy_backdrop.gd _spawn_planet)
	if p is Control:
		p.anchor_left = 0.0; p.anchor_top = 0.0
		p.anchor_right = 0.0; p.anchor_bottom = 0.0
		p.offset_right = 100.0; p.offset_bottom = 100.0
		p.size = Vector2(100, 100)
		p.custom_minimum_size = Vector2(100, 100)
		p.pivot_offset = Vector2.ZERO
	var sf := actual_size / 100.0
	p.scale = Vector2(sf, sf)
	var x := (480.0 - actual_size) * 0.5
	var y := -actual_size * 0.78
	p.position = Vector2(x, y)
	add_child(p)  # MUST come before _apply_pixel_parity
	_apply_pixel_parity(p, actual_size)
	_duplicate_materials(p)
	if planet_seed >= 0:
		# Deterministic — reproduce the sector map's exact planet.
		if p.has_method("set_seed"):    p.set_seed(planet_seed % 100000)
		# seed() reseeds the GLOBAL RNG, which bleeds into gameplay rolls project-wide
		# (asteroid/bg-mine/effect randf) — capture + restore around the deterministic
		# palette so PixelPlanets stays reproducible without correlating game randomness.
		var _rng_state := randi()
		seed(planet_seed)
		if p.has_method("randomize_colors"): p.randomize_colors()
		seed(_rng_state)
		if p.has_method("set_rotates"): p.set_rotates(true)
		if p.has_method("set_light"):   p.set_light(Vector2(0.0, 0.5))
	else:
		# No stored seed (tuner / no Run) — random per spawn.
		if p.has_method("set_seed"):    p.set_seed(rng.randi() % 100000)
		if p.has_method("randomize_colors"): p.randomize_colors()
		if p.has_method("set_rotates"): p.set_rotates(rng.randf() < 0.7)
		if p.has_method("set_dither"):  p.set_dither(rng.randf() < 0.5)
	if "override_time" in p:
		p.override_time = true
	if p.has_method("update_time"):
		_animated.append(p)
	# Star-color wash on the planet — matches the sector map's planet modulate.
	if p is CanvasItem:
		p.modulate = Color.WHITE.lerp(star_color, 0.18)
	# Per-type HDR glow: scale this body's palette so it blooms in its own hue at threshold 1.5 (kit
	# untouched — uses its own get/set_colors). No-ops at 1.0, so production is unchanged until tuned.
	var pg_main: float = PlanetGlow.prod_mult(planet_idx)
	if pg_main != 1.0:
		apply_palette_glow(p, pg_main)
	# Store planet node and size for POI moons attachment
	_planet_node = p
	_planet_actual_size = actual_size
	_planet_spawn_x = x
	# Sample the post-randomize palette once per spawn so use_dominant_grade can
	# grade the scene to the body's actual hue (fallback to the type tint).
	_dominant_color = _compute_dominant_color(p, planet_idx)
	_make_planet_halo(p, planet_idx, actual_size, x, y)
	_register_parallax_body(p, actual_size)
	# Spawn companion bodies (moons/binary stars) around the main planet
	_spawn_companions(rng, planet_idx, x, y, actual_size)


# Spawn ONE body of a star-system at an arbitrary screen position + size,
# WITHOUT clearing prior bodies. Generalizes _spawn_companion_body for the
# row-system backdrop (backdrop_coordinator iterates current_stellar.system).
# Deterministic from planet_seed (mirrors spawn_planet) so a revisit reproduces
# the same surfaces. The coordinator calls clear_planet() ONCE before looping.
# `top_left` is the body's top-left in LayerPlanet-local coords (Control planets
# are authored top-left); pass center - actual_size/2 if you have a center.
func spawn_system_body(planet_idx: int, actual_size: float, top_left: Vector2, planet_seed: int, star_color: Color = Color.WHITE, glow_boost: float = 1.0) -> void:
	# WP8 star FX: system star entries route to the tiered renderer (replaces glow_boost — no
	# double-halo). Re-center on the original body center when the clamp shrinks a near_star.
	if star_fx and planet_idx == 8:
		var clamped: float = minf(actual_size, star_clamp_max)
		var orig_center: Vector2 = top_left + Vector2(actual_size, actual_size) * 0.5
		_spawn_star_fx(clamped, orig_center - Vector2(clamped, clamped) * 0.5, planet_seed, star_color)
		return
	var scene_path: String = PLANETS.get(planet_idx, PLANETS[2])
	var ps := load(scene_path) as PackedScene
	if ps == null:
		return
	var p := ps.instantiate()
	if p is Control:
		p.anchor_left = 0.0; p.anchor_top = 0.0
		p.anchor_right = 0.0; p.anchor_bottom = 0.0
		p.offset_left = 0.0; p.offset_top = 0.0
		p.offset_right = 100.0; p.offset_bottom = 100.0
		p.size = Vector2(100, 100)
		p.custom_minimum_size = Vector2(100, 100)
		p.pivot_offset = Vector2.ZERO
	var sf: float = actual_size / 100.0
	p.scale = Vector2(sf, sf)
	p.position = top_left
	add_child(p)  # MUST come before _apply_pixel_parity
	_apply_pixel_parity(p, actual_size)
	_duplicate_materials(p)
	# Deterministic surfaces (mirror spawn_planet's seeded branch).
	if p.has_method("set_seed"):    p.set_seed(planet_seed % 100000)
	# Capture/restore the global RNG around seed() — otherwise this reseeds every
	# subsequent gameplay randf() from a node-determined state (see spawn_planet).
	var _rng_state := randi()
	seed(planet_seed)
	if p.has_method("randomize_colors"): p.randomize_colors()
	seed(_rng_state)
	if p.has_method("set_rotates"): p.set_rotates(true)
	if p.has_method("set_light"):   p.set_light(Vector2(0.0, 0.5))
	if "override_time" in p:
		p.override_time = true
	if p.has_method("update_time"):
		_animated.append(p)
	# Star-color wash (skip the star itself — its own light shouldn't be tinted).
	if p is CanvasItem and planet_idx != 8:
		p.modulate = Color.WHITE.lerp(star_color, 0.18)
	# glow_boost (item 5): over-boost the body's HDR palette so a small distant star still
	# clears the bloom threshold and reads brilliant. Proportional (near_star = 1.0 = today).
	var pg_sys: float = PlanetGlow.prod_mult(planet_idx) * glow_boost
	if pg_sys != 1.0:
		apply_palette_glow(p, pg_sys)
	# A boosted star (distant_star) also gets an additive bloom halo so the tiny point of light
	# reads as luminous once WP6's WorldEnvironment blooms it. Planets keep _make_planet_halo only.
	if planet_idx == 8 and glow_boost > 1.0:
		var s_center := top_left + Vector2(actual_size, actual_size) * 0.5
		var s_col := Color(star_color.r, star_color.g, star_color.b, 0.7)
		_make_halo_sprite(s_center, actual_size * 2.6, s_col)
	_make_planet_halo(p, planet_idx, actual_size, top_left.x, top_left.y)
	_register_parallax_body(p, actual_size)


# Render an EXTREME-DISTANCE body as a tiny glowing dot in `color` instead of a
# sphere. Used by the row-system backdrop when a body's computed size drops below
# the dot threshold (backdrop_coordinator.SYS_DOT_THRESHOLD_PX). The dot is a
# small additive halo (so it reads as a glowing point of light) with a crisp
# `dot_px` bright core on top. `center` is in LayerPlanet-local coords.
func spawn_system_dot(center: Vector2, dot_px: float, color: Color) -> void:
	# Soft additive glow behind the core so the point reads as luminous, not a
	# flat pixel. Reuse the shared radial halo texture; keep it small (a few px)
	# so distant bodies stay subtle.
	var glow_color: Color = Color(color.r, color.g, color.b, 0.55)
	_make_halo_sprite(center, dot_px * 4.0, glow_color)
	# Crisp bright core — a 2px additive ColorRect, color pushed bright.
	var core := ColorRect.new()
	core.name = "SystemDot"
	core.size = Vector2(dot_px, dot_px)
	core.position = Vector2(round(center.x - dot_px * 0.5), round(center.y - dot_px * 0.5))
	core.color = Color(min(color.r * 1.4, 1.0), min(color.g * 1.4, 1.0), min(color.b * 1.4, 1.0), 1.0)
	core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	core.material = mat
	core.z_index = 1
	add_child(core)


# Per-type fallback tint (mirrors backdrop_coordinator.PLANET_TINT) — used when a
# body's kit exposes no CPU-readable palette (get_colors) to sample.
const FALLBACK_TINT := {
	0: Color(1.0, 0.45, 0.20), 1: Color(0.60, 0.85, 1.0), 2: Color(0.85, 0.65, 0.40),
	3: Color(0.65, 0.80, 0.55), 4: Color(0.70, 0.70, 0.75), 5: Color(0.45, 0.75, 0.55),
	6: Color(0.10, 0.10, 0.15), 7: Color(0.55, 0.45, 0.80), 8: Color(1.00, 0.95, 0.75),
}


# Dominant color of the currently-spawned main planet, cached at spawn time.
# Port of V1's brightest/most-vivid palette sampler (galaxy_backdrop.gd
# _sample_blackhole_disc_color): picks the most saturated × bright color from the
# kit's post-randomize get_colors() so the grade reads the hue the player sees.
func get_dominant_color() -> Color:
	return _dominant_color


func _compute_dominant_color(p: Node, planet_idx: int) -> Color:
	var fallback: Color = FALLBACK_TINT.get(planet_idx, Color.WHITE)
	if p == null or not p.has_method("get_colors"):
		return fallback
	var cols = p.get_colors()
	if cols == null or (cols is Array and cols.is_empty()):
		return fallback
	# Most saturated AND luminous color — favours a vivid hue over a dim saturated
	# one the eye barely registers (mirrors V1's sat × brightness pick).
	var best: Color = fallback
	var best_sat: float = -1.0
	for c in cols:
		var col: Color = c
		var maxc: float = maxf(col.r, maxf(col.g, col.b))
		var minc: float = minf(col.r, minf(col.g, col.b))
		var sat: float = (maxc - minc) * maxc
		if sat > best_sat:
			best_sat = sat
			best = col
	# Kits hand back HDR-boosted palettes (>1.0 channels via PlanetGlowConfig).
	# Normalize to SDR before use as a grade tint — an HDR grade would BRIGHTEN
	# the composite (and trip bloom) instead of tinting it.
	var m := maxf(best.r, maxf(best.g, best.b))
	if m > 1.0:
		return Color(best.r / m, best.g / m, best.b / m, 1.0)
	return Color(best.r, best.g, best.b, 1.0)


# ── Star FX tiers (WP8) ──────────────────────────────────────────────────────
# Halo display px for a star of `star_px`, linearly interpolated between the fixed anchors
# (32→98, 120→360) × the tuner multiplier. Exposed so the test can spot-check the formula.
func _star_halo_size(star_px: float) -> float:
	var t: float = clampf((star_px - STAR_HALO_ANCHOR_LO) / (STAR_HALO_ANCHOR_HI - STAR_HALO_ANCHOR_LO), 0.0, 1.0)
	return lerpf(STAR_HALO_PX_LO, STAR_HALO_PX_HI, t) * halo_scale_mult


# Hero-star (idx 8) FX spawn — mirrors spawn_planet's bookkeeping (screen position, _planet_node,
# dominant color) but routes through the tiered star renderer. star_fx-only caller.
func _spawn_star_planet(actual_size: float, rng: RandomNumberGenerator, planet_seed: int, star_color: Color) -> void:
	var size: float = minf(actual_size, star_clamp_max)
	var x: float = (480.0 - size) * 0.5
	var y: float = -size * 0.78
	# planet_seed < 0 = tuner/no-Run: fall back to the spawn rng (deterministic within the run).
	var s_seed: int = planet_seed if planet_seed >= 0 else rng.randi()
	var grp := _spawn_star_fx(size, Vector2(x, y), s_seed, star_color)
	_planet_node = grp
	_planet_actual_size = size
	_planet_spawn_x = x
	# Dominant color: sample the kit's palette in the halo tier, else the per-type star fallback.
	var kit = grp.get_meta("star_kit", null)
	_dominant_color = _compute_dominant_color(kit, 8) if kit != null else FALLBACK_TINT[8]


# Build a star body's FX into a container at `top_left` and return it. Every child (kit/halo/
# sparkle/dot) rides the container as ONE unit — scroll()/apply_lateral()/body_parallax act on
# grp.position, and clear_planet() frees grp (freeing them with it). Caller MUST clamp `actual_size`
# to star_clamp_max first. Deterministic from `star_seed` (no unseeded randomness).
func _spawn_star_fx(actual_size: float, top_left: Vector2, star_seed: int, star_color: Color) -> Node2D:
	var grp := Node2D.new()
	grp.name = "StarFx"
	grp.position = top_left
	grp.set_meta("star_px", actual_size)
	add_child(grp)  # in-tree BEFORE the kit's _apply_pixel_parity (SIGSEGV contract)
	var center: Vector2 = Vector2(actual_size, actual_size) * 0.5   # grp-local star center
	if actual_size < star_sparkle_max:
		grp.set_meta("star_tier", "sparkle")
		_make_star_sparkle(grp, center, actual_size, star_color)
		_make_star_dot(grp, center, actual_size, star_color)
	else:
		grp.set_meta("star_tier", "halo")
		var kit := _make_star_kit(grp, actual_size, star_seed, star_color)
		grp.set_meta("star_kit", kit)
		_make_star_halo(grp, center, actual_size, star_seed, star_color, kit)
	_register_parallax_body(grp, actual_size)
	return grp


# The PixelPlanets Star kit as a child of the FX container — mirrors spawn_system_body's kit
# setup (anchors/scale/seed with global-RNG capture-restore/HDR palette). Returns the kit node.
func _make_star_kit(grp: Node2D, actual_size: float, star_seed: int, star_color: Color) -> Node:
	var ps := load(PLANETS[8]) as PackedScene
	if ps == null:
		return null
	var p := ps.instantiate()
	if p is Control:
		p.anchor_left = 0.0; p.anchor_top = 0.0
		p.anchor_right = 0.0; p.anchor_bottom = 0.0
		p.offset_left = 0.0; p.offset_top = 0.0
		p.offset_right = 100.0; p.offset_bottom = 100.0
		p.size = Vector2(100, 100)
		p.custom_minimum_size = Vector2(100, 100)
		p.pivot_offset = Vector2.ZERO
	var sf: float = actual_size / 100.0
	p.scale = Vector2(sf, sf)
	p.position = Vector2.ZERO   # relative to grp (already at top_left)
	grp.add_child(p)  # MUST come before _apply_pixel_parity
	_apply_pixel_parity(p, actual_size)
	_duplicate_materials(p)
	if p.has_method("set_seed"): p.set_seed(star_seed % 100000)
	# Capture/restore the global RNG around seed() (see spawn_planet's note).
	var _rng_state := randi()
	seed(star_seed)
	if p.has_method("randomize_colors"): p.randomize_colors()
	seed(_rng_state)
	if p.has_method("set_rotates"): p.set_rotates(true)
	if p.has_method("set_light"):   p.set_light(Vector2(0.0, 0.5))
	if "override_time" in p:
		p.override_time = true
	if p.has_method("update_time"):
		_animated.append(p)   # driven at ANIM_SPEED like the other kits
	var pg: float = PlanetGlow.prod_mult(8)
	if pg != 1.0:
		apply_palette_glow(p, pg)   # kit blooms in its own hue (before the halo samples get_colors)
	if p is CanvasItem:
		p.z_index = 1   # above the halo ring
	return p


# pixel_halo_glow ray-burst ring behind the star kit (Shader Lab "Star Glow" recipe: pixelation =
# displayed px for a 1:1 pixel effect, 3-stop gradient from the star's own palette). Sibling of the
# kit inside grp so it rides the body. Animates on raw shader TIME (backdrop convention, see below).
func _make_star_halo(grp: Node2D, center: Vector2, actual_size: float, star_seed: int, star_color: Color, kit: Node) -> void:
	var halo_px: float = _star_halo_size(actual_size)
	var rect := ColorRect.new()
	rect.name = "StarHalo"
	rect.color = Color(1, 1, 1, 1)
	rect.size = Vector2(halo_px, halo_px)
	rect.position = center - rect.size * 0.5
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = 0   # behind the kit
	var mat := ShaderMaterial.new()
	mat.shader = STAR_HALO_SHADER
	mat.set_shader_parameter("pixelation", Vector2(halo_px, halo_px))
	mat.set_shader_parameter("gradient_steps", 64.0)
	mat.set_shader_parameter("spread", 0.33)
	mat.set_shader_parameter("size", 0.365)
	mat.set_shader_parameter("speed", 0.6)
	mat.set_shader_parameter("ray1_density", 8.5)
	mat.set_shader_parameter("ray2_density", 8.5)
	mat.set_shader_parameter("ray2_intensity", 0.5)
	mat.set_shader_parameter("core_intensity", halo_core_intensity)
	mat.set_shader_parameter("hdr", false)
	mat.set_shader_parameter("seed", float(abs(star_seed) % 100) * 0.1)   # deterministic ray phase
	mat.set_shader_parameter("gradient", _star_halo_gradient(kit, star_color))
	rect.material = mat
	grp.add_child(rect)


# 3-stop horizontal gradient for the halo shader, sourced from the star's own palette
# (darkest→mid→brightest by luma, alphas 0→0.75→1). Palette is HDR-boosted, so normalize each
# stop to SDR. Falls back to a star_color ramp when the kit exposes no CPU-readable palette.
func _star_halo_gradient(kit: Node, star_color: Color) -> GradientTexture1D:
	var lo := Color(star_color.r * 0.6, star_color.g * 0.6, star_color.b * 0.6, 0.0)
	var mid := Color(star_color.r, star_color.g, star_color.b, halo_mid_alpha)
	var hi := Color(1, 1, 1, 1).lerp(Color(star_color.r, star_color.g, star_color.b, 1.0), 0.4)
	hi.a = 1.0
	if kit != null and kit.has_method("get_colors"):
		var cols = kit.get_colors()
		if cols is Array and cols.size() >= 2:
			var s := _sorted_by_luma(cols)
			lo = _norm_sdr(s[0]);                 lo.a = 0.0
			mid = _norm_sdr(s[s.size() / 2]);     mid.a = halo_mid_alpha
			hi = _norm_sdr(s[s.size() - 1]);      hi.a = 1.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([lo, mid, hi])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t


func _norm_sdr(c: Color) -> Color:
	var m: float = maxf(c.r, maxf(c.g, c.b))
	if m > 1.0:
		return Color(c.r / m, c.g / m, c.b / m, c.a)
	return c


func _sorted_by_luma(cols) -> Array:
	var arr: Array = []
	for c in cols:
		arr.append(c)
	arr.sort_custom(func(a, b): return (a.r + a.g + a.b) < (b.r + b.g + b.b))
	return arr


# Sparkle diffraction-spike overlay (Shader Lab "Star Sparkle" recipe, Roman's tuned block at star
# size 32). The rect is 2× the star and the shader `scale` is 4300 at that 32px reference — both
# shrink proportionally with the star so tiny distant stars twinkle at the right scale. The shader's
# render_mode is blend_add (additive on its own) and animates on raw TIME (backdrop convention).
func _make_star_sparkle(grp: Node2D, center: Vector2, actual_size: float, star_color: Color) -> void:
	var f: float = actual_size / SPARKLE_REF_STAR
	var rect_px: float = actual_size * SPARKLE_RECT_RATIO
	var rect := ColorRect.new()
	rect.name = "StarSparkle"
	rect.color = Color(1, 1, 1, 1)
	rect.size = Vector2(rect_px, rect_px)
	rect.position = center - rect.size * 0.5
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = 0
	var mat := ShaderMaterial.new()
	mat.shader = STAR_SPARKLE_SHADER
	mat.set_shader_parameter("color", star_color)
	mat.set_shader_parameter("scale", SPARKLE_REF_SCALE * f * sparkle_scale_mult)
	mat.set_shader_parameter("circle_ratio", 0.0)
	mat.set_shader_parameter("decay_magnitude", sparkle_decay)
	mat.set_shader_parameter("cut_magnitude", 0.0)
	mat.set_shader_parameter("rotate_speed", 0.0)
	mat.set_shader_parameter("time_speed", 1.0)
	mat.set_shader_parameter("frequency_base", 1.75)
	mat.set_shader_parameter("frequency_disturbance_scale", 2.35)
	mat.set_shader_parameter("stop_shine", true)
	rect.material = mat
	grp.add_child(rect)


# The star POINT — a separable glint (star_glint.gdshader, Starry-Night technique: intensity
# = k / clamp(|dx|) / clamp(|dy|), cross-shaped by construction). Round profiles (flat disc,
# then radial gaussians) all read as circles at this size no matter how steep (Roman
# 2026-07-08, rounds 1-3) — a distant star wants a POINT + thin cross rays, which only a
# separable falloff gives. dot_size_frac scales the glint energy (core heat + ray length);
# dot_hdr pushes it past the 1.5 bloom threshold.
func _make_star_dot(grp: Node2D, center: Vector2, actual_size: float, star_color: Color) -> void:
	var quad_px: float = actual_size * SPARKLE_RECT_RATIO   # same footprint as the sparkle rect
	var dot := ColorRect.new()
	dot.name = "StarDot"
	dot.color = Color(1, 1, 1, 1)
	dot.size = Vector2(quad_px, quad_px)
	dot.position = center - dot.size * 0.5
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = STAR_GLINT_SHADER
	# Near-white core faintly tinted toward the star hue.
	var tint := Color.WHITE.lerp(Color(star_color.r, star_color.g, star_color.b, 1.0), 0.3)
	mat.set_shader_parameter("color", Color(tint.r, tint.g, tint.b, 1.0))
	mat.set_shader_parameter("quad_px", quad_px)
	# dot_size_frac 0.45 (default) → brightness 2.0; slider scales energy monotonically.
	mat.set_shader_parameter("brightness", 2.0 * (dot_size_frac / 0.45))
	mat.set_shader_parameter("hdr_boost", dot_hdr)
	mat.set_shader_parameter("ray_falloff", 1.0)
	dot.material = mat
	dot.z_index = 1
	grp.add_child(dot)


func clear_planet() -> void:
	_animated.clear()
	_parallax_bodies.clear()
	_prev_lateral_x = 0.0
	_dominant_color = Color.WHITE
	_planet_node = null
	for child in get_children():
		if child is not CanvasModulate:
			child.queue_free()


func _on_reset() -> void:
	clear_planet()


func _process(delta: float) -> void:
	_anim_time += delta * ANIM_SPEED
	for n in _animated:
		if is_instance_valid(n) and n.has_method("update_time"):
			n.update_time(_anim_time)
	# Planet lateral wander (Parallax V4 showcase) — sinusoid around spawn X,
	# ~40s period. Inert at the default 0. Uses unscaled real time so the drift
	# is independent of the anim-speed slowdown.
	if lateral_wander > 0.0 and _planet_node != null and is_instance_valid(_planet_node):
		var t := Time.get_ticks_msec() / 1000.0
		_planet_node.position.x = _planet_spawn_x + sin(t * TAU / 40.0) * lateral_wander


# Pixel cell count for a body of `displayed_size` viewport-px at the
# current `pixel_density` setting. Below `pixels_floor` we cap so tiny
# distant bodies don't degenerate into a handful of cells — they render
# slightly chunkier than target rather than disappear into mush.
func _pixels_for_size(displayed_size: float) -> float:
	var raw: float = displayed_size / max(pixel_density, 0.01)
	return max(raw, pixels_floor)


# Apply pixel parity to a procedural body: drive the shader's `pixels`
# uniform AND reset each internal ColorRect back to its canonical
# logical size. The reset is what decouples shader resolution from
# display footprint — without it, PixelPlanets' set_pixels resizes the
# ColorRect in lockstep with the uniform, leaving cell viewport size
# pinned to the parent's scale.
#
# Returns the cell count used so callers can stash it for later (e.g.,
# the BlackHole boss attack reuses it via _apply_pixels_only).
#
# CRITICAL: must be called AFTER add_child(p) — see commit 7d834da
func _apply_pixel_parity(p: Node, displayed_size: float) -> float:
	var px: float = _pixels_for_size(displayed_size)
	# CRASH FIX (Roman 2026-06-15): normalize inner ColorRect anchors to offset-based (all 0) BEFORE
	# any size is set. Several PixelPlanets scenes (Galaxy, Star, GasPlanet, Rivers, LandMasses) ship
	# their ColorRect with anchor_right/bottom = 1.0 (NON-equal opposite anchors). set_pixels and
	# _reset_colorrect_sizes both assign `.size` on it, which routes through the engine's
	# anchor-override re-layout — and that intermittently SIGSEGVs when the body is spawned into the
	# HD backdrop SubViewport (captured Galaxy crash: Galaxy.gd:5 set_pixels -> _apply_pixel_parity).
	# Equal anchors make every subsequent size assignment a plain set, killing the warning + the crash.
	_normalize_colorrect_anchors(p)
	# Prefer the planet asset's own set_pixels(amount) when present —
	# each variant knows whether sub-shaders need a multiplier (BlackHole
	# scales the Disk by 3×; GasPlanetLayers Ring similarly). Fallback
	# walks ColorRect children and sets the uniform directly.
	if p.has_method("set_pixels"):
		p.set_pixels(px)
	else:
		_apply_pixels_only(p, px)
	_reset_colorrect_sizes(p)
	return px


# Reset every ColorRect descendant to offset-based anchors (all four anchors 0). PixelPlanets ships
# some inner ColorRects with anchor_right/bottom = 1.0; assigning `.size` on a non-equal-anchored
# Control routes through the engine's size-override re-layout, the source of the backdrop SIGSEGV.
# _reset_colorrect_sizes (called right after) re-establishes the canonical offset size.
func _normalize_colorrect_anchors(root: Node) -> void:
	for child in root.get_children():
		if child is ColorRect:
			var cr := child as ColorRect
			cr.anchor_left = 0.0
			cr.anchor_top = 0.0
			cr.anchor_right = 0.0
			cr.anchor_bottom = 0.0
		_normalize_colorrect_anchors(child)


# Walk ColorRect descendants and reset their `size` to the canonical
# logical dimensions the addon shipped with. Lookup table handles ring
# overlays (Disk/Ring) which are authored at 300×300 by convention.
func _reset_colorrect_sizes(root: Node) -> void:
	for child in root.get_children():
		if child is ColorRect:
			var canon: Dictionary = COLORRECT_CANONICAL_BY_NAME.get(String(child.name), COLORRECT_DEFAULT_CANONICAL)
			(child as ColorRect).size = canon["size"]
			(child as ColorRect).position = canon["pos"]
		_reset_colorrect_sizes(child)


func _apply_pixels_only(root: Node, value: float) -> void:
	for child in root.get_children():
		if child is ColorRect and child.material is ShaderMaterial:
			child.material.set_shader_parameter("pixels", value)
		_apply_pixels_only(child, value)


# Per-planet atmosphere treatment. The GradientTexture2D atmosphere/bloom halos were RETIRED
# 2026-06-27: planets now bloom purely via their HDR palette (apply_palette_glow scales the kit's
# OWN colours past the 1.5 threshold), which is the PixelPlanets plugin's self-contained design.
# Only the BlackHole keeps a bespoke halo — its breathing pulse-glow disc (a shader, not a gradient
# sprite) — since a black body has nothing bright to bloom on its own.
func _make_planet_halo(planet_node: Node, planet_idx: int, actual_size: float, planet_x: float, planet_y: float) -> void:
	if planet_idx == 6:  # BlackHole. Colour from the sampled disc palette (planet meta, set at spawn);
		# the pulse_glow shader drives the radial falloff + a slow sine breathe.
		var center: Vector2 = Vector2(planet_x + actual_size * 0.5, planet_y + actual_size * 0.5)
		var disc: Color = planet_node.get_meta("blackhole_halo_color", Color(0.85, 0.6, 1.0, 1.0))
		_attach_pulse_glow(center, actual_size * 2.2, disc)


# Additive halo behind/beside the planet. z_index is kept at 0 so the
# parallax layer stays in its own render layer.
func _make_halo_sprite(center: Vector2, diameter: float, color: Color) -> void:
	var halo := Sprite2D.new()
	halo.name = "PlanetHalo"
	# Bake the gradient at >= the displayed pixel size so the radial falloff maps
	# ~1:1 to viewport pixels (1 source texel per pixel, or super-sampled when the
	# pow2 bucket overshoots). Removes the chunky nearest-upscale on large planets.
	var res: int = _halo_res_for(diameter)
	halo.texture = _build_halo_texture(res)
	halo.position = center
	var s: float = diameter / float(res)
	halo.scale = Vector2(s, s)
	halo.self_modulate = color
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = mat
	halo.z_index = 0
	halo.add_to_group("backdrop_halo")  # group, NOT name — add_child renames colliding "PlanetHalo" siblings
	add_child(halo)


# Item-pulse-glow style halo for the BlackHole. Radial falloff from quad
# center, sine-pulsed intensity, color sourced from the sampled disc tone.
# Composited additively via CanvasItemMaterial so it adds glow over the
# disc rather than darkening it.
func _attach_pulse_glow(center: Vector2, diameter: float, color: Color) -> void:
	var rect := ColorRect.new()
	rect.name = "BlackHolePulseGlow"
	rect.color = Color(1, 1, 1, 1)
	rect.size = Vector2(diameter, diameter)
	rect.position = center - rect.size * 0.5
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = PULSE_GLOW_SHADER
	mat.set_shader_parameter("glow_color", Color(color.r, color.g, color.b, 0.85))
	rect.material = mat
	rect.add_to_group("backdrop_halo")
	add_child(rect)


# Spawn 1-2 companion bodies near a freshly-placed celestial. Globe
# planets get a 30% chance for a moon (or two), stars get a 15% chance
# for a binary companion. BlackHole / Galaxy skip — their visuals are
# already busy.
func _spawn_companions(rng: RandomNumberGenerator, main_idx: int, main_x: float, main_y: float, main_size: float) -> void:
	if main_idx == 6 or main_idx == 7:
		return
	var is_star: bool = main_idx == 8
	var roll: float = rng.randf()
	var companion_count: int = 0
	if is_star:
		if roll < 0.15:
			companion_count = 1   # binary
	else:
		if roll < 0.30:
			companion_count = 1
		elif roll < 0.45:
			companion_count = 2
	for i in companion_count:
		var comp_idx: int = main_idx
		if not is_star:
			# Globe planets: pick a different globe variant for variety.
			comp_idx = rng.randi() % 6
			if comp_idx == main_idx and rng.randf() < 0.5:
				comp_idx = (main_idx + 1 + rng.randi() % 5) % 6
		var size_mult: float = rng.randf_range(0.30, 0.55) if not is_star else rng.randf_range(0.55, 0.75)
		var size_px: float = main_size * size_mult
		# Offset from main planet — sideways + slight vertical.
		var angle: float = rng.randf_range(-PI, PI)
		var dist: float = main_size * rng.randf_range(0.65, 0.95)
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * dist
		_spawn_companion_body(PLANETS[comp_idx], rng, comp_idx, main_x + offset.x, main_y + offset.y, size_px)


# Lightweight companion spawner — same lifecycle hooks as spawn_planet
# but at a custom size + position. No companion-of-companion recursion.
func _spawn_companion_body(scene_path: String, rng: RandomNumberGenerator, planet_idx_used: int, x: float, y: float, actual_size: float) -> void:
	var ps := load(scene_path)
	if ps == null:
		return
	var p = ps.instantiate()
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
	var sf: float = actual_size / 100.0
	p.scale = Vector2(sf, sf)
	if "override_time" in p:
		p.override_time = true
	if p.has_method("update_time"):
		_animated.append(p)
	if p.has_method("set_seed"):
		p.set_seed(rng.randi() % 100000)
	if p.has_method("randomize_colors"):
		p.randomize_colors()
	if p.has_method("set_rotates"):
		p.set_rotates(rng.randf() < 0.7)
	p.position = Vector2(x, y)
	add_child(p)
	_apply_pixel_parity(p, actual_size)
	_duplicate_materials(p)
	var pg_comp: float = PlanetGlow.prod_mult(planet_idx_used)
	if pg_comp != 1.0:
		apply_palette_glow(p, pg_comp)
	_make_planet_halo(p, planet_idx_used, actual_size, x, y)
	_register_parallax_body(p, actual_size)


# Attach POI moons from sector map data. Moons are projected around the
# main planet in orbits specified by their descriptor (rx, ry, phase).
# Layer scrolls as a unit via offset.y, so moons move with the planet automatically.
func attach_moons(moons: Array) -> void:
	if moons.is_empty():
		return
	if _planet_node == null:
		return
	var moon_scene := load(POI_MOON_SCENE)
	if moon_scene == null:
		push_warning("[LayerPlanet] could not load POI moon scene: %s" % POI_MOON_SCENE)
		return
	# Deterministic per-POI seed so a revisit to the same node produces the
	# same moon surfaces. Salt with index per-moon below.
	var base_seed: int = 0
	if has_node("/root/Run"):
		base_seed = abs(hash(String(get_node("/root/Run").current_node_id)))
	# Scale moon orbit radii from the V3 map's tiny planet (~16-32 px) up
	# to the combat planet's footprint.
	var scale_factor: float = _planet_actual_size / 24.0
	var moon_idx: int = 0
	for m in moons:
		var radius_descriptor: int = clampi(int(m.get("radius", 1)), 1, 3)
		# Map descriptor radius 1/2/3 -> 18/22/26 vp-px. Above pixels_floor
		# (16) so the procgen silhouette renders cleanly; small enough to
		# read as "moon" beside a 240-px planet.
		var actual_size: float = 14.0 + float(radius_descriptor) * 4.0
		var p = moon_scene.instantiate()
		# Reset Control anchors the same way spawn_planet does — the
		# PlanetKit scenes ship with full-rect anchors that collapse when
		# reparented under a Node2D.
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
			p.pivot_offset = Vector2(50, 50)
		var sf: float = actual_size / 100.0
		p.scale = Vector2(sf, sf)
		# Duplicate the inline ShaderMaterial per-moon BEFORE set_seed — the moon
		# kit ships one shared inline material, so without this every moon renders
		# the last moon's surface (last-write-wins). Mirrors the other three spawn
		# sites (spawn_planet/spawn_system_body/_spawn_companion_body).
		_duplicate_materials(p)
		if "override_time" in p:
			p.override_time = true
		if p.has_method("update_time"):
			_animated.append(p)
		# Deterministic per-moon seed — same POI revisit reproduces the
		# same moon surfaces. Skip randomize_colors so the descriptor's
		# `color` field drives the visible tint (spec: "color should be
		# influenced by the sector map pixel moons").
		if p.has_method("set_seed"):
			p.set_seed((base_seed + moon_idx * 1009) % 100000)
		if p.has_method("set_rotates"):
			p.set_rotates(true)
		p.name = "PoiMoon"
		p.modulate = m.get("color", Color.WHITE)
		p.z_index = 0
		# Static placement around the planet: project the descriptor's
		# (rx, ry, phase) ellipse to a single point and place the moon's
		# CENTER there (Controls are authored top-left, so subtract half the
		# display size). Use the planet's spawn position — moons + planet
		# both ride the layer's offset.y scroll so they stay in sync.
		var rx_px: float = float(m.get("rx", 12.0)) * scale_factor
		var ry_px: float = float(m.get("ry", 10.0)) * scale_factor
		var phase: float = float(m.get("phase", 0.0))
		var planet_center: Vector2 = _planet_node.position + Vector2(_planet_actual_size, _planet_actual_size) * 0.5
		var anchor: Vector2 = planet_center + Vector2(cos(phase) * rx_px, sin(phase) * ry_px)
		p.position = anchor - Vector2(actual_size, actual_size) * 0.5
		add_child(p)
		_apply_pixel_parity(p, actual_size)
		moon_idx += 1


# Smallest power-of-two texture resolution >= the displayed glow diameter, so the
# baked radial gradient maps at (or above) 1:1 to viewport pixels. Bucketing to
# pow2 bounds the cache to a handful of shared textures no matter how many
# distinct halo sizes a backdrop spawns (companions, moons, atmosphere + bloom).
static func _halo_res_for(diameter: float) -> int:
	var need: int = maxi(int(ceil(diameter)), 16)
	var res: int = 64
	while res < need and res < HALO_TEX_MAX:
		res <<= 1
	return res


# Cache baked radial-gradient textures by resolution bucket — a backdrop spawns
# several halos and they cluster onto a few pow2 sizes, so they share textures
# (mirrors the static texture-cache idiom in burn_fx / death_dust / em_burst_fx).
static var _halo_tex_cache: Dictionary = {}

static func _build_halo_texture(res: int = 64) -> Texture2D:
	if _halo_tex_cache.has(res):
		return _halo_tex_cache[res]
	var g = Gradient.new()
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.45),
		Color(1, 1, 1, 0.0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var t = GradientTexture2D.new()
	t.gradient = g
	t.width = res
	t.height = res
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_halo_tex_cache[res] = t
	return t
