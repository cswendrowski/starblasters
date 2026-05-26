extends Node2D

# Per-sector decorative backdrop using the PixelPlanets shaders.
# Picks a random planet variant per node visit, scatters asteroids,
# slowly drifts everything downward over the level's duration.
# Also overlays a procedural twinkling starfield so the void doesn't
# feel like a tiled image.

const PLANETS = {
	0: "res://Planets/LavaWorld/LavaWorld.tscn",
	1: "res://Planets/IceWorld/IceWorld.tscn",
	2: "res://Planets/DryTerran/DryTerran.tscn",
	3: "res://Planets/GasPlanet/GasPlanet.tscn",
	4: "res://Planets/NoAtmosphere/NoAtmosphere.tscn",
	5: "res://Planets/LandMasses/LandMasses.tscn",
	6: "res://Planets/BlackHole/BlackHole.tscn",
	7: "res://Planets/Galaxy/Galaxy.tscn",
	8: "res://Planets/Star/Star.tscn",
}

# How far above the viewport top to position each planet (as a fraction of
# planet_size). 0.78 means the planet sits high, only the bottom curve peeks
# in — works for "globe" textures where the planet is the bottom-left circle
# of the ColorRect. Black hole / galaxy / star fill the whole rect, so they
# need a smaller offset to actually show on screen.
const PLANET_VERT_OFFSET = {
	0: 0.78,  # LavaWorld - globe
	1: 0.78,  # IceWorld - globe
	2: 0.78,  # DryTerran - globe
	3: 0.78,  # GasPlanet - globe
	4: 0.78,  # NoAtmosphere - globe
	5: 0.78,  # LandMasses - globe
	6: 0.25,  # BlackHole - centered phenomenon
	7: 0.25,  # Galaxy - centered phenomenon
	8: 0.45,  # Star - mid-high phenomenon
}
const ASTEROID_SCENE = "res://Planets/Asteroids/Asteroid.tscn"
const STARFIELD_SHADER = "res://graphics/starfield.gdshader"
const NEBULA_SHADER = "res://graphics/nebula.gdshader"
const NEBULA2_SHADER = "res://graphics/nebula2.gdshader"
const STARSTUFF_SHADER = "res://graphics/starstuff.gdshader"
const SPACE_COLORSCHEME = "res://SpaceBG/Colorscheme.tres"

const PLANET_DRIFT_MULT_SLOW := 0.18
# Per-planet "anchor tint" — a soft color wash applied over the entire
# parallax to unify the palette around the visual "star" of the level. Hue
# follows the planet variant; alpha is intentionally light so detail and
# interest survive (Roman, 2026-05-16: "unify colors, don't rob interest").
const PLANET_TINT = {
	0: Color(1.00, 0.45, 0.22),  # LavaWorld   → hot orange
	1: Color(0.55, 0.75, 1.00),  # IceWorld    → cool blue
	2: Color(1.00, 0.82, 0.55),  # DryTerran   → sandy warm
	3: Color(0.80, 0.55, 1.00),  # GasPlanet   → purple-magenta
	4: Color(0.70, 0.78, 0.90),  # NoAtmosphere → muted blue-grey
	5: Color(0.55, 0.92, 0.78),  # LandMasses  → green-cyan
	6: Color(0.55, 0.30, 0.70),  # BlackHole   → deep violet
	7: Color(0.78, 0.55, 1.00),  # Galaxy      → cool magenta
	8: Color(1.00, 0.88, 0.55),  # Star        → warm yellow-white
}
@export_range(0.0, 0.5) var tint_alpha: float = 0.09

@export var drift_speed: float = 22.0
# Stellar foundation: slightly bigger + slower per Roman 2026-05-16
# parallax overhaul ("should be somewhat bigger and move a bit slower").
@export var planet_size: float = 240.0  # 480×270 widescreen rework — sized so the body comfortably peeks in at the top of the new aspect without smothering the playfield
@export_range(0.0, 0.9) var planet_size_variance: float = 0.35
@export var planet_drift_mult: float = 0.10
@export var asteroid_count: int = 3
@export var asteroid_spin_min: float = 0.03
@export var asteroid_spin_max: float = 0.10
# Minimum decorative asteroid size in viewport pixels. Below ~16 vp-px the
# procgen shader can't generate a recognizable rock silhouette at 1:1
# pixel parity (it'd render as 16 indistinct cells). Cobalt 2026-05-20 —
# this is the legibility floor for "somewhat small" parallax asteroids.
@export_range(8.0, 48.0) var asteroid_min_size: float = 16.0
# Per-sector chance of asteroid spawns. Levels without asteroids feel more
# like deep-space cruising.
@export_range(0.0, 1.0) var asteroid_presence: float = 0.65
# Multi-band asteroid distribution. Deep-band asteroids are tiny and dim and
# drift slowly; near-band asteroids are big, bright, and fast.
@export var asteroid_deep_count: int = 4
@export var asteroid_mid_count: int = 5
@export var asteroid_near_count: int = 3
# Warp-streak foreground layer for hyperspace-ish rush feel.
@export var use_warp_streaks: bool = true
@export var warp_streak_count: int = 14
@export var warp_streak_speed: float = 520.0
@export_range(0.0, 1.0) var surface_time_scale: float = 0.15
# Pixel parity (Cobalt 2026-05-20): every procedural backdrop body
# (planets, asteroids, nebula) renders at exactly `pixel_density` viewport
# pixels per art pixel, regardless of how big the body is on screen. Set
# to 1.0 to match the player ship's 1 viewport-px per art-pixel. Raise
# above 1.0 (e.g., 2.0) for a chunkier "deep space" look.
#
# This replaces the old per-knob system (planet_pixels, asteroid_pixels,
# nebula_pixels, pixels_per_size, pixels_floor, pixels_ceiling), all of
# which were partial fixes for the same underlying equation. The rule:
#
#     shader_pixels = display_size_in_vp / pixel_density
#
# combined with resetting each procedural body's internal ColorRect back
# to its canonical size, gives 1:1 parity from tiny moons to screen-
# filling black holes.
@export_range(0.5, 6.0) var pixel_density: float = 1.0
# Safety-net minimum cell count. Asteroid bands clamp their own size to
# `asteroid_min_size` so the floor rarely kicks in for them; this is here
# in case something else (companion moon, custom spawn) feeds a tiny
# value. 16 is the legibility threshold for the procgen rock silhouette.
@export_range(8.0, 64.0) var pixels_floor: float = 16.0
# Canonical ColorRect logical sizes by node name. PixelPlanets'
# set_pixels() resizes inner ColorRects to (amount, amount), which
# couples shader resolution to display footprint. After calling
# set_pixels we reset every ColorRect back to its canonical size so the
# shader runs at the requested cell count over the original area. Ring
# overlays (BlackHole's Disk, GasPlanetLayers' Ring) are authored as 3×
# the body's footprint, so they get 300×300 instead of 100×100.
# Each entry: {size, pos}. set_pixels() in PixelPlanets writes both —
# Disk/Ring overlays sit at a negative offset so the ring extends past
# the body. Resetting only size and leaving position alone left flares
# + discs drifting off-screen.
const COLORRECT_DEFAULT_CANONICAL := {"size": Vector2(100.0, 100.0), "pos": Vector2.ZERO}
const COLORRECT_CANONICAL_BY_NAME := {
	"Disk":       {"size": Vector2(300.0, 300.0), "pos": Vector2(-100.0, -100.0)},
	"Ring":       {"size": Vector2(300.0, 300.0), "pos": Vector2(-100.0, -100.0)},
	"Blobs":      {"size": Vector2(200.0, 200.0), "pos": Vector2(-50.0, -50.0)},
	"StarFlares": {"size": Vector2(200.0, 200.0), "pos": Vector2(-50.0, -50.0)},
}
# Procedural starfield overlay. Set density=0 to disable.
@export_range(0.0, 80.0) var starfield_density: float = 40.0
@export_range(0.0, 200.0) var starfield_scroll: float = 8.0
@export_range(0.80, 0.99) var starfield_threshold: float = 0.93
# Nebula background layer (custom soft shader).
@export var use_nebula: bool = true
@export var use_starstuff: bool = false  # legacy, kept for compatibility
@export_range(10.0, 1000.0) var starstuff_pixels: float = 200.0  # legacy
@export_range(1.0, 8.0) var nebula_octaves: float = 5.0
@export_range(0.0, 0.05) var nebula_drift: float = 0.004
@export_range(0.0, 0.1) var starstuff_drift: float = 0.002      # legacy
@export_range(0.0, 1.0) var nebula_alpha: float = 0.22
@export_range(0.0, 2.0) var nebula_density: float = 0.9
@export_range(0.0, 1.0) var nebula_edge: float = 0.4
@export_range(0.5, 8.0) var nebula_scale: float = 2.5
# Override planet pick. -1 = use sector logic; 0..8 = force this planet idx.
# Test bed uses this to cycle through planet variants.
@export var forced_planet_idx: int = -1

