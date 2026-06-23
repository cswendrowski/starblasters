extends Resource

# Base class for enemy movement patterns. Refactored 2026-05-16 to a
# velocity/step contract so all patterns share the same shape and so the
# common per-frame plumbing (delta cap, side clamp, offscreen cycle, auto
# rotation) lives in exactly one place (enemy_core).
#
# Contract for new patterns:
#   on_start(enemy)              — fully reset all pattern state. Patterns
#                                   are duplicate()'d per enemy, but the
#                                   parallax cycle re-calls on_start after
#                                   each fly-back, so re-init must be
#                                   idempotent.
#   compute_step(enemy, delta)   — return the position delta (in pixels)
#                                   to apply this frame. NEVER mutate
#                                   enemy.position directly — the caller
#                                   (enemy_core / boss.gd) handles that.
#
# Why step-deltas instead of velocity:
#   Some patterns are inherently position-based (sin-wave absolute x).
#   Returning a step lets those patterns compute (target - current) and
#   coexist with velocity-based patterns under one shape.

func on_start(_enemy) -> void:
	pass


func compute_step(_enemy, _delta: float) -> Vector2:
	return Vector2.ZERO


# Whether this pattern descends MONOTONICALLY through the playfield, so the enemy
# can fire by path progress (band-Y) instead of a random timer — "path-phase
# firing" (construction plan §8). Default false. Monotonic descenders override
# true; patterns that reverse vertically (advance/retreat) or hold a position
# (loiter) must NOT, since band-Y progress isn't monotonic for them.
func path_phase_capable() -> bool:
	return false


# Whether enemy_core should apply UNIT-WEIGHTED velocity smoothing (inertia) to this
# pattern's steps: the applied velocity eases toward the desired one, scaled by the
# unit's size-weight, so heavy ships approach/leave a hold point softly instead of
# snapping (Roman 2026-06-11). Position-error patterns (drift/loiter) opt in; the
# smoothing lives in the unit (enemy_core), not the pattern.
func uses_inertia() -> bool:
	return false


# --- Chassis locomotion accessors (locomotion refactor 2026-06-19) ---
# Patterns express SHAPE only; they read SCALE from the enemy through these. Each falls back to a
# "medium enemy" default when the enemy lacks the field or leaves it unset (0) — load-bearing for
# bosses/hazards without the stat block AND the bare-Node2D dummies in dev tools / headless tests.
func _move_speed(enemy) -> float:
	return enemy.move_speed if ("move_speed" in enemy and enemy.move_speed > 0.0) else 180.0


func _turn_rate(enemy) -> float:   # deg/s
	return enemy.turn_rate if ("turn_rate" in enemy and enemy.turn_rate > 0.0) else 300.0


func _accel(enemy) -> float:       # px/s²
	return enemy.accel if ("accel" in enemy and enemy.accel > 0.0) else 600.0


func _weight(enemy) -> float:
	return enemy.weight if ("weight" in enemy and enemy.weight > 0.0) else 1.0


# Effective engagement depth (Zones.band_progress 0..1). `fallback` is the pattern's OWN default
# depth, used when the enemy doesn't set one (depth_bp < 0) so unconfigured enemies keep today's
# behavior. A formation override is already resolved onto enemy.depth_bp before this is read.
func _depth_bp(enemy, fallback: float) -> float:
	return enemy.depth_bp if ("depth_bp" in enemy and enemy.depth_bp >= 0.0) else fallback


# --- Locomotion capability flags (Roman 2026-06-21) — chassis booleans the enemy carries. Patterns
# query these to decide whether they may slide/reverse/face-player without turning; facing itself is
# applied in enemy_base._apply_auto_rotation. Default false for bare-Node2D dummies / hosts without
# the chassis fields. ---
func _can_omni(enemy) -> bool:
	return "omni" in enemy and bool(enemy.omni)


func _can_strafe(enemy) -> bool:
	return "strafe" in enemy and bool(enemy.strafe)


func _can_retro(enemy) -> bool:
	return "retro" in enemy and bool(enemy.retro)


# Resolve the player node (first member of the "player" group), or null. Shared by the
# patterns that steer toward the player (omni_thrust, beeline_player).
func _find_player(enemy) -> Node:
	for n in enemy.get_tree().get_nodes_in_group("player"):
		return n
	return null
