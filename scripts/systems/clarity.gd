class_name Clarity
extends RefCounted

# Motion-clarity speed math for the 480×270 / 60fps pixel-art pipeline.
#
# The problem: an object that moves more than ~its own length (along the
# travel axis) per frame leaves visible gaps between afterimages — it
# strobes instead of gliding. And because `snap_2d_transforms_to_pixel`
# is on, any speed that isn't an integer px/frame produces an uneven
# step cadence (snap-wobble). Run tools/clarity_audit.gd (headless) to
# audit every projectile/enemy speed against this scale and surface any
# that exceed 8 px/frame or sit off a rung.
#
# Two rules define a "safe" speed:
#   1. Snap-clean cadence  → speed is a multiple of RUNG_STEP (integer
#      px/frame), so pixel-snapping is a no-op and the step is even.
#   2. No-gap (anti-strobe) → px/frame stays under a fraction (tier) of
#      the sprite's length along travel.
#
# A "rung" is one integer px/frame = RUNG_STEP px/s. Pick the highest
# rung whose ratio stays under your tier for that sprite's length.
#
# NOTE: helpers are static — call as `Clarity.proposed_speed(...)`.

const FPS := 60.0
const RUNG_STEP := 60.0   # px/s per 1 internal-px/frame at 60fps

# Ratio = px-per-frame ÷ sprite-length-along-travel.
const TIER_BUTTERY := 0.5   # sprite overlaps itself every frame
const TIER_CLEAN := 0.8     # clean glide, slight step at the top
const TIER_MAX := 1.0       # hard ceiling — strobe onset past here

# Absolute readability ceiling, independent of sprite size: at 480×270/60fps
# anything past ~8 px/frame is "too fast to track" even if it doesn't gap.
# Bands (px/frame): slow 1.0–1.5, medium 2.0–3.0, fast 4.0–8.0, over = >8.
const MAX_PXF := 8.0
const ABS_MAX_SPEED := MAX_PXF * RUNG_STEP   # 480 px/s = rung 8


static func px_per_frame(speed: float) -> float:
	return speed / FPS


static func ratio(speed: float, travel_len: float) -> float:
	if travel_len <= 0.0:
		return 0.0
	return px_per_frame(speed) / travel_len


# Nearest rung (multiple of RUNG_STEP) to an arbitrary speed.
static func snap_to_rung(speed: float) -> float:
	return roundf(speed / RUNG_STEP) * RUNG_STEP


# Highest rung whose ratio stays <= tier for a sprite of this travel-length.
static func max_clean_speed(travel_len: float, tier: float = TIER_CLEAN) -> float:
	var ceil_speed: float = tier * travel_len * FPS
	var rungs: float = floorf(ceil_speed / RUNG_STEP)
	return maxf(RUNG_STEP, rungs * RUNG_STEP)


# The recommended replacement for a current speed: cap it at the sprite's
# clean ceiling, then snap to the nearest rung that still respects the tier.
# (High-rate-of-fire stream weapons can safely sit a rung lower — that's a
# manual call, not encoded here.)
static func proposed_speed(current: float, travel_len: float, tier: float = TIER_CLEAN) -> float:
	if travel_len <= 0.0 or current <= 0.0:
		return current
	# Two ceilings: the per-sprite anti-gap cap AND the absolute too-fast cap.
	var capped: float = minf(current, max_clean_speed(travel_len, tier))
	capped = minf(capped, ABS_MAX_SPEED)
	var snapped: float = snap_to_rung(capped)
	# snap_to_rung can round UP past a cap; step down a rung if so.
	if ratio(snapped, travel_len) > tier or snapped > ABS_MAX_SPEED:
		snapped -= RUNG_STEP
	return maxf(RUNG_STEP, snapped)


# Human label for a ratio, matching the audit/lab vocabulary.
static func classify(r: float) -> String:
	if r > TIER_MAX:
		return "STROBE"
	if r >= TIER_CLEAN:
		return "marginal"
	if r >= TIER_BUTTERY:
		return "step"
	return "clean"


# Speed band by absolute px/frame, matching Roman's readability scale.
static func band(speed: float) -> String:
	var pxf: float = px_per_frame(speed)
	if pxf > MAX_PXF:
		return "OVER"
	if pxf >= 4.0:
		return "fast"
	if pxf >= 2.0:
		return "medium"
	if pxf >= 1.0:
		return "slow"
	return "crawl"
