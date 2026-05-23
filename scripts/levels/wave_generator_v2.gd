extends Node
class_name WaveGeneratorV2

# Wave V2 (Roman, 2026-05-18 plan). Builds a LevelDef from 3 knobs:
#   density_mult   1.0 = baseline counts. Doubles to 2.0 = dense.
#   wave_count     3-7 waves per combat
#   tier_max       0=common, 1=+uncommon, 2=+rare, 3=+elite
# Plus sector_idx, which scales:
#   - enemy_hp += sector_idx - 1
#   - density gets a 1+0.1*(sector_idx-1) multiplier
#
# Picks a `shape` template per wave from the pool below. Each shape
# defines spawn pattern (sweep / pincer / drip / loiter / burst).

const WaveSpec = preload("res://scripts/levels/wave_def.gd")
const LevelData = preload("res://scripts/levels/level_def.gd")
const EnemyRoster = preload("res://scripts/levels/enemy_roster.gd")
const StraightDown = preload("res://scripts/enemies/patterns/straight_down.gd")
const SCurve = preload("res://scripts/enemies/patterns/s_curve.gd")
const Loiter = preload("res://scripts/enemies/patterns/loiter.gd")
const OmniThrust = preload("res://scripts/enemies/patterns/omni_thrust.gd")
const InertialThrust = preload("res://scripts/enemies/patterns/inertial_thrust.gd")
const SingleShot = preload("res://scripts/enemies/shoot_patterns/single_shot.gd")
const SpreadShot = preload("res://scripts/enemies/shoot_patterns/spread_shot.gd")
const AimedShot = preload("res://scripts/enemies/shoot_patterns/aimed_fire.gd")
const EnemyBullet = preload("res://scenes/projectiles/enemy_bullet.tscn")

# Chaff side-entry scenes: when shape="side_alternating" runs, formation 4
# is used and director alternates spawn side + sets movement direction.
const SIDE_ENTRY_SCENES := {
	"res://scenes/enemies/enemy_cutter.tscn": true,
}
# Max tier index used by sector_depth auto-progression (common/uncommon/rare/elite).
const TIER_MAX_IDX := 3

const SHAPES := ["sweep", "counter_sweep", "pincer", "drip", "loiter", "burst", "harasser"]
# Rare random event chance per wave slot — bomber wing intrudes occasionally.
const BOMBER_WING_CHANCE: float = 0.08
const BomberScene = preload("res://scenes/enemies/enemy_bomber.tscn")


