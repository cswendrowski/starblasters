extends Node2D
# Test damage target for the BeamEmitter test — counts take_damage calls.
var hits: int = 0
func take_damage(d: int) -> void:
	hits += d
