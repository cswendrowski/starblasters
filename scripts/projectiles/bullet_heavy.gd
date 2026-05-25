extends "res://scripts/bullet.gd"

# Heavy blaster bullet — single-frame static sprite (Roman, 2026-05-24:
# new blaster_heavy.png is a 6×16 single-frame projectile, not the old
# 5-frame strip). If the sprite is ever returned to a multi-frame strip,
# the frame-cycler below will reactivate.
const FRAME_TIME := 0.06

var _anim_t: float = 0.0


func _process(delta: float) -> void:
	super._process(delta)
	if not has_node("Sprite2D"):
		return
	var spr := $Sprite2D as Sprite2D
	if spr.hframes <= 1:
		return
	_anim_t += delta
	if _anim_t >= FRAME_TIME:
		_anim_t -= FRAME_TIME
		spr.frame = (spr.frame + 1) % spr.hframes