static func build_combat(sector_idx: int = 1, knobs: Dictionary = {}) -> LevelData:
	# Sector depth = which combat in the sector (1 = first, N = Nth).
	# Drives wave_count / density / tier_max automatically so the tester
	# can simulate "how does the 5th combat in sector 3 feel" with two
	# sliders instead of micro-tuning four knobs (Roman 2026-05-18).
	var sector_depth: int = clampi(int(knobs.get("sector_depth", 1)), 1, 10)
	# Auto-derived progression:
	#   wave_count = 2 + depth  (3 waves at depth 1, 8 at depth 6+)
	#   density_mult ramps with depth + sector
	#   tier_max unlocks every 2 depths (depth 1-2 = common, 3-4 = uncommon, etc.)
	var sector_scale: float = 1.0 + 0.1 * float(sector_idx - 1)
	# Resolve knobs first (override > auto-derive), then apply sector scale
	# exactly once at the end.
	var wave_count: int
	if knobs.has("wave_count"):
		wave_count = clampi(int(knobs["wave_count"]), 2, 8)
	else:
		wave_count = clampi(2 + sector_depth, 2, 8)
	var density_base: float
	if knobs.has("density_mult"):
		density_base = float(knobs["density_mult"])
	else:
		density_base = 1.0 + 0.15 * float(sector_depth - 1)
	var density_mult: float = density_base * sector_scale
	var tier_max: int
	if knobs.has("tier_max"):
		tier_max = clampi(int(knobs["tier_max"]), 0, TIER_MAX_IDX)
	else:
		tier_max = clampi(int(floor(float(sector_depth - 1) * 0.5)), 0, TIER_MAX_IDX)

	# Reset the bomber-wing slot registry so a stale wing from a prior
	# level (player died before bombers spawned, scene change, etc.)
	# doesn't bleed into the new build.
	_pending_wings.clear()
	var rng := RandomNumberGenerator.new()
	if knobs.has("seed"):
		rng.seed = int(knobs["seed"])
	else:
		rng.randomize()

	# Weighted, gated pool from the roster — honors unlock_sector / unlock_depth
	# / weight so new chaff stagger into rolls without scripted indices.
	var pool: Array = EnemyRoster.eligible_pool(sector_idx, sector_depth, tier_max)
	assert(not pool.is_empty(), "WaveGeneratorV2: no chaff entries match sector=%d depth=%d tier_max=%d — check enemy_roster.gd unlock gates" % [sector_idx, sector_depth, tier_max])

	var waves: Array = []
	var delay: float = 0.5
	var prev_tags: PackedStringArray = PackedStringArray()
	for i in wave_count:
		# Rare random event: bomber wing intrusion. Replaces a normal wave
		# slot with a V-formation of 3-5 bombers (Roman 2026-05-18).
		if rng.randf() < BOMBER_WING_CHANCE:
			var bomber_specs: Array = _shape_bomber_wing(delay, i == 0, rng, sector_idx)
			for w in bomber_specs:
				waves.append(w)
			delay += 6.0 + rng.randf_range(0.0, 1.5)
			continue
		var allowed: Array = _filter_by_conflict(pool, prev_tags)
		if allowed.is_empty():
			push_warning("WaveGeneratorV2: conflict filter emptied pool at wave %d — falling back to full pool" % i)
			allowed = pool
		var enemy_path: String = allowed[rng.randi() % allowed.size()]
		var shape: String
		if SIDE_ENTRY_SCENES.has(enemy_path):
			# Cutter must enter from a side, not the top — force SIDE_ALTERNATING.
			shape = "side_alternating"
		else:
			shape = SHAPES[rng.randi() % SHAPES.size()]
		var wave_specs: Array = _build_shape(shape, enemy_path, delay, i == 0, density_mult, sector_idx, rng)
		for w in wave_specs:
			waves.append(w)
		delay += 3.0 + rng.randf_range(0.0, 1.5)
		var picked_entry: Dictionary = EnemyRoster.entry_for_scene(enemy_path)
		prev_tags = PackedStringArray(picked_entry.get("conflict_tags", []))

	var level := LevelData.new()
	level.level_name = "S%d Combat" % sector_idx
	level.waves = waves
	return level


static func _build_shape(shape: String, enemy_path: String, delay: float, is_lead: bool, density: float, sector_idx: int, rng: RandomNumberGenerator) -> Array:
	var scene = load(enemy_path)
	if scene == null:
		return []
	var specs: Array = []
	match shape:
		"sweep":         specs = _shape_sweep(scene, delay, is_lead, density, sector_idx)
		"counter_sweep": specs = _shape_counter_sweep(scene, delay, is_lead, density, sector_idx)
		"pincer":        specs = _shape_pincer(scene, delay, is_lead, density, sector_idx)
		"drip":          specs = _shape_drip(scene, delay, is_lead, density, sector_idx)
		"loiter":        specs = _shape_loiter(scene, delay, is_lead, density, sector_idx)
		"burst":         specs = _shape_burst(scene, delay, is_lead, density, sector_idx)
		"harasser":      specs = _shape_harasser(scene, delay, is_lead, density, sector_idx, rng)
		"side_alternating": specs = _shape_side_alternating(scene, delay, is_lead, density, sector_idx)
	var entry: Dictionary = EnemyRoster.entry_for_scene(enemy_path)
	if not entry.is_empty():
		var stats: Dictionary = EnemyRoster.compose_stats(entry)
		var no_shoot: bool = entry.get("shoot", null) == null
		for w in specs:
			w.max_health = stats["max_health"]
			w.bounty_value = stats["bounty_value"]
			if stats["shield_charges"] > 0:
				w.shield_charges = stats["shield_charges"]
			if stats["recycle_passes"] >= -1:
				w.recycle_passes = stats["recycle_passes"]
			if no_shoot:
				w.shoot_pattern_override = null
	return specs


