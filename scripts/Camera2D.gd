extends Camera2D

@export var decay: float = 0.85
@export var max_offset: Vector2 = Vector2(4, 4)  # 320×400 res rework — halved
@export var max_roll: float = 0.2
@export var noise: FastNoiseLite

var trauma: float = 0.0
var trauma_power: int = 2
var noise_pos: Vector3 = Vector3.ZERO

func add_trauma(amount: float) -> void:
	trauma = min(trauma + amount, 0.5)

func _process(delta: float) -> void:
	if trauma:
		trauma = max(trauma - decay * delta, 0)
		shake()

func shake() -> void:
	# Honor the Options menu's Screen Shake slider. shake_scale 0 = no shake,
	# 1 = stock. Pulled live so the change takes effect during the current
	# trauma decay.
	var scale: float = 1.0
	if Engine.has_singleton("Settings") or has_node("/root/Settings"):
		scale = clamp(get_node("/root/Settings").shake_scale, 0.0, 1.0)
	var amount = pow(trauma, trauma_power) * scale
	rotation = max_roll * amount * randf_range(-1, 1)
	offset.x = max_offset.x * amount * randf_range(-1, 1)
	offset.y = max_offset.y * amount * randf_range(-1, 1)
	noise_pos += Vector3.ONE
