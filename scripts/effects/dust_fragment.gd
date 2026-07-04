extends Node2D

const BulletWorld = preload("res://scripts/systems/bullet_world.gd")

# Small inert debris chunk (Roman 2026-06-11) — an asteroid fragment or a dust mote
# thrown out by an asteroid shatter. Drifts outward with drag, leaves a thin
# same-colour 1px dust trail, and fades out. Harmless: no collision, no gameplay.

var velocity: Vector2 = Vector2.ZERO
var color: Color = Color(0.6, 0.55, 0.5)
var size_px: float = 2.0
var lifetime: float = 0.9
# Per-frame brightness flicker (0 = none). A 1px mote that jitters brightness reads as
# moving even when nearly still (Roman 2026-06-11: "brightness variation/jitter").
var brightness_jitter: float = 0.0
# Per-second velocity bleed. Low = a steady straight drift (persistent asteroid motes).
var drag: float = 1.2

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
	# Parent the trail to OUR OWN container (combat scene, or a dev lab's SubViewport
	# world) so it renders in the same viewport as the fragment — not the window root.
	var p: Node = get_parent()
	if p == null:
		# Prefer a SubViewport dev bench's gameplay layer over current_scene/root (no-op in production)
		# so an unparented trail doesn't render in the window's top-left corner.
		p = BulletWorld.spawn_root(get_tree(), get_tree().current_scene if get_tree().current_scene != null else get_tree().root)
	p.add_child(_trail)


func _process(delta: float) -> void:
	_t += delta
	position += velocity * delta
	velocity *= maxf(0.0, 1.0 - drag * delta)   # drag
	if _rect != null:
		var a: float = clampf(1.0 - _t / lifetime, 0.0, 1.0)
		var j: float = 1.0 + (randf_range(-brightness_jitter, brightness_jitter) if brightness_jitter > 0.0 else 0.0)
		_rect.modulate = Color(j, j, j, a)
	_sample -= delta
	if _sample <= 0.0 and _trail != null and is_instance_valid(_trail):
		_sample = 0.04
		_trail.add_point(global_position)
		# Longer streak that fades out along its tail (gradient head→transparent tail).
		while _trail.get_point_count() > 16:
			_trail.remove_point(0)
	if _t >= lifetime:
		if _trail != null and is_instance_valid(_trail):
			var line: Line2D = _trail
			_trail = null
			var tw := line.create_tween()
			tw.tween_property(line, "modulate:a", 0.0, 0.3)
			tw.tween_callback(line.queue_free)
		queue_free()
