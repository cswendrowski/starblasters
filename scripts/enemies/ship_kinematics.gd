class_name ShipKinematics
extends RefCounted

# Ship kinematics filter (roadmap P1.5 / conductor review §7 — 2026-07-02).
#
# Generalizes the binary inertia hook that used to live inline in enemy_core._process into a
# per-chassis velocity filter, so composed enemies read as SHIPS WITH MASS (accel/decel limits,
# banking) instead of pixels that snap direction. Static-helper style (Effects family) so bespoke
# hosts — bosses, cruiser/burner, hazards — can adopt it later without welding it into enemy_core.
#
# Core rule (spec §7 constraint 1): the applied velocity move_toward()s the pattern's desired
# velocity by an accel budget derived from chassis accel/weight. move_toward (NOT an asymptotic lerp)
# so the steady-state speed converges EXACTLY to the pattern's rung value; transients off-rung are
# fine. Result is capped at Clarity.ABS_MAX_SPEED.
#
# Determinism (spec §7 constraint 4): pure function of its inputs — ZERO per-instance randomness. A
# step_wall row spawned in one frame with identical params stays lockstep.
#
# The filter has no persistent object; the caller owns the applied-velocity state (reset on
# on_start/recycle — spec §7 constraint 5) and passes it in each frame.

# Fidelity classes — how heavily a pattern's step is filtered. Declared per-pattern via
# movement_pattern.fidelity(). EXACT is the default so nothing changes behavior without an explicit
# opt-in.
enum Fidelity {
	EXACT,           # bypass entirely — telegraphs, spawn teleports, hard-authored geometry.
	SMOOTH,          # full velocity filter (the old uses_inertia() behavior).
	EXACT_Y_SMOOTH_X # vertical raw, lateral filtered (lane patterns — geometry stays exact, snapiness gone).
}

# Reference accel budget for the SMOOTH class: enemy_core's old INERTIA_ACCEL. Divided by the
# chassis weight so heavier ships lag more (Roman 2026-06-11). Preserved verbatim as the default so
# the SMOOTH class reproduces the shipped inertia feel exactly.
const SMOOTH_ACCEL: float = 2400.0

# Lateral accel budget for EXACT_Y_SMOOTH_X. Sized so the lane-lag error stays inside the <~4px
# bound the LaneTraffic free-checks + director occupancy scans assume (spec §7 constraint 2). See
# the derivation in filter() below — a 30px lane hop over 0.25s produces a peak lateral speed of
# ~180 px/s; at this budget the filter reaches that speed in <1 frame, so tracking lag is a fraction
# of a pixel. High + weight-independent on purpose: lane geometry must stay tight regardless of mass.
const LANE_LAT_ACCEL: float = 6000.0
# Hard safety clamp on the lateral position error vs the closed-form lane X (belt-and-suspenders on
# top of the budget above): if the filtered X ever drifts past this from the pattern's desired X, the
# caller snaps the residual. Keeps the free-check invariant true even under a frame hitch.
const LANE_LAT_MAX_ERR: float = 4.0


# The velocity filter. Given the current applied velocity, the pattern's desired velocity, the
# chassis, delta, and the fidelity class → the new applied velocity. Caps at ABS_MAX_SPEED.
#
#   applied_vel : the velocity actually used last frame (caller-owned state).
#   desired_vel : step / delta from the pattern this frame (the contract target).
#   accel       : chassis accel (px/s²) — unused for SMOOTH (which uses SMOOTH_ACCEL/weight to
#                 preserve the shipped feel) but threaded through for future bespoke tuning.
#   weight      : chassis mass; heavier = laggier.
#   delta       : frame time (already delta-capped by the caller).
#   fidelity    : one of Fidelity.*.
static func filter(applied_vel: Vector2, desired_vel: Vector2, accel: float, weight: float,
		delta: float, fidelity: int) -> Vector2:
	if delta <= 0.0:
		return applied_vel
	if fidelity == Fidelity.EXACT:
		# Bypass — the caller shouldn't even call filter() for EXACT patterns, but return the
		# desired velocity verbatim if it does, so behavior is identical to no filter.
		return _cap(desired_vel)
	var w: float = maxf(0.6, weight)
	if fidelity == Fidelity.EXACT_Y_SMOOTH_X:
		# Vertical applied RAW (never filter a descender's Y — spec §7 constraint 3 relatives:
		# lane-Y drives crosser/anchor stagger arrival). Lateral filtered at the high lane budget.
		var out_x: float = move_toward(applied_vel.x, desired_vel.x, LANE_LAT_ACCEL * delta)
		return _cap(Vector2(out_x, desired_vel.y))
	# SMOOTH: full velocity filter at the reference budget / weight — the shipped inertia behavior.
	var budget: float = (SMOOTH_ACCEL / w) * delta
	return _cap(applied_vel.move_toward(desired_vel, budget))


# Cap a velocity's magnitude at the absolute readability ceiling (Clarity rung 8 = 480 px/s). A
# transient off-rung during a filter transient is fine; a filtered velocity must never exceed the
# strobe ceiling.
static func _cap(v: Vector2) -> Vector2:
	var sp: float = v.length()
	if sp > Clarity.ABS_MAX_SPEED and sp > 0.0:
		return v * (Clarity.ABS_MAX_SPEED / sp)
	return v
