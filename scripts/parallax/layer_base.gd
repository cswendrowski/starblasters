extends CanvasLayer
class_name ParallaxLayerBase

@export var scroll_rate: float = 0.0

@export var modulate_color: Color = Color.WHITE:
	set(v):
		modulate_color = v
		_recompute_modulate()

@export var brightness: float = 1.0:
	set(v):
		brightness = v
		_recompute_modulate()

@export var contrast: float = 1.0:
	set(v):
		contrast = v
		_recompute_modulate()

var _canvas_mod: CanvasModulate = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas_mod = $CanvasModulate if has_node("CanvasModulate") else null
	if _canvas_mod != null:
		_recompute_modulate()


func scroll(delta_y: float) -> void:
	offset.y += delta_y
	_on_scrolled()


func _on_scrolled() -> void:
	pass


func reset() -> void:
	offset = Vector2.ZERO
	_on_reset()


func _on_reset() -> void:
	pass


func _recompute_modulate() -> void:
	if _canvas_mod == null:
		return
	var base := modulate_color
	var r := clampf((base.r - 0.5) * contrast + 0.5, 0.0, 1.0) * brightness
	var g := clampf((base.g - 0.5) * contrast + 0.5, 0.0, 1.0) * brightness
	var b := clampf((base.b - 0.5) * contrast + 0.5, 0.0, 1.0) * brightness
	_canvas_mod.color = Color(r, g, b, base.a)
