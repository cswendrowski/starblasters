extends HBoxContainer
class_name HullPips

# Pip strip that doesn't depend on Unicode glyph support. Each pip is a
# TextureRect using a procedurally-generated diamond texture, so the pips
# render identically in editor and web export.

@export var pip_count: int = 6
@export var pip_size: int = 26

static var _filled_tex: Texture2D = null
static var _empty_tex: Texture2D = null

var _pips: Array = []  # of TextureRect

func _ready() -> void:
	_ensure_textures()
	add_theme_constant_override("separation", 8)
	alignment = BoxContainer.ALIGNMENT_CENTER
	for i in pip_count:
		var tr := TextureRect.new()
		tr.texture = _empty_tex
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.custom_minimum_size = Vector2(pip_size, pip_size)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
		_pips.append(tr)


func set_state(cur: int, max_val: int) -> void:
	if _pips.is_empty():
		return
	var ratio: float = 0.0
	if max_val > 0:
		ratio = clamp(float(cur) / float(max_val), 0.0, 1.0)
	# Round up so 1 HP always shows at least one filled pip.
	var n_cur: int = int(ceil(ratio * pip_count))
	if cur > 0 and n_cur < 1:
		n_cur = 1
	for i in pip_count:
		_pips[i].texture = _filled_tex if i < n_cur else _empty_tex


static func _ensure_textures(s: int = 26) -> void:
	if _filled_tex != null and _empty_tex != null:
		return
	_filled_tex = _make_diamond_tex(s, true)
	_empty_tex = _make_diamond_tex(s, false)


# Diamond shape via L1-norm distance from center. Filled = solid alpha inside,
# empty = 2-pixel outline only. Anti-aliasing kept off for the pixel-art look.
static func _make_diamond_tex(s: int, filled: bool) -> Texture2D:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center: float = float(s) / 2.0
	var radius: float = center - 1.5
	for y in s:
		for x in s:
			var dx: float = abs(float(x) + 0.5 - center)
			var dy: float = abs(float(y) + 0.5 - center)
			var dist: float = dx + dy
			if filled:
				if dist <= radius:
					img.set_pixel(x, y, Color(1, 1, 1, 1))
			else:
				# 2px outline band
				if dist <= radius and dist >= radius - 2.0:
					img.set_pixel(x, y, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)
