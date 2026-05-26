extends HBoxContainer
class_name HullPips

# Sprite-strip pip HUD for hull. Uses hud_hull_light.png (32x16, 2 frames):
#   Frame 0 (left 16x16)  — dim red  = missing pip
#   Frame 1 (right 16x16) — bright red = full pip
# Hull spec 2026-05-26: replaces procedural diamond pips.

const STRIP = preload("res://graphics/ui/hud_hull_light.png")
const FRAME_MISSING: int = 0   # dim = pip lost
const FRAME_FULL: int = 1      # bright = pip intact
const FRAME_W: int = 16
const FRAME_H: int = 16

var _pips: Array = []         # Array of TextureRect
var _flash_tween: Tween = null
var _flashing: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	alignment = BoxContainer.ALIGNMENT_CENTER


func set_state(cur: int, max_val: int) -> void:
	# Rebuild pip count if max changed.
	if _pips.size() != max_val:
		for c in get_children():
			c.queue_free()
		_pips.clear()
		for i in max_val:
			var tr := TextureRect.new()
			tr.texture = _atlas(FRAME_MISSING)
			tr.stretch_mode = TextureRect.STRETCH_KEEP
			tr.custom_minimum_size = Vector2(FRAME_W, FRAME_H)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(tr)
			_pips.append(tr)
	# Set frames.
	for i in _pips.size():
		_pips[i].texture = _atlas(FRAME_FULL if i < cur else FRAME_MISSING)
		_pips[i].modulate = Color(1, 1, 1, 1)
	# Flash when at zero pips.
	if cur <= 0 and max_val > 0:
		_start_flash()
	else:
		_stop_flash()


func _start_flash() -> void:
	if _flashing:
		return
	_flashing = true
	_run_flash_cycle()


func _run_flash_cycle() -> void:
	if not _flashing:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	# 2s visible, 2s hidden, repeat.
	_flash_tween.tween_callback(func(): _set_pip_visible(true))
	_flash_tween.tween_interval(2.0)
	_flash_tween.tween_callback(func(): _set_pip_visible(false))
	_flash_tween.tween_interval(2.0)
	_flash_tween.tween_callback(_run_flash_cycle)


func _stop_flash() -> void:
	_flashing = false
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_set_pip_visible(true)


func _set_pip_visible(v: bool) -> void:
	for pip in _pips:
		pip.modulate.a = 1.0 if v else 0.0


static var _atlas_cache: Array = []
static func _atlas(frame: int) -> Texture2D:
	if _atlas_cache.is_empty():
		_atlas_cache.resize(2)
		for i in 2:
			var at := AtlasTexture.new()
			at.atlas = STRIP
			at.region = Rect2(i * FRAME_W, 0, FRAME_W, FRAME_H)
			_atlas_cache[i] = at
	return _atlas_cache[clamp(frame, 0, 1)]
