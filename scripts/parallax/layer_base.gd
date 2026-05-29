extends CanvasLayer
class_name ParallaxLayerBase

@export var scroll_rate: float = 0.0

@export var modulate_color: Color = Color.WHITE:
	set(v):
		modulate_color = v
		if _canvas_mod != null:
			_canvas_mod.color = v

var _canvas_mod: CanvasModulate = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas_mod = $CanvasModulate if has_node("CanvasModulate") else null
	if _canvas_mod != null:
		_canvas_mod.color = modulate_color


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
