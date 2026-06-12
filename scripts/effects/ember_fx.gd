extends Node

# EmberFx (Roman 2026-06-10) — burning-debris ember spray: a one-shot
# GPUParticles2D driven entirely by graphics/ember_spray.gdshader. A cone of
# stretched streaks whose colour over life is read from a TUNABLE gradient
# (white-hot → yellow → orange → red → char by default), then fading. The
# explosion's "embers", NOT the explosion itself — pair with ExplosionFx.
#
#   EmberFx.spray(parent, pos, dir)        → defaults (see DEFAULTS)
#   EmberFx.spray(parent, pos, dir, {..})  → override any knob
#
# Tune in the Shader Lab (dev menu) — its Copy GDScript emits this call.
# Spawn under get_tree().root (projectile convention) or any node that
# outlives the burst; the emitter frees itself when the burst finishes.

const EMBER_SHADER: Shader = preload("res://graphics/ember_spray.gdshader")

# Default colour ramp (Roman's reference hexes): t=0 hottest → t=1 charred.
const DEFAULT_RAMP_COLORS := [
	Color(1.0, 1.0, 1.0),       # ffffff
	Color(0.984, 0.820, 0.184), # fbd12f
	Color(1.0, 0.294, 0.0),     # ff4b00
	Color(0.541, 0.063, 0.0),   # 8a1000
	Color(0.063, 0.024, 0.020), # 100605
]
const DEFAULT_RAMP_OFFSETS := [0.0, 0.16, 0.38, 0.62, 0.85]

# Defaults reflect the Shader Lab Embers tune (Roman 2026-06-11).
const DEFAULTS := {
	"amount": 96,
	"lifetime": 2.0,
	"explosiveness": 0.95, # <1 staggers spawns: fresh white heads at the origin
	"spread_deg": 48.0,
	"speed_min": 100.0,
	"speed_max": 320.0,
	"drag": 2.3,
	"gravity": -25.0,
	"streak_sec": 0.15,
	"thickness": 1.0,
	"cool_bias": 0.0,
	"fade_start": 0.95,
	"lifetime_rand": 0.4,
	"variant": "normal",  # "normal" (cool) | "inverted" (heat up) | "smoke" (grey wisps)
	"gradient": null,     # optional GradientTexture1D; null = default ramp
}

# Smoke-variant overlay: grey wisps that persist until the END of travel. A late
# fade_start (lifetime-vs-distance decoupling) keeps the tail opaque while the head
# is still moving, so the trail doesn't fade from the back early (Roman 2026-06-11).
const SMOKE_FADE_START := 0.92

static var _pixel_tex: Texture2D = null
static var _default_ramp: GradientTexture1D = null


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
	mat.shader = EMBER_SHADER
	mat.set_shader_parameter("direction_angle", direction.angle())
	mat.set_shader_parameter("spread_deg", float(v["spread_deg"]))
	mat.set_shader_parameter("speed_min", float(v["speed_min"]))
	mat.set_shader_parameter("speed_max", float(v["speed_max"]))
	mat.set_shader_parameter("drag", float(v["drag"]))
	mat.set_shader_parameter("gravity_y", float(v["gravity"]))
	mat.set_shader_parameter("streak_sec", float(v["streak_sec"]))
	mat.set_shader_parameter("thickness", float(v["thickness"]))
	mat.set_shader_parameter("cool_bias", float(v["cool_bias"]))
	var is_smoke: bool = String(v["variant"]) == "smoke"
	# Smoke holds its tail until end-of-travel UNLESS the caller overrode fade_start.
	var fade_start: float = float(v["fade_start"])
	if is_smoke and not params.has("fade_start"):
		fade_start = SMOKE_FADE_START
	mat.set_shader_parameter("fade_start", fade_start)
	mat.set_shader_parameter("lifetime_rand", float(v["lifetime_rand"]))
	mat.set_shader_parameter("invert", 1.0 if String(v["variant"]) == "inverted" else 0.0)
	mat.set_shader_parameter("smoke", 1.0 if is_smoke else 0.0)
	var ramp: Texture2D = v["gradient"] if v["gradient"] != null else default_ramp()
	mat.set_shader_parameter("color_ramp", ramp)
	p.process_material = mat

	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


# Build a GradientTexture1D from parallel colour + offset lists. Used by the
# Shader Lab's gradient editor; also the shape of the default ramp.
static func build_ramp(colors: Array, offsets: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 128
	return t


static func default_ramp() -> GradientTexture1D:
	if _default_ramp == null:
		_default_ramp = build_ramp(DEFAULT_RAMP_COLORS, DEFAULT_RAMP_OFFSETS)
	return _default_ramp


# 2×2 white pixel; the particle shader stretches it into streaks.
static func _pixel() -> Texture2D:
	if _pixel_tex == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_pixel_tex = ImageTexture.create_from_image(img)
	return _pixel_tex
