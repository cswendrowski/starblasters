extends Sprite2D

func _ready() -> void:
	var light_x : float = randf_range(0.0, 1.0)
	var light_y : float = randf_range(0.0, 1.0)
	var _seed : float = randf_range(1.0, 10.0)
	var _size : int = randi_range(1,10)
	var _pixels : int = int(scale.x*256)
	if _pixels < 128:
		_pixels = 128
	elif _pixels > 2048:
		_pixels = 2048
	
	material.set_shader_parameter("size" , _size)
	material.set_shader_parameter("light_origin", Vector2(light_x, light_y))
	material.set_shader_parameter("seed", _seed)
	material.set_shader_parameter("pixels", _pixels)
