extends "res://scripts/enemies/shoot_patterns/shoot_pattern.gd"

# Fires one bullet straight down (default), or at a diagonal angle toward the
# opposite side of the playfield when `aim_toward_center` is enabled.
#
# aim_toward_center = true: enemies entering from the left angle right-down,
# enemies from the right angle left-down. Good for drifter / firecore chaff
# that spawn from a side — the shot naturally threatens the player's lane.
# aim_angle_deg sets the horizontal lean in degrees from straight-down (30°
# is a noticeable diagonal without being oppressive).

@export var aim_angle_deg: float = 0.0
@export var aim_toward_center: bool = false


func fire(enemy) -> void:
	if aim_toward_center and aim_angle_deg != 0.0:
		# Positive angle_deg tilts right (+x), negative tilts left.
		# Enemy on the left half → tilt right; enemy on the right half → tilt left.
		var sign: float = 1.0 if enemy.global_position.x < Playfield.CENTER.x else -1.0
		var rad: float = deg_to_rad(aim_angle_deg * sign)
		var dir: Vector2 = Vector2(sin(rad), cos(rad))
		_spawn_bullet(enemy, dir)
	else:
		_spawn_bullet(enemy, Vector2(0, 1))
