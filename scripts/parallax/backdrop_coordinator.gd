extends Node2D

@export var drift_speed: float = 22.0
@export var planet_size: float = 240.0
@export var planet_size_variance: float = 0.35
@export var tint_alpha: float = 0.09
@export var use_warp_streaks: bool = true
@export var warp_streak_count: int = 14
@export var warp_streak_speed: float = 750.0
@export var forced_planet_idx: int = -1
@export var pixel_density: float = 1.0
@export var asteroid_presence: float = 0.65
@export_range(1.0, 2.0) var asteroid_density_scale: float = 1.0
# Hazard-node decoration (background mines). OFF by default so the SHARED coordinator
# (also used by the main menu + signal events) never paints mines from a stale
# current_hazard_subtype. ONLY the combat backdrop (main.tscn) turns this on, so mines
# decorate minefield COMBAT and nowhere else (Roman 2026-06-11).
@export var enable_hazard_decor: bool = false

# Planet-to-tint mapping from V1 PLANET_TINT. Read galaxy_backdrop.gd for the exact colors.
const PLANET_TINT := {
	0: Color(1.0, 0.45, 0.20),  # LavaWorld
	1: Color(0.60, 0.85, 1.0),  # IceWorld
	2: Color(0.85, 0.65, 0.40), # DryTerran
	3: Color(0.65, 0.80, 0.55), # GasPlanet
	4: Color(0.70, 0.70, 0.75), # NoAtmosphere
	5: Color(0.45, 0.75, 0.55), # LandMasses
	6: Color(0.10, 0.10, 0.15), # BlackHole — skip tint
	7: Color(0.55, 0.45, 0.80), # Galaxy
	8: Color(1.00, 0.95, 0.75), # Star — skip tint
}
const SKIP_TINT := [6, 8]

# ── Row-system staging position knobs (Roman to tune) ──────────────────────
# When current_stellar carries a `system` array (star + nearest planets), the
# bodies are spread across the upper backdrop by their `frac` (0=left/near star,
# 1=right/far). Bodies are decorative + behind gameplay, so the full 480 width
# (incl. side gutters) is fair game for spreading them out without overlap.
const SYS_X_MIN        := 40.0    # KNOB: screen-x for frac 0.0 (star, left)
const SYS_X_MAX        := 440.0   # KNOB: screen-x for frac 1.0 (far-right body)
const SYS_Y_BASE       := -40.0   # KNOB: baseline top-y of a body's top-left
const SYS_Y_JITTER     := 70.0    # KNOB: per-seed vertical spread band (px)
const SYS_Y_LOWER_BIG  := 26.0    # KNOB: nearer/larger bodies sit this much lower
# Size ceiling for the NEAREST body (scale 1.0). Roman v2: the body at the
# current node should FILL the screen — the playfield is 480×270, so a ceiling
# of 330px makes the nearest body ~330px tall (taller than the 270 viewport;
# partially off-frame is intended). `scale` (0..1) from _stage_scale multiplies
# this. Distant bodies fall off fast via the exponential curve in sector_map_v3.
const SYS_SIZE_CEILING := 330.0   # KNOB: px size of a body at scale 1.0 (fills screen)
# Below this RAW px size (before any floor) a body is too far to read as a
# sphere — render it as a ~2px glowing dot in its main color instead.
const SYS_DOT_THRESHOLD_PX := 6.0 # KNOB: raw px under which a body becomes a 2px dot
const SYS_DOT_PX           := 2.0 # KNOB: the glowing dot's core size (px)
const SYS_MIN_BODY_PX  := 18.0    # KNOB: clamp so NON-dot bodies don't degenerate

var _layer_stars: Node = null
var _layer_planet: Node = null
var _layer_stellar_far: Node = null
var _layer_stellar_mid: Node = null
var _layer_stellar_near: Node = null
var _layer_streaks: Node = null
var _layer_composite: Node = null
var _scroll_layers: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer_stars         = get_node_or_null("LayerStars")
	_layer_planet        = get_node_or_null("LayerPlanet")
	_layer_stellar_far   = get_node_or_null("LayerStellarFar")
	_layer_stellar_mid   = get_node_or_null("LayerStellarMid")
	_layer_stellar_near  = get_node_or_null("LayerStellarNear")
	_layer_streaks       = get_node_or_null("LayerStreaks")
	_layer_composite     = get_node_or_null("LayerComposite")
	_scroll_layers = [_layer_planet, _layer_stellar_far, _layer_stellar_mid, _layer_stellar_near]
	_populate()


