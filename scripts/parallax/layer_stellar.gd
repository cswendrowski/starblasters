extends "res://scripts/parallax/layer_base.gd"

const RESET_THRESHOLD := 340.0

@export var asteroid_count: int = 4
@export var asteroid_min_size: float = 12.0
@export var asteroid_max_size: float = 24.0
@export var nebula_enabled: bool = false
@export var nebula_alpha: float = 0.18
@export var mine_count: int = 0

# Use the actual ASTEROID_SCENE path from galaxy_backdrop.gd
const ASTEROID_SCENE = "res://Planets/Asteroids/Asteroid.tscn"

var _objects: Array = []
var _nebula_rect: ColorRect = null
var _local_rng: RandomNumberGenerator = null

const NEBULA_TILE: float = 270.0


func populate(rng: RandomNumberGenerator) -> void:
	_local_rng = rng
	_clear_content()
	for _i in asteroid_count:
		_spawn_asteroid()
	if nebula_enabled:
		_spawn_nebula()
	if mine_count > 0:
		_spawn_bg_mines()


func _clear_content() -> void:
	for entry in _objects:
		if is_instance_valid(entry.node):
			entry.node.queue_free()
	_objects.clear()
	if _nebula_rect and is_instance_valid(_nebula_rect):
		_nebula_rect.queue_free()
		_nebula_rect = null


func _spawn_asteroid() -> void:
	if _local_rng == null:
		return
	var ps := load(ASTEROID_SCENE) as PackedScene
	if ps == null:
		return
	var a := ps.instantiate()
	var sz := _local_rng.randf_range(asteroid_min_size, asteroid_max_size)
	var sf := sz / 100.0
	a.scale = Vector2(sf, sf)
	a.modulate = Color(0.9, 0.88, 0.85, 1.0)
	a.position = Vector2(_local_rng.randf_range(16, 464), _local_rng.randf_range(-270, 0))
	add_child(a)
	if a.has_method("set_pixels"):
		a.set_pixels(maxf(sz, 16.0))
	_objects.append({"node": a, "size": sz})


func _spawn_nebula() -> void:
	var nebula_path := "res://graphics/nebula2.gdshader"
	if not ResourceLoader.exists(nebula_path):
		return
	_nebula_rect = ColorRect.new()
	_nebula_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load(nebula_path) as Shader
	mat.set_shader_parameter("alpha", nebula_alpha)
	if _local_rng:
		mat.set_shader_parameter("seed_val", float(_local_rng.randi() % 10000))
	_nebula_rect.material = mat
	add_child(_nebula_rect)


func _spawn_bg_mines() -> void:
	if _local_rng == null:
		return
	for _i in mine_count:
		var s := Sprite2D.new()
		s.position = Vector2(_local_rng.randf_range(80, 400), _local_rng.randf_range(-270, 0))
		s.scale = Vector2(0.4, 0.4)
		s.modulate = Color(0.5, 0.5, 0.5, 0.7)
		add_child(s)
		_objects.append({"node": s, "size": 8.0})


func _on_scrolled() -> void:
	for entry in _objects:
		var n: Node = entry.node
		if not is_instance_valid(n):
			continue
		if offset.y + n.position.y > RESET_THRESHOLD:
			if _local_rng:
				n.position.x = _local_rng.randf_range(16, 464)
				n.position.y = -_local_rng.randf_range(0, 270) - offset.y
	if _nebula_rect and is_instance_valid(_nebula_rect) and _nebula_rect.material is ShaderMaterial:
		(_nebula_rect.material as ShaderMaterial).set_shader_parameter(
			"scroll_offset", Vector2(0, offset.y / NEBULA_TILE)
		)


func _on_reset() -> void:
	_clear_content()