var _shader_time: float = 0.0
var _last_planet_idx: int = -1

func _ready() -> void:
	var sector_num: int = 0
	var seed_val: int = 0
	var visit_count: int = 0
	var node_id: String = ""
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		sector_num = run.sectors_cleared
		seed_val = run.run_seed
		visit_count = run.visited_nodes.size()
		node_id = run.current_node_id
	# Per-scene RNG so spawn positions/random planet pick differ per node visit
	var step: int = max(visit_count - 1, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + step * 1009 + sector_num * 9973
	# Planet pick: the sector node carries its own planet_idx in
	# Run.current_stellar — read that first so the combat backdrop matches
	# what the player saw on the sector map. Falls back to a random roll
	# when the node didn't seed one (Test Hazard etc.).
	var planet_idx: int = -1
	if has_node("/root/Run"):
		var stellar = get_node("/root/Run").current_stellar
		if stellar is Dictionary and stellar.has("planet_idx"):
			planet_idx = int(stellar["planet_idx"])
	if planet_idx < 0 or planet_idx >= PLANETS.size():
		planet_idx = _weighted_celestial_pick(rng)
		if planet_idx == _last_planet_idx:
			# Re-roll once on a back-to-back repeat so the previous level's
			# pick doesn't show up twice in a row.
			planet_idx = _weighted_celestial_pick(rng)
	# Test bed / debug override always wins
	if forced_planet_idx >= 0 and forced_planet_idx < PLANETS.size():
		planet_idx = forced_planet_idx
	_last_planet_idx = planet_idx
	# Render order (back → front):
	#   1. DeepSky base (solid cleared color)
	#   2. Starfield — far / mid / near. Stars are literally the most distant
	#      thing, so they sit BEHIND the nebula.
	#   3. Nebula clouds — two passes at different scales/speeds for that
	#      "dust cloud has depth" feel.
	#   4. Planet — single dramatic backdrop, drifts slowly down across the
	#      whole level.
	#   5. Asteroids — three bands (deep, mid, near) with different sizes,
	#      brightnesses, and drift speeds. Each level rolls whether to spawn
	#      them at all.
	#   6. Warp streaks — sparse hyperspace lines, foreground.
	# Nebula band info from the node — when present, push the band's tint
	# into the nebula layers and bump the anchor tint so the whole scene
	# reads as "we're inside that nebula".
	var nebula_band: String = ""
	var nebula_tint: Color = Color(1, 1, 1, 1)
	# V3 sector-map POI descriptor — drives planet/asteroid/moon/star fields
	# so the combat scene visually echoes the node the player clicked.
	var poi_has_asteroids_override: bool = false
	var poi_asteroid_density: float = 0.0
	var poi_moons: Array = []
	var poi_star_color: Color = Color(1, 1, 1, 1)
	var poi_star_cool: bool = false
	var has_poi_star: bool = false
	if has_node("/root/Run"):
		var stellar = get_node("/root/Run").current_stellar
		if stellar is Dictionary:
			nebula_band = String(stellar.get("nebula_band", ""))
			nebula_tint = stellar.get("nebula_tint", Color(1, 1, 1, 1))
			if stellar.has("has_asteroids"):
				poi_has_asteroids_override = bool(stellar.get("has_asteroids", false))
			poi_asteroid_density = float(stellar.get("asteroid_density", 0.0))
			if stellar.has("moons") and stellar.get("moons") is Array:
				poi_moons = stellar.get("moons")
			if stellar.has("star_color"):
				poi_star_color = stellar.get("star_color", Color(1, 1, 1, 1))
				poi_star_cool = bool(stellar.get("star_cool", false))
				has_poi_star = true
	# Roman, 2026-05-16 parallax overhaul: 3 foundation layers (back, bright,
	# slow) + up to 5 above (progressively dimmed toward silhouettes against
	# the foundation lights). The dominant_tint pushed into the silhouette
	# modulate is sampled from the planet's palette so the silhouette
	# shadowing matches what the player is lit by.
	var dominant_tint: Color = PLANET_TINT.get(planet_idx, Color(1, 1, 1, 1))
	_spawn_deep_clear(poi_star_color if has_poi_star else Color(1, 1, 1, 1), poi_star_cool, has_poi_star)
	# Foundation 1 + 2: starfields. Bright, slow.
	if starfield_density > 0.0:
		_spawn_starfield()
	# Above-foundation: nebulae as the first silhouette band.
	_spawn_nebulae(rng, nebula_band, nebula_tint)
	_apply_silhouette_to_layer_named("NebulaFar", 1, dominant_tint)
	_apply_silhouette_to_layer_named("NebulaNear", 2, dominant_tint)
	# Foundation 3: planet (stellar object). Boosted size + bloom so it
	# anchors as the dominant light source.
	if PLANETS.has(planet_idx):
		_spawn_planet(PLANETS[planet_idx], rng, planet_idx)
		# Sector-map POI moons: drop moonlets at fixed offsets around the
		# foundation planet and let the shared drift loop carry them downward
		# at the same speed as the planet. No per-frame orbit (Roman, 2026-05-24
		# — "Pixel moons should not orbit when placed in the background").
		if not poi_moons.is_empty():
			_attach_poi_moons(poi_moons)
	# Per-sector roll: do we have asteroids in this level at all?
	# Asteroid Field hazard forces parallax-side asteroids in every layer at
	# higher density (Roman, 2026-05-16). Detected via Run.current_hazard_subtype.
	var asteroid_hazard: bool = false
	if has_node("/root/Run"):
		asteroid_hazard = String(get_node("/root/Run").current_hazard_subtype) == "asteroid_field"
	var has_asteroids: bool = asteroid_hazard or poi_has_asteroids_override or (rng.randf() < asteroid_presence)
	# Asteroid hazard doubles density again per Roman, 2026-05-16
	# ("doubled across all parallax layers"). 2.5 → 5.0.
	var density_mult: float = 5.0 if asteroid_hazard else 1.0
	# Sector-map POI declares an asteroid object (large or cluster) — ramp
	# the per-band counts so the combat scene reflects what the player saw.
	# asteroid_density runs roughly 0.6 (single large) .. 1.2 (cluster).
	if poi_asteroid_density > 0.0 and not asteroid_hazard:
		density_mult *= 1.5 * max(1.0, poi_asteroid_density)
	if has_asteroids:
		for i in range(int(asteroid_deep_count * density_mult)):
			var a_d := _spawn_asteroid_in_band(rng, "deep")
			_apply_silhouette_to_node(a_d, 3, dominant_tint)
		for i in range(int(asteroid_mid_count * density_mult)):
			var a_m := _spawn_asteroid_in_band(rng, "mid")
			_apply_silhouette_to_node(a_m, 4, dominant_tint)
		for i in range(int(asteroid_near_count * density_mult)):
			var a_n := _spawn_asteroid_in_band(rng, "near")
			_apply_silhouette_to_node(a_n, 4, dominant_tint)
	# Mine hazard background flair (Roman, 2026-05-18: "Place ongoing
	# waves of mines in the top three parallax layers. These will be
	# harmless, but will sell the density of the minefield"). Only on
	# minefield hazard nodes.
	var minefield_hazard: bool = false
	if has_node("/root/Run"):
		minefield_hazard = String(get_node("/root/Run").current_hazard_subtype) == "minefield"
	if minefield_hazard:
		_spawn_background_mines(rng)
	if use_warp_streaks:
		_spawn_warp_streaks()
		_apply_silhouette_to_layer_named("WarpStreaks", 4, dominant_tint)
	# Unifying anchor tint — added last so it draws over everything in the
	# Backdrop. Gameplay objects (player, enemies, bullets) are siblings of
	# the Backdrop and stay clear.
	# Color grading (Roman, 2026-05-16): anchor the whole scene to the
	# dominant color of the level. If the node sits in a nebula band, that
	# nebula tint wins (it's the big visual element). Otherwise pull from
	# the planet palette.
	# Stellar phenomena (BlackHole idx 6, Star idx 8) bypass the multiplicative
	# anchor tint so the disc/halo don't get dimmed ~10% (Roman, 2026-05-17:
	# "the glow should make celestial objects BRIGHTER, including planets and
	# stars"). Other planets still get the tint for the unified-palette pass.
	if planet_idx == 6 or planet_idx == 8:
		pass
	elif nebula_band != "":
		_spawn_anchor_tint_color(nebula_tint, tint_alpha * 1.7)
	else:
		_spawn_anchor_tint(planet_idx)
	# Vignette: darken the screen corners slightly so the centre of the
	# playfield "pops" — same trick photographers use for depth focus.
	_spawn_vignette()


# Soft color overlay that unifies the parallax palette around the level's
# "star" (the planet variant in play). Uses MULTIPLY blend so we DARKEN the
# scene toward the tint hue rather than brightening it (Roman, 2026-05-16).
# Strength controlled by lerping the multiplier toward white — tint_alpha=0
# means white = no change; tint_alpha=1 means full hue mul.
# Adds a soft vignette over the parallax. Corners darken, centre stays
# bright — pulls the eye to the playfield without obscuring it. MULTIPLY
# blend with a radial-gradient sprite that's white in the middle, ~50%
# at the corners.
func _spawn_vignette() -> void:
	var sprite := Sprite2D.new()
	sprite.name = "Vignette"
	sprite.texture = _build_vignette_texture()
	# Cover the 480×270 viewport. Texture is 64×80; uniform 7.5× scales it to
	# 480×600, more than enough to span the playfield horizontally and
	# vertically with comfortable falloff. Position = viewport centre.
	# (Previous values 5× / (160,200) were sized for the legacy 320×400
	# viewport and left the right 160 px of the new aspect un-vignetted —
	# read as a bright vertical bar on the right side. Cody 2026-05-19.)
	sprite.scale = Vector2(7.5, 7.5)
	sprite.position = Vector2(240, 135)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	sprite.material = mat
	add_child(sprite)


static func _build_vignette_texture() -> Texture2D:
	# White in the centre, ramping to ~50% at the corners. Multiplied, this
	# leaves the playfield untouched while subtly darkening edges.
	var g = Gradient.new()
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(0.92, 0.92, 0.95, 1),
		Color(0.74, 0.74, 0.80, 1),
	])
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	var t = GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 80
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


