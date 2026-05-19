extends Node

# Reusable additive glow attachments. Three flavors:
#   attach_glow(host, color, scale) → constant halo behind the host sprite.
#   attach_flickering_glow(...)     → halo + per-frame random alpha jitter.
#   attach_engine_glow(host, ...)   → halo at a child node's position (e.g.
#                                     the player's booster animation).

const FLICKER_SCRIPT = preload("res://scripts/effects/flicker.gd")

static var _dot_tex: GradientTexture2D = null


static func _ensure_tex() -> void:
	if _dot_tex != null:
		return
	var g = Gradient.new()
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.55),
		Color(1, 1, 1, 0.0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	_dot_tex = GradientTexture2D.new()
	_dot_tex.gradient = g
	_dot_tex.width = 32
	_dot_tex.height = 32
	_dot_tex.fill = GradientTexture2D.FILL_RADIAL
	_dot_tex.fill_from = Vector2(0.5, 0.5)
	_dot_tex.fill_to = Vector2(1.0, 0.5)


# Add an additive Sprite2D glow to `host`. Returns the sprite so callers can
# tune further (e.g. set position, offset, scale per-frame, etc.).
static func attach_glow(host: Node2D, color: Color, scale: float = 2.0, alpha: float = 0.7, behind: bool = true) -> Sprite2D:
	_ensure_tex()
	var s := Sprite2D.new()
	s.texture = _dot_tex
	s.scale = Vector2(scale, scale)
	s.modulate = Color(color.r, color.g, color.b, alpha)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	s.z_index = -1 if behind else 1
	host.add_child(s)
	return s


# Attach a glow that lives at a child node's position (useful for the engine
# glow under the player ship's booster). The glow's local position is set to
# the child's position so it tracks if the child moves.
static func attach_engine_glow(host: Node2D, child_path: NodePath, color: Color, scale: float = 1.8, alpha: float = 0.7) -> Sprite2D:
	_ensure_tex()
	var anchor: Node2D = host.get_node_or_null(child_path) as Node2D
	if anchor == null:
		# Fall back to attaching at host origin so we still get a glow.
		return attach_glow(host, color, scale, alpha)
	var s := Sprite2D.new()
	s.texture = _dot_tex
	s.scale = Vector2(scale, scale)
	s.modulate = Color(color.r, color.g, color.b, alpha)
	s.position = anchor.position
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	# Behind the anchor's sprite so the engine sprite sits over the glow.
	s.z_index = -1
	host.add_child(s)
	host.move_child(s, anchor.get_index())
	return s


# Attach a glow that flickers its alpha at a random cadence. Used for the
# firecore enemy and similar pulsing core lights.
static func attach_flickering_glow(host: Node2D, color: Color, scale: float = 1.5, base_alpha: float = 0.7, amplitude: float = 0.25) -> Sprite2D:
	var glow := attach_glow(host, color, scale, base_alpha)
	var flick := Node.new()
	flick.set_script(FLICKER_SCRIPT)
	flick.target = glow
	flick.base_alpha = base_alpha
	flick.amplitude = amplitude
	glow.add_child(flick)
	return glow
