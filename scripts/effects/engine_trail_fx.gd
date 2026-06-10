extends Node2D

# Centralized yellow engine trail (Roman 2026-06-07). Attached by EnemyBase to ANY
# enemy that has `Engine*` Marker2D descendants — so a unit opts in purely by placing
# engine markers in its scene, no per-enemy code. Each engine marker emits a short
# yellow streak left behind in WORLD space as the enemy moves (the Line2D points are
# parented to the scene root, so the enemy outruns its own exhaust). Modeled on the
# damage smoke trail, but always-on, yellow, additive, and short (a tight exhaust
# streak, not a billowing smoke column).

const TRAIL_COLOR := Color(1.0, 0.86, 0.22)   # warm engine yellow
const POINT_LIFETIME := 0.28                   # seconds a streak point lingers
const MAX_POINTS := 14
const HEAD_WIDTH := 2.5

var _markers: Array = []      # Array[Marker2D]
var _lines: Array = []        # Array[Line2D], parallel to _markers (world-space)
var _point_t: Array = []      # Array[Array[float]], point ages per line
var _enemy: Node2D = null
var _emitting: bool = true


# Build one world-space trail line per engine marker. Call right after add_child. `color` lets a
# non-enemy host (the player) reuse this exact trail style in a different hue.
func setup(enemy: Node2D, markers: Array, color: Color = TRAIL_COLOR) -> void:
	_enemy = enemy
	_markers = markers
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	for _m in markers:
		var line := Line2D.new()
		line.width = HEAD_WIDTH
		line.default_color = color
		# Width tapers thin at the tail, full at the head (engine).
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.15))
		curve.add_point(Vector2(1.0, 1.0))
		line.width_curve = curve
		# Alpha fades to nothing at the tail; bright at the head.
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 1.0])
		grad.colors = PackedColorArray([
			Color(color.r, color.g, color.b, 0.0),
			Color(color.r, color.g, color.b, 0.9),
		])
		line.gradient = grad
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.z_index = -1          # behind the hull but OVER the outline (z -2)
		line.z_as_relative = false
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # glowy exhaust
		line.material = mat
		root.add_child(line)
		_lines.append(line)
		_point_t.append([])


# Stop/resume emitting (kept aging+fading) — EnemyBase pauses this while the enemy
# recycles (faux-parallax) or is dying, so no fresh exhaust appears.
func set_emitting(v: bool) -> void:
	_emitting = v


func _process(delta: float) -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		_free_lines()
		queue_free()
		return
	for i in _markers.size():
		var line: Line2D = _lines[i]
		if line == null or not is_instance_valid(line):
			continue
		var ages: Array = _point_t[i]
		for j in ages.size():
			ages[j] = float(ages[j]) + delta
		while ages.size() > 0 and float(ages[0]) >= POINT_LIFETIME:
			line.remove_point(0)
			ages.pop_front()
		if not _emitting:
			continue
		var mk: Node2D = _markers[i]
		if mk == null or not is_instance_valid(mk):
			continue
		line.add_point(mk.global_position)
		ages.append(0.0)
		while line.get_point_count() > MAX_POINTS:
			line.remove_point(0)
			ages.pop_front()


func _exit_tree() -> void:
	_free_lines()


func _free_lines() -> void:
	for line in _lines:
		if line != null and is_instance_valid(line):
			line.queue_free()
	_lines.clear()
	_point_t.clear()