func _spawn_anchor_tint(planet_idx: int) -> void:
	var c: Color = Color(1, 1, 1, 1)
	if PLANET_TINT.has(planet_idx):
		c = PLANET_TINT[planet_idx]
	_spawn_anchor_tint_color(c, tint_alpha)


# Color grading helper. `alpha` is the strength of the multiplicative shift
# toward `hue` (1.0 white = no shift).
func _spawn_anchor_tint_color(hue: Color, alpha: float) -> void:
	if alpha <= 0.001:
		return
	var multiplier: Color = Color(1, 1, 1, 1).lerp(Color(hue.r, hue.g, hue.b, 1.0), clamp(alpha, 0.0, 1.0))
	multiplier.a = 1.0
	var tint = ColorRect.new()
	tint.name = "AnchorTint"
	tint.color = multiplier
	tint.size = Vector2(480, 270)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	tint.material = mat
	add_child(tint)

func _spawn_deep_clear(star_color: Color = Color(1, 1, 1, 1), star_cool: bool = false, has_poi_star: bool = false) -> void:
	var deep = ColorRect.new()
	deep.name = "DeepSky"
	# Base deep-space color, then bias toward the POI's row star color. Warm
	# stars push the deep sky a touch warm, cool stars a touch cool — a wash,
	# not a recolor (alpha ~0.12 keeps the planet/nebula readable).
	var base := Color(0.06, 0.06, 0.09, 1.0)
	if has_poi_star:
		# Push toward warm-orange or cool-blue bias before blending the
		# specific star hue, so the difference between row 0 (cool blue) and
		# row 2 (warm red) reads even when the actual hues are similar.
		var bias := Color(0.50, 0.62, 0.95, 1.0) if star_cool else Color(0.95, 0.62, 0.40, 1.0)
		var biased := base.lerp(Color(base.r * bias.r * 1.4, base.g * bias.g * 1.4, base.b * bias.b * 1.4, 1.0), 0.35)
		var tinted := biased.lerp(Color(star_color.r * 0.18, star_color.g * 0.18, star_color.b * 0.18, 1.0), 0.45)
		base = tinted
	deep.color = base
	deep.size = Vector2(480, 270)
	deep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(deep)


