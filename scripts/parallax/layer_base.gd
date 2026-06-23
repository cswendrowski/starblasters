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

# HDR-bright glow multiplier on top of brightness. Default 1.0 = no change. Pushed > 1.5 (with the
# scene's HDR WorldEnvironment) it makes the whole layer bloom — the one mechanism that works on the
# shader-driven planets too, since CanvasModulate multiplies the layer's composited output post-shader
# (a CanvasItem `modulate` is ignored by planet shaders that overwrite COLOR). Tuned per-layer.
@export var glow_mult: float = 1.0:
	set(v):
		glow_mult = v
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
	var r := clampf((base.r - 0.5) * contrast + 0.5, 0.0, 1.0) * brightness * glow_mult
	var g := clampf((base.g - 0.5) * contrast + 0.5, 0.0, 1.0) * brightness * glow_mult
	var b := clampf((base.b - 0.5) * contrast + 0.5, 0.0, 1.0) * brightness * glow_mult
	_canvas_mod.color = Color(r, g, b, base.a)
