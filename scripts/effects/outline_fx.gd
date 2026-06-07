extends Node

# Reusable 1px black outline for enemy sprites (Roman 2026-06-07). Extends the
# asteroid's "shootable foreground" outline read to ALL enemy ships.
#
# WHY A SEPARATE BEHIND-NODE (not a material on the sprite):
#   1. The hull Sprite2D already carries the damage-overlay ShaderMaterial — a
#      CanvasItem has only one material slot, so we can't add the outline there.
#   2. Enemy hulls are TWO-FRAME sheets (hframes=2: frame 0 hull + frame 1 glow).
#      A neighbour-sampling outline shader on the live Sprite2D would read across
#      the frame boundary and outline the glow frame too.
#   Both problems vanish if the outline lives on its OWN node carrying a CROPPED,
#   PADDED single-frame copy of the hull — same trick GlowShaderFx uses. The node
#   sits 1px behind the hull (drawn first), so the hull covers the silhouette and
#   only the black ring in the 1px transparent pad shows.
#
#   apply(hull_sprite) -> the "Outline" node (or null). Toggle visibility to drop
#   the outline while recycling / in parallax (enemy_core handles that).

const OUTLINE_SHADER: Shader = preload("res://shaders/outline_1px.gdshader")
const PAD := 1   # transparent border (px) so the 1px ring always has room to draw

static var _mat: ShaderMaterial = null
# Cache: "<texid>:<frame>:<hf>x<vf>" -> padded single-frame ImageTexture.
static var _tex_cache: Dictionary = {}


static func _material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = OUTLINE_SHADER
		_mat.set_shader_parameter("clr", Color(0, 0, 0, 1))
		_mat.set_shader_parameter("type", 2)        # 2 = square (8-neighbour)
		_mat.set_shader_parameter("thickness", 1.0)
	return _mat


# Attach a 1px black outline behind `host` (a Sprite2D). Returns the outline node,
# or null if no frame image could be read. Safe to call in _ready (the node is
# added to the host's PARENT, which by then exists for a scene child).
static func apply(host: Sprite2D) -> Sprite2D:
	if host == null or host.texture == null:
		return null
	var tex: Texture2D = _padded_frame(host)
	if tex == null:
		return null
	var o := Sprite2D.new()
	o.name = "Outline"
	o.texture = tex
	o.material = _material()
	o.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	o.centered = host.centered
	o.flip_h = host.flip_h
	o.flip_v = host.flip_v
	var parent: Node = host.get_parent()
	if parent == null:
		host.add_child(o)
		host.move_child(o, 0)
		return o
	parent.add_child(o)
	parent.move_child(o, host.get_index())   # draw BEFORE the hull -> behind it
	o.position = host.position
	o.rotation = host.rotation
	return o


# Build a padded single-frame ImageTexture for the host's displayed frame (frame 0
# for a freshly-spawned hull). Cropped to one cell (no cross-frame bleed) + a 1px
# transparent border so the outline ring has somewhere to land. Cached per frame.
static func _padded_frame(host: Sprite2D) -> Texture2D:
	var src: Image = host.texture.get_image()
	if src == null:
		return null
	var hf: int = maxi(host.hframes, 1)
	var vf: int = maxi(host.vframes, 1)
	var key: String = "%d:%d:%dx%d" % [host.texture.get_instance_id(), host.frame, hf, vf]
	if _tex_cache.has(key):
		return _tex_cache[key]
	src = src.duplicate()
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	var cell_w: int = src.get_width() / hf
	var cell_h: int = src.get_height() / vf
	if cell_w <= 0 or cell_h <= 0:
		_tex_cache[key] = null
		return null
	var col: int = host.frame % hf
	var row: int = host.frame / hf
	var cell: Image = src.get_region(Rect2i(col * cell_w, row * cell_h, cell_w, cell_h))
	# Pad with a transparent border on every edge.
	var padded := Image.create(cell_w + 2 * PAD, cell_h + 2 * PAD, false, Image.FORMAT_RGBA8)
	padded.fill(Color(0, 0, 0, 0))
	padded.blit_rect(cell, Rect2i(0, 0, cell_w, cell_h), Vector2i(PAD, PAD))
	var itex := ImageTexture.create_from_image(padded)
	_tex_cache[key] = itex
	return itex