func _populate() -> void:
	var run_node := get_node_or_null("/root/Run")
	var stellar: Dictionary = {}
	if run_node and "current_stellar" in run_node:
		stellar = run_node.current_stellar

	var rng := RandomNumberGenerator.new()
	# Deterministic per-run seed in gameplay (from Run); a fresh time-based
	# seed everywhere else (tuner "Generate New", capture tool) so each
	# regeneration actually varies instead of repeating one fixed backdrop.
	var seed_val := int(Time.get_ticks_usec())
	if run_node:
		var rs := 12345 if not "run_seed" in run_node else int(run_node.run_seed)
		var sc := 0 if not "sectors_cleared" in run_node else int(run_node.sectors_cleared)
		var node_id: String = run_node.get("current_node_id") if "current_node_id" in run_node else ""
		var node_hash := hash(node_id) if node_id != "" else 0
		seed_val = rs + sc * 9973 + node_hash
	rng.seed = abs(seed_val)

	# Planet
	var planet_idx := forced_planet_idx
	if planet_idx < 0:
		planet_idx = stellar.get("planet_idx", rng.randi() % 9)
	var size_mult := rng.randf_range(1.0 - planet_size_variance, 1.0 + planet_size_variance)
	var actual_size := planet_size * size_mult

	# Row-system staging: if current_stellar carries a non-empty `system` array,
	# render every body (star + nearest planets) staged by frac/scale instead of
	# a single planet. Bodies are decorative + behind gameplay. Moons are SKIPPED
	# in system mode (KNOB) — the bodies themselves are the decoration, and there
	# is no single "the planet" for moons to orbit.
	var system: Array = stellar.get("system", [])
	if _layer_planet != null:
		_layer_planet.set("pixel_density", pixel_density)
		if not system.is_empty() and _layer_planet.has_method("spawn_system_body"):
			_spawn_system(system)
		elif _layer_planet.has_method("spawn_planet"):
			var planet_seed: int = int(stellar.get("planet_seed", -1))
			var star_color: Color = stellar.get("star_color", Color.WHITE)
			_layer_planet.spawn_planet(planet_idx, actual_size, rng, "", planet_seed, star_color)
			# Attach POI moons if present (single-planet path only).
			if _layer_planet.has_method("attach_moons"):
				var moons: Array = stellar.get("moons", [])
				if not moons.is_empty():
					_layer_planet.attach_moons(moons)

	# Stellar layers.
	# Decorative parallax asteroids appear ONLY when the current node is an
	# asteroid-field hazard (Roman 2026-05-30). The sector map sets
	# current_stellar.has_asteroids = true only for those nodes
	# (see sector_map_v3._compute_poi_stellar). When false we drive the per-layer
	# asteroid + mini-asteroid counts to ZERO so nothing spawns — note we must
	# bypass the maxi(1, ...) floor below, which previously forced >=1 asteroid
	# per layer regardless of density. Planets / nebula / stars are unaffected.
	var has_asteroids: bool = bool(stellar.get("has_asteroids", false))
	var asteroid_density: float = float(stellar.get("asteroid_density", 0.0))
	var density_mult: float = (0.5 + asteroid_density) * asteroid_density_scale
	var ast_color: Color = Color(0.9, 0.88, 0.85, 1.0)
	if run_node != null and run_node.has_meta("asteroid_base_color"):
		ast_color = run_node.get_meta("asteroid_base_color")
	for layer in _scroll_layers:
		if layer != null and layer.has_method("populate"):
			if "asteroid_count" in layer:
				if has_asteroids:
					var base_ct: int = int(layer.get("asteroid_count"))
					layer.set("asteroid_count", maxi(1, int(round(base_ct * density_mult))))
				else:
					layer.set("asteroid_count", 0)
			if "mini_asteroid_count" in layer:
				if has_asteroids:
					var base_mini: int = int(layer.get("mini_asteroid_count"))
					layer.set("mini_asteroid_count", maxi(1, int(round(base_mini * density_mult))))
				else:
					layer.set("mini_asteroid_count", 0)
			if "asteroid_tint" in layer:
				layer.set("asteroid_tint", ast_color)
			layer.populate(rng)

	# Warp streaks
	if _layer_streaks != null:
		_layer_streaks.set("streak_count", warp_streak_count)
		_layer_streaks.set("streak_speed", warp_streak_speed)
		_layer_streaks.set("enabled", use_warp_streaks)

	# Tints
	_apply_tints(planet_idx)
	_setup_composite(planet_idx)

	# Decorative background mines on minefield levels (Roman 2026-06-11): mine sprites
	# in 3 depth bands, each carrying a DIMMED pulse light, so the minefield reads as
	# a layered hazard. Pure decoration — no collision. Combat backdrop only (the flag),
	# so a stale "minefield" subtype can't leak mines into the menu / signal events.
	if enable_hazard_decor and run_node and "current_hazard_subtype" in run_node \
			and String(run_node.current_hazard_subtype) == "minefield":
		_spawn_background_mines(rng)


