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


# Ship-kinematics fidelity class (roadmap P1.5 / review §7 — 2026-07-02). Declares HOW HEAVILY
# enemy_core filters this pattern's step through the ShipKinematics velocity filter:
#   ShipKinematics.Fidelity.EXACT            — bypass (default; nothing changes without an opt-in).
#   ShipKinematics.Fidelity.SMOOTH           — full velocity filter (the old uses_inertia behavior).
#   ShipKinematics.Fidelity.EXACT_Y_SMOOTH_X — vertical raw, lateral filtered (lane STEP hops).
# EXACT is the deliberate default so unconfigured/telegraph/hard-authored patterns keep today's
# exact motion. Patterns that need mass opt in by overriding this (or, legacy, uses_inertia()).
# NB: returns EXACT unless a subclass overrides EITHER this OR uses_inertia() — the alias bridge in
# the base maps a true uses_inertia() to SMOOTH so the four already-opted patterns need no edit.
func fidelity() -> int:
	# Bridge: honor a legacy uses_inertia() override (drift/loiter/loiter_sweep/skirmish) → SMOOTH.
	return ShipKinematics.Fidelity.SMOOTH if uses_inertia() else ShipKinematics.Fidelity.EXACT


# DEPRECATED alias for fidelity() (kept working per the P1.5 spec). Historically: "apply
# unit-weighted velocity smoothing (inertia) to this pattern's steps" — position-error patterns
# (drift/loiter) opt in; the smoothing lives in the unit (enemy_core), not the pattern. New patterns
# should override fidelity() directly (EXACT/SMOOTH/EXACT_Y_SMOOTH_X); this maps only to SMOOTH.
func uses_inertia() -> bool:
	return false


# --- Chassis locomotion accessors (locomotion refactor 2026-06-19) ---
# Patterns express SHAPE only; they read SCALE from the enemy through these. Each falls back to a
# "medium enemy" default when the enemy lacks the field or leaves it unset (0) — load-bearing for
# bosses/hazards without the stat block AND the bare-Node2D dummies in dev tools / headless tests.
# The DEFAULT_* consts are the ONE source for those medium-chassis fallbacks — enemy_base's
# _apply_auto_rotation reads DEFAULT_TURN_RATE/DEFAULT_WEIGHT from here too (no re-hardcoding).
const DEFAULT_MOVE_SPEED := 180.0   # px/s
const DEFAULT_TURN_RATE := 300.0    # deg/s
const DEFAULT_ACCEL := 600.0        # px/s²
const DEFAULT_WEIGHT := 1.0

func _move_speed(enemy) -> float:
	return enemy.move_speed if ("move_speed" in enemy and enemy.move_speed > 0.0) else DEFAULT_MOVE_SPEED


func _turn_rate(enemy) -> float:   # deg/s
	return enemy.turn_rate if ("turn_rate" in enemy and enemy.turn_rate > 0.0) else DEFAULT_TURN_RATE


func _accel(enemy) -> float:       # px/s²
	return enemy.accel if ("accel" in enemy and enemy.accel > 0.0) else DEFAULT_ACCEL


func _weight(enemy) -> float:
	return enemy.weight if ("weight" in enemy and enemy.weight > 0.0) else DEFAULT_WEIGHT


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


# Shared descend-to-depth step (review §7 dedup — 2026-07-02). The "descend at chassis speed,
# clamp the final frame so we land exactly on `depth` (never overshoot), report arrival" idiom was
# copy-pasted ~5× (loiter_sweep/skirmish/drift enter phases, boss_sweep). Returns the vertical step
# (px) to apply THIS frame; sets `arrived[0]` true on the frame the enemy reaches/passes `depth`.
# `speed` px/s (pass _move_speed(enemy) or a bespoke value). Pure vertical — callers that also move
# laterally add their own X. Behavior is byte-identical to the inlined form it replaces.
func descend_to(enemy, depth: float, speed: float, delta: float, arrived: Array) -> float:
	var sy: float = speed * delta
	if enemy.position.y + sy >= depth:
		sy = depth - enemy.position.y
		arrived[0] = true
	return sy


# Resolve the player node (first member of the "player" group), or null. Shared by the
# patterns that steer toward the player (omni_thrust, beeline_player).
func _find_player(enemy) -> Node:
	for n in enemy.get_tree().get_nodes_in_group("player"):
		return n
	return null
