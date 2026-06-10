extends Node

# EmberFx (Roman 2026-06-10) — burning-debris ember spray: a one-shot
# GPUParticles2D driven entirely by graphics/ember_spray.gdshader (white-hot
# streaks cooling yellow → orange → red → char-black, then fading). The
# explosion's "embers", NOT the explosion itself — pair with ExplosionFx.
#
#   EmberFx.spray(parent, pos, dir)        → defaults (see DEFAULTS)
#   EmberFx.spray(parent, pos, dir, {..})  → override any knob
#
# Tune in the Shader Lab (dev menu) — its Copy GDScript emits this call.
# Spawn under get_tree().root (projectile convention) or any node that
# outlives the burst; the emitter frees itself when the burst finishes.

const EMBER_SHADER: Shader = preload("res://graphics/ember_spray.gdshader")
# Inverted-ramp variant: embers heat UP (char → white-hot) instead of cooling.
const EMBER_SHADER_INVERTED: Shader = preload("res://graphics/ember_spray_inverted.gdshader")

const DEFAULTS := {
	"amount": 28,
	"lifetime": 0.9,
	"explosiveness": 0.85, # <1 staggers spawns: fresh white heads at the origin
	"spread_deg": 35.0,
	"speed_min": 110.0,
	"speed_max": 320.0,
	"drag": 2.6,
	"gravity": 30.0,
	"streak_sec": 0.05,
	"thickness": 1.0,
	"cool_bias": 0.55,
	"fade_start": 0.78,
	"lifetime_rand": 0.4,
	"inverted": false, # true = use the heat-up ramp (ember_spray_inverted)
}

static var _pixel_tex: Texture2D = null


static func spray(parent: Node, pos: Vector2, direction: Vector2 = Vector2.UP, params: Dictionary = {}) -> GPUParticles2D:
	if parent == null:
		return null
	var v: Dictionary = DEFAULTS.duplicate()
	v.merge(params, true)

	var p := GPUParticles2D.new()
	p.name = "EmberSpray"
	p.amount = int(v["amount"])
	p.lifetime = float(v["lifetime"])
	p.one_shot = true
	p.explosiveness = float(v["explosiveness"])
	p.local_coords = false
	p.texture = _pixel()
	p.position = pos

	var mat := ShaderMaterial.new()
	mat.shader = EMBER_SHADER_INVERTED if bool(v["inverted"]) else EMBER_SHADER
	mat.set_shader_parameter("direction_angle", direction.angle())
	mat.set_shader_parameter("spread_deg", float(v["spread_deg"]))
	mat.set_shader_parameter("speed_min", float(v["speed_min"]))
	mat.set_shader_parameter("speed_max", float(v["speed_max"]))
	mat.set_shader_parameter("drag", float(v["drag"]))
	mat.set_shader_parameter("gravity_y", float(v["gravity"]))
	mat.set_shader_parameter("streak_sec", float(v["streak_sec"]))
	mat.set_shader_parameter("thickness", float(v["thickness"]))
	mat.set_shader_parameter("cool_bias", float(v["cool_bias"]))
	mat.set_shader_parameter("fade_start", float(v["fade_start"]))
	mat.set_shader_parameter("lifetime_rand", float(v["lifetime_rand"]))
	p.process_material = mat

	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


# 2×2 white pixel; the particle shader stretches it into streaks.
static func _pixel() -> Texture2D:
	if _pixel_tex == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_pixel_tex = ImageTexture.create_from_image(img)
	return _pixel_tex
