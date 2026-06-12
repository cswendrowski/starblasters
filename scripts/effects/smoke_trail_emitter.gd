extends GPUParticles2D

# Smoke-trail emitter (rebuilt 2026-06-11). One job: when follow_motion is on, point the
# emission DIRECTION opposite the host's velocity so the puffs stream out BEHIND the motion
# (a trail that follows the path), instead of always drifting the fixed `angle_deg`. Tracks
# its own global_position delta, so a trail attached to a moving node needs no caller help.
#
# Particle rotation now lives entirely on the ParticleProcessMaterial (angle_min/max +
# angular_velocity) — this script no longer touches per-particle angle (the old per-frame
# angle hacks never read). When follow_motion is off, the material's default direction stands.

@export var follow_motion: bool = true
@export var move_threshold: float = 6.0   # px/s below which we hold the last direction

var _last_pos: Vector2 = Vector2.ZERO
var _primed: bool = false


func _ready() -> void:
	_last_pos = global_position
	_primed = true


func _process(delta: float) -> void:
	if not follow_motion:
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
		var back: Vector2 = -vel.normalized()   # stream behind the motion
		pm.direction = Vector3(back.x, back.y, 0.0)
