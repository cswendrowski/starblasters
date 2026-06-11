extends "res://scripts/projectiles/base_bullet.gd"

# Shredder pellet (Roman 2026-06-11). A STRAIGHT base_bullet wearing the Swarm
# Launcher's visual — the 1px flickering yellow core + diffuse glow + smoke trail —
# but NOT its homing behavior (Roman: "same bullet and particle effects as the swarm
# launcher, but not the same bullet behavior"). Damage/speed/direction come from the
# primary spread-fire path; this script only adds the cosmetics. Mirrors the look in
# scripts/projectiles/swarm_missile.gd.

const GlowShaderFx = preload("res://scripts/effects/glow_shader_fx.gd")
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
	GlowShaderFx.apply(_core, GLOW_COLOR)
	# Same smoke/flame trail fx the swarm missile emits.
	var trail = MissileSmokeTrail.new()
	add_child(trail)
	trail.call_deferred("attach_to", self)


func _process(delta: float) -> void:
	super._process(delta)
	# Brightness flicker, hue pinned to pure yellow (matches swarm_missile.gd).
	if _core != null and is_instance_valid(_core):
		_flicker_t += delta
		var f: float = 0.7 + 0.3 * absf(sin(_flicker_t * 28.0))
		_core.modulate = Color(f, f, 0.0, 1.0)


static func _pixel_texture() -> Texture2D:
	if _pixel_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_pixel_tex = ImageTexture.create_from_image(img)
	return _pixel_tex