# Two nebula passes for volumetric dust feel. Far pass is huge, soft and slow.
# Near pass is denser, more contrasty, drifts noticeably faster — sells the
# idea that we're passing through an actual cloud, not painted-on backdrop.
func _spawn_nebulae(rng: RandomNumberGenerator, band_tag: String = "", band_tint: Color = Color(1, 1, 1, 1)) -> void:
	if not use_nebula:
		return
	var cs = load(SPACE_COLORSCHEME)
	var sd_base: float = 1.0 + (float(rng.seed % 900) / 100.0)
	# A non-empty band_tag means this node is inside a sector-map nebula
	# band — push the tint via ColorRect.modulate so the existing shader
	# colorscheme is biased toward the band hue, and bump the alpha so the
	# nebula reads stronger.
	var in_band: bool = band_tag != ""
	var tint_for_layer: Color = band_tint if in_band else Color(1, 1, 1, 1)
	var alpha_mult: float = 1.6 if in_band else 1.0
	# Nebula cell count derives from viewport size + pixel_density so each
	# cell lands at the target viewport-pixels-per-art-pixel. Same value
	# for far + near — both targets are player-pixel parity.
	var nebula_px: float = 480.0 / max(pixel_density, 0.01)
	# FAR nebula — huge, very soft, slow, and dimmed for depth.
	_make_space_layer(
		"NebulaFar", NEBULA_SHADER, cs,
		sd_base, nebula_px, int(nebula_octaves), nebula_drift * 0.6,
		nebula_alpha * 0.4 * alpha_mult, nebula_density * 0.6, nebula_scale * 1.4,
		tint_for_layer
	)
	# NEAR nebula — smaller scale, contrastier, drifts faster.
	# Staged rollout of nebula2.gdshader: near pass gets the domain-warped
	# / filament version with conservative swirl, far pass still on the
	# original shader. If the near pass reads right, swap far too.
	_make_space_layer(
		"NebulaNear", NEBULA2_SHADER, cs,
		sd_base + 4.3, nebula_px, int(nebula_octaves), nebula_drift * 2.0,
		nebula_alpha * alpha_mult, nebula_density, nebula_scale,
		tint_for_layer
	)

func _make_space_layer(layer_name: String, shader_path: String, colorscheme, sd: float, px: float, octaves: int, drift: float = 0.0, alpha_override: float = -1.0, density_override: float = -1.0, scale_override: float = -1.0, modulate_tint: Color = Color(1, 1, 1, 1)) -> void:
	var shader = load(shader_path)
	if shader == null:
		return
	var rect = ColorRect.new()
	rect.name = layer_name
	rect.size = Vector2(480, 270)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color(0, 0, 0, 0)
	var mat = ShaderMaterial.new()
	mat.shader = shader
	if shader_path == NEBULA_SHADER or shader_path == NEBULA2_SHADER:
		# Per-layer overrides so we can stack multiple nebula passes at
		# different scales / alphas / densities for volumetric depth.
		var use_scale: float = scale_override if scale_override > 0.0 else nebula_scale
		var use_alpha: float = alpha_override if alpha_override > 0.0 else nebula_alpha
		var use_density: float = density_override if density_override > 0.0 else nebula_density
		mat.set_shader_parameter("scale", use_scale)
		mat.set_shader_parameter("octaves", octaves)
		mat.set_shader_parameter("seed", sd)
		mat.set_shader_parameter("pixels", px)
		mat.set_shader_parameter("drift_speed", drift)
		mat.set_shader_parameter("max_alpha", use_alpha)
		mat.set_shader_parameter("density", use_density)
		mat.set_shader_parameter("edge_sharpness", nebula_edge)
		mat.set_shader_parameter("uv_correct", Vector2(1.0, 1.0))
		if colorscheme != null:
			mat.set_shader_parameter("colorscheme", colorscheme)
		# nebula2-only knobs — conservative defaults for the live near pass.
		# Swirl is gentle (0.8) so it reads as motion in the cloud, not a
		# painterly distortion. Filaments are subtle (0.2). Opacity left at
		# 1.0 so the existing max_alpha threshold continues to drive fade.
		if shader_path == NEBULA2_SHADER:
			mat.set_shader_parameter("warp_strength", 0.8)
			mat.set_shader_parameter("warp_scale", 1.0)
			mat.set_shader_parameter("wisp_strength", 0.2)
			mat.set_shader_parameter("opacity", 1.0)
			mat.set_shader_parameter("scroll_offset", Vector2.ZERO)
	else:
		# Legacy PixelSpace StarStuff fallback (kept for option toggling)
		mat.set_shader_parameter("size", 50.0)
		mat.set_shader_parameter("OCTAVES", octaves)
		mat.set_shader_parameter("seed", sd)
		mat.set_shader_parameter("pixels", px)
		mat.set_shader_parameter("should_tile", false)
		mat.set_shader_parameter("reduce_background", false)
		mat.set_shader_parameter("uv_correct", Vector2(1.0, 1.0))
		mat.set_shader_parameter("drift_speed", drift)
		if colorscheme != null:
			mat.set_shader_parameter("colorscheme", colorscheme)
	rect.material = mat
	# Bias the existing nebula colorscheme toward the sector-map band tint
	# via ColorRect.modulate.
	if modulate_tint != Color(1, 1, 1, 1):
		rect.modulate = modulate_tint
	add_child(rect)

func _spawn_starfield() -> void:
	var shader = load(STARFIELD_SHADER)
	if shader == null:
		return
	# Foundation 1 + 2: two bright, slow starfields per Roman 2026-05-16
	# parallax overhaul. These are the deepest visible layers and stay
	# bright/clear — everything in front of them gets silhouetted, not
	# these.  Was three layers (far/mid/near) collapsing into atmospheric
	# perspective; now just two foundation-density passes.
	var density_scale: float = starfield_density / 40.0
	var scroll_scale: float = starfield_scroll / 8.0
	var layers = [
		# Foundation 1 — denser, slowest, soft white. Reads as a dust of
		# pinpricks that anchor the deep background.
		{"name": "StarsFoundation1", "density": 32.0, "scroll":  3.0, "thresh": 0.95, "modulate": Color(0.95, 0.98, 1.00, 1.00), "seed": Vector2(0.0,  0.0)},
		# Foundation 2 — slightly less dense, slightly faster, full-bright.
		{"name": "StarsFoundation2", "density": 48.0, "scroll":  8.0, "thresh": 0.92, "modulate": Color(1.10, 1.10, 1.10, 1.00), "seed": Vector2(50.0, 17.0)},
	]
	for layer in layers:
		var rect = ColorRect.new()
		rect.name = layer["name"]
		rect.color = Color(0, 0, 0, 0)
		rect.size = Vector2(480, 270)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.modulate = layer["modulate"]
		var mat = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("density", float(layer["density"]) * density_scale)
		mat.set_shader_parameter("scroll_speed", float(layer["scroll"]) * scroll_scale)
		mat.set_shader_parameter("star_threshold", float(layer["thresh"]))
		mat.set_shader_parameter("seed_offset", layer["seed"])
		rect.material = mat
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


