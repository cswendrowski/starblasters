extends Node2D

# Shared hangar plate + runway lights for the dock cinematics (outpost arrival / patrol start).
# Roman 2026-06-21 — extracted from outpost_arrival.gd (patrol had a hand-copied port; runway
# tweaks were having to be made twice). Builds the `outpost_background` plate sprite + a yellow
# pixel & small amber point light on each "+" marker down the bay, pulsing bottom→top like runway
# approach lights. SELF-UPDATING (its own _process).
#
# USAGE: the caller instantiates this, positions/animates the NODE (the plate is centred on the
# node origin), and parents it into its world — outpost DESCENDS the node from above to centred;
# patrol rides it at local centre inside its rising `_hangar`. Set `brightness` (plate dim) +
# `runway_speed` before add_child, or live via the setters. The runway pixels/lights are children
# of the plate sprite, so `brightness` (self_modulate) dims the plate WITHOUT dimming them.

const PointLightFx = preload("res://scripts/effects/point_light_fx.gd")
const OUTPOST_BG := "res://graphics/backgrounds/outpost_background.png"

# "+" marker centres (image px, x≈108, every 6px; the tan landing circle hides y~100..168).
const MARKER_TOP := 30
const MARKER_BOTTOM := 240
const MARKER_STEP := 6
const CIRCLE_MIN := 96
const CIRCLE_MAX := 174
const DARK := Color(0.30, 0.16, 0.0)     # dark amber (off)
const LIT := Color(1.0, 0.80, 0.16)      # amber yellow (lit)
const K := TAU                           # one travelling band across the strip
const LIGHT_COLOR := Color(1.0, 0.70, 0.16)
const LIGHT_ENERGY := 0.7
const LIGHT_SCALE := 0.12
const LIGHT_TEX_SIZE := 64               # the runway-light texture size the scales were tuned against
const PIXEL_SIZE := 1.0
const X_OFFSET := 1.0                     # column sits 1px right of the sprite centre
const NATIVE_H := 270.0

var brightness: float = 1.0
var runway_speed: float = 0.9

var _plate: Sprite2D = null
var _light_tex: Texture2D = null
var _pixels: Array = []
var _lights: Array = []
var _v: Array = []
var _t: float = 0.0


func _ready() -> void:
	_light_tex = PointLightFx.make_texture(LIGHT_TEX_SIZE)
	_plate = Sprite2D.new()
	_plate.name = "Plate"
	_plate.texture = load(OUTPOST_BG)
	_plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_plate.z_index = -8
	_plate.self_modulate = Color(brightness, brightness, brightness, 1.0)   # dims plate, NOT runway children
	add_child(_plate)
	_build_runway()


func _build_runway() -> void:
	var s := PIXEL_SIZE / 2.0
	var my := MARKER_TOP
	while my <= MARKER_BOTTOM:
		if my > CIRCLE_MIN and my < CIRCLE_MAX:
			my += MARKER_STEP   # behind the landing circle — no light
			continue
		var ly: float = float(my) - NATIVE_H / 2.0
		if my <= CIRCLE_MIN:
			ly += 1.0   # top-half markers sit 1px below the 6px grid
		var pix := Polygon2D.new()
		pix.polygon = PackedVector2Array([Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)])
		pix.position = Vector2(X_OFFSET, ly)
		pix.color = DARK
		_plate.add_child(pix)
		_pixels.append(pix)
		var lt := PointLightFx.make(Vector2(X_OFFSET, ly), LIGHT_COLOR, LIGHT_SCALE, _light_tex)
		_plate.add_child(lt)
		_lights.append(lt)
		_v.append((float(my) - float(MARKER_TOP)) / float(MARKER_BOTTOM - MARKER_TOP))
		my += MARKER_STEP


# Pulse the runway bottom→top: a travelling amber band (sharpened by pow) over dark amber.
func _process(delta: float) -> void:
	if _pixels.is_empty():
		return
	_t += delta
	for i in _pixels.size():
		var s: float = 0.5 + 0.5 * sin(_t * runway_speed + float(_v[i]) * K)
		var lit: float = pow(s, 2.5)
		var pix = _pixels[i]
		if is_instance_valid(pix):
			pix.color = DARK.lerp(LIT, lit)
		var lt = _lights[i]
		if is_instance_valid(lt):
			lt.energy = lit * LIGHT_ENERGY


func set_brightness(b: float) -> void:
	brightness = b
	if _plate != null and is_instance_valid(_plate):
		_plate.self_modulate = Color(b, b, b, 1.0)


func set_runway_speed(v: float) -> void:
	runway_speed = v


func plate_size() -> Vector2:
	if _plate != null and _plate.texture != null:
		return _plate.texture.get_size()
	return Vector2(215, 270)
