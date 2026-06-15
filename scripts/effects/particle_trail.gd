extends Line2D

@export var particle_node: Node2D          # the emitter to follow
@export var max_points: int = 30
@export var min_step: float = 2.0           # px before a new point is added

func _ready() -> void:
	set_as_top_level(true)                  # points are in global space
	# fade the tail out instead of popping
	width_curve = _falloff_curve()

func _process(_delta: float) -> void:
	if particle_node == null:
		return
	var p := particle_node.global_position
	if points.is_empty() or p.distance_to(points[points.size() - 1]) >= min_step:
		add_point(p)
	while points.size() > max_points:
		remove_point(0)

func _falloff_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))          # tail end thin
	c.add_point(Vector2(1.0, 1.0))          # head full width
	return c
