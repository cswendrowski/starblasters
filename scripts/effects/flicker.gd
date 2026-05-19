extends Node

# Tiny periodic-noise driver. Lerps `target.modulate.a` toward a random
# offset around `base_alpha` every ~0.06–0.14s, giving a candle-like flicker
# without the cost of a per-frame tween.

@export var base_alpha: float = 0.7
@export var amplitude: float = 0.25
var target: CanvasItem = null

var _t: float = 0.0
var _next_t: float = 0.0
var _from_a: float = 0.7
var _to_a: float = 0.7


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	_t += delta
	if _t >= _next_t:
		_from_a = target.modulate.a
		_to_a = clamp(base_alpha + randf_range(-amplitude, amplitude), 0.0, 1.0)
		_next_t = _t + randf_range(0.06, 0.14)
	# Smooth interpolation between picks so it reads as "wavering" not "stutter".
	var span: float = max(_next_t - (_t - delta), 0.0001)
	var t: float = clamp(1.0 - (_next_t - _t) / span, 0.0, 1.0)
	target.modulate.a = lerp(_from_a, _to_a, t)
