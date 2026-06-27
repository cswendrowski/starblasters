extends RefCounted

# Lightweight hangar clutter scatterer (Roman 2026-06-21; non-overlap + rotation pass 2026-06-26).
# Realistic-ish crate groupings WITHOUT runtime collision math: the artist authors ClutterZone markers
# in clear areas of the hangar stage (so "out of the way of the lifter/tractor/ships" is guaranteed by
# placement, and tunable). This seed-picks a random subset of the zones and drops a randomized pile at
# each. Piles NEVER self-overlap — crates accrete FLUSH against their neighbours (side-by-side, no gap)
# but are never stacked on top of one another.
#
# Each crate also gets a random 90° orientation + h/v flip for variety. Rotation is kept to 90° steps
# by default so the pixels stay crisp and grid-locked to the moving plate (free tilt is available via
# `rot_jitter` but defaults OFF — arbitrary angles fuzz tiny sprites and can crawl against the plate as
# it slides in).
#
# Crate art: three UNIFORM square sheets — 6px / 7px / 8px (ammo) — drawn at 1:1 (the art is already
# sized for the 8px-prop world; never scale it). Deterministic per seed — a shop REFRESH re-rolls, a
# re-visit is stable (the caller controls the seed).

# {tex, size (px; square frame), frames (count across the strip)}.
const SHEETS := [
	{"tex": "res://graphics/backgrounds/outpost_clutter_6px_crates.png", "size": 6, "frames": 10},
	{"tex": "res://graphics/backgrounds/outpost_clutter_7px_crates.png", "size": 7, "frames": 6},
	{"tex": "res://graphics/backgrounds/outpost_clutter_8px_ammo_crates.png", "size": 8, "frames": 8},
]
const SHADOW_COL := Color(0, 0, 0, 0.4)
const SHADOW_OFF := Vector2(1.0, 1.5)
const NO_SPOT := Vector2(-99999.0, -99999.0)
const CARDINALS := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]


# Drop randomized crate piles at a random subset of `zones` (local positions). `parent` receives the
# crates. `amount` zones get a pile (clamped to zones.size()). `min/max_per_pile` size each pile.
# `rot_jitter` (radians) adds optional free tilt ON TOP of the 90° steps (0 = crisp 90°-only).
static func populate(parent: Node2D, zones: Array, seed_value: int, amount: int,
		crate_z: int = -5, shadow_z: int = -6, min_per_pile: int = 1, max_per_pile: int = 4,
		rot_jitter: float = 0.0, make_shadows: bool = true) -> void:
	if parent == null or zones.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var order := range(zones.size())
	_shuffle(order, rng)
	var n := clampi(amount, 0, zones.size())
	for zi in n:
		_pile(parent, zones[order[zi]], rng, crate_z, shadow_z, min_per_pile, max_per_pile, rot_jitter, make_shadows)


# One pile: a few crates that accrete FLUSH against each other — guaranteed non-overlapping (they may
# touch with no gap, but never stack). Each crate carries its own offset shadow.
static func _pile(parent: Node2D, center: Vector2, rng: RandomNumberGenerator,
		crate_z: int, shadow_z: int, min_n: int, max_n: int, rot_jitter: float, make_shadows: bool = true) -> void:
	var count := rng.randi_range(min_n, max_n)
	var placed: Array = []   # [{pos: Vector2, he: int}] — he = integer half-extent of the (rotated) AABB
	for i in count:
		var sheet: Dictionary = SHEETS[rng.randi() % SHEETS.size()]
		var size: int = int(sheet["size"])
		var frame: int = rng.randi() % int(sheet["frames"])
		var rot: float = float(rng.randi() % 4) * (PI / 2.0)
		if rot_jitter > 0.0:
			rot += rng.randf_range(-rot_jitter, rot_jitter)
		# Half-extent of the AABB of a `size`-square rotated by `rot`, rounded UP so the integer-grid
		# packing test never lets two crates interpenetrate (90° steps → exactly size/2, no growth).
		var he: int = int(ceil(size / 2.0 * (absf(cos(rot)) + absf(sin(rot)))))
		var pos: Vector2 = _find_spot(center, he, placed, rng)
		if pos == NO_SPOT:
			continue   # pile is full — drop this crate rather than overlap
		placed.append({"pos": pos, "he": he})
		var fh: bool = rng.randi() % 2 == 0
		var fv: bool = rng.randi() % 2 == 0
		if make_shadows:
			# Baked drop shadow. Skipped when a light-derived shadow system (light_shadow_fx) will
			# project the shadows from the bay lights instead.
			var sh := _crate_sprite(sheet, frame, rot, fh, fv)
			sh.modulate = SHADOW_COL
			sh.position = pos + SHADOW_OFF
			sh.z_index = shadow_z
			parent.add_child(sh)
		var crate := _crate_sprite(sheet, frame, rot, fh, fv)
		crate.position = pos
		crate.z_index = crate_z
		parent.add_child(crate)


