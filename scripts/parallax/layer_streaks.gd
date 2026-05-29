extends "res://scripts/parallax/layer_base.gd"

@export var streak_count: int = 14
@export var streak_speed: float = 750.0
@export var enabled: bool = true

var _particles: GPUParticles2D = null


func _ready() -> void:
	super._ready()
	if enabled:
		_spawn_warp_streaks()


func _spawn_warp_streaks() -> void:
	# Foreground hyperspace streaks — short bright vertical lines, sparse, very
	# fast. Sells the "rush" feel without crowding the playfield.
	var p := GPUParticles2D.new()
	p.name = "WarpStreaks"
	p.amount = streak_count
	p.lifetime = 1000.0 / max(streak_speed, 1.0)
	p.preprocess = p.lifetime  # populate the field on spawn rather than empty
	p.one_shot = false
	p.explosiveness = 0.0
	p.local_coords = false
	p.position = Vector2(240, -10)
	p.texture = _build_streak_texture()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(260, 6, 0)
	m.direction = Vector3(0, 1, 0)
	m.spread = 0.0
	m.initial_velocity_min = streak_speed * 0.8
	m.initial_velocity_max = streak_speed * 1.2
	m.gravity = Vector3.ZERO
	m.scale_min = 0.7
	m.scale_max = 1.6
	var grad = Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.6),
		Color(0.55, 0.7, 1.0, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	var ramp = GradientTexture1D.new()
	ramp.gradient = grad
	ramp.width = 32
	m.color_ramp = ramp
	p.process_material = m
	# Additive blend so streaks add light over the scene.
	var canvas_mat := CanvasItemMaterial.new()
	canvas_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = canvas_mat
	_particles = p
	add_child(p)


static func _build_streak_texture() -> Texture2D:
	# Tall thin gradient: faint at the tips, bright in the middle.
	var g = Gradient.new()
	g.colors = PackedColorArray([
		Color(1, 1, 1, 0),
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0),
	])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var t = GradientTexture2D.new()
	t.gradient = g
	t.width = 2
	t.height = 28
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0.5, 0.0)
	t.fill_to = Vector2(0.5, 1.0)
	return t


func _on_reset() -> void:
	if _particles and is_instance_valid(_particles):
		_particles.queue_free()
		_particles = null
	if enabled:
		_spawn_warp_streaks()
