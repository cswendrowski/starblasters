extends "res://scripts/parallax/layer_base.gd"

const RESET_THRESHOLD := 340.0

@export var asteroid_count: int = 4
@export var asteroid_min_size: float = 12.0
@export var asteroid_max_size: float = 24.0
@export var nebula_enabled: bool = false
@export var nebula_alpha: float = 0.18
@export var nebula_shader_path: String = "res://graphics/nebula2.gdshader"
@export var nebula_scale: float = 2.5
@export var nebula_octaves: int = 5
@export var nebula_density: float = 0.9
@export var nebula_edge: float = 0.4
@export var nebula_drift: float = 0.004
@export var pixel_density: float = 1.0
@export var mine_count: int = 0

# Use the actual ASTEROID_SCENE path from galaxy_backdrop.gd
const ASTEROID_SCENE = "res://Planets/Asteroids/Asteroid.tscn"
const SPACE_COLORSCHEME := "res://SpaceBG/Colorscheme.tres"

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
	var shader := load(nebula_shader_path) as Shader
	if shader == null:
		return
	var cs = load(SPACE_COLORSCHEME)  # gradient texture — required for color
	_nebula_rect = ColorRect.new()
	_nebula_rect.name = "Nebula"
	_nebula_rect.size = Vector2(480, 270)
	_nebula_rect.color = Color(0, 0, 0, 0)
	_nebula_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var nebula_px: float = 480.0 / max(pixel_density, 0.01)
	var sd: float = 1.0
	if _local_rng:
		sd = 1.0 + float(_local_rng.seed % 900) / 100.0
	mat.set_shader_parameter("scale", nebula_scale)
	mat.set_shader_parameter("octaves", nebula_octaves)
	mat.set_shader_parameter("seed", sd)
	mat.set_shader_parameter("pixels", nebula_px)
	mat.set_shader_parameter("drift_speed", nebula_drift)
	mat.set_shader_parameter("max_alpha", nebula_alpha)
	mat.set_shader_parameter("density", nebula_density)
	mat.set_shader_parameter("edge_sharpness", nebula_edge)
	mat.set_shader_parameter("uv_correct", Vector2(1.0, 1.0))
	if cs != null:
		mat.set_shader_parameter("colorscheme", cs)
	# nebula2-only knobs — gentle swirl/filaments per V1's live near pass.
	if nebula_shader_path.ends_with("nebula2.gdshader"):
		mat.set_shader_parameter("warp_strength", 0.8)
		mat.set_shader_parameter("warp_scale", 1.0)
		mat.set_shader_parameter("wisp_strength", 0.2)
		mat.set_shader_parameter("opacity", 1.0)
		mat.set_shader_parameter("scroll_offset", Vector2.ZERO)
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
	if _nebula_rect and is_instance_valid(_nebula_rect):
		# Keep the nebula screen-fixed (counter the layer's offset.y) so it
		# doesn't scroll off and leave a gap; drift comes from the shader.
		_nebula_rect.position.y = -offset.y
		if _nebula_rect.material is ShaderMaterial:
			(_nebula_rect.material as ShaderMaterial).set_shader_parameter(
				"scroll_offset", Vector2(0, offset.y / NEBULA_TILE)
			)


func _on_reset() -> void:
	_clear_content()
