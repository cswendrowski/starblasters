extends Object

# Formation composer (roadmap P2.6 — grammar → authored-schema dicts).
#
# Procedurally GENERATES pattern dicts in the exact AuthoredPatterns.DATA schema, so they flow
# through the EXISTING AuthoredPatterns.build_phrase() → Phrase(shape &"authored") →
# director._dispatch_authored path with ZERO new dispatch code (conductor review §4). This is the
# machine behind the LevelMotif escalation ledger (§5): one signature primitive grown v1→v2→v3
# across a level's three stretches.
#
# A composed pattern is a Dictionary:
#   {name, faction:"any", min_sector, stagger, lockstep, placements:[{lane,row,enemy,movement,size,dir,depth}]}
# with enemy left "" (wildcard) so the roster/faction fill in build_phrase does its job. Rows lead
# from the HIGHEST row (authored convention — build_phrase enters the max-row first); formation_shapes
# leads from row 0, so any cells converted from there are ROW-FLIPPED here (spec §4 gotcha).
#
# The grammar's composition CONSTRAINTS (spec §4 — every authored pattern satisfies them, zero
# violations) are ENFORCED in code: validate() re-checks a composed pattern and compose() only
# returns validating output (retry/fallback to a simpler primitive on failure). This guarantees a
# generated formation is as navigable + readable as a hand-authored one.
#
# All randomness flows through a passed-in RandomNumberGenerator — same seed ⇒ identical dict
# (determinism; a node retry reproduces the level). Preload-referenced, NOT a class_name
# (headless-safe; matches authored_patterns.gd / formation_shapes.gd / factions.gd).

const Lanes = preload("res://scripts/systems/lanes.gd")
const FormationShapesC = preload("res://scripts/levels/formation_shapes.gd")

# 7-lane grid; keep row math local so we never touch the grid width literal.
const N_LANES: int = 7           # == Lanes.COUNT (asserted at compose time)
const PARITY_EVEN: Array = [0, 2, 4, 6]
const PARITY_ODD: Array = [1, 3, 5]

# Grammar primitives (spec §4). String ids so a caller / motif can name one.
const PRIM_LINE: String = "LINE"           # one parity ROW
const PRIM_PICKET: String = "PICKET"        # parity row (== LINE on a chosen parity), the spacing rhythm
const PRIM_FILE: String = "FILE"            # vertical column(s) in alternating lanes
const PRIM_SLASH: String = "SLASH"          # a diagonal, emitted as an L/R MIRROR pair
const PRIM_WEDGE: String = "WEDGE"          # vee/chevron (converted from formation_shapes, row-flipped)
const PRIM_PILLAR: String = "PILLAR"        # edge pincer arm(s) — the lane-0/lane-6 columns
const PRIM_CORRIDOR: String = "CORRIDOR"    # negative-space fill: block all BUT a free lane/corridor
const PRIM_CROSS_PAIR: String = "CROSS_PAIR"  # two point-symmetric mediums (the accent sting shape)
const PRIM_CORE_SCREEN: String = "CORE_SCREEN"  # escort: interior mediums between chaff rows

const PRIMITIVES: Array = [
	PRIM_LINE, PRIM_PICKET, PRIM_FILE, PRIM_SLASH, PRIM_WEDGE,
	PRIM_PILLAR, PRIM_CORRIDOR, PRIM_CROSS_PAIR, PRIM_CORE_SCREEN,
]

# Modifiers (spec §4). Applied on top of a primitive by compose() via a flags dict.
const MOD_MIRROR: String = "MIRROR"
const MOD_ECHO: String = "ECHO"
const MOD_PARITY_OFFSET: String = "PARITY_OFFSET"
const MOD_THICKEN: String = "THICKEN"
const MOD_LEAD: String = "LEAD"
const MOD_DEPTH_BAND: String = "DEPTH_BAND"
const MOD_ZONE_ASSIGN: String = "ZONE_ASSIGN"

# Movement-key speed classes (spec §4 motif 3, derived from the catalog: fast movers appear ≤4/row
# and never full-7; full-7 rows only pair with the slow/holding keys). Keys are the make_movement
# SHAPE keys (enemy_roster.make_movement) plus the legacy speed aliases the authored library still
# uses (straight_charge is a key; straight_crawl aliases to straight but reads "slow").
const FAST_KEYS: Array = [
	"straight_charge", "hunt_beeline", "lane_cut", "lane_weave", "side_turn", "hunt_omni",
]
const SLOW_KEYS: Array = [
	"straight", "straight_crawl", "loiter", "lane_drift", "lane_shift", "lane_hook",
	"drift", "side_traverse",
]