static func _hp_bump(sector_idx: int) -> int:
	return max(0, sector_idx - 1)


static func _shape_sweep(scene, delay: float, is_lead: bool, density: float, sector_idx: int) -> Array:
	var w = WaveSpec.new()
	w.enemy_scene = scene
	w.count = int(round(6.0 * density))
	w.spawn_interval = 0.45
	w.spawn_delay = delay
	w.formation = 0  # left-to-right
	w.formation_padding = 50.0
	w.shoot_pattern_override = _single()
	w.fire_interval_min = 1.4
	w.fire_interval_max = 2.4
	w.health_bonus = _hp_bump(sector_idx)
	if is_lead:
		w.announce_text = "INCOMING"
	else:
		w.silent = true
	return [w]


static func _shape_counter_sweep(scene, delay: float, is_lead: bool, density: float, sector_idx: int) -> Array:
	var w = WaveSpec.new()
	w.enemy_scene = scene
	w.count = int(round(6.0 * density))
	w.spawn_interval = 0.45
	w.spawn_delay = delay
	w.formation = 1  # right-to-left
	w.formation_padding = 50.0
	w.shoot_pattern_override = _single()
	w.health_bonus = _hp_bump(sector_idx)
	if is_lead:
		w.announce_text = "INCOMING"
	else:
		w.silent = true
	return [w]


static func _shape_pincer(scene, delay: float, is_lead: bool, density: float, sector_idx: int) -> Array:
	var left = WaveSpec.new()
	left.enemy_scene = scene
	left.count = int(round(4.0 * density))
	left.spawn_interval = 0.35
	left.spawn_delay = delay
	left.formation = 0
	left.formation_padding = 32.0
	left.shoot_pattern_override = _aimed()
	left.health_bonus = _hp_bump(sector_idx)
	if is_lead:
		left.announce_text = "INCOMING"
	else:
		left.silent = true
	var right = WaveSpec.new()
	right.enemy_scene = scene
	right.count = int(round(4.0 * density))
	right.spawn_interval = 0.35
	right.spawn_delay = delay
	right.formation = 1
	right.formation_padding = 32.0
	right.shoot_pattern_override = _aimed()
	right.health_bonus = _hp_bump(sector_idx)
	right.silent = true
	return [left, right]


static func _shape_drip(scene, delay: float, is_lead: bool, density: float, sector_idx: int) -> Array:
	var w = WaveSpec.new()
	w.enemy_scene = scene
	w.count = int(round(10.0 * density))
	w.spawn_interval = 0.55
	w.spawn_delay = delay
	w.formation = 2  # TOP_RANDOM
	w.shoot_pattern_override = _single()
	w.health_bonus = _hp_bump(sector_idx)
	if is_lead:
		w.announce_text = "INCOMING"
	else:
		w.silent = true
	return [w]


static func _shape_loiter(scene, delay: float, is_lead: bool, density: float, sector_idx: int) -> Array:
	var w = WaveSpec.new()
	w.enemy_scene = scene
	w.count = int(round(3.0 * density))
	w.spawn_interval = 0.8
	w.spawn_delay = delay
	w.formation = 3  # TOP_CENTER_OUT
	var p = Loiter.new()
	p.hover_y = 180.0
	p.enter_speed = 180.0
	p.loiter_time = 5.0
	p.exit_accel = 400.0
	p.exit_max_speed = 500.0
	w.movement_override = p
	w.shoot_pattern_override = _spread(3, 28.0)
	w.fire_interval_min = 1.6
	w.fire_interval_max = 2.4
	w.health_bonus = _hp_bump(sector_idx)
	if is_lead:
		w.announce_text = "INCOMING"
	else:
		w.silent = true
	return [w]