# Find an integer position for a `he`-half-extent crate: the first crate sits at the pile centre; each
# next one is placed FLUSH against a random already-placed crate in a random cardinal direction, trying
# other anchors/dirs until one doesn't overlap. NO_SPOT if the pile can't grow without overlapping.
static func _find_spot(center: Vector2, he: int, placed: Array, rng: RandomNumberGenerator) -> Vector2:
	if placed.is_empty():
		return center.round()
	var cands: Array = []
	for a in placed:
		var step: int = int(a["he"]) + he
		for d in CARDINALS:
			cands.append((a["pos"] as Vector2) + d * step)
	_shuffle(cands, rng)
	for c in cands:
		if not _overlaps(c, he, placed):
			return c
	return NO_SPOT


# Square-AABB overlap test on the integer grid. Strict `<` so FLUSH (touching: distance == sum of the
# half-extents) is allowed — only true interpenetration is rejected.
static func _overlaps(c: Vector2, he: int, placed: Array) -> bool:
	for a in placed:
		var sum: float = float(he + int(a["he"]))
		var p: Vector2 = a["pos"]
		if absf(c.x - p.x) < sum and absf(c.y - p.y) < sum:
			return true
	return false


# Fill a trailer's carrying space with 1–2 small crates (1:1, never scaled), z above the trailer body.
# `trailer` is the instanced trailer scene; reads its Body/TrailerArea (a small invisible Sprite2D).
static func fill_trailer(trailer: Node, seed_value: int) -> void:
	if trailer == null:
		return
	var area = trailer.get_node_or_null("Body/TrailerArea")
	if area == null or not (area is Sprite2D):
		return
	var spr := area as Sprite2D
	var sz := Vector2(6, 8)
	if spr.texture != null:
		sz = spr.texture.get_size() * spr.scale
	var half := sz * 0.5
	# Only crates that actually FIT the bed (size <= its shorter side). The bed is ~6×8, so the 6px
	# sheet qualifies and the 7/8px ones (which would overhang the rails) are excluded; falls back to
	# the smallest sheet if the bed is ever tighter than every crate.
	var pool := _sheets_fitting(minf(sz.x, sz.y))
	if pool.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var body := area.get_parent()
	var count := rng.randi_range(0, 1)   # 6-wide bed → at most one crate across
	for i in count:
		var sheet: Dictionary = pool[rng.randi() % pool.size()]
		var frame: int = rng.randi() % int(sheet["frames"])
		var rot: float = float(rng.randi() % 4) * (PI / 2.0)
		var ch := float(sheet["size"]) * 0.5
		# Keep the crate fully inside the bed — wiggle only within the spare room on each axis.
		var room := Vector2(maxf(0.0, half.x - ch), maxf(0.0, half.y - ch))
		var crate := _crate_sprite(sheet, frame, rot, rng.randi() % 2 == 0, rng.randi() % 2 == 0)
		crate.position = (spr.position + Vector2(rng.randf_range(-room.x, room.x), rng.randf_range(-room.y, room.y))).round()
		crate.z_index = 2   # above the trailer body
		body.add_child(crate)


# The SHEETS whose crate fits within `max_side` px, smallest-first fallback so a tight bed still gets one.
static func _sheets_fitting(max_side: float) -> Array:
	var out: Array = []
	var smallest: Dictionary = {}
	for s in SHEETS:
		if smallest.is_empty() or int(s["size"]) < int(smallest["size"]):
			smallest = s
		if float(s["size"]) <= max_side:
			out.append(s)
	if out.is_empty() and not smallest.is_empty():
		out.append(smallest)
	return out


static func _crate_sprite(sheet: Dictionary, frame: int, rot: float, flip_h: bool, flip_v: bool) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(sheet["tex"])
	s.hframes = int(sheet["frames"])
	s.frame = frame
	s.rotation = rot
	s.flip_h = flip_h
	s.flip_v = flip_v
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return s


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