const BgMineScript = preload("res://scripts/parallax/bg_mine.gd")
# Live-mine art (the SAME sprites the gameplay mines use) so the background reads as
# dimmed, distant versions of the real thing — NOT the retired mine_basic.png (Roman 2026-06-11).
const MINE_BG_TEX := preload("res://graphics/mines/enemy_mine.png")
const BOMBLET_BG_TEX := preload("res://graphics/mines/enemy_mine_bomblet.png")

func _spawn_background_mines(rng: RandomNumberGenerator) -> void:
	var layers := [
		{"count": 6, "scale": 0.35, "speed": 14.0, "z": -2, "dim": 0.16},
		{"count": 10, "scale": 0.45, "speed": 24.0, "z": -1, "dim": 0.26},
		{"count": 12, "scale": 0.55, "speed": 34.0, "z": -1, "dim": 0.34},
	]
	for layer in layers:
		for i in int(layer["count"]):
			var spr := Sprite2D.new()
			spr.set_script(BgMineScript)
			# 35% bomblets for variety (mirrors the live minefield mix).
			spr.texture = BOMBLET_BG_TEX if (rng.randf() < 0.35) else MINE_BG_TEX
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.scale = Vector2.ONE * float(layer["scale"])
			# Plain MIX blend, dimmed + semi-transparent so they read as distant background.
			# (The old BLEND_MODE_MUL multiplied the sprite's transparent border to BLACK,
			# painting a black box around every mine — Roman 2026-06-11.)
			spr.modulate = Color(0.6, 0.6, 0.66, 0.7)
			spr.position = Vector2(rng.randf_range(-16.0, 496.0), rng.randf_range(-270.0, 270.0))
			spr.z_index = int(layer["z"])
			spr.fall_speed = float(layer["speed"])
			add_child(spr)
			# Dimmed pulse light (the live-mine warning pixel, dimmed for background).
			var pulse := ColorRect.new()
			pulse.size = Vector2(1.5, 1.5)
			pulse.position = Vector2(-0.75, -0.75)
			pulse.color = Color(1.0, 0.35, 0.25, 1.0)
			pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var pmat := CanvasItemMaterial.new()
			pmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			pulse.material = pmat
			spr.add_child(pulse)
			var dim: float = float(layer["dim"])
			var ptw := pulse.create_tween().set_loops()
			ptw.tween_property(pulse, "modulate:a", dim, rng.randf_range(0.7, 1.2)).set_trans(Tween.TRANS_SINE)
			ptw.tween_property(pulse, "modulate:a", dim * 0.15, rng.randf_range(0.7, 1.2)).set_trans(Tween.TRANS_SINE)