# Lane-PRESERVING movement keys (FIX 3, 2026-07-06): keys whose enemy stays confined to (or holds)
# its authored lane rather than riding across the top band / exiting sideways / free-roam chasing.
# Formation-fill + motif-signature keys are restricted to THIS set so a composed/motif formation
# actually holds the shape it paints — the excluded keys (side_traverse crosser, lane_cut/lane_hook
# exits, hunt_beeline/hunt_omni free-roam, side_turn) abandoned the lane and produced the
# "enemies spawned outside established lanes / flying over each other" overrun. The excluded keys
# stay available everywhere else (accents, wave movement_overrides, authored library patterns that
# deliberately use them). Verified lane-confinement against enemy_roster.make_movement:
#   straight/straight_charge(LaneCharge)/straight_crawl(→straight) — pure descent, hold lane.
#   lane_weave — wobble WITHIN the lane (<half lane width). lane_drift/lane_shift — slide then HOLD.
#   loiter — hover in the fire band. drift — tank hover+jiggle, holds lane.
const LANE_PRESERVING_KEYS: Array = [
	"straight", "straight_charge", "straight_crawl",
	"lane_weave", "lane_drift", "lane_shift", "loiter", "drift",
]


# True if a movement key keeps its enemy in (or holding) its authored lane. Unknown keys are treated
# as lane-preserving? NO — conservative the other way: a lane-abandoning unknown would break the
# formation, so only the explicit whitelist counts. Callers fall back to "straight" on an empty set.
static func is_lane_preserving(key: String) -> bool:
	return LANE_PRESERVING_KEYS.has(key)

# ZONE_ASSIGN column groups (left / centre / right thirds) — one movement key per zone (spec §4
# "one movement key per column-zone"). Lanes 0-1 | 2-4 | 5-6.
const ZONE_LEFT: Array = [0, 1]
const ZONE_MID: Array = [2, 3, 4]
const ZONE_RIGHT: Array = [5, 6]

const DEPTHS_HIGH_MID_LOW: Array = ["high", "mid", "low"]


# True if a movement key is a FAST mover (≤4/row, never full-7). Unknown keys treated as slow
# (conservative — a full row of an unknown key is safe; a fast row of a truly-fast unknown is not).
static func is_fast_key(key: String) -> bool:
	return FAST_KEYS.has(key)


# ---------------------------------------------------------------------------------------------
# compose() — the public entry. Build a validated pattern dict for `primitive` at `tier` density,
# honoring `movement` and the `flags` modifier set, seeded by `rng`, sized ≤ `budget` members.
# Returns a pattern dict that PASSES validate(); on failure it falls back to the simplest safe
# primitive (a single PICKET row) so a caller always gets a usable formation. `flags` keys are the
# MOD_* strings mapping to true.
# ---------------------------------------------------------------------------------------------
static func compose(primitive: String, movement: String, tier: int, budget: int, flags: Dictionary, rng: RandomNumberGenerator, name_hint: String = "") -> Dictionary:
	var mv: String = movement if movement != "" else "straight"
	var pat: Dictionary = _compose_raw(primitive, mv, tier, budget, flags, rng)
	pat["name"] = name_hint if name_hint != "" else ("composed_%s_t%d" % [primitive.to_lower(), tier])
	pat["faction"] = "any"
	pat["min_sector"] = 0
	pat["stagger"] = 0.18
	# Trim to budget defensively (validate also checks) — drop trailing (top-most) rows first so the
	# LEAD/low rows survive.
	_trim_to_budget(pat, budget)
	if validate(pat):
		return pat
	# Fallback: the simplest safe primitive — a single parity PICKET on the movement key, sized to fit.
	var fb: Dictionary = _prim_picket(mv, 1, PARITY_EVEN, rng)
	fb["name"] = pat.get("name", "composed_fallback")
	fb["faction"] = "any"
	fb["min_sector"] = 0
	fb["stagger"] = 0.18
	fb["lockstep"] = false
	_trim_to_budget(fb, budget)
	return fb


