extends GPUParticles2D

# Smoke-trail emitter that auto-orients each emitted puff so the sprite's BOTTOM
# (+Y) faces the emitter's MOVEMENT direction. It tracks its OWN global_position
# delta, so a trail attached to a moving projectile orients with no caller
# involvement. When (near-)stationary it holds the last orientation.
#
# Built by SmokeTrailFx.trail(); the colour ramp / scale / animation all live on
# the ParticleProcessMaterial — this only drives the per-emission angle.

@export var orient: bool = true
@export var jitter_deg: float = 18.0
@export var move_threshold: float = 6.0  # px/s below which we don't re-orient

var _last_pos: Vector2 = Vector2.ZERO
var _base_deg: float = 0.0  # 0 = sprite upright (puff billows up from its base)
var _primed: bool = false


func _ready() -> void:
	_last_pos = global_position
	_primed = true


func _process(delta: float) -> void:
	if not orient:
		return
	var pm := process_material as ParticleProcessMaterial
	if pm == null:
		return
	if not _primed:
		_last_pos = global_position
		_primed = true
		return
	var vel: Vector2 = (global_position - _last_pos) / maxf(delta, 0.0001)
	_last_pos = global_position
	if vel.length() > move_threshold:
		# The sprite's bottom (+Y) points world-down (angle 90°) at rotation 0;
		# rotate so it points along the motion direction instead.
		_base_deg = rad_to_deg(vel.angle()) - 90.0
	# Newly-emitted puffs get this angle (± jitter); ones already alive keep theirs.
	pm.angle_min = _base_deg - jitter_deg
	pm.angle_max = _base_deg + jitter_deg
