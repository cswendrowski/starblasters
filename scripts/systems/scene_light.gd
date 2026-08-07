class_name SceneLight
extends Object

# THE scene light direction — one source of truth for "where the light comes from" across PlanetKit
# planets, PlanetKit asteroids, building drop shadows, ship drop shadows and the flyover surface.
# Design: docs/scene_light_direction_2026-07-28.md. Same shape as `Playfield` — constants plus pure
# helpers, no node, no autoload.
#
# Conventions (Godot screen space, +Y DOWN, azimuth measured from +X):
#   azimuth_deg() — where the LIGHT sits relative to the object. 225° = up-left.
#   light_dir()   — unit vector pointing FROM the scene TOWARD the light.
#   shadow_dir()  — unit vector shadows are cast ALONG = -light_dir().
#
# ⚠ Two shaders take a uniform named `sun_dir` and mean OPPOSITE things by it — always check which:
#   graphics/building_shadow.gdshader  → wants shadow_dir()  (it marches `uv -= step_uv`)
#   graphics/planet_ground.gdshader    → wants light_dir()   (lambert `-(∇h · sun_dir)`)

# The canonical direction. Everything that casts a shadow or lights a body derives from this.
# 225° (up-left) is PixelPlanets' own shipped default — every kit shader ships
# `light_origin = vec2(0.39, 0.39)`, which is exactly this azimuth at RADIUS_PLANETKIT_DEFAULT.
const DEFAULT_AZIMUTH_DEG: float = 225.0

# Per-consumer terminator radii — how far the light origin is pushed across the sprite, i.e. how
# much of the body reads as lit. Preserved from what each consumer already used; unifying the
# AZIMUTH must not re-shape anyone's terminator. (Baked rocks at 0.45 vs live rocks at the kit
# default is a pre-existing mismatch, deliberately left alone here.)
const RADIUS_PLANETKIT_DEFAULT: float = 0.1556   # kit default — vec2(0.39, 0.39)
const RADIUS_BAKED_ROCK: float = 0.45
const RADIUS_PLANET: float = 0.5                 # terminator right at the sprite edge

# How far a level's sun may swing either side of canonical as you cross the system (§4). The scene's
# star is staged at the LEFT edge of the row (frac 0.0) and shrinks with distance, so the honest
# screen-derived range would be ~176°–212° — but that is the flat due-left read 225° was chosen to
# get away from, so instead the same signal drives a bounded swing CENTRED on canonical. Set to 0.0
# for a fixed sun; raise for a more dramatic per-level difference.
const STAR_SWING_DEG: float = 18.0

# Per-level azimuth, cached. Star-reactive lighting resolves the angle ONCE at level start (see
# backdrop_coordinator._populate) and calls set_level_azimuth_deg(); azimuth_deg() reads this back.
# Cached rather than re-read from Run meta per call because per-frame consumers (AsteroidShadowRig)
# hit shadow_dir() every frame.
# Contract: the azimuth is CONSTANT for the duration of a level — see the design doc §4.
static var _level_azimuth_deg: float = DEFAULT_AZIMUTH_DEG


static func azimuth_deg() -> float:
	return _level_azimuth_deg


# Publish the level's azimuth. Call once at level start (L3); pair with reset_level_azimuth() so a
# level that doesn't publish one falls back to canonical instead of inheriting the previous level's.
static func set_level_azimuth_deg(deg: float) -> void:
	_level_azimuth_deg = deg


static func reset_level_azimuth() -> void:
	_level_azimuth_deg = DEFAULT_AZIMUTH_DEG


# THE star-reactive rule: where the sun sits for a level, given that level's stellar composition.
# `system_frac` is the current node's position along its row (0.0 = hard against the star, 1.0 = the
# far/boss end), written by stellar_gameplay.gd. Near the star the sun sits shallower; out at the
# rim it rakes further over. Compositions with no row context (StellarComposer's random dev dicts,
# menus, labs) have no frac and get canonical.
static func azimuth_for_stellar(stellar: Dictionary) -> float:
	if not stellar.has("system_frac"):
		return DEFAULT_AZIMUTH_DEG
	var f: float = clampf(float(stellar["system_frac"]), 0.0, 1.0)
	return DEFAULT_AZIMUTH_DEG + lerpf(-STAR_SWING_DEG, STAR_SWING_DEG, f)


# Unit vector pointing FROM the scene TOWARD the light.
static func light_dir() -> Vector2:
	var a: float = deg_to_rad(azimuth_deg())
	return Vector2(cos(a), sin(a))


# Unit vector shadows are cast ALONG (away from the light).
static func shadow_dir() -> Vector2:
	return -light_dir()


# UV-space point for a PlanetKit `set_light()` / `light_origin` uniform: the unit circle around the
# sprite centre, pushed out by `radius`. At DEFAULT_AZIMUTH_DEG + RADIUS_PLANETKIT_DEFAULT this
# reproduces the kit's own vec2(0.39, 0.39) exactly.
static func planetkit_light_origin(radius: float = RADIUS_PLANETKIT_DEFAULT) -> Vector2:
	return Vector2(0.5, 0.5) + light_dir() * radius


# Apply to any PlanetKit body exposing set_light(). Inert on the 4 kit scenes whose set_light() takes
# `_pos` and no-ops (Planet, Star, Galaxy, BlackHole) — 9 of the 13 actually respond.
static func apply_to_planetkit(node: Node, radius: float = RADIUS_PLANETKIT_DEFAULT) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_method("set_light"):
		node.set_light(planetkit_light_origin(radius))
