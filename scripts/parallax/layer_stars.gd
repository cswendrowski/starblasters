extends ParallaxLayerBase

@export var far_density: float = 32.0
@export var far_threshold: float = 0.96
@export var near_density: float = 20.0
@export var near_threshold: float = 0.94
@export var near_brightness: float = 1.15

var _far_para: Node = null
var _near_para: Node = null
var _scroll_accum_far: float = 0.0
var _scroll_accum_near: float = 0.0

const FAR_RATE  := 0.02
const NEAR_RATE := 0.08


func _ready() -> void:
	super._ready()
	_far_para  = get_node_or_null("FarStars")
	_near_para = get_node_or_null("NearStars")
	_apply_star_shaders()


func _apply_star_shaders() -> void:
	var shader_path := "res://graphics/starfield.gdshader"
	if not ResourceLoader.exists(shader_path):
		# Try alternate paths used in V1
		for p in ["res://graphics/starfield.gdshader", "res://shaders/starfield.gdshader"]:
			if ResourceLoader.exists(p):
				shader_path = p
				break
	if not ResourceLoader.exists(shader_path):
		return
	var shader := load(shader_path) as Shader
	var far_rect := get_node_or_null("FarStars/FarRect") as ColorRect
	var near_rect := get_node_or_null("NearStars/NearRect") as ColorRect
	if far_rect:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("density",    far_density)
		mat.set_shader_parameter("threshold",  far_threshold)
		mat.set_shader_parameter("brightness", 1.0)
		mat.set_shader_parameter("scroll_speed", 0.0)
		far_rect.material = mat
	if near_rect:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("density",    near_density)
		mat.set_shader_parameter("threshold",  near_threshold)
		mat.set_shader_parameter("brightness", near_brightness)
		mat.set_shader_parameter("scroll_speed", 0.0)
		near_rect.material = mat


func scroll_stars(drift_delta: float) -> void:
	_scroll_accum_far  += drift_delta * FAR_RATE
	_scroll_accum_near += drift_delta * NEAR_RATE
	if _far_para != null:
		_far_para.scroll_offset = Vector2(0, _scroll_accum_far)
	if _near_para != null:
		_near_para.scroll_offset = Vector2(0, _scroll_accum_near)


func _on_reset() -> void:
	_scroll_accum_far  = 0.0
	_scroll_accum_near = 0.0
	if _far_para != null:
		_far_para.scroll_offset = Vector2.ZERO
	if _near_para != null:
		_near_para.scroll_offset = Vector2.ZERO
