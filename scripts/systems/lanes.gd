class_name Lanes
extends Object

# Combat playfield vertical-LANE geometry. X-axis only. Pure static math —
# never instantiate. Companion to Playfield (scripts/playfield.gd).
#
# Canonical vocabulary (docs/combat_lane_wave_bridge_2026-06-03.md §0):
#   LANE  = one of the 7 vertical columns in the combat playfield (HERE).
#   ROW   = a combat horizontal latitude (crossers/statics) — not built yet.
#   ROUTE = a sector-map traversal track — map-space, NOT here.
# Never cross map-space and combat-space terms.
#
# Layout fills the 216 px band exactly with uniform 6 px gaps, including the
# two edge gaps:  GAP + COUNT*WIDTH + (COUNT-1)*GAP + GAP
#               = 6 + 7*24 + 6*6 + 6 = 216 = Playfield.W
# Equivalently: COUNT*WIDTH + (COUNT+1)*GAP  (COUNT+1 = 8 gaps total).

const COUNT: int = 7         # number of vertical lanes
const WIDTH: float = 24.0    # px, lane interior width
const GAP: float = 6.0       # px, uniform gap (between lanes AND both edges)
const PITCH: float = WIDTH + GAP  # 30.0 px, lane-center to lane-center step

# First (leftmost) lane center, absolute viewport X.
# Playfield.X_MIN + GAP + WIDTH/2 = 132 + 6 + 12 = 150.0
const FIRST_CENTER: float = Playfield.X_MIN + GAP + WIDTH * 0.5

# Absolute X of lane center i (0 = leftmost, COUNT-1 = rightmost).
# Centers: 150, 180, 210, 240, 270, 300, 330. Lane 3 == Playfield.CENTER.x.
static func lane_center(i: int) -> float:
	return FIRST_CENTER + PITCH * float(i)


# Lane center as a Vector2 at a given Y.
static func lane_center_v(i: int, y: float) -> Vector2:
	return Vector2(lane_center(i), y)


# Nearest lane index to an absolute X (clamped to a valid lane).
static func nearest_lane(x: float) -> int:
	return clampi(int(round((x - FIRST_CENTER) / PITCH)), 0, COUNT - 1)


# Hysteretic nearest-lane: stays in `current` until x clearly crosses into a
# neighbor (deadzone past the half-pitch boundary). Prevents flicker when an
# actor straddles a lane edge. Pass current < 0 for a cold read.
static func nearest_lane_hyst(x: float, current: int, deadzone: float = 4.0) -> int:
	if current < 0 or current >= COUNT:
		return nearest_lane(x)
	if absf(x - lane_center(current)) <= PITCH * 0.5 + deadzone:
		return current
	return nearest_lane(x)


# Mirror a lane index left<->right (lane 0 <-> COUNT-1). Used by the conductor
# to reflect a lane-relative path's anchor.
static func mirror_lane(i: int) -> int:
	return (COUNT - 1) - i


# True if anchor + delta lands on a valid lane — the conductor's legal-placement
# check for a lane-relative path of span `delta`.
static func span_fits(anchor: int, delta: int) -> bool:
	var target: int = anchor + delta
	return target >= 0 and target < COUNT


static func clamp_lane(i: int) -> int:
	return clampi(i, 0, COUNT - 1)


static func lane_left(i: int) -> float:
	return lane_center(i) - WIDTH * 0.5


static func lane_right(i: int) -> float:
	return lane_center(i) + WIDTH * 0.5
