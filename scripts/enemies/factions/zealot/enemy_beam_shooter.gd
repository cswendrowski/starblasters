extends "res://scripts/enemies/enemy_core.gd"
class_name EnemyBeamShooter

# Beamer — beam specialist. LOCOMOTION is on the lane system (SWEEP uses LoiterSweep — descend →
# rake L↔R; CHASE/LOCK use Drift — descend → hold). The BEAM is now a data BEAM mount (roster
# BEAMER_SWEEP_MOUNT / BEAMER_CHASE_MOUNT, 2026-06-23): the shared BeamEmitter with configurable aim
# + a settle_y gate (begins firing once descended into the band), realized by MountBuilder on the
# BeamEmitter marker. This script keeps only the BESPOKE bits the mount can't express: anti-stacking
# repulsion + the movement fallback (aim_behavior picks rake-vs-hold for direct/dev instantiation).
# NOTE: the LOCK variant (enemy_beamer_lock.tscn) is Enemy-Bench-only (no roster entry / mount), so
# it has no default beam in the bench — add a BEAM mount in the Mounts editor to test it.

const LoiterSweep = preload("res://scripts/enemies/patterns/loiter_sweep.gd")
const Drift = preload("res://scripts/enemies/patterns/drift.gd")

enum AimBehavior { SWEEP, CHASE, LOCK }
@export var aim_behavior: int = AimBehavior.SWEEP

const SETTLE_Y       := 58.0
const SPACING_RADIUS := 32.0
const PUSH_STRENGTH  := 60.0


func _ready() -> void:
	max_health = 12
	bounty_value = 30
	auto_rotate = false                       # the beam mount owns aim; the hull holds a fixed facing
	offscreen_mode = OffscreenMode.NONE       # holds until destroyed
	rotation = PI                             # front/maw toward the player below (LOCAL_FORWARD beam)
	# Locomotion fallback (the matrix assigns loiter_sweep / drift_high). SWEEP rakes; the tracker
	# variants hold and aim.
	if movement == null:
		if aim_behavior == AimBehavior.SWEEP:
			var m := LoiterSweep.new()
			m.settle_y = SETTLE_Y
			movement = m
		else:
			var d := Drift.new()
			d.hover_y = SETTLE_Y
			d.jiggle_px = 0.0
			movement = d
	super._ready()


func _process(delta: float) -> void:
	super._process(delta)        # movement (LoiterSweep / Drift) + components (incl. the beam mount)
	if _dying:
		return
	_repel_siblings(delta)


# Push apart from any other beamer within SPACING_RADIUS so sweeps don't stack.
func _repel_siblings(delta: float) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self or not is_instance_valid(node):
			continue
		if node.get_script() != get_script():
			continue
		var diff: Vector2 = global_position - (node as Node2D).global_position
		var dist: float = diff.length()
		if dist < SPACING_RADIUS and dist > 0.001:
			global_position += diff.normalized() * PUSH_STRENGTH * delta
	global_position = Playfield.clamp_pos(global_position, 8.0)