static func _shape_burst(scene, delay: float, is_lead: bool, density: float, sector_idx: int) -> Array:
	var w = WaveSpec.new()
	w.enemy_scene = scene
	w.count = int(round(8.0 * density))
	w.spawn_interval = 0.18  # tight burst
	w.spawn_delay = delay
	w.formation = 0
	w.formation_padding = 28.0
	w.shoot_pattern_override = _single()
	w.health_bonus = _hp_bump(sector_idx)
	if is_lead:
		w.announce_text = "INCOMING"
	else:
		w.silent = true
	return [w]


static func _shape_side_alternating(scene, delay: float, is_lead: bool, density: float, sector_idx: int) -> Array:
	# Cutter pattern: 3-4 enemies alternate L/R side entry. Director handles
	# spawn x + movement direction per index when formation == SIDE_ALTERNATING.
	var w = WaveSpec.new()
	w.enemy_scene = scene
	w.count = max(3, int(round(4.0 * density)))
	w.spawn_interval = 0.65
	w.spawn_delay = delay
	w.formation = 4  # SIDE_ALTERNATING
	w.spawn_y = 72.0  # side_cut snaps y itself but match the pattern's travel_y
	w.shoot_pattern_override = _single()
	w.fire_interval_min = 0.4
	w.fire_interval_max = 0.7
	w.health_bonus = _hp_bump(sector_idx)
	if is_lead:
		w.announce_text = "INCOMING"
	else:
		w.silent = true
	return [w]


static func _shape_bomber_wing(delay: float, is_lead: bool, rng: RandomNumberGenerator, sector_idx: int) -> Array:
	# V-formation of 3-5 bombers. Each bomber is a separate WaveSpec with
	# count=1, staggered spawn_delay, and a unique x offset so they form
	# a V as they descend to their hover row.
	var count: int = rng.randi_range(3, 5)
	# X offsets (px) for the V — center, then ± inner, then ± outer.
	# Bombers are 48 px wide at 1× scale (ship_6), so spacing must clear
	# that plus room for sway. Roman 2026-05-18: avoid overlapping.
	var offsets := [0.0, -62.0, 62.0, -118.0, 118.0]
	# Y depth — wingmen lag behind the lead.
	var y_depths := [0.0, 28.0, 28.0, 54.0, 54.0]
	var specs: Array = []
	for i in count:
		var w = WaveSpec.new()
		w.enemy_scene = BomberScene
		w.count = 1
		w.spawn_interval = 0.1
		w.spawn_delay = delay + float(i) * 0.18  # leader first, wings trail
		w.formation = 2  # TOP_RANDOM (will override below via spawn_y)
		# Use a hand-positioned spawn — formation TOP_RANDOM lands somewhere
		# top-of-screen but we want a precise V. Instead use TOP_CENTER_OUT
		# with one bomber and a custom padding hack: set formation_padding
		# to (vp_width/2 + offset). Director's TOP_LEFT_TO_RIGHT with
		# count=1 puts the lone enemy at left edge; we use formation=3
		# (TOP_CENTER_OUT) with count=1 which centers it, then bake the
		# offset into the bomber's slot anchor after spawn.
		w.formation = 3
		# Encode the slot offset on the WaveSpec via custom metadata —
		# director doesn't read this; the bomber pulls it from elsewhere.
		# Simpler: use formation_padding as a SIGNED offset hack by
		# repurposing it. Actually the cleanest path is to set spawn_y
		# differently per bomber to stagger Y arrival.
		w.spawn_y = -12.0 - y_depths[i]
		# Store offset in fire_interval_min as a smuggle channel — gross.
		# Cleaner: handle V offset entirely in the bomber via spawn order
		# tracking. For now, all bombers settle to hover_y but at the
		# director-given x; the y_depths give them a staggered entry.
		specs.append(w)
		# Track which slot this bomber occupies via a static-like counter.
	# Slot anchors are handled via a wing-wide singleton — see
	# `_BomberWingTracker` below.
	_register_wing(count, offsets, y_depths)
	if is_lead:
		specs[0].announce_text = "BOMBER WING"
	return specs


