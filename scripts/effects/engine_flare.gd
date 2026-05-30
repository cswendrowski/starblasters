extends Sprite2D
class_name EngineFlare

# Looping engine plume built from the 5-frame gun_muzzle_flash strip,
# flipped vertically so the burst points out the rear of the exhaust.
# Additive blend; renders BEHIND the (tiny) projectile body. Self-animating.
const STRIP := preload("res://graphics/gun_muzzle_flash.png")
const HFRAMES := 5
const ANIM_FPS := 14.0
const FLARE_SCALE := 0.55   # 16px flash over a 4-6px body — tune via capture
const FLARE_Z := -2          # behind the projectile body
const FRAME_PX := 16         # per-frame height of the 16x16 strip

var _t := 0.0

func _ready() -> void:
	texture = STRIP
	hframes = HFRAMES
	flip_v = true
	# Anchor the flash so its near edge sits ON the exhaust_point rather than
	# the sprite center (Roman 2026-05-30). flip_v already aims the burst out
	# the rear (+y local); shifting +half a frame puts the base at the marker
	# and the plume trails outward instead of half-overlapping the body.
	offset = Vector2(0, FRAME_PX * 0.5)
	scale = Vector2(FLARE_SCALE, FLARE_SCALE)
	z_index = FLARE_Z
	z_as_relative = true
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

func _process(delta: float) -> void:
	_t += delta
	frame = int(_t * ANIM_FPS) % HFRAMES
