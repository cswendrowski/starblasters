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


# A small additive PointLight2D at `pos`, energy 0 AND disabled (caller drives energy + must set
# `enabled = true` when it raises the light). Starts disabled because an ENABLED energy-0 light still
# occupies a per-CanvasItem light slot — and the full-bay hangar plate can only take 16 lights (see the
# LIGHT BUDGET note in hangar_stage.gd). Parking off lights as disabled keeps them out of that cap.
static func make(pos: Vector2, col: Color, scale: float, tex: Texture2D) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = tex
	l.color = col
	l.energy = 0.0
	l.enabled = false
	l.texture_scale = scale
	l.blend_mode = Light2D.BLEND_MODE_ADD
	l.shadow_enabled = false
	# Light every sprite layer (not just the default) so a stray non-default light_mask on a background
	# sprite can't exclude these dock lights. Roman 2026-06-26.
	l.range_item_cull_mask = 0xFFFFF
	l.position = pos
	return l
