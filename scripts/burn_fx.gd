extends Node

# Pixelated-burn death effect. Static helpers create the shader material with
# the right noise + color curve and tween the burn radius. Call apply_burn()
# from any death sequence to dissolve a sprite.

const BURN_SHADER = preload("res://graphics/pixelated_burn.gdshader")

# Cached resources so we only build them once across all calls.
static var _noise_tex: NoiseTexture2D = null
static var _curve_tex: GradientTexture1D = null

static func _ensure_resources() -> void:
	if _noise_tex == null:
		var noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.06
		noise.seed = 1337
		_noise_tex = NoiseTexture2D.new()
		_noise_tex.noise = noise
		_noise_tex.width = 64
		_noise_tex.height = 64
		_noise_tex.seamless = true
	if _curve_tex == null:
		var grad = Gradient.new()
		# Burn color ramp: bright white core -> yellow -> orange -> red -> black
		grad.colors = PackedColorArray([
			Color(1, 1, 1, 1),
			Color(1, 0.9, 0.4, 1),
			Color(1, 0.55, 0.15, 1),
			Color(0.9, 0.15, 0.05, 1),
			Color(0.2, 0.05, 0.0, 1),
		])
		grad.offsets = PackedFloat32Array([0.0, 0.2, 0.45, 0.75, 1.0])
		_curve_tex = GradientTexture1D.new()
		_curve_tex.gradient = grad
		_curve_tex.width = 64

# Applies the pixelated-burn shader to `sprite` (typically a Sprite2D) and
# tweens the burn from 0 to full consumption over `duration` seconds.
# When done, the sprite is hidden so the parent can queue_free safely.
static func apply_burn(sprite: CanvasItem, duration: float = 0.5, custom_color: Color = Color(0, 0, 0, 0)) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	_ensure_resources()
	var mat = ShaderMaterial.new()
	mat.shader = BURN_SHADER
	mat.set_shader_parameter("noiseTexture", _noise_tex)
	mat.set_shader_parameter("colorCurve", _curve_tex)
	mat.set_shader_parameter("position", Vector2(0.5, 0.5))
	mat.set_shader_parameter("radius", 0.0)
	mat.set_shader_parameter("borderWidth", 0.18)
	mat.set_shader_parameter("burnMult", 0.34)
	mat.set_shader_parameter("pixel_size", 0.04)
	mat.set_shader_parameter("blend_steps", 6.0)
	if custom_color.a > 0.0:
		mat.set_shader_parameter("burnColor", custom_color)
	sprite.material = mat
	var tw = sprite.create_tween()
	# Burn expands beyond 1.0 so the trailing edge consumes the corners
	tw.tween_method(func(r): mat.set_shader_parameter("radius", r), 0.0, 1.6, duration)