# Raw primitive+modifier build (pre-metadata, pre-validate). Split out so compose() owns the
# schema wrapper + validation retry.
static func _compose_raw(primitive: String, mv: String, tier: int, budget: int, flags: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var fast: bool = is_fast_key(mv)
	# Rows to build scales with tier (v1 bare / v2 grown / v3 full). Fast keys never fill full-7 rows
	# and cap at 4/row, so a fast primitive stays shallow; slow keys may stack deeper.
	var rows: int = clampi(1 + tier, 1, 3)
	var pat: Dictionary = {}
	match primitive:
		PRIM_LINE, PRIM_PICKET:
			var parity: Array = PARITY_EVEN if rng.randf() < 0.5 else PARITY_ODD
			pat = _prim_picket(mv, rows, parity, rng)
		PRIM_FILE:
			pat = _prim_file(mv, rows, rng)
		PRIM_SLASH:
			pat = _prim_slash(mv, rng)   # always a mirrored L/R pair
		PRIM_WEDGE:
			pat = _prim_wedge(mv, tier, rng)
		PRIM_PILLAR:
			pat = _prim_pillar(mv, rows, rng)
		PRIM_CORRIDOR:
			pat = _prim_corridor(mv, rows, rng)
		PRIM_CROSS_PAIR:
			pat = _prim_cross_pair(mv, rng)
		PRIM_CORE_SCREEN:
			pat = _prim_core_screen(mv, rng)
		_:
			pat = _prim_picket(mv, rows, PARITY_EVEN, rng)

	# --- modifiers ---------------------------------------------------------------------------
	if bool(flags.get(MOD_MIRROR, false)):
		_apply_mirror(pat)
	if bool(flags.get(MOD_PARITY_OFFSET, false)):
		_apply_parity_offset(pat)
	if bool(flags.get(MOD_THICKEN, false)) and not fast:
		# THICKEN fills the complementary parity on existing rows — SLOW keys only (a full row is
		# slow-only per the density constraint; thickening a fast row would exceed 4/row).
		_apply_thicken(pat)
	if bool(flags.get(MOD_ZONE_ASSIGN, false)):
		_apply_zone_assign(pat, mv, rng)
	if bool(flags.get(MOD_DEPTH_BAND, false)):
		_apply_depth_band(pat)
	if bool(flags.get(MOD_ECHO, false)):
		_apply_echo(pat)
	if bool(flags.get(MOD_LEAD, false)):
		_apply_lead(pat)
		pat["lockstep"] = true

	# Mixed sizes/speeds ⇒ lockstep (spec §4). Detect after all modifiers.
	if _is_mixed(pat):
		pat["lockstep"] = true
	elif not pat.has("lockstep"):
		pat["lockstep"] = false
	return pat


# ---------------------------------------------------------------------------------------------
# Primitives — each returns {placements:[...]} (rows lead from HIGHEST row already). lockstep left
# for compose() to decide from mixing. A placement is {lane,row,enemy:"",movement,size,dir,depth}.
# ---------------------------------------------------------------------------------------------

# PICKET / LINE — `rows` parity rows, each on `parity` lanes, separated by ≥1 empty row (rows spaced
# by 2) so a full/dense row keeps a clear row between it and the next (navigability cadence).
static func _prim_picket(mv: String, rows: int, parity: Array, rng: RandomNumberGenerator) -> Dictionary:
	var lanes: Array = parity.duplicate()
	# Fast keys cap at 4/row (the parity sets are already ≤4, so this is a no-op for ODD=3 / EVEN=4).
	if is_fast_key(mv) and lanes.size() > 4:
		lanes = lanes.slice(0, 4)
	var placements: Array = []
	for r in rows:
		var row: int = r * 2   # ≥1 empty row between picket rows
		for ln in lanes:
			placements.append(_cell(int(ln), row, mv, "small"))
	return {"placements": placements}


# FILE — vertical columns on alternating lanes (0/2/4/6), filled row-by-row. Open lanes (1/3/5) stay
# clear as descending gaps. A holding/slow shape; caps depth at `rows`+2.
static func _prim_file(mv: String, rows: int, _rng: RandomNumberGenerator) -> Dictionary:
	var depth: int = clampi(rows + 1, 2, 4)
	var placements: Array = []
	for ln in PARITY_EVEN:
		for r in depth:
			placements.append(_cell(int(ln), r, mv, "small"))
	return {"placements": placements}


# SLASH — a single diagonal stair, emitted as a MIRRORED L/R pair (spec: slashes come in L/R pairs).
# Left slash climbs lanes 0..3 up rows; the mirror climbs 6..3. Point-of-convergence at centre.
static func _prim_slash(mv: String, _rng: RandomNumberGenerator) -> Dictionary:
	var placements: Array = []
	# Left arm: lane == row for rows 0..3.
	for r in 4:
		placements.append(_cell(r, r, mv, "small"))
	# Right arm (mirror about lane 3): lane == 6-row.
	for r in 4:
		var ln: int = 6 - r
		if ln != r:   # avoid double-placing the shared centre cell (r==3 → lane 3)
			placements.append(_cell(ln, r, mv, "small"))
	return {"placements": placements}


# WEDGE — a vee or chevron converted from formation_shapes (row 0 leads THERE), ROW-FLIPPED to the
# authored convention (highest row leads). Tier scales the member count.
static func _prim_wedge(mv: String, tier: int, rng: RandomNumberGenerator) -> Dictionary:
	var shape: StringName = &"vee" if rng.randf() < 0.5 else &"chevron"
	var count: int = clampi(5 + tier * 2, 5, 9)
	var cells: Array = FormationShapesC.placements(shape, count)   # Vector2i(lane,row), row0 leads
	var max_r: int = 0
	for c in cells:
		max_r = maxi(max_r, int(c.y))
	var placements: Array = []
	for c in cells:
		var flipped_row: int = max_r - int(c.y)   # flip: formation_shapes row0 → authored max_row
		placements.append(_cell(int(c.x), flipped_row, mv, "small"))
	return {"placements": placements}


# PILLAR — the pincer arm: solid edge columns (lanes 0 and 6) descending `rows`+1 deep, leaving the
# whole interior (lanes 1-5) as a navigable channel. Slow/holding shape.
static func _prim_pillar(mv: String, rows: int, _rng: RandomNumberGenerator) -> Dictionary:
	var depth: int = clampi(rows + 1, 2, 4)
	var placements: Array = []
	for ln in [0, 6]:
		for r in depth:
			placements.append(_cell(int(ln), r, mv, "small"))
	return {"placements": placements}


# CORRIDOR — negative-space fill: on each row, block every lane EXCEPT a 1-3-lane free corridor, and
# STAGGER the corridor across rows so no lane is sealed on two consecutive rows (navigability by
# construction). Slow keys only in practice (a full-ish row), so the caller pairs it with a slow key.
static func _prim_corridor(mv: String, rows: int, rng: RandomNumberGenerator) -> Dictionary:
	var n_rows: int = clampi(rows + 1, 2, 3)
	# Corridor width 2 (adjacent free lanes). Start position walks so each row's free lanes differ.
	var free_start: int = rng.randi() % (N_LANES - 1)
	var placements: Array = []
	for r in n_rows:
		var f0: int = (free_start + r) % (N_LANES - 1)   # walk the corridor each row
		var f1: int = f0 + 1
		for ln in N_LANES:
			if ln == f0 or ln == f1:
				continue
			placements.append(_cell(ln, r, mv, "small"))
	return {"placements": placements}


# CROSS_PAIR — two point-symmetric mediums crossing (the accent-sting shape, e.g. shift_cross_pair).
# Opposite corners, opposite dirs; mixed with mediums so compose() will lockstep it.
static func _prim_cross_pair(mv: String, _rng: RandomNumberGenerator) -> Dictionary:
	var placements: Array = [
		_cell_full(1, 1, mv, "medium", "right", ""),
		_cell_full(5, 0, mv, "medium", "left", ""),
	]
	return {"placements": placements}


# CORE_SCREEN — escort: interior MEDIUMS nested between chaff SMALL rows. Converted from
# formation_shapes.escort (row0 leads there), ROW-FLIPPED. Mixed-size ⇒ lockstep (compose sets it).
# The core rides the given movement; the screen holds a straight descent so it shields the core.
static func _prim_core_screen(mv: String, rng: RandomNumberGenerator) -> Dictionary:
	var layout: Dictionary = FormationShapesC.escort(1 + (rng.randi() % 2))
	var core_cells: Array = layout["core"]
	var screen_cells: Array = layout["screen"]
	var max_r: int = 0
	for c in core_cells + screen_cells:
		max_r = maxi(max_r, int(c.y))
	var placements: Array = []
	for c in screen_cells:
		placements.append(_cell(int(c.x), max_r - int(c.y), "straight", "small"))
	for c in core_cells:
		placements.append(_cell(int(c.x), max_r - int(c.y), mv, "medium"))
	return {"placements": placements}


# ---------------------------------------------------------------------------------------------
# Modifiers -------------------------------------------------------------------------------------
# ---------------------------------------------------------------------------------------------

# MIRROR — reflect every placement about lane 3 and MERGE (dedupe) so a one-sided shape becomes a
# symmetric 6-lane one. Skips cells whose mirror already exists.
static func _apply_mirror(pat: Dictionary) -> void:
	var placements: Array = pat["placements"]
	var occupied: Dictionary = _occupancy(placements)
	var added: Array = []
	for pl in placements:
		var ml: int = 6 - int(pl["lane"])
		var key: String = "%d,%d" % [ml, int(pl["row"])]
		if occupied.has(key):
			continue
		occupied[key] = true
		var m: Dictionary = pl.duplicate()
		m["lane"] = ml
		# Mirror a lateral dir too.
		if String(m.get("dir", "")) == "left":
			m["dir"] = "right"
		elif String(m.get("dir", "")) == "right":
			m["dir"] = "left"
		added.append(m)
	placements.append_array(added)


# PARITY_OFFSET — checkerboard: on odd rows, shift the parity lanes by +1 so the blocked lanes
# alternate row-to-row (no lane sealed on consecutive rows). Applied to existing placements.
static func _apply_parity_offset(pat: Dictionary) -> void:
	for pl in pat["placements"]:
		if int(pl["row"]) % 2 == 1:
			var ln: int = int(pl["lane"]) + 1
			if ln > 6:
				ln -= 2
			pl["lane"] = ln


# THICKEN — add the complementary-parity lanes on each existing row (slow-only; enforced by caller).
static func _apply_thicken(pat: Dictionary) -> void:
	var placements: Array = pat["placements"]
	var occupied: Dictionary = _occupancy(placements)
	# Rows present, and each row's movement/size (take the first cell's).
	var rows_seen: Dictionary = {}
	for pl in placements:
		rows_seen[int(pl["row"])] = pl
	var added: Array = []
	for row in rows_seen.keys():
		var proto: Dictionary = rows_seen[row]
		for ln in N_LANES:
			var key: String = "%d,%d" % [ln, row]
			if occupied.has(key):
				continue
			# Only fill so the row stays parity-spaced-ish: fill every other empty lane.
			if ln % 2 != (int(row) % 2):
				continue
			occupied[key] = true
			added.append(_cell(ln, int(row), String(proto["movement"]), String(proto.get("size", "small"))))
	placements.append_array(added)


# ECHO — repeat the whole shape two rows higher (a trailing copy). Shifts a duplicate up by
# (max_row + 2) so it enters after the lead copy holding the same shape.
static func _apply_echo(pat: Dictionary) -> void:
	var placements: Array = pat["placements"]
	var max_row: int = 0
	for pl in placements:
		max_row = maxi(max_row, int(pl["row"]))
	var offset: int = max_row + 2
	var echo: Array = []
	for pl in placements:
		var e: Dictionary = pl.duplicate()
		e["row"] = int(pl["row"]) + offset
		echo.append(e)
	placements.append_array(echo)


# LEAD — promote the (lane 3, max_row) cell to a MEDIUM (leader tip). If no centre-lead cell exists,
# add one. Mixed size ⇒ lockstep (compose sets it). The leader keeps the shape's movement key.
static func _apply_lead(pat: Dictionary) -> void:
	var placements: Array = pat["placements"]
	var max_row: int = 0
	for pl in placements:
		max_row = maxi(max_row, int(pl["row"]))
	# Find (3, max_row).
	for pl in placements:
		if int(pl["lane"]) == 3 and int(pl["row"]) == max_row:
			pl["size"] = "medium"
			return
	# None there — promote the lowest centre-ish cell, or append a leader.
	var best: Dictionary = {}
	var best_row: int = -1
	for pl in placements:
		if int(pl["lane"]) in [2, 3, 4] and int(pl["row"]) > best_row:
			best_row = int(pl["row"]); best = pl
	if not best.is_empty():
		best["size"] = "medium"
	else:
		placements.append(_cell(3, max_row, String(placements[0]["movement"]) if not placements.is_empty() else "straight", "medium"))


# ZONE_ASSIGN — assign one movement key per column-zone (left/mid/right thirds). The MID zone keeps
# the base movement; the flanks get a paired key (a lateral for a straight base, straight for a
# lateral base) so no zone is per-unit random. Seeded pick.
static func _apply_zone_assign(pat: Dictionary, base_mv: String, rng: RandomNumberGenerator) -> void:
	var flank_key: String = _pair_key_for(base_mv, rng)
	for pl in pat["placements"]:
		var ln: int = int(pl["lane"])
		if ZONE_LEFT.has(ln) or ZONE_RIGHT.has(ln):
			pl["movement"] = flank_key
		# MID keeps base_mv (already set).


# DEPTH_BAND — map rows monotonically to depth bands high→mid→low, LEAD rows (lowest = highest row
# number, enters first) get the LOW band. Uses each row's ordinal among the sorted distinct rows.
static func _apply_depth_band(pat: Dictionary) -> void:
	var placements: Array = pat["placements"]
	var rows: Array = []
	for pl in placements:
		if not rows.has(int(pl["row"])):
			rows.append(int(pl["row"]))
	rows.sort()   # ascending: lower row number = trails higher on screen
	# Highest row (leads / enters first) → LOW; lowest row (trails) → HIGH.
	var n: int = rows.size()
	var row_depth: Dictionary = {}
	for i in n:
		var row: int = int(rows[i])
		# i=0 is the smallest row (trails) → high; last (leads) → low.
		var band_idx: int = 0
		if n > 1:
			band_idx = int(round(float(i) / float(n - 1) * 2.0))   # 0,1,2 across the rows
		row_depth[row] = DEPTHS_HIGH_MID_LOW[clampi(band_idx, 0, 2)]
	for pl in placements:
		pl["depth"] = row_depth[int(pl["row"])]


# ---------------------------------------------------------------------------------------------
# validate() — assert the composition constraints (spec §4). compose() only returns validating
# output. Constraints: fast keys ≤4/row and never full-7; full-7 rows slow-only with a clear row
# between; global navigability (no lane sealed on 2 consecutive rows unless a free lane exists);
# one movement key per column-zone; member count small/positive. Returns true if the pattern is
# navigable + readable.
# ---------------------------------------------------------------------------------------------
static func validate(pattern: Dictionary) -> bool:
	var placements: Array = pattern.get("placements", [])
	if placements.is_empty():
		return false
	# Group by row.
	var by_row: Dictionary = {}
	for pl in placements:
		var ln: int = int(pl["lane"])
		if ln < 0 or ln >= N_LANES:
			return false   # off-grid
		var row: int = int(pl["row"])
		if not by_row.has(row):
			by_row[row] = []
		by_row[row].append(pl)

	# Per-row: fast keys ≤4/row and never full-7; full-7 only for slow keys.
	for row in by_row.keys():
		var cells: Array = by_row[row]
		# Duplicate lane on the same row = illegal overlap.
		var lanes_here: Dictionary = {}
		for pl in cells:
			var ln: int = int(pl["lane"])
			if lanes_here.has(ln):
				return false
			lanes_here[ln] = true
		var count: int = cells.size()
		var any_fast: bool = false
		for pl in cells:
			if is_fast_key(String(pl.get("movement", ""))):
				any_fast = true
				break
		if any_fast and count > 4:
			return false            # fast keys ≤4/row
		if count >= N_LANES and any_fast:
			return false            # fast never full-7
		# A full-7 row must be slow AND have a clear row above+below (checked in navigability below).

	# Full-7 rows: require ≥1 empty row between them (a full row must not touch another full row).
	var rows_sorted: Array = by_row.keys()
	rows_sorted.sort()
	for i in range(rows_sorted.size() - 1):
		var r0: int = int(rows_sorted[i])
		var r1: int = int(rows_sorted[i + 1])
		if by_row[r0].size() >= N_LANES and by_row[r1].size() >= N_LANES and (r1 - r0) <= 1:
			return false

	# Global navigability: no lane may be BLOCKED on two consecutive rows unless SOME lane is free on
	# both — i.e. there must always be a passable channel. We require: for every consecutive row pair,
	# the UNION of blocked lanes must leave ≥1 lane free (a lane free on both rows), OR the two rows'
	# free sets share an adjacent-lane corridor. Simplest sufficient check: the intersection of FREE
	# lanes across each consecutive pair is non-empty (a lane free on both) OR checkerboard parity.
	for i in range(rows_sorted.size() - 1):
		var free_a: Dictionary = _free_lanes(by_row[int(rows_sorted[i])])
		var free_b: Dictionary = _free_lanes(by_row[int(rows_sorted[i + 1])])
		# Only enforce on truly ADJACENT rows (a gap row between them is already free).
		if int(rows_sorted[i + 1]) - int(rows_sorted[i]) > 1:
			continue
		var shared: bool = false
		for ln in free_a.keys():
			if free_b.has(ln):
				shared = true
				break
		if not shared:
			# No lane free on both — a wall. Allowed ONLY if each row individually still leaves a free
			# lane (checkerboard parity: player crosses laterally between rows). Require both rows to
			# have ≥2 free lanes so a lateral dodge exists.
			if free_a.size() < 2 or free_b.size() < 2:
				return false

	# One movement key per column-zone (no per-unit random within a zone).
	if not _zones_consistent(placements):
		return false
	return true


# Free (unoccupied) lanes on a row, as a lane→true set.
static func _free_lanes(cells: Array) -> Dictionary:
	var occ: Dictionary = {}
	for pl in cells:
		occ[int(pl["lane"])] = true
	var free: Dictionary = {}
	for ln in N_LANES:
		if not occ.has(ln):
			free[ln] = true
	return free


# True if each column-zone (left/mid/right) uses at most ONE movement key across all its cells.
static func _zones_consistent(placements: Array) -> bool:
	var zone_keys: Dictionary = {"L": "", "M": "", "R": ""}
	for pl in placements:
		var ln: int = int(pl["lane"])
		var z: String = "M"
		if ZONE_LEFT.has(ln):
			z = "L"
		elif ZONE_RIGHT.has(ln):
			z = "R"
		var mv: String = String(pl.get("movement", ""))
		if zone_keys[z] == "":
			zone_keys[z] = mv
		elif zone_keys[z] != mv:
			return false
	return true


# ---------------------------------------------------------------------------------------------
# helpers ---------------------------------------------------------------------------------------
# ---------------------------------------------------------------------------------------------

static func _cell(lane: int, row: int, mv: String, size: String) -> Dictionary:
	return {"lane": lane, "row": row, "enemy": "", "movement": mv, "size": size}


static func _cell_full(lane: int, row: int, mv: String, size: String, dir: String, depth: String) -> Dictionary:
	return {"lane": lane, "row": row, "enemy": "", "movement": mv, "size": size, "dir": dir, "depth": depth}


static func _occupancy(placements: Array) -> Dictionary:
	var occ: Dictionary = {}
	for pl in placements:
		occ["%d,%d" % [int(pl["lane"]), int(pl["row"])]] = true
	return occ


# True if the pattern mixes SIZES or SPEED-CLASSES (mixed ⇒ lockstep).
static func _is_mixed(pat: Dictionary) -> bool:
	var placements: Array = pat.get("placements", [])
	if placements.is_empty():
		return false
	var size0: String = String(placements[0].get("size", "small"))
	var fast0: bool = is_fast_key(String(placements[0].get("movement", "")))
	for pl in placements:
		if String(pl.get("size", "small")) != size0:
			return true
		if is_fast_key(String(pl.get("movement", ""))) != fast0:
			return true
	return false


# A paired flank key for ZONE_ASSIGN: a straight base gets a lateral flank, a lateral base gets a
# straight flank, so the flanks read as a distinct-but-compatible zone. Seeded.
static func _pair_key_for(base_mv: String, rng: RandomNumberGenerator) -> String:
	var laterals: Array = ["lane_drift", "lane_shift"]
	if base_mv in laterals or base_mv == "lane_weave" or base_mv == "lane_cut":
		return "straight"
	return laterals[rng.randi() % laterals.size()]


# Trim a pattern to ≤ `budget` members by dropping the TOP-most rows (highest row numbers) first,
# so the leading (low) rows + any LEAD cell survive.
static func _trim_to_budget(pat: Dictionary, budget: int) -> void:
	var placements: Array = pat.get("placements", [])
	if placements.size() <= budget or budget <= 0:
		return
	# Sort by row DESC (top-most first), drop until within budget.
	placements.sort_custom(func(a, b): return int(a["row"]) > int(b["row"]))
	while placements.size() > budget:
		placements.pop_front()
	pat["placements"] = placements
