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
#
# Legacy compatibility:
#   The old on_process(enemy, delta) hook still exists as a thin wrapper
#   that calls compute_step + applies the step. Any caller that hasn't
#   been migrated yet will still work.

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


# Legacy entry point. Internally routes through compute_step so old
# callers (or patterns that still mutate enemy.position directly inside
# overridden on_process) keep working during migration. Once everything
# is on compute_step we can delete this.
func on_process(enemy, delta: float) -> void:
	var step: Vector2 = compute_step(enemy, delta)
	if step != Vector2.ZERO and enemy is Node2D:
		enemy.position += step
