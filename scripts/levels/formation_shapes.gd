extends Object

# Parametric formation-shape geometry (wave-conductor readability pass, 2026-06-23).
#
# Pure static math: given a SHAPE id + a target member count, returns an ordered Array of
# Vector2i(lane, row) placements on the 7-lane grid. The director explodes a homogeneous
# count-N wave spec across these cells and bursts them in PRE-STACKED ROWS so the burst
# descends holding its shape (director._dispatch_geometric) — exactly how the hand-authored
# wave-pattern editor lays out formations (authored_patterns.gd), but rolled by the generator
# at any wave size.
#
# These mirror the geometric archetypes the authored library revealed (spearhead / chevron /
# echelon / columns / diamond) — the insight being that what makes a burst read as a FORMATION
# is (a) members entering together, not trickling, and (b) a recognizable shape. The generator's
# old random spread produced neither. WALL / PINCER / STEP_WALL already had bespoke director
# dispatch; this fills in the missing "held shape" vocabulary.
#
# Convention (matches authored_patterns + director pre-stack):
#   lane  0..COUNT-1, left->right (clamped).
#   row   0 = the LEADING latitude (enters first, lowest pre-stack); higher rows TRAIL above.
# Cells are returned LEADING-ROW-FIRST so taking the first N of a larger template still reads
# as a partial of the same shape.
#
# Preload-referenced, NOT a class_name (headless-safe; matches authored_patterns.gd / factions.gd).

const Lanes = preload("res://scripts/systems/lanes.gd")

# Shapes this library can build. The generator rolls from here; the director routes a wave's
# shape_override StringName through placements(). Keep in sync with director.GEOMETRIC_SHAPES.
const SHAPES: Array[StringName] = [&"vee", &"chevron", &"diamond", &"echelon", &"columns"]


# True if `shape` is one this library builds (cheap guard for the director / generator).
static func is_geometric(shape: StringName) -> bool:
	return SHAPES.has(shape)


# Build `count` lane/row placements for `shape`. Returns [] for an unknown shape or count <= 0
# (caller falls back to its normal placement). Lanes are clamped to the grid; rows start at 0.
static func placements(shape: StringName, count: int) -> Array:
	if count <= 0:
		return []
	match shape:
		&"vee":      return _tile(_VEE_UNIT, _VEE_H, count)
		&"chevron":  return _tile(_CHEVRON_UNIT, _CHEVRON_H, count)
		&"diamond":  return _tile(_DIAMOND_UNIT, _DIAMOND_H, count)
		&"echelon":  return _tile(_ECHELON_UNIT, _ECHELON_H, count)
		&"columns":  return _columns(count)
		_:           return []


# --- Shape units -------------------------------------------------------------------------------
# Each unit is one copy of the shape on the 7-lane grid, cells ordered LEADING-ROW-FIRST. _tile()
# stacks copies upward (row += unit_height per band) until `count` cells exist, then truncates —
# so a count larger than one unit reads as a flight of the shape, and a smaller count as a partial.

# VEE — wings lead at the edges, converging to a single point that TRAILS at center (a "˅" whose
# point aims up-screen / away from the player; the classic descending flock).
const _VEE_UNIT: Array = [
	Vector2i(0, 0), Vector2i(6, 0),
	Vector2i(1, 1), Vector2i(5, 1),
	Vector2i(2, 2), Vector2i(4, 2),
	Vector2i(3, 3),
]
const _VEE_H: int = 4

# CHEVRON — the inverse: a single point LEADS at center (aimed at the player), wings fan out and
# TRAIL. Reads as a spearhead driving downward.
const _CHEVRON_UNIT: Array = [
	Vector2i(3, 0),
	Vector2i(2, 1), Vector2i(4, 1),
	Vector2i(1, 2), Vector2i(5, 2),
	Vector2i(0, 3), Vector2i(6, 3),
]
const _CHEVRON_H: int = 4

# DIAMOND — a compact rhombus: tip leads, widens to a 3-wide waist, narrows back to a tail. A
# tight cluster the player must arc around rather than a screen-wide wall.
const _DIAMOND_UNIT: Array = [
	Vector2i(3, 0),
	Vector2i(2, 1), Vector2i(4, 1),
	Vector2i(1, 2), Vector2i(3, 2), Vector2i(5, 2),
	Vector2i(2, 3), Vector2i(4, 3),
	Vector2i(3, 4),
]
const _DIAMOND_H: int = 5

# ECHELON — two parallel diagonal slashes (a staggered "////" stair). Reads as raked lines sweeping
# across the lanes; pairs naturally with a side-leaning movement.
const _ECHELON_UNIT: Array = [
	Vector2i(0, 0), Vector2i(4, 0),
	Vector2i(1, 1), Vector2i(5, 1),
	Vector2i(2, 2), Vector2i(6, 2),
	Vector2i(3, 3),
]
const _ECHELON_H: int = 4


# COLUMNS — vertical files in alternating lanes (0,2,4,6), filled row-by-row so the open lanes
# (1,3,5) stay clear as descending gaps to weave through. Width-first (unlike the height-first
# units above): it grows DEEPER, not taller-per-member, so a big count stays readable.
const _COLUMN_LANES: Array = [0, 2, 4, 6]

static func _columns(count: int) -> Array:
	var out: Array = []
	var row: int = 0
	while out.size() < count:
		for ln in _COLUMN_LANES:
			out.append(Vector2i(ln, row))
			if out.size() >= count:
				break
		row += 1
		if row > 16:   # safety against a pathological count
			break
	return out


# Stack copies of `unit` upward until at least `count` cells, then truncate to exactly `count`.
# Lanes are clamped defensively so a malformed unit can never spawn off-grid.
static func _tile(unit: Array, unit_height: int, count: int) -> Array:
	var out: Array = []
	var band: int = 0
	while out.size() < count:
		for c in unit:
			out.append(Vector2i(clampi(int(c.x), 0, Lanes.COUNT - 1), int(c.y) + band * unit_height))
			if out.size() >= count:
				break
		band += 1
		if band > 16:   # safety: never loop unbounded on a bad unit
			break
	return out
