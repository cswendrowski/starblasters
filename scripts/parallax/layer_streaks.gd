extends "res://scripts/parallax/layer_base.gd"

@export var streak_count: int = 14
@export var streak_speed: float = 750.0
@export var enabled: bool = true
# Streak color alpha (promoted from the hardcoded 0.6 mid-gradient stop).
# Default 0.6 = today's look; lower it to make streaks less projectile-like.
@export var streak_alpha: float = 0.6
# Lower bound of the per-streak speed multiplier (upper stays 1.2). Promoted
# from the hardcoded 0.8; widen it (→0.5) for more depth-spread variance.
@export var streak_speed_variance_min: float = 0.8
# Palette tint multiplying the streak color. WHITE = today's neutral streaks;
# set from the level's dominant hue to tie streaks into the palette.
@export var streak_tint: Color = Color.WHITE

var _particles: GPUParticles2D = null
# Config snapshot the live particles were built with — rebuild() compares against
# it so unchanged configs are a no-op (keeps the default path visually untouched).
var _spawned_cfg: Array = []


func _ready() -> void:
	super._ready()
	if enabled:
		_spawn_warp_streaks()


func _current_cfg() -> Array:
	return [streak_count, streak_speed, enabled, streak_alpha, streak_speed_variance_min, streak_tint]


# Re-spawn the particles IF the exports changed since the live spawn. Needed
# because the gradient/material are built once at spawn: the coordinator's
# _populate writes streak config AFTER _on_reset already respawned (regenerate
# order), so without this the config always landed one generation late.
func rebuild() -> void:
	if _current_cfg() == _spawned_cfg:
		return
	if _particles and is_instance_valid(_particles):
		_particles.queue_free()
		_particles = null
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
	m.initial_velocity_min = streak_speed * streak_speed_variance_min
	m.initial_velocity_max = streak_speed * 1.2
	m.gravity = Vector3.ZERO
	m.scale_min = 0.7
	m.scale_max = 1.6
	# streak_tint multiplies the base colors (WHITE = neutral); streak_alpha drives
	# the bright mid-stop (default 0.6 = today's look).
	var t0 := Color(1.0, 1.0, 1.0, 0.0) * streak_tint
	var t1 := Color(streak_tint.r, streak_tint.g, streak_tint.b, streak_alpha)
	var t2 := Color(0.55, 0.7, 1.0, 0.0) * streak_tint
	var grad = Gradient.new()
	grad.colors = PackedColorArray([t0, t1, t2])
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
	_spawned_cfg = _current_cfg()
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
