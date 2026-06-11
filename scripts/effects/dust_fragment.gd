extends Node2D

# Small inert debris chunk (Roman 2026-06-11) — an asteroid fragment or a dust mote
# thrown out by an asteroid shatter. Drifts outward with drag, leaves a thin
# same-colour 1px dust trail, and fades out. Harmless: no collision, no gameplay.

var velocity: Vector2 = Vector2.ZERO
var color: Color = Color(0.6, 0.55, 0.5)
var size_px: float = 2.0
var lifetime: float = 0.9

var _t: float = 0.0
var _rect: ColorRect = null
var _trail: Line2D = null
var _sample: float = 0.0


func _ready() -> void:
	_rect = ColorRect.new()
	_rect.size = Vector2(size_px, size_px)
	_rect.position = -Vector2(size_px, size_px) * 0.5
	_rect.color = color
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	z_index = 4
	# 1px dust trail (same colour, faint) parented to the scene so it outlives this node.
	_trail = Line2D.new()
	_trail.width = 1.0
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(color.r, color.g, color.b, 0.25), Color(color.r, color.g, color.b, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	_trail.gradient = g
	_trail.z_index = 3
	_trail.z_as_relative = false
	var p: Node = get_tree().current_scene
	if p == null:
		p = get_tree().root
	p.add_child(_trail)


func _process(delta: float) -> void:
	_t += delta
	position += velocity * delta
	velocity *= maxf(0.0, 1.0 - 1.2 * delta)   # drag
	if _rect != null:
		_rect.modulate.a = clampf(1.0 - _t / lifetime, 0.0, 1.0)
	_sample -= delta
	if _sample <= 0.0 and _trail != null and is_instance_valid(_trail):
		_sample = 0.04
		_trail.add_point(global_position)
		while _trail.get_point_count() > 8:
			_trail.remove_point(0)
	if _t >= lifetime:
		if _trail != null and is_instance_valid(_trail):
			var line: Line2D = _trail
			_trail = null
			var tw := line.create_tween()
			tw.tween_property(line, "modulate:a", 0.0, 0.3)
			tw.tween_callback(line.queue_free)
		queue_free()
