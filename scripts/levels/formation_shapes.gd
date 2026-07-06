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
const Roster = preload("res://scripts/levels/enemy_roster.gd")

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


# ESCORT — a heavy CORE screened by a chaff formation (the audit's mixed-size escort, e.g. the
# authored straight_escort_wall). Returns two cell lists: `core` (the heavy/heavies) and `screen`
# (the chaff shield). The forward screen (row 0) leads — it faces the player, who attacks from below
# — and a rear guard trails, with the core nested at the centre. Unlike the homogeneous shapes above
# this is type-mixed, so the caller fills the two lists from different roster entries and the whole
# burst is lockstep-clamped to the slow core (wave_generator._build_escort_phrase). `core_count`
# 1..3 sets how many heavies sit at the centre.
static func escort(core_count: int) -> Dictionary:
	core_count = clampi(core_count, 1, 3)
	var core: Array
	match core_count:
		1: core = [Vector2i(3, 2)]
		2: core = [Vector2i(2, 2), Vector2i(4, 2)]
		_: core = [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)]
	var screen: Array = [
		Vector2i(1, 0), Vector2i(3, 0), Vector2i(5, 0),                   # forward shield (leads, faces player)
		Vector2i(0, 1), Vector2i(2, 1), Vector2i(4, 1), Vector2i(6, 1),   # mid screen
		Vector2i(1, 3), Vector2i(3, 3), Vector2i(5, 3),                   # rear guard (trails)
	]
	return {"core": core, "screen": screen}


# --- Shared formation utilities (dedup, conductor review §3, 2026-07-02) -----------------------
# Row pre-stack + speed-lockstep + seeded shuffle were copy-pasted across director / wave_generator
# / authored_patterns / levels_v2 (four ROW_GAP constants of one value, two verbatim lockstep clamps,
# two Fisher-Yates). Consolidated here (the pure-static formation-utility hub every formation site
# already imports) so a new value/behavior lands in ONE place.

# Vertical pre-stack: rows lead from the BOTTOM (row == max_row enters at the top edge, SPAWN_Y_TOP);
# each row up trails ROW_GAP px higher, so a painted formation descends holding its shape. This was
# four separate constants (authored_patterns.ROW_GAP_PX, director.GEOMETRIC_ROW_GAP,
# wave_generator.ESCORT_ROW_GAP, levels_v2.HAZ_ROW_GAP) — all 40.0.
const SPAWN_Y_TOP: float = -12.0
const ROW_GAP: float = 40.0


# Pre-stacked spawn_y for a placement's `row` within a formation whose deepest (leading) row is
# `max_row`. row == max_row → SPAWN_Y_TOP (enters at the edge); each row above adds ROW_GAP.
# CONVENTION: MAX_ROW LEADS. This is the AUTHORED-pattern convention (authored_patterns.build_phrase
# flips its editor rows so the bottom-painted row == max_row leads). Callers whose cells use the
# ROW-0-LEADS convention (formation_shapes shape cells, escort(), hazard_shapes channel cells — all
# documented "row 0 leads") must use leads_from_zero() instead, or they render vertically INVERTED.
static func prestack_y(row: int, max_row: int) -> float:
	return SPAWN_Y_TOP - float(max_row - row) * ROW_GAP


# Pre-stacked spawn_y for cells using the ROW-0-LEADS convention (formation_shapes shape cells,
# escort(), hazard_shapes) — row 0 enters at the top edge, each higher row trails one ROW_GAP up.
# Equivalent to prestack_y(max_row - row, max_row); named so the row-0-leads call sites read
# correctly instead of feeding the raw row into the max_row-leads prestack_y (which inverts them).
static func leads_from_zero(row: int, max_row: int) -> float:
	return SPAWN_Y_TOP - float(row) * ROW_GAP


# Lockstep speed: clamp every speed-bearing spec to the SLOWEST member's move_speed so a mixed-speed
# formation advances in unison instead of spreading as fast units outrun slow ones. Specs with no
# resolved speed (move_speed <= 0 — non-roster scenes that keep scene-baked motion) are left untouched
# and don't drag the minimum to zero. (Was authored_patterns._lock_to_slowest ≡ wave_generator.
# _lock_specs_to_slowest, verbatim.)
static func lock_to_slowest(specs: Array) -> void:
	var slowest: float = INF
	for ws in specs:
		if ws.move_speed > 0.0:
			slowest = minf(slowest, ws.move_speed)
	if slowest == INF:
		return   # nothing had a resolved speed
	for ws in specs:
		if ws.move_speed > 0.0:
			ws.move_speed = slowest


# Seeded Fisher-Yates shuffle in place (uses the caller's rng so a shuffle reproduces per run+node).
# Was director._rng_shuffle (instance, on `_rng`) ≡ wave_generator._shuffle (static, rng param).
static func fisher_yates(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var t = arr[i]; arr[i] = arr[j]; arr[j] = t


# Stamp the SHARED roster-behavior block onto a count-1 WaveSpec `ws` from roster `entry` — the
# verbatim-identical portion that wave_generator._make_wave_spec and authored_patterns._spec_for_placement
# both apply so a placed enemy behaves like a normal spawn: shoot pattern, components(+emitters), fire
# interval overrides, composed stats (health/bounty/shield/recycle), and chassis locomotion. Callers
# apply their DIVERGENT extras separately (wave_generator: mounts + chaff-recycle override; authored:
# per-placement depth-band override) — those are intentionally NOT here (dedup, conductor review §3).
# `entry` must be non-empty; caller guards for the non-roster (raw-scene) case where none of this applies.
static func stamp_roster_behavior(ws, entry: Dictionary) -> void:
	var sp = Roster.make_shoot(entry)
	if sp != null:
		ws.shoot_pattern_override = sp
	ws.components_override = Roster.make_components(entry) + Roster.make_emitters(entry)
	if entry.has("fire_min"):
		ws.fire_interval_min = float(entry["fire_min"])
	if entry.has("fire_max"):
		ws.fire_interval_max = float(entry["fire_max"])
	var stats: Dictionary = Roster.compose_stats(entry)
	ws.max_health = int(stats["max_health"])
	ws.bounty_value = int(stats["bounty_value"])
	if int(stats["shield_charges"]) > 0:
		ws.shield_charges = int(stats["shield_charges"])
	if int(stats["recycle_passes"]) >= -1:
		ws.recycle_passes = int(stats["recycle_passes"])
	ws.move_speed = float(stats.get("move_speed", 0.0))
	ws.weight = float(stats.get("weight", 0.0))
	ws.turn_rate = float(stats.get("turn_rate", 0.0))
	ws.accel = float(stats.get("accel", 0.0))


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