# Lightweight companion spawner — same lifecycle hooks as _spawn_planet
# but at a custom size + position. No companion-of-companion recursion.
func _spawn_companion_body(scene_path: String, rng: RandomNumberGenerator, planet_idx_used: int, x: float, y: float, actual_size: float) -> void:
	var ps = load(scene_path)
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
	_apply_pixel_parity(p, actual_size)
	if "override_time" in p:
		p.override_time = true
	if p.has_method("set_seed"):
		p.set_seed(rng.randi() % 100000)
	if p.has_method("randomize_colors"):
		p.randomize_colors()
	if p.has_method("set_rotates"):
		p.set_rotates(rng.randf() < 0.7)
	p.position = Vector2(x, y)
	p.set_meta("drift", true)
	p.set_meta("drift_mult", planet_drift_mult)
	p.set_meta("planet_actual_size", actual_size)
	p.set_meta("time_update", true)
	add_child(p)


# Weighted celestial pick (Roman 2026-05-18 — black holes appeared too often).
# Indices 0-5 are planets, 6=BlackHole, 7=Galaxy, 8=Star.
#   Regular planets: 50% total (split evenly across the 6 planet types)
#   Star:            40%
#   BlackHole:        7%
#   Galaxy:           3%
static func _weighted_celestial_pick(rng: RandomNumberGenerator) -> int:
	var r: float = rng.randf()
	if r < 0.07:
		return 6   # BlackHole
	if r < 0.10:
		return 7   # Galaxy
	if r < 0.50:
		return 8   # Star
	# Regular planets: indices 0..5, evenly split across the remaining 50%.
	var planet_count: int = 6
	var planet_roll: float = (r - 0.50) / 0.50   # 0..1 within the planet bucket
	return clampi(int(floor(planet_roll * float(planet_count))), 0, planet_count - 1)


func _spawn_planet(scene_path: String, rng: RandomNumberGenerator, planet_idx_used: int) -> void:
	var ps = load(scene_path)
	if ps == null:
		push_warning("[Backdrop] could not load: %s" % scene_path)
		return
	var p = ps.instantiate()
	# Some planet scenes (Star, GasPlanet, Galaxy) ship with anchors_preset = 15
	# (full rect with negative offsets), which collapses to zero size when
	# reparented under our Node2D Backdrop. Also some have non-zero pivot_offset
	# (e.g. GasPlanet pivots at (100,100)) which combined with our scaling
	# shifts the visual hundreds of pixels off-screen. Force a clean 100x100
	# box with top-left pivot so Control.scale produces the visible planet.
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
	var v: float = clampf(planet_size_variance, 0.0, 0.9)
	var size_mult: float = rng.randf_range(1.0 - v, 1.0 + v)
	var actual_size: float = planet_size * size_mult
	var sf: float = actual_size / 100.0
	p.scale = Vector2(sf, sf)
	# Pixel-parity helper handles set_pixels + ColorRect reset (see
	# _apply_pixel_parity). Same path for every planet variant including
	# BlackHole / GasPlanetLayers, whose ring overlays are special-cased
	# via COLORRECT_CANONICAL_BY_NAME.
	_apply_pixel_parity(p, actual_size)
	if "override_time" in p:
		p.override_time = true
	# Use the full range of Planet builder randomization (Roman, 2026-05-16:
	# "Make sure that generation is using the full range of randomization
	# options"). Each planet variant has its own set_seed + randomize_colors
	# hooks — call them when present so cloud patterns, surface details,
	# and palettes vary per visit.
	if p.has_method("set_seed"):
		p.set_seed(rng.randi() % 100000)
	if p.has_method("randomize_colors"):
		p.randomize_colors()
	if p.has_method("set_rotates"):
		p.set_rotates(rng.randf() < 0.7)
	if p.has_method("set_dither"):
		p.set_dither(rng.randf() < 0.5)
	# Jitter clamped so the planet's bloom/halo (up to ~2.2× actual_size
	# for stars + black holes) doesn't bleed past the 480-wide viewport
	# and form a vertical bright bar on either edge (Cody 2026-05-19).
	var max_glow_half: float = actual_size * 1.1
	var jitter_max: float = max(0.0, 240.0 - max_glow_half - 8.0)
	var jitter: float = rng.randf_range(-jitter_max, jitter_max)
	var x: float = (480.0 - actual_size) * 0.5 + jitter
	var vert_off: float = PLANET_VERT_OFFSET.get(planet_idx_used, 0.78)
	var y: float = -actual_size * vert_off
	p.position = Vector2(x, y)
	p.set_meta("drift", true)
	p.set_meta("drift_mult", planet_drift_mult)
	p.set_meta("planet_actual_size", actual_size)
	p.set_meta("time_update", true)
	# Mark this as the foundation planet so _attach_poi_moons can find it
	# unambiguously — companion bodies share the planet_actual_size meta.
	p.set_meta("is_foundation_planet", true)
	add_child(p)
	# BlackHole disc colors are randomized per-spawn (set_colors via
	# randomize_colors), so the halo can't be hardcoded — it has to be
	# sampled from the actual disc palette or it'll mismatch (Roman, 2026-
	# 05-17: "the disc was green but the halo was magenta"). Extract the
	# dominant disc color now and stash it on the planet's meta so
	# _add_planet_visuals can read it.
	if planet_idx_used == 6 and p.has_method("get_colors"):
		var disc_color: Color = _sample_blackhole_disc_color(p)
		p.set_meta("blackhole_halo_color", disc_color)
	# Visual atmosphere / brightness pass per planet type:
	#   - Stars + Black holes "blow bright": additive bright halo + raised
	#     z_index so the anchor-tint multiplier can't darken them.
	#   - Globe planets get a softer atmosphere glow behind them.
	_add_planet_visuals(p, planet_idx_used, actual_size, x, y)
	# Companions (Roman 2026-05-18). Globe planets can have 1-2 smaller
	# satellite planets/moons; stars have a rare binary-star chance.
	_spawn_companions(rng, planet_idx_used, x, y, actual_size)


