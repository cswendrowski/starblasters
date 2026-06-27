extends Object

# Parametric NAVIGABLE hazard-field structures (hazard readability pass, 2026-06-23).
#
# Learned from Roman's authored asteroid/mine layouts (asteroid_channel, mine_narrow_lane,
# mine_lane_wide, asteroid_sides/center…): a hazard field should always present a GUARANTEED clear
# PATH — a channel/lane — not a random scatter that can happen to wall off every lane. Given a SAFE
# lane window, these return the (lane, row) cells to FILL with hazards; the complementary lanes stay
# open by construction. The flowing variant migrates the gap row-to-row so the corridor SNAKES as it
# descends and the player must keep re-positioning (the lateral-flow lesson).
#
# Pure static math (mirrors formation_shapes.gd). The caller pins one count-1 hazard spec per cell,
# pre-stacks the rows, and dispatches on the &"authored" burst path (levels_v2._channel_phrase).
# Preload-referenced, NOT a class_name (headless-safe).

const Lanes = preload("res://scripts/systems/lanes.gd")


# Fill every lane OUTSIDE the safe window [safe_lo, safe_hi] (inclusive) for `rows` rows — a STABLE
# corridor the player can commit to. safe_lo/hi clamp to the grid. Returns Vector2i(lane, row);
# row 0 leads (enters first).
static func channel_cells(safe_lo: int, safe_hi: int, rows: int) -> Array:
	safe_lo = clampi(safe_lo, 0, Lanes.COUNT - 1)
	safe_hi = clampi(safe_hi, 0, Lanes.COUNT - 1)
	var out: Array = []
	for r in maxi(rows, 0):
		for lane in Lanes.COUNT:
			if lane < safe_lo or lane > safe_hi:
				out.append(Vector2i(lane, r))
	return out


# A corridor whose gap MIGRATES one lane per row (±1, seeded), so as the field descends the safe path
# snakes left/right. `gap_width` is the half-extent each side of the centre (0 = single lane, 1 = three
# lanes…). The gap centre stays in [1, COUNT-2] so a usable gap never pins hard against an edge.
static func flowing_channel_cells(rows: int, gap_width: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var c: int = 1 + (rng.randi() % maxi(Lanes.COUNT - 2, 1))   # gap centre
	for r in maxi(rows, 0):
		var lo: int = clampi(c - gap_width, 0, Lanes.COUNT - 1)
		var hi: int = clampi(c + gap_width, 0, Lanes.COUNT - 1)
		for lane in Lanes.COUNT:
			if lane < lo or lane > hi:
				out.append(Vector2i(lane, r))
		# Migrate the gap for the next (higher) row so the corridor snakes as it falls.
		c = clampi(c + (rng.randi() % 3 - 1), 1, Lanes.COUNT - 2)
	return out
