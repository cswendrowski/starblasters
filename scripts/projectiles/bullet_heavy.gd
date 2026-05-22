extends "res://scripts/bullet.gd"

# Heavy blaster bullet — cycles the 4-frame strip at ~16 fps.
const FRAME_TIME := 0.06

var _anim_t: float = 0.0


func _process(delta: float) -> void:
	super._process(delta)
	_anim_t += delta
	if _anim_t >= FRAME_TIME:
		_anim_t -= FRAME_TIME
		if has_node("Sprite2D"):
			var spr := $Sprite2D as Sprite2D
			spr.frame = (spr.frame + 1) % spr.hframes
