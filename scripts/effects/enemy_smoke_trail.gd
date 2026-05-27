extends DamageSmokeTrail
class_name EnemySmokeTrail

# Upward-drifting smoke for enemies. Identical to DamageSmokeTrail except
# drift_sign = -1.0 so particles rise toward the top of the screen.

func _init() -> void:
	drift_sign = -1.0
