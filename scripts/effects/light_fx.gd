extends Object

# Combat-VFX point-light LIFECYCLE helpers (Roman 2026-06-22): a one-shot flash that fades + frees, and
# a persistent attached light. Built ON the shared low-level factory point_light_fx.gd (PointLightFx —
# owns the radial cookie + the configured PointLight2D the dock cinematics also use), so the factory is
# NOT duplicated. Replaces the per-effect GradientTexture2D glow sprites (muzzle flashes, explosion
# light cast, enemy engine flame) and adds lights to the danger pulse + missile salvo. Additive blend →
# reads as a glow, lights nearby lit sprites, and blooms via the combat WorldEnvironment.
#
# Preload-const (NOT a class_name), the effects convention.
#   const LightFx = preload("res://scripts/effects/light_fx.gd")
#   LightFx.flash(world_node, world_pos, Color(1,0.7,0.3), 1.6, 40.0, 0.12)   # one-shot punch
#   var l = LightFx.attach(self, tint, 1.0, 14.0)                              # persistent child

const PointLightFx = preload("res://scripts/effects/point_light_fx.gd")
const COOKIE_PX := 128

static var _cookie: Texture2D = null


# Shared radial light cookie (reuses PointLightFx's builder, cached).
static func cookie() -> Texture2D:
	if _cookie == null:
		_cookie = PointLightFx.make_texture(COOKIE_PX)
	return _cookie


# A configured additive PointLight2D from the shared cookie. radius_px = the light's RADIUS (half its
# rendered diameter). Not yet in any tree (caller adds it).
static func make(color: Color, energy: float, radius_px: float, z: int = 0) -> PointLight2D:
	var l := PointLightFx.make(Vector2.ZERO, color, radius_px / (float(COOKIE_PX) * 0.5), cookie())
	l.energy = energy
	l.z_index = z
	return l


# Persistent point-light child of `parent` (e.g. an engine flame). The caller owns its lifetime + any
# flicker/animation. Returns the light.
static func attach(parent: Node2D, color: Color, energy: float, radius_px: float, offset: Vector2 = Vector2.ZERO, z: int = 0) -> PointLight2D:
	var l := make(color, energy, radius_px, z)
	l.position = offset
	parent.add_child(l)
	return l


# One-shot flash at a WORLD position: held at `energy`, tweened to 0 over `dur`, then freed. For
# muzzle / explosion-style punches. `parent` must be a world-space Node (the fx container / scene).
static func flash(parent: Node, world_pos: Vector2, color: Color, energy: float, radius_px: float, dur: float, z: int = 5) -> PointLight2D:
	if parent == null:
		return null
	var l := make(color, energy, radius_px, z)
	parent.add_child(l)
	l.global_position = world_pos
	var tw := l.create_tween()
	tw.tween_property(l, "energy", 0.0, dur)
	tw.tween_callback(l.queue_free)
	return l