# Pull a representative "this is what the disc looks like" color out of the
# BlackHole's randomized palette. get_colors() returns
#   [event_horizon, photon_ring_inner, photon_ring_outer,
#    disc_0, disc_1, disc_2, disc_3, disc_4]
# (3 BlackHole shader cols + 5 Disk shader cols, per BlackHole.gd).
# Averaging the disc colors desaturates to white when the palette spans many
# hues. Instead, pick the most saturated disc color so the halo reads as
# the same hue the player sees in the disc.
func _sample_blackhole_disc_color(planet: Node) -> Color:
	var cols = planet.get_colors()
	if cols == null or cols.size() < 8:
		return Color(0.85, 0.6, 1.0, 1.0)  # fallback to old magenta
	var best: Color = cols[4]
	var best_sat: float = -1.0
	for i in range(3, 8):  # disc colors only
		var c: Color = cols[i]
		var maxc: float = max(c.r, max(c.g, c.b))
		var minc: float = min(c.r, min(c.g, c.b))
		# Saturation × brightness — favor vivid AND luminous over a dim
		# saturated color the eye barely registers.
		var sat: float = (maxc - minc) * maxc
		if sat > best_sat:
			best_sat = sat
			best = c
	return Color(best.r, best.g, best.b, 1.0)

# Per-planet brightness + atmosphere treatment.
#   Star / BlackHole get a hot additive halo and an above-tint z_index so the
#   multiplicative anchor tint can't darken the phenomenon itself.
#   Globe planets get a softer atmosphere glow underneath (where it's a
#   "appropriate" — no atmosphere for the airless NoAtmosphere variant).
func _add_planet_visuals(planet_node: Node, planet_idx: int, actual_size: float, planet_x: float, planet_y: float) -> void:
	# Stellar objects are the FOUNDATION 3 lighting source. Roman, 2026-05-16
	# parallax overhaul: "should also have a bright bloom effect attached
	# to them". Adds a wide, soft outer halo that sits behind the planet
	# regardless of variant — amplifies the existing per-variant haloing.
	var center_pre: Vector2 = Vector2(planet_x + actual_size * 0.5, planet_y + actual_size * 0.5)
	var bloom_color: Color = PLANET_TINT.get(planet_idx, Color(1, 1, 1, 1))
	bloom_color.a = 0.35
	_make_planet_halo(center_pre, actual_size * 1.7, bloom_color, true)
	# Center of the planet visual in Backdrop-local coords. For Control planets
	# we placed the (100x100) rect at top-left planet_pos and scaled it up, so
	# center = planet_pos + size/2.
	var center: Vector2 = Vector2(planet_x + actual_size * 0.5, planet_y + actual_size * 0.5)
	match planet_idx:
		8:  # Star — full additive halo, blow it bright
			_make_planet_halo(center, actual_size * 1.5, Color(1.0, 0.95, 0.6, 0.8))
			_raise_above_tint(planet_node)
		6:  # BlackHole — pulse-glow halo (Roman, 2026-05-17). Color comes
			# from the sampled disc palette (set on planet meta during
			# spawn); pulse_glow shader drives radial falloff + a slow
			# sine intensity pulse so the glow breathes.
			var disc: Color = planet_node.get_meta("blackhole_halo_color", Color(0.85, 0.6, 1.0, 1.0))
			_attach_pulse_glow(center, actual_size * 2.2, disc)
			_raise_above_tint(planet_node)
		7:  # Galaxy — soft additive bloom but a bit dimmer
			_make_planet_halo(center, actual_size * 1.4, Color(0.6, 0.85, 1.0, 0.45))
			_raise_above_tint(planet_node)
		0:  # LavaWorld — magma glow
			_make_planet_halo(center, actual_size * 1.25, Color(1.0, 0.5, 0.2, 0.35), true)
		1:  # IceWorld — pale cyan atmosphere
			_make_planet_halo(center, actual_size * 1.22, Color(0.65, 0.85, 1.0, 0.32), true)
		2:  # DryTerran — thin warm atmosphere
			_make_planet_halo(center, actual_size * 1.18, Color(1.0, 0.82, 0.55, 0.28), true)
		3:  # GasPlanet — vivid magenta atmosphere
			_make_planet_halo(center, actual_size * 1.28, Color(0.85, 0.55, 1.0, 0.4), true)
		5:  # LandMasses — green atmosphere
			_make_planet_halo(center, actual_size * 1.22, Color(0.55, 0.95, 0.75, 0.32), true)
		# NoAtmosphere (4): intentionally no halo — airless rock
		_:
			pass


const PULSE_GLOW_SHADER = preload("res://graphics/pulse_glow.gdshader")


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
	var ci_mat := CanvasItemMaterial.new()
	ci_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	rect.material = mat  # ShaderMaterial wins, blend lives on the canvas item
	# Composite-blend the canvas item via a wrapping CanvasItemMaterial.
	rect.set_meta("drift", true)
	rect.set_meta("drift_mult", planet_drift_mult)
	add_child(rect)
	# Apply additive blend through the rect's own canvas_item material slot.
	# Godot 4: setting `material` accepts both Shader & CanvasItem; we want
	# blending additive so we stash CanvasItemMaterial via a wrapping child.
	# Simplest path: rely on the shader output's alpha (premultiplied glow
	# in the fragment shader writes RGB*a + a, which composites additively
	# when blend_mode = mix on a transparent rect). No extra material needed.


# Additive halo behind/beside the planet. `behind` = drawn behind the planet
# (atmosphere); otherwise drawn over. z_index is kept at 0 so the backdrop
# stays in its own render layer — otherwise the menu UI would draw beneath
# any halo with z_index > 0.
func _make_planet_halo(center: Vector2, diameter: float, color: Color, behind: bool = false) -> void:
	var halo := Sprite2D.new()
	halo.name = "PlanetHalo"
	halo.texture = _build_halo_texture()
	halo.position = center
	var s: float = diameter / 64.0
	halo.scale = Vector2(s, s)
	halo.self_modulate = color
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = mat
	halo.z_index = 0
	# Halos drift with the planet (Roman, 2026-05-16: "lights associated
	# with stellar bodies are attached and moving with them"). Same drift
	# meta as the planet itself — the _process loop already animates any
	# child tagged with `drift`.
	halo.set_meta("drift", true)
	halo.set_meta("drift_mult", planet_drift_mult)
	add_child(halo)


# Previously raised z_index of stars/black holes to escape the tint. That
# leaked out of the Backdrop's z bucket and drew over the menu UI. Now a
# no-op — additive halos handle the "blow bright" via additive blend, which
# still adds brightness even through the multiplicative tint.
func _raise_above_tint(_n: Node) -> void:
	pass


