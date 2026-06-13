extends "res://scripts/projectiles/base_bullet.gd"

# Shredder pellet (Roman 2026-06-11). A STRAIGHT base_bullet wearing the Swarm
# Launcher's visual — the 1px flickering yellow core + diffuse glow + smoke trail —
# but NOT its homing behavior (Roman: "same bullet and particle effects as the swarm
# launcher, but not the same bullet behavior"). Damage/speed/direction come from the
# primary spread-fire path; this script only adds the cosmetics. Mirrors the look in
# scripts/projectiles/swarm_missile.gd.

const MissileSmokeTrail = preload("res://scripts/effects/missile_smoke_trail.gd")
const GLOW_COLOR := Color(1.0, 1.0, 0.0)  # #FFFF00 — matches the swarm core

static var _pixel_tex: Texture2D = null
var _core: Sprite2D = null
var _flicker_t: float = 0.0


func _apply_visuals() -> void:
	# Bright 1px yellow core + diffuse glow at the bullet origin (swarm identity).
	_core = Sprite2D.new()
	_core.name = "Core"
	_core.texture = _pixel_texture()
	_core.modulate = GLOW_COLOR
	add_child(_core)
	# No glow-halo quad — the WorldEnvironment bloom glows the bright yellow core directly
	# (Roman 2026-06-12, glow-halo redundancy pass).
	# Same smoke/flame trail fx the swarm missile emits.
	var trail = MissileSmokeTrail.new()
	add_child(trail)
	trail.call_deferred("attach_to", self)


func _process(delta: float) -> void:
	super._process(delta)
	# Pellet decays as it travels: colour ramps white -> yellow -> orange -> red across
	# its lifespan and the core shrinks toward the end (Roman 2026-06-11).
	if _core != null and is_instance_valid(_core):
		var t: float = clampf(_t / maxf(0.01, max_lifetime), 0.0, 1.0)
		# #ffc800 (amber) -> #ff0000 (red) as it travels (Roman 2026-06-11).
		var col: Color = Color(1.0, 0.784, 0.0).lerp(Color(1.0, 0.0, 0.0), t)
		_flicker_t += delta
		var f: float = 0.82 + 0.18 * absf(sin(_flicker_t * 28.0))
		_core.modulate = Color(col.r * f, col.g * f, col.b * f, 1.0)
		_core.scale = Vector2.ONE * lerpf(1.0, 0.5, t)


static func _pixel_texture() -> Texture2D:
	if _pixel_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_pixel_tex = ImageTexture.create_from_image(img)
	return _pixel_tex
