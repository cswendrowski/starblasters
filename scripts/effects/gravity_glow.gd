extends Node2D

# Gravity-mine glow (Roman 2026-06-09). Renders the mine sprite's GLOWMASK frame (the LAST frame
# of the 2-frame enemy_mine_gravity strip) as an additive overlay tinted #c73bff, PLUS a soft
# diffuse halo of the same colour via GlowShaderFx. Alpha is controllable so tether mines can keep
# the glow OFF while dormant and fade it in when they activate. The Gravity Mine keeps it on.
#
# Usage: add as a child of the mine, then `setup($Sprite2D)`. Optional start_alpha 0 + fade_in().

const GlowShaderFx = preload("res://scripts/effects/glow_shader_fx.gd")
const GRAVITY_COLOR := Color(0.78, 0.231, 1.0)   # #c73bff

var _mask: Sprite2D = null
var _halo: CanvasItem = null
var _color: Color = GRAVITY_COLOR
var _alpha: float = 1.0


# Build the glowmask overlay + diffuse halo off `body`'s texture (uses its last frame as the mask).
func setup(body: Sprite2D, color: Color = GRAVITY_COLOR, start_alpha: float = 1.0) -> void:
	if body == null or body.texture == null:
		return
	_color = color
	_alpha = clampf(start_alpha, 0.0, 1.0)
	z_index = 1   # above the body sprite
	_mask = Sprite2D.new()
	_mask.texture = body.texture
	_mask.hframes = maxi(body.hframes, 1)
	_mask.vframes = maxi(body.vframes, 1)
	_mask.frame = _mask.hframes * _mask.vframes - 1   # last frame = the glowmask
	_mask.flip_v = body.flip_v
	_mask.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_mask.material = mat
	add_child(_mask)
	# Soft diffuse halo of the same colour, derived from the glowmask silhouette.
	_halo = GlowShaderFx.apply(_mask, color)
	_apply_alpha()


func set_glow_alpha(a: float) -> void:
	_alpha = clampf(a, 0.0, 1.0)
	_apply_alpha()


func fade_in(duration: float = 0.5) -> void:
	var tw := create_tween()
	tw.tween_method(set_glow_alpha, _alpha, 1.0, maxf(duration, 0.01))


func _apply_alpha() -> void:
	if _mask != null and is_instance_valid(_mask):
		_mask.modulate = Color(_color.r, _color.g, _color.b, _alpha)
	if _halo != null and is_instance_valid(_halo):
		_halo.modulate = Color(1.0, 1.0, 1.0, _alpha)