# Render a staged star-system: clear LayerPlanet ONCE, then spawn each body at a
# frac-derived screen position + scale-derived size. `system` entries are dicts:
#   {kind, planet_idx, planet_seed, frac, scale, star_color}
func _spawn_system(system: Array) -> void:
	if _layer_planet.has_method("clear_planet"):
		_layer_planet.clear_planet()
	for body in system:
		var b: Dictionary = body
		var p_idx: int = int(b.get("planet_idx", 8))
		var p_seed: int = int(b.get("planet_seed", 0))
		var scale_f: float = float(b.get("scale", 1.0))
		var frac: float = clampf(float(b.get("frac", 0.0)), 0.0, 1.0)
		var star_color: Color = b.get("star_color", Color.WHITE)
		# RAW (unfloored) px from the size ceiling — this is what decides whether
		# the body is close enough to render as a sphere or far enough to collapse
		# to a glowing dot. Do NOT floor before this branch (see dot-threshold).
		var raw_px: float = SYS_SIZE_CEILING * scale_f
		# Position: x by frac across the comfortable spread; y is a per-seed
		# jitter within the band, with larger (nearer) bodies nudged lower so
		# they read as more central/present.
		var jrng := RandomNumberGenerator.new()
		jrng.seed = abs(p_seed) ^ 0x5A17C0DE
		var center_x: float = lerpf(SYS_X_MIN, SYS_X_MAX, frac)
		if raw_px < SYS_DOT_THRESHOLD_PX:
			# Extreme distance: render a tiny additive glowing dot in the body's
			# MAIN color instead of a degenerate sphere. The dot sits centered in
			# the upper band (no big-body lower-nudge, it has no size to nudge).
			var dot_color: Color = _body_main_color(p_idx, star_color)
			var dot_y: float = SYS_Y_BASE + jrng.randf_range(0.0, SYS_Y_JITTER)
			var dot_center: Vector2 = Vector2(center_x, dot_y)
			if _layer_planet.has_method("spawn_system_dot"):
				_layer_planet.spawn_system_dot(dot_center, SYS_DOT_PX, dot_color)
			continue
		# Close enough to read as a body — floor so it doesn't degenerate.
		var size_px: float = maxf(SYS_MIN_BODY_PX, raw_px)
		var y_top: float = SYS_Y_BASE + jrng.randf_range(0.0, SYS_Y_JITTER) + scale_f * SYS_Y_LOWER_BIG
		var top_left: Vector2 = Vector2(center_x - size_px * 0.5, y_top)
		_layer_planet.spawn_system_body(p_idx, size_px, top_left, p_seed, star_color)


# Representative MAIN color for a far body's glowing dot. The star (planet_idx
# 8) uses its actual star_color; planets use the per-type PLANET_TINT palette
# (PixelPlanets are shader-driven ColorRects with no CPU-readable texture, so
# _derive_color can't be used here — Roman 2026-05-30).
func _body_main_color(planet_idx: int, star_color: Color) -> Color:
	if planet_idx == 8:
		return Color(star_color.r, star_color.g, star_color.b, 1.0)
	var c: Color = PLANET_TINT.get(planet_idx, Color(0.8, 0.85, 1.0))
	return Color(c.r, c.g, c.b, 1.0)


func _apply_tints(planet_idx: int) -> void:
	var base_tint: Color = PLANET_TINT.get(planet_idx, Color.WHITE)
	var skip := planet_idx in SKIP_TINT

	_set_modulate(_layer_stellar_far,  base_tint.lerp(Color.WHITE, 0.75) if not skip else Color.WHITE)
	_set_modulate(_layer_stellar_mid,  base_tint.lerp(Color.WHITE, 0.60) if not skip else Color.WHITE)
	_set_modulate(_layer_stellar_near, base_tint.lerp(Color.WHITE, 0.45) if not skip else Color.WHITE)


func _set_modulate(layer: Node, color: Color) -> void:
	if layer == null:
		return
	if "modulate_color" in layer:
		layer.modulate_color = color
	else:
		var cm := layer.get_node_or_null("CanvasModulate") as CanvasModulate
		if cm:
			cm.color = color


func _setup_composite(planet_idx: int) -> void:
	if _layer_composite == null:
		return
	var base_tint: Color = PLANET_TINT.get(planet_idx, Color.WHITE)
	var skip := planet_idx in SKIP_TINT
	var grade_color := Color.WHITE.lerp(base_tint, tint_alpha) if not skip else Color.WHITE

	var cm := _layer_composite.get_node_or_null("CanvasModulate") as CanvasModulate
	if cm:
		cm.color = grade_color

	var grade := _layer_composite.get_node_or_null("GradeRect") as ColorRect
	if grade and grade.material == null:
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		grade.material = mat

	var vignette := _layer_composite.get_node_or_null("Vignette") as Sprite2D
	if vignette and vignette.texture == null:
		var mat2 := CanvasItemMaterial.new()
		mat2.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		vignette.material = mat2
		var grad := Gradient.new()
		grad.colors = PackedColorArray([Color(1,1,1,1), Color(0.74, 0.74, 0.74, 1)])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 64
		tex.height = 64
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to   = Vector2(1.0, 0.5)
		vignette.texture = tex


func _process(delta: float) -> void:
	var drift_delta := drift_speed * delta
	for layer in _scroll_layers:
		if layer != null and layer.has_method("scroll"):
			layer.scroll(drift_delta * float(layer.get("scroll_rate") if "scroll_rate" in layer else 1.0))
	if _layer_stars != null and _layer_stars.has_method("scroll_stars"):
		_layer_stars.scroll_stars(drift_delta)
