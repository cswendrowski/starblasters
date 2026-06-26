extends RefCounted

# Shared additive 2D point-light factory for the dock cinematics (outpost arrival / patrol
# start). ONE place for the soft radial light texture + the small PointLight2D both screens
# spawn for engine glow, sparks, runway markers, hangar fill, the lifter, etc. — instead of each
# screen re-implementing `_make_light_texture` + `_make_point_light`. Roman 2026-06-21.

# Soft radial light texture (white centre → transparent edge). `size` × the caller's texture_scale
# sets the on-screen light size, so callers pass the size their scales were tuned against.
static func make_texture(size: int = 128) -> Texture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = size
	tex.height = size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex


# A small additive PointLight2D at `pos`, energy 0 (caller drives it), no shadows.
static func make(pos: Vector2, col: Color, scale: float, tex: Texture2D) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = tex
	l.color = col
	l.energy = 0.0
	l.texture_scale = scale
	l.blend_mode = Light2D.BLEND_MODE_ADD
	l.shadow_enabled = false
	l.position = pos
	return l
