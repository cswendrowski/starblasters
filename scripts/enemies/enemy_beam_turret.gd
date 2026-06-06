extends EnemyBase
class_name EnemyBeamTurret

# Beam turret — child of EnemyCruiser, no independent movement. Locks aim on the
# player at windup start, then fires a directed beam (narrower than the Beamer).
#
# M6a.2 step 4b: the bespoke beam FSM + 4-layer Line2D + segment-distance damage
# were replaced by a single LOCKED-aim BeamEmitter. The emitter snapshots the aim at
# each windup and self-ticks; this script is now just stats + the beam config.

const BeamEmitter = preload("res://scripts/enemies/beam_emitter.gd")

# Aim behavior (Roman 2026-06-06), shared with the Beamer: LOCK = snapshot aim at
# windup and hold (the classic turret/cruiser feel); CHASE = track the player while
# firing (rate-limited so they can stay ahead).
enum AimBehavior { LOCK, CHASE }
@export var aim_behavior: int = AimBehavior.LOCK

var _beam: Node = null


func _ready() -> void:
	max_health   = 4
	bounty_value = 5
	auto_rotate  = false
	display_scale = 0.5
	super._ready()
	var mode: int = BeamEmitter.AimMode.TRACKING if aim_behavior == AimBehavior.CHASE else BeamEmitter.AimMode.LOCKED
	_beam = BeamEmitter.new()
	_beam.configure({
		# IDLE 2 -> WINDUP 3 -> FIRING 2 -> COOLDOWN 3, then loop back to WINDUP
		# (skip idle on repeat, as the bespoke turret did).
		"idle_time": 2.0, "windup_time": 3.0, "firing_time": 2.0, "cooldown_time": 3.0,
		"cycle": BeamEmitter.Cycle.LOOP_WINDUP, "autostart": true,
		"endpoint": BeamEmitter.Endpoint.RAY, "aim_mode": mode, "tracking_rate": 1.3,
		"reach": 300.0, "dps": 3.0, "hit_radius": 8.0, "emitter_offset": Vector2.ZERO,
		"target_group": "player",
		# Narrower than the Beamer: outer 8 / mid 5 / core 2, telegraph 1.
		"layers": [
			{"width": 8.0, "color": Color(0.65, 0.15, 1.0, 0.55)},
			{"width": 5.0, "color": Color(1.0, 0.5, 0.1, 0.85)},
			{"width": 2.0, "color": Color(1.0, 0.95, 0.35, 1.0)},
		],
		"telegraph_width": 1.0,
	})
	add_child(_beam)