static func _build_halo_texture() -> Texture2D:
	var g = Gradient.new()
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.45),
		Color(1, 1, 1, 0.0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var t = GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


# Background mines for the minefield hazard. Decorative — no collision,
# no damage, just drifting parallax flair in the deep/mid/near bands so
# the playfield feels packed. Density scales with parallax depth so the
# closer bands have more visible mines.
const MINE_BG_TEX := preload("res://graphics/mines/mine_basic.png")

func _spawn_background_mines(rng: RandomNumberGenerator) -> void:
	# Three parallax layers. Cody, 2026-05-18: background mines were too
	# similar in size + brightness to gameplay mines, hard to read what's
	# shootable. Pull scale below 1.0 across the board and apply a cool
	# blue tint so they read as "in the distance" instead of competing
	# with foreground targets.
	# Roman 2026-05-19: visible bg mines, 50% black overlay via blend_mul
	# so they READ as inactive/in-background and can never be confused
	# with live targets. No collision shape — pure decoration.
	var layers := [
		{"count": 6, "scale": 0.35, "speed": 22.0, "z": -2},
		{"count": 10, "scale": 0.45, "speed": 36.0, "z": -1},
		{"count": 12, "scale": 0.55, "speed": 50.0, "z": -1},
	]
	var vp_x: float = 480.0
	var vp_y: float = 270.0
	for layer in layers:
		var count: int = int(layer["count"])
		var spr_scale: float = float(layer["scale"])
		var fall_speed: float = float(layer["speed"])
		var z: int = int(layer["z"])
		for i in count:
			var spr := Sprite2D.new()
			spr.name = "BgMine"
			spr.texture = MINE_BG_TEX
			spr.scale = Vector2(spr_scale, spr_scale)
			# Multiply-blend material: COLOR = src.rgb × dst.rgb. With
			# modulate = (0.5, 0.5, 0.5, 1) the destination pixels get
			# halved where the sprite covers them — a 50% black overlay.
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
			spr.material = mat
			spr.modulate = Color(0.5, 0.5, 0.5, 1.0)
			spr.position = Vector2(rng.randf_range(-16, vp_x + 16), rng.randf_range(-vp_y, vp_y))
			spr.z_index = z
			spr.set_meta("drift", true)
			spr.set_meta("drift_mult", fall_speed / max(1.0, drift_speed))
			add_child(spr)


func _spawn_asteroid_in_band(rng: RandomNumberGenerator, band: String) -> Node:
	var ps = load(ASTEROID_SCENE)
	if ps == null:
		return null
	var a = ps.instantiate()
	# Duplicate the shader material per-instance so each gets its own seed.
	var inner: Node = a.get_node_or_null("Asteroid")
	if inner and "material" in inner and inner.material != null:
		inner.material = inner.material.duplicate()
		# Parallax-only: strip the 1-px outline. Outline reads as "shootable
		# foreground rock" — keep it on the asteroid-hazard / freespace-miner
		# instances (which spawn via scripts/enemies/asteroid.gd, not here)
		# but background parallax rocks should be flat (Roman, 2026-05-25).
		if inner.material is ShaderMaterial:
			(inner.material as ShaderMaterial).set_shader_parameter("draw_outline", false)
		# Per-band size + speed + visual weight. Deep band asteroids are small,
	# dim, slow — they sit behind the stars conceptually but in front of
	# nebula for visual depth. Near band is big, bright, fast — they whip past.
	#
	# Cobalt 2026-05-20: every band's lower bound clamps to
	# `asteroid_min_size` so even the smallest decorative rock stays
	# legible at 1:1 pixel parity. Below ~16 vp-px the procgen shader
	# can't generate a recognizable silhouette.
	var sz: float = 80.0
	var base_drift: float = 1.0
	var modulate_color: Color = Color(1, 1, 1, 1)
	match band:
		"deep":
			sz = rng.randf_range(max(16.0, asteroid_min_size), max(24.0, asteroid_min_size + 4.0))
			base_drift = rng.randf_range(0.18, 0.32)
			modulate_color = Color(0.35, 0.45, 0.65, 0.50)
		"mid":
			sz = rng.randf_range(max(22.0, asteroid_min_size + 4.0), max(32.0, asteroid_min_size + 12.0))
			base_drift = rng.randf_range(0.5, 0.9)
			modulate_color = Color(0.55, 0.65, 0.80, 0.70)
		"near":
			sz = rng.randf_range(max(32.0, asteroid_min_size + 12.0), max(44.0, asteroid_min_size + 24.0))
			base_drift = rng.randf_range(1.1, 1.7)
			modulate_color = Color(0.70, 0.78, 0.90, 0.85)
	var sf: float = sz / 100.0
	a.scale = Vector2(sf, sf)
	a.modulate = modulate_color
	_apply_pixel_parity(a, sz)
	if a.has_method("set_seed"):
		a.set_seed(rng.randi() % 100000)
	if "override_time" in a:
		a.override_time = true
	a.position = Vector2(rng.randf_range(8.0, 304.0 - sz), rng.randf_range(20.0, 300.0))
	if a is Control:
		a.pivot_offset = Vector2(50, 50)
	a.set_meta("drift", true)
	a.set_meta("drift_mult", base_drift)
	var spin: float = rng.randf_range(asteroid_spin_min, asteroid_spin_max)
	if sz < 60:
		spin *= 1.5
	if rng.randi() % 2 == 0:
		spin = -spin
	a.set_meta("spin", spin)
	a.set_meta("time_update", true)
	add_child(a)
	return a


# Apply progressive silhouette darkening + tint toward `dominant` to a
# layer Node. `depth` is 1..4+ where higher = closer to the player = more
# silhouetted. Roman, 2026-05-16: "Parallax contrast should be reduced by
# 15% per level... reach 60% reduction... nearly silhouettes" at the
# top. Cap at 60% per the spec.
func _apply_silhouette_to_node(node: Node, depth: int, dominant: Color) -> void:
	if node == null:
		return
	if not (node is CanvasItem):
		return
	var ci := node as CanvasItem
	# Traditional pixel-art parallax: far layers go DARKER (not hue-shifted to
	# a muddy tint). Keep a faint dominant push so the level still feels
	# unified, but mostly just dim — that's what classic shmups do.
	var strength: float = clamp(float(depth) * 0.12, 0.0, 0.48)
	var hue_pull: float = strength * 0.35  # was 1.0 — was washing layers out
	var base: Color = ci.modulate
	var dim: float = 1.0 - strength
	var r: float = lerp(base.r * dim, dominant.r * dim * 0.7, hue_pull)
	var g: float = lerp(base.g * dim, dominant.g * dim * 0.7, hue_pull)
	var b: float = lerp(base.b * dim, dominant.b * dim * 0.7, hue_pull)
	ci.modulate = Color(r, g, b, base.a)


# Look up a layer by node name (helper for the named ColorRects spawned by
# _make_space_layer / _spawn_warp_streaks) and silhouette it.
func _apply_silhouette_to_layer_named(layer_name: String, depth: int, dominant: Color) -> void:
	var n: Node = get_node_or_null(layer_name)
	if n != null:
		_apply_silhouette_to_node(n, depth, dominant)


# Foreground hyperspace streaks — short bright vertical lines, sparse, very
# fast. Sells the "rush" feel without crowding the playfield.
func _spawn_warp_streaks() -> void:
	var p := GPUParticles2D.new()
	p.name = "WarpStreaks"
	p.amount = warp_streak_count
	p.lifetime = 1000.0 / max(warp_streak_speed, 1.0)
	p.preprocess = p.lifetime  # populate the field on spawn rather than empty
	p.one_shot = false
	p.explosiveness = 0.0
	p.local_coords = false
	p.position = Vector2(240, -10)
	p.texture = _build_streak_texture()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(260, 6, 0)
	m.direction = Vector3(0, 1, 0)
	m.spread = 0.0
	m.initial_velocity_min = warp_streak_speed * 0.8
	m.initial_velocity_max = warp_streak_speed * 1.2
	m.gravity = Vector3.ZERO
	m.scale_min = 0.7
	m.scale_max = 1.6
	var grad = Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.6),
		Color(0.55, 0.7, 1.0, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	var ramp = GradientTexture1D.new()
	ramp.gradient = grad
	ramp.width = 32
	m.color_ramp = ramp
	p.process_material = m
	# Additive blend so streaks add light over the scene.
	var canvas_mat := CanvasItemMaterial.new()
	canvas_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = canvas_mat
	add_child(p)


static func _build_streak_texture() -> Texture2D:
	# Tall thin gradient: faint at the tips, bright in the middle.
	var g = Gradient.new()
	g.colors = PackedColorArray([
		Color(1, 1, 1, 0),
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var t = GradientTexture2D.new()
	t.gradient = g
	t.width = 2
	t.height = 28
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0.5, 0.0)
	t.fill_to = Vector2(0.5, 1.0)
	return t

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
func _apply_pixel_parity(p: Node, displayed_size: float) -> float:
	var px: float = _pixels_for_size(displayed_size)
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


# PlanetKit moon scene. NoAtmosphere is airless rock — the right shape for a
# moon. Spec said "may need to use a small planet scene instead"; this is it.
const POI_MOON_SCENE := "res://Planets/NoAtmosphere/NoAtmosphere.tscn"


# Spawn PlanetKit NoAtmosphere instances as moonlets placed at fixed
# positions around the foundation planet. Each moon gets the standard
# `drift` / `drift_mult` meta so the shared _process drift loop carries it
# downward at the same rate as the planet — no per-frame orbit math, no
# parenting (parenting under the scaled planet Control would distort moon
# scale). Roman, 2026-05-24: "place them around the parent planet at
# appropriate distances and apply the same slow movement as any other
# planets in the background."
#
# Descriptor mapping (from sector_map_v3._derive_moon_descriptors):
#   radius (1..3) -> display_size (18/22/26 vp-px) — keeps the moon legible
#       above `pixels_floor` (16) while staying small vs. the ~240 px planet.
#   color           -> Control.modulate tint (skip randomize_colors to keep
#       the visual influenced by the sector-map moon palette, AND to keep
#       same poi.id deterministic).
#   rx, ry          -> elliptical placement radii scaled up from map-px to
#       combat-px by planet_size_px / 24.0 (the V3 map planet is ~16-32 px,
#       the combat planet is ~planet_size_px).
#   phase           -> static angular offset that determines where on the
#       ellipse the moon sits. `speed` is ignored now (kept on descriptor
#       for back-compat with the sector map).
func _attach_poi_moons(moons: Array) -> void:
	if moons.is_empty():
		return
	# Find the foundation planet (not a companion body — those also have
	# planet_actual_size meta). _spawn_planet tags it with is_foundation_planet.
	var planet: Node = null
	var planet_size_px: float = planet_size
	for c in get_children():
		if c.has_meta("is_foundation_planet"):
			planet = c
			planet_size_px = float(c.get_meta("planet_actual_size"))
			break
	if planet == null:
		return
	var moon_scene = load(POI_MOON_SCENE)
	if moon_scene == null:
		push_warning("[Backdrop] could not load POI moon scene: %s" % POI_MOON_SCENE)
		return
	# Deterministic per-POI seed so a revisit to the same node produces the
	# same moon surfaces. Salt with index per-moon below.
	var base_seed: int = 0
	if has_node("/root/Run"):
		base_seed = abs(hash(String(get_node("/root/Run").current_node_id)))
	# Scale moon orbit radii from the V3 map's tiny planet (~16-32 px) up
	# to the combat planet's footprint.
	var scale_factor: float = planet_size_px / 24.0
	var moon_idx: int = 0
	for m in moons:
		var radius_descriptor: int = clampi(int(m.get("radius", 1)), 1, 3)
		# Map descriptor radius 1/2/3 -> 18/22/26 vp-px. Above pixels_floor
		# (16) so the procgen silhouette renders cleanly; small enough to
		# read as "moon" beside a 240-px planet.
		var actual_size: float = 14.0 + float(radius_descriptor) * 4.0
		var p = moon_scene.instantiate()
		# Reset Control anchors the same way _spawn_planet does — the
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
		_apply_pixel_parity(p, actual_size)
		if "override_time" in p:
			p.override_time = true
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
		p.set_meta("time_update", true)
		# Static placement around the planet: project the descriptor's
		# (rx, ry, phase) ellipse to a single point and place the moon's
		# CENTER there (Controls are authored top-left, so subtract half the
		# display size). Use the planet's spawn position — moons + planet
		# both ride the shared drift loop afterwards so they stay in sync.
		var rx_px: float = float(m.get("rx", 12.0)) * scale_factor
		var ry_px: float = float(m.get("ry", 10.0)) * scale_factor
		var phase: float = float(m.get("phase", 0.0))
		var planet_center: Vector2 = planet.position + Vector2(planet_size_px, planet_size_px) * 0.5
		var anchor: Vector2 = planet_center + Vector2(cos(phase) * rx_px, sin(phase) * ry_px)
		p.position = anchor - Vector2(actual_size, actual_size) * 0.5
		# Inherit the planet's drift speed so the moon stays at a fixed
		# offset from the planet as the whole stack scrolls down.
		p.set_meta("drift", true)
		p.set_meta("drift_mult", planet_drift_mult)
		p.set_meta("planet_actual_size", actual_size)
		add_child(p)
		moon_idx += 1


func _apply_pixels_only(root: Node, value: float) -> void:
	for child in root.get_children():
		if child is ColorRect and child.material is ShaderMaterial:
			child.material.set_shader_parameter("pixels", value)
		_apply_pixels_only(child, value)

func _process(delta: float) -> void:
	_shader_time += delta * surface_time_scale
	for c in get_children():
		if not c.has_meta("drift"):
			continue
		var mult: float = 1.0
		if c.has_meta("drift_mult"):
			mult = c.get_meta("drift_mult")
		c.position.y += drift_speed * mult * delta
		# Reset bound was 440 at 400-tall viewport; 270-tall viewport uses
		# 310 as the corresponding off-bottom mark.
		if c.position.y > 310:
			var reset_y: float = -120.0
			if mult < 0.3 and c.has_meta("planet_actual_size"):
				reset_y = -float(c.get_meta("planet_actual_size")) * 0.78
			c.position.y = reset_y
		if c.has_meta("spin"):
			c.rotation += float(c.get_meta("spin")) * delta
		if c.has_meta("time_update") and c.has_method("update_time"):
			c.update_time(_shader_time)