# Bomber wing slot registry. Each spawned bomber pulls its slot index
# from here in start() / _ready and uses it to compute its V offset.
static var _pending_wings: Array = []   # Array of {count, offsets, y_depths, assigned}

static func _register_wing(count: int, offsets: Array, y_depths: Array) -> void:
	_pending_wings.append({
		"count": count,
		"offsets": offsets.duplicate(),
		"y_depths": y_depths.duplicate(),
		"assigned": 0,
	})

# Called by enemy_bomber to claim its slot.
static func claim_bomber_slot() -> Dictionary:
	for wing in _pending_wings:
		if int(wing["assigned"]) < int(wing["count"]):
			var idx: int = int(wing["assigned"])
			wing["assigned"] = idx + 1
			var result := {
				"slot_index": idx,
				"x_offset": float(wing["offsets"][idx]),
				"y_depth": float(wing["y_depths"][idx]),
				"is_lead": idx == 0,
			}
			# Garbage collect fully-assigned wings.
			if int(wing["assigned"]) >= int(wing["count"]):
				_pending_wings.erase(wing)
			return result
	return {"slot_index": 0, "x_offset": 0.0, "y_depth": 0.0, "is_lead": true}


static func _shape_harasser(scene, delay: float, is_lead: bool, density: float, sector_idx: int, rng: RandomNumberGenerator) -> Array:
	# Live-game harassment shape (Roman 2026-05-18, Lab -> live).
	# Spawns a small squad that gets in the player's face — Omni for half,
	# Inertial for half — strafing at close range instead of just diving.
	var w = WaveSpec.new()
	w.enemy_scene = scene
	w.count = max(2, int(round(3.0 * density)))
	w.spawn_interval = 0.55
	w.spawn_delay = delay
	w.formation = 2  # TOP_RANDOM
	if rng.randf() < 0.5:
		w.movement_override = OmniThrust.new()
	else:
		w.movement_override = InertialThrust.new()
	w.shoot_pattern_override = _aimed()
	w.fire_interval_min = 1.1
	w.fire_interval_max = 1.9
	w.health_bonus = _hp_bump(sector_idx)
	if is_lead:
		w.announce_text = "HARASSERS"
	else:
		w.silent = true
	return [w]


static func _filter_by_conflict(pool: Array, prev_tags: PackedStringArray) -> Array:
	if prev_tags.is_empty():
		return pool
	var out: Array = []
	for path in pool:
		var entry: Dictionary = EnemyRoster.entry_for_scene(str(path))
		var tags: Array = entry.get("conflict_tags", [])
		var clash: bool = false
		for t in tags:
			if prev_tags.has(str(t)):
				clash = true
				break
		if not clash:
			out.append(path)
	return out


static func _single() -> Resource:
	var sp = SingleShot.new()
	sp.bullet_scene = EnemyBullet
	return sp


static func _spread(count: int, degrees: float) -> Resource:
	var sp = SpreadShot.new()
	sp.bullet_scene = EnemyBullet
	sp.bullet_count = count
	sp.spread_degrees = degrees
	return sp


static func _aimed() -> Resource:
	var sp = AimedShot.new()
	sp.bullet_scene = EnemyBullet
	return sp
