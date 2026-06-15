extends Node2D

# AsteroidFragment (Roman 2026-06-11) — a procgen asteroid chunk thrown from a
# shattered hazard asteroid. New random SHAPE (fresh seed), same colour as the parent,
# spins, disperses along its launch vector, and inherits the parent's downward drift so
# it leaves the map at the bottom at the same speed — fading out as it recedes (a
# stand-in for sinking into the wreck layer).
#
#   AsteroidFragment.spawn(parent, world_pos, {...}) -> Node2D

const PROCGEN_ASTEROID = "res://Planets/Asteroids/Asteroid.tscn"

var velocity: Vector2 = Vector2.ZERO   # launch (cone) velocity
var down_speed: float = 60.0           # parent's drift speed — fragment leaves at the same rate
var drag: float = 1.1                  # bleed the cone velocity so the down-drift dominates
var spin: float = 0.0                  # rad/s
var size_px: float = 22.0
var color: Color = Color(0.5, 0.48, 0.46)
var lifetime: float = 1.8

var _t: float = 0.0
var _visual: Node = null
var _dead: bool = false

static var _self_script: GDScript = null


static func spawn(parent: Node, world_pos: Vector2, opts: Dictionary = {}) -> Node2D:
	if parent == null:
		return null
	if _self_script == null:
		_self_script = load("res://scripts/effects/asteroid_fragment.gd")
	var f = _self_script.new()
	f.global_position = world_pos
	if opts.has("velocity"): f.velocity = opts["velocity"]
	if opts.has("down_speed"): f.down_speed = float(opts["down_speed"])
	if opts.has("spin"): f.spin = float(opts["spin"])
	if opts.has("size_px"): f.size_px = float(opts["size_px"])
	if opts.has("color"): f.color = opts["color"]
	if opts.has("lifetime"): f.lifetime = float(opts["lifetime"])
	parent.add_child(f)
	return f


func _ready() -> void:
	z_index = 5
	z_as_relative = false
	var ps = load(PROCGEN_ASTEROID)
	if ps == null:
		queue_free()
		return
	_visual = ps.instantiate()
	# Unique seed → a NEW silhouette for every chunk (Roman: "new shapes").
	var inner: Node = _visual.get_node_or_null("Asteroid")
	if inner != null and "material" in inner and inner.material != null:
		inner.material = inner.material.duplicate()
	if _visual.has_method("set_seed"):
		_visual.set_seed(randi() % 100000)
	if _visual is Control:
		(_visual as Control).custom_minimum_size = Vector2(size_px, size_px)
		(_visual as Control).size = Vector2(size_px, size_px)
		(_visual as Control).position = Vector2(-size_px * 0.5, -size_px * 0.5)
		(_visual as Control).pivot_offset = Vector2(size_px * 0.5, size_px * 0.5)
	if _visual.has_method("set_colors"):
		# Less lightening so chunks aren't washed out (Roman 2026-06-11).
		_visual.set_colors(PackedColorArray([color.lightened(0.2), color, color.darkened(0.38)]))
	if inner != null and "material" in inner and inner.material != null:
		inner.material.set_shader_parameter("roundness", 0.4)
		inner.material.set_shader_parameter("draw_outline", false)   # chunks: no pixel outline
		# Chunks FADE (translucent) — two overlapping dithered translucent rocks interleave
		# their dither checkerboards into a moiré that reads as inverted/odd colours. The main
		# hazard rocks are opaque so they're unaffected; smooth-shade the chunks. (Roman 2026-06-14)
		inner.material.set_shader_parameter("should_dither", false)
	if _visual.has_method("set_pixels"):
		_visual.set_pixels(size_px)
	add_child(_visual)


func _process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	velocity *= maxf(0.0, 1.0 - drag * delta)
	position += (velocity + Vector2(0.0, down_speed)) * delta
	if _visual is Control:
		(_visual as Control).rotation += spin * delta
	# Recede: fade out across the lifetime (sinking into the wreck layer).
	modulate.a = clampf(1.0 - _t / maxf(0.01, lifetime), 0.0, 1.0)
	if _t >= lifetime or position.y > 320.0:
		_dead = true
		queue_free()
