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

var _t := 0.0

func _ready() -> void:
	texture = STRIP
	hframes = HFRAMES
	flip_v = true
	scale = Vector2(FLARE_SCALE, FLARE_SCALE)
	z_index = FLARE_Z
	z_as_relative = true
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

func _process(delta: float) -> void:
	_t += delta
	frame = int(_t * ANIM_FPS) % HFRAMES
