extends Node

# Drives enemy spawning for the current level. Conductor v3 (combat overhaul,
# streaming): the incoming LevelData is lifted to a CombatScore via ScoreAdapter,
# then flattened to ordered phrase steps. Dispatch is STREAMING:
#   - spawning is gated by a concurrency cap (max_concurrent) so on-screen
#     density can never exceed it by construction (bridge §1.2);
#   - there is NO per-wave clear-gate — a wave advances as soon as its spawn
#     budget is spent, so the 5-8 waves blend into one continuous stream;
#   - banners are non-blocking markers — spawning no longer halts for the banner.
# level_cleared still fires when all phrases are dispatched AND the "enemies"
# group is empty. Conductor v3 walks the Wave->Phrase structure natively,
# dispatching FORMATION / FILLER / BREATHER (v2 lane placement applies to TOP
# spawns). On legacy-adapted content (all FORMATION) this matches v2; FILLER and
# BREATHER appear in authored content. See
# docs/combat_construction_plan_2026-06-03.md §3 and the bridge §1-2.

signal enemy_died(value: int, scene_path: String)
signal enemy_spawned(scene_path: String, bounty_value: int)
signal wave_started(wave_index: int, wave_count: int, silent: bool, announce_text: String)
signal level_cleared

const FactionsC = preload("res://scripts/levels/factions.gd")

# Banner fade-in+hold+fade-out budget. Director waits this long before the
# first enemy of an ANNOUNCED wave so spawns never overlap the WAVE alert.
const BANNER_HOLD: float = 1.9  # Roman 2026-06-01: halved inter-wave windows
# Extra beat after the banner clears before enemies start (Roman, 2026-05-15).
const POST_BANNER_GRACE: float = 0.2
# Grace period AFTER a wave is cleared (all enemies in the group dead) and
# BEFORE the next banner pops. "Wait a beat, show next wave banner."
const POST_CLEAR_GRACE: float = 0.2

@export var level: Resource  # LevelData
@export var auto_start: bool = false
# Streaming concurrency cap (bridge §1.2 / composition guide §9). On-screen
# non-hazard density never exceeds this. Depth-ramped 12->16 per level by
# main.gd via WaveGen.cap_for(sd, li); this export is the fallback for content
# that doesn't set it (hazards/custom/slice). The lane/free-plane split lands
# later. Counts recyclers (an on-screen body); recycling-vs-cap is a tracked
# open item (construction §6).
@export var max_concurrent: int = 14
# Minimum gap between spawns regardless of cap headroom — stops a fast-killing
# player from machine-gunning fresh spawns (wave §1.2).
const ANTI_BURST_FLOOR: float = 0.20
# WALL dispatch (construction §8): a wall arrives as successive ROWS. Each row fills
# all but WALL_GAP_LANES lanes (the gap shifts row-to-row so the safe lane moves),
# members within a row spawn on a tight stagger, and WALL_ROW_BEAT pauses between
# rows so each reads as a distinct "pick a gap" beat instead of one mega-burst.
const WALL_GAP_LANES: int = 2       # lanes left open per row (7 lanes -> rows of ~5)
const WALL_ROW_BEAT: float = 0.55   # pause between successive wall rows
const WALL_MEMBER_STAGGER: float = 0.05  # intra-row spawn stagger (near-simultaneous)
# Crosser height-stagger (P2 row choreography): a horizontal crosser (movement with
# a `travel_y` field, e.g. side_traverse) would otherwise have every member ride the
# SAME latitude and rear-end its siblings. Spread successive crossers across
# CROSSER_STAGGER_BANDS latitudes (CROSSER_STAGGER_STEP apart) so a stream reads as
# distinct passes at different heights. Kept in the upper band so crossers stay a
# top-of-screen threat (4 bands * 26 = 78px spread, base ~80 -> ~80..158).
const CROSSER_STAGGER_BANDS: int = 4
const CROSSER_STAGGER_STEP: float = 26.0
# Grace beat after the player gains control before the first wave dispatches, so
# the level doesn't open the instant the slide-in ends.
@export var start_grace: float = 1.2

var _running: bool = false
var _check_clear: bool = false
var _score: Resource = null   # CombatScore (adapter output)
var _steps: Array = []        # flattened phrase steps (phrase + wave context)
var _step_idx: int = -1
var _wave_total: int = 0
var _last_lane: int = -1      # last lane chosen by _pick_lane (alternate-anchor)

func start_level(new_level: Resource = null) -> void:
	# COMPAT SHIM (M5 native emission): production now emits a CombatScore at the
	# producer chokepoint (main.gd) and calls start_score directly. This remains for
	# LevelData-holding callers — dev tools + the director v0-v2 tests — lifting via
	# the shared builder. New code should call start_score(WaveGen.build_score(...)).
	if new_level != null:
		level = new_level
	if level == null or level.waves.is_empty():
		push_warning("WaveDirector: no level / no waves")
		return
	start_score(ScoreAdapter.from_level_data(level))


# Perform a CombatScore: flatten to ordered phrase steps (each carries its wave
# context for the banner) and walk them, dispatching FORMATION/FILLER/BREATHER.
func start_score(score: Resource) -> void:
	_score = score
	if _score == null or _score.waves.is_empty():
		push_warning("WaveDirector: empty score")
		return
	_wave_total = _score.waves.size()
	_steps = _build_steps(_score)
	if _steps.is_empty():
		push_warning("WaveDirector: score has no phrases")
		return
	_running = true
	_step_idx = -1
	_check_clear = false
	_last_lane = -1
	# Opening grace: let the player settle after the slide-in before waves come.
	if start_grace > 0.0:
		await get_tree().create_timer(start_grace).timeout
		if not _running:
			return
	_advance_step()

func stop() -> void:
	_running = false
	_check_clear = false


# Flatten a CombatScore into an ordered list of phrase "steps". Each step is the
# phrase plus its wave context (index + whether it opens the wave, so the banner
# fires once per ScoreWave). Order across waves is preserved.
func _build_steps(score: Resource) -> Array:
	var out: Array = []
	if score == null:
		return out
	for wi in score.waves.size():
		var w: Resource = score.waves[wi]
		for pi in w.phrases.size():
			out.append({
				"phrase": w.phrases[pi],
				"wave_idx": wi,
				"is_wave_start": pi == 0,
				"banner": w.banner,
			})
	return out


# Count of live, non-hazard enemies on screen — the concurrency-cap measure.
# Includes recyclers (they occupy screen space); excludes is_hazard terrain
# (mines/asteroids keep their own bespoke pacing, uncapped in v1).
func _alive_count() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if "is_hazard" in e and e.is_hazard:
			continue
		n += 1
	return n


# Lane selection for TOP spawns (conductor v2): alternate-anchor — prefer the
# side opposite the previous spawn (Toaplan rhythm, composition guide §3),
# among lanes not currently occupied near the entry band so the stream spreads
# across the 7 lanes and forces player movement.
func _pick_lane() -> int:
	var occupied: Array = _occupied_lanes()
	var candidates: Array = []
	for i in Lanes.COUNT:
		if not occupied.has(i):
			candidates.append(i)
	if candidates.is_empty():
		for i in Lanes.COUNT:
			candidates.append(i)
	if _last_lane >= 0:
		var want_high: bool = _last_lane < Lanes.COUNT / 2
		var side: Array = candidates.filter(
			func(i): return (i >= Lanes.COUNT / 2) == want_high)
		if not side.is_empty():
			candidates = side
	var pick: int = candidates[randi() % candidates.size()]
	_last_lane = pick
	return pick


# Staggered travel-y for the index-th crosser in a dispatch (P2 row choreography):
# spread across CROSSER_STAGGER_BANDS latitudes so consecutive crossers (and
# opposite-direction siblings) ride different heights instead of overlapping.
func _crosser_travel_y(base: float, index: int) -> float:
	return base + float(index % CROSSER_STAGGER_BANDS) * CROSSER_STAGGER_STEP


# Lanes currently holding a non-hazard enemy in the top entry band, so a fresh
# spawn doesn't stack directly onto one.
func _occupied_lanes() -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if "is_hazard" in e and e.is_hazard:
			continue
		if e.position.y <= 40.0:
			var ln: int = Lanes.nearest_lane(e.position.x)
			if not out.has(ln):
				out.append(ln)
	return out

func _advance_step() -> void:
	_step_idx += 1
	if _step_idx >= _steps.size():
		_running = false
		_check_clear = true   # all phrases dispatched; watch for clear
		return
	var st: Dictionary = _steps[_step_idx]
	# Non-blocking banner once per ScoreWave (bridge §1.1): emit and keep going.
	if st["is_wave_start"]:
		wave_started.emit(int(st["wave_idx"]), _wave_total, false, String(st["banner"]))
	var ph: Resource = st["phrase"]
	match ph.kind:
		Phrase.Kind.FORMATION:
			_dispatch_formation(ph)
		Phrase.Kind.FILLER:
			_dispatch_filler(ph)
		Phrase.Kind.BREATHER:
			_dispatch_breather(ph)
		_:
			_advance_step()


# FORMATION: spawn the phrase's spec group(s), cap-gated, at each spec's cadence
# (tandem pairs spawn their mirrored partner on the same tick). On legacy-adapted
# content this reproduces the v2 trickle; authored small formations burst.
func _dispatch_formation(ph: Resource) -> void:
	# WALL: chunk into SUCCESSIVE rows (each leaving 1-2 shifting gap lanes, a beat
	# between rows) so a big fast-chaff wave reads as "pick a gap, NOW" repeated,
	# not a one-at-a-time spread trickle (construction §8, dart-trickle bug).
	if ph.shape == &"wall":
		await _dispatch_wall(ph)
		_advance_step()
		return
	# PINCER: near-simultaneous burst across edge-inward lanes ("sent whole").
	if ph.shape == &"pincer":
		await _dispatch_shaped(ph)
		_advance_step()
		return
	# STEP_WALL: a coordinated stepping row — fills all but one edge lane, spawns in
	# one frame with shared synced-STEP params, then shifts in UNISON so the gap
	# relocates (P2d, react-to-the-new-gap).
	if ph.shape == &"step_wall":
		await _dispatch_step_wall(ph)
		_advance_step()
		return
	# Default (spread): per-member alternate-anchor lane at each spec's cadence;
	# preserves tandem/side placement via spec.formation.
	for sp in ph.specs:
		if sp == null:
			continue
		var i: int = 0
		while i < sp.count:
			if not _running:
				return
			while _running and _alive_count() >= max_concurrent:
				await get_tree().create_timer(0.1).timeout
			if not _running:
				return
			_spawn_enemy(sp, i)
			i += 1
			# Tandem partner on the same tick (formation 5), mirrored X.
			if sp.formation == 5 and i < sp.count and (i % 2) == 1:
				_spawn_enemy(sp, i)
				i += 1
			await get_tree().create_timer(maxf(sp.spawn_interval, ANTI_BURST_FLOOR)).timeout
	_advance_step()


# Spawn a shaped formation's members across computed lanes as a quick burst.
func _dispatch_shaped(ph: Resource) -> void:
	var members: Array = []
	for sp in ph.specs:
		if sp == null:
			continue
		for _k in sp.count:
			members.append(sp)
	if members.is_empty():
		return
	var lanes: Array = _formation_lanes(ph.shape, members.size())
	for idx in members.size():
		if not _running:
			return
		while _running and _alive_count() >= max_concurrent:
			await get_tree().create_timer(0.1).timeout
		if not _running:
			return
		_spawn_enemy(members[idx], idx, int(lanes[idx]))
		await get_tree().create_timer(0.06).timeout


# WALL: spawn members as successive rows across the lanes. Each row leaves
# WALL_GAP_LANES open (the gap shifts off the previous row so the player must
# re-position), members spawn on a tight stagger, and a beat separates rows. A
# count-N wall becomes ceil(N / row_size) readable walls instead of one burst.
func _dispatch_wall(ph: Resource) -> void:
	var members: Array = []
	for sp in ph.specs:
		if sp == null:
			continue
		for _k in sp.count:
			members.append(sp)
	if members.is_empty():
		return
	var row_size: int = maxi(1, Lanes.COUNT - WALL_GAP_LANES)
	var prev_gaps: Array = []
	var idx: int = 0
	while idx < members.size():
		if not _running:
			return
		# Cap-gate before each row so a wall never blows past the concurrency cap.
		while _running and _alive_count() >= max_concurrent:
			await get_tree().create_timer(0.1).timeout
		if not _running:
			return
		var n_this: int = mini(row_size, members.size() - idx)
		var lanes: Array = _wall_row_lanes(n_this, prev_gaps)
		# Record this row's gaps so the next row shifts off them.
		prev_gaps = []
		for i in Lanes.COUNT:
			if not lanes.has(i):
				prev_gaps.append(i)
		for k in n_this:
			if not _running:
				return
			_spawn_enemy(members[idx], idx, int(lanes[k]))
			idx += 1
			await get_tree().create_timer(WALL_MEMBER_STAGGER).timeout
		# Beat between rows (only if more remain).
		if idx < members.size():
			await get_tree().create_timer(WALL_ROW_BEAT).timeout


# STEP_WALL: spawn a coordinated stepping row (P2d). The row fills a contiguous block
# of lanes leaving the opposite edge open, all members spawn in ONE frame with the
# SAME synced-STEP params (offset bounds sized so the whole block stays on-board, a
# shared start direction toward the gap), so they step in unison and the gap relocates.
func _dispatch_step_wall(ph: Resource) -> void:
	var members: Array = []
	for sp in ph.specs:
		if sp == null:
			continue
		for _k in sp.count:
			members.append(sp)
	if members.is_empty():
		return
	# Cap-gate before the row (one cohesive burst).
	while _running and _alive_count() >= max_concurrent:
		await get_tree().create_timer(0.1).timeout
	if not _running:
		return
	var layout: Dictionary = _step_wall_layout(members.size())
	var lanes: Array = layout["lanes"]
	var sync: Dictionary = {"lo": layout["lo"], "hi": layout["hi"], "dir": layout["dir"]}
	# Spawn the whole row in this frame (no stagger) so their step clocks align.
	for i in lanes.size():
		if not _running:
			return
		_spawn_enemy(members[i], i, int(lanes[i]), sync)


# Lane layout + shared offset bounds for a step wall of n members: a contiguous block
# at one (random) edge leaving the other open; offset bounds [lo,hi] keep the whole
# block on-board; dir shifts toward the open edge. n is capped at COUNT-1 so there is
# always a gap to shift into.
func _step_wall_layout(n: int) -> Dictionary:
	n = clampi(n, 1, Lanes.COUNT - 1)
	var left_block: bool = randf() < 0.5
	var start_lane: int = 0 if left_block else (Lanes.COUNT - n)
	var lanes: Array = []
	for i in n:
		lanes.append(start_lane + i)
	var min_l: int = int(lanes[0])
	var max_l: int = int(lanes[lanes.size() - 1])
	return {
		"lanes": lanes,
		"lo": -min_l,
		"hi": (Lanes.COUNT - 1) - max_l,
		"dir": 1 if left_block else -1,
	}


# Choose the n filled lanes for one wall row. The (COUNT - n) gap lanes are picked
# to differ from `avoid_gaps` (the previous row's gaps) where possible, so the safe
# lane moves between rows. Returns the filled lanes ascending.
func _wall_row_lanes(n: int, avoid_gaps: Array) -> Array:
	var gap_count: int = clampi(Lanes.COUNT - n, 0, Lanes.COUNT)
	var pool: Array = []
	for i in Lanes.COUNT:
		pool.append(i)
	pool.shuffle()
	var gaps: Array = []
	# First pass: gaps NOT used by the previous row (shift the safe lane).
	for ln in pool:
		if gaps.size() >= gap_count:
			break
		if not avoid_gaps.has(ln):
			gaps.append(ln)
	# Top up if we couldn't avoid enough (e.g. tiny lane count).
	for ln in pool:
		if gaps.size() >= gap_count:
			break
		if not gaps.has(ln):
			gaps.append(ln)
	var lanes: Array = []
	for i in Lanes.COUNT:
		if not gaps.has(i):
			lanes.append(i)
	return lanes


# Lane layout for a shaped formation of n members.
#   wall   — fill lanes leaving one randomized safe gap (then wrap if n is big).
#   pincer — alternate inward from both edges: 0, 6, 1, 5, 2, 4, 3 ...
#   else   — spread via alternate-anchor _pick_lane per member.
func _formation_lanes(shape: StringName, n: int) -> Array:
	var out: Array = []
	match shape:
		&"wall":
			var gap: int = randi() % Lanes.COUNT
			for i in Lanes.COUNT:
				if i != gap and out.size() < n:
					out.append(i)
			var j: int = 0
			while out.size() < n:
				out.append(j % Lanes.COUNT)
				j += 1
		&"pincer":
			var lo: int = 0
			var hi: int = Lanes.COUNT - 1
			var from_left: bool = true
			while out.size() < n:
				if lo > hi:
					lo = 0
					hi = Lanes.COUNT - 1
				if from_left:
					out.append(lo)
					lo += 1
				else:
					out.append(hi)
					hi -= 1
				from_left = not from_left
		_:
			for _i in n:
				out.append(_pick_lane())
	return out


# FILLER: trickle single enemies from the pool, cap-gated, until the stop
# condition. Supports until="duration" (until_value seconds) and "budget"
# (until_value enemies); anything else trickles for a short default window.
func _dispatch_filler(ph: Resource) -> void:
	if ph.pool.is_empty():
		_advance_step()
		return
	var elapsed: float = 0.0
	var spawned: int = 0
	var dur_limit: float = ph.until_value if ph.until == &"duration" else 3.0
	var budget_limit: int = int(ph.until_value) if ph.until == &"budget" else -1
	while _running:
		if budget_limit >= 0 and spawned >= budget_limit:
			break
		if budget_limit < 0 and elapsed >= dur_limit:
			break
		while _running and _alive_count() >= max_concurrent:
			await get_tree().create_timer(0.1).timeout
			elapsed += 0.1
		if not _running:
			return
		var sp: Resource = ph.pool[randi() % ph.pool.size()]
		if sp != null:
			_spawn_enemy(sp, spawned)
			spawned += 1
		var gap: float = maxf(1.0 / maxf(ph.rate, 0.01), ANTI_BURST_FLOOR)
		await get_tree().create_timer(gap).timeout
		elapsed += gap
	_advance_step()


# BREATHER: hold spawning for `duration` seconds, or until the screen drains to
# alive_floor if set. The readability exhale between intense waves (bridge §2.3).
func _dispatch_breather(ph: Resource) -> void:
	var elapsed: float = 0.0
	while _running and elapsed < ph.duration:
		if ph.alive_floor >= 0 and _alive_count() <= ph.alive_floor:
			break
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	_advance_step()


func _spawn_enemy(wave: Resource, index: int, lane_override: int = -1, step_sync: Dictionary = {}) -> void:
	if wave.enemy_scene == null:
		push_warning("WaveDirector: spec has no enemy_scene")
		return
	var enemy = wave.enemy_scene.instantiate()
	# 320×400 internal resolution rework (Roman, 2026-05-17): sprites render
	# at native 1× by default. Per-ship display_scale overrides still apply
	# but are now sized for the new playfield (e.g. boss 1.0 instead of 3.0).
	var s_default: float = 1.0
	if "display_scale" in enemy and enemy.display_scale > 0.0:
		s_default = enemy.display_scale
	enemy.scale = Vector2(s_default, s_default)
	# Apply per-wave overrides
	# All four overrides are guarded with `in` checks so hazard enemies
	# (mines, asteroids, bomblets) can drop the dead compatibility-shim
	# fields. (Roman, 2026-05-16 enemy refactor.)
	if wave.movement_override != null and "movement" in enemy:
		enemy.movement = wave.movement_override
	if wave.shoot_pattern_override != null and "shoot_pattern" in enemy:
		enemy.shoot_pattern = wave.shoot_pattern_override
	# Behavior components (m6 §3): set before add_child so enemy_base._ready dupes them.
	if not wave.components_override.is_empty() and "components" in enemy:
		enemy.components = wave.components_override
	# Crosser height-stagger (P2 row choreography): a horizontal crosser (its
	# movement has a `travel_y`) rides a per-index latitude so a stream doesn't
	# overlap. Duplicate first so siblings don't share the mutated resource (the
	# formation-4 direction dup below preserves this via duplicate()).
	if "movement" in enemy and enemy.movement != null and "travel_y" in enemy.movement:
		var mv_cross: Resource = enemy.movement.duplicate()
		mv_cross.travel_y = _crosser_travel_y(mv_cross.travel_y, index)
		enemy.movement = mv_cross
	# STEP_WALL (P2d): stamp the shared synced-STEP params so the row steps in unison.
	# Duplicate per instance; the anchor lane comes from lane_override.
	if not step_sync.is_empty() and "movement" in enemy and enemy.movement != null \
			and "step_synced" in enemy.movement:
		var mv_sync: Resource = enemy.movement.duplicate()
		mv_sync.step_synced = true
		mv_sync.step_offset_lo = int(step_sync["lo"])
		mv_sync.step_offset_hi = int(step_sync["hi"])
		mv_sync.step_start_dir = int(step_sync["dir"])
		enemy.movement = mv_sync
	# Pattern-claimed intervals are step 1 (pattern owns its rhythm), wave
	# overrides win as step 2. Final precedence: wave > pattern > .tscn
	# default. Works regardless of how shoot_pattern landed on the enemy
	# (authored in .tscn vs assigned just above from wave_override).
	if "shoot_pattern" in enemy and enemy.shoot_pattern != null:
		if "fire_interval_min" in enemy.shoot_pattern \
				and enemy.shoot_pattern.fire_interval_min > 0.0 \
				and "fire_interval_min" in enemy:
			enemy.fire_interval_min = enemy.shoot_pattern.fire_interval_min
		if "fire_interval_max" in enemy.shoot_pattern \
				and enemy.shoot_pattern.fire_interval_max > 0.0 \
				and "fire_interval_max" in enemy:
			enemy.fire_interval_max = enemy.shoot_pattern.fire_interval_max
	if wave.fire_interval_min > 0.0 and "fire_interval_min" in enemy:
		enemy.fire_interval_min = wave.fire_interval_min
	if wave.fire_interval_max > 0.0 and "fire_interval_max" in enemy:
		enemy.fire_interval_max = wave.fire_interval_max
	if wave.max_health > 0 and "max_health" in enemy:
		enemy.max_health = wave.max_health
		if "health" in enemy:
			enemy.health = wave.max_health
	if wave.health_bonus > 0 and "max_health" in enemy:
		enemy.max_health += wave.health_bonus
		if "health" in enemy:
			enemy.health = enemy.max_health
	if wave.bounty_value > 0 and "bounty_value" in enemy:
		enemy.bounty_value = wave.bounty_value
	if wave.shield_charges > 0 and "max_shield" in enemy:
		enemy.max_shield = wave.shield_charges
		enemy.shield = wave.shield_charges
	if wave.recycle_passes >= -1 and "recycle_passes" in enemy:
		enemy.recycle_passes = wave.recycle_passes
	# Firecore Drone ring count — set before add_child() below (the drone
	# builds its rings in _ready()). Guarded so other enemies ignore it.
	if wave.ring_count_override >= 0 and "ring_count" in enemy:
		enemy.ring_count = wave.ring_count_override
	# Conducted enemies fire in the engagement band (bridge §1.8-1.9): hold fire
	# on entry, cease fire once low. Guarded so non-enemy_core types skip it.
	if "fire_zone_gated" in enemy:
		enemy.fire_zone_gated = true
	# Sector modifiers — applied last so they stack on top of wave overrides.
	var _run = get_node_or_null("/root/Run")
	if _run and "sector_modifiers" in _run and not _run.sector_modifiers.is_empty():
		_apply_sector_modifiers(enemy, _run.sector_modifiers)
	# M6b faction overlay: theme + modify every spawn with the level's faction (Shield /
	# firecore-drop / tough / fast-fire + tint). Applied BEFORE add_child so enemy_base
	# dups the attached components. Privateer sprinkles in as an interloper by chance.
	if _run != null and _run.has_meta("active_faction"):
		var pf: int = int(_run.get_meta("active_faction", -1))
		if pf >= 0:
			FactionsC.apply(FactionsC.effective_faction_for_spawn(pf), enemy)
	# Compute spawn x based on formation. Spawn x is confined to the
	# playfield band (Playfield.X_MIN..X_MAX), not the full viewport,
	# so the side gutters stay clear.
	# Lanes are the spawn-anchor grid (scripts/lanes.gd). A lane_override (from a
	# shaped formation) forces a specific lane; otherwise TOP formations (0-3) use
	# alternate-anchor selection and SIDE (4)/TANDEM (5) keep bespoke placement.
	var x := 0.0
	var pos: Vector2
	if lane_override >= 0:
		pos = Vector2(Lanes.lane_center(lane_override), wave.spawn_y)
	else:
		match wave.formation:
			5: # TOP_TANDEM_PAIRS — two streams in concert, ±tandem_offset_x from CENTER.
				var center: float = Playfield.CENTER.x
				var side: int = -1 if (index % 2) == 0 else 1
				x = center + float(side) * wave.tandem_offset_x
				pos = Vector2(x, wave.spawn_y)
			4: # SIDE_ALTERNATING — alternate sides per spawn; pattern direction matches.
				var side: int = 1 if (index % 2) == 0 else -1
				if side > 0:
					x = Playfield.X_MIN - 12.0
				else:
					x = Playfield.X_MAX + 12.0
				pos = Vector2(x, wave.spawn_y)
				# Per-instance direction override; duplicate so siblings don't share.
				if "movement" in enemy and enemy.movement != null and "direction" in enemy.movement:
					var mv_dup: Resource = enemy.movement.duplicate()
					mv_dup.direction = side
					enemy.movement = mv_dup
			_: # TOP formations (0-3) -> alternate-anchor lane placement
				var lane: int = _pick_lane()
				pos = Vector2(Lanes.lane_center(lane), wave.spawn_y)
	# Make the enemy a child of our parent (typically Main) so it lives in the world
	var parent = get_parent()
	parent.add_child(enemy)
	enemy.add_to_group("enemies")
	# Per-instance wave context (e.g. gunship role assignment). Called before
	# start() so the enemy can adjust its settle position before entering.
	if enemy.has_method("on_spawned_in_wave"):
		enemy.on_spawned_in_wave(index, wave.count)
	if enemy.has_method("start"):
		enemy.start(pos)
	elif enemy.has_method("spawn"):
		enemy.spawn(pos)
	else:
		enemy.position = pos
	var scene_path: String = ""
	if wave.enemy_scene:
		scene_path = wave.enemy_scene.resource_path
	var bounty_val: int = 0
	if "bounty_value" in enemy:
		bounty_val = enemy.bounty_value
	enemy_spawned.emit(scene_path, bounty_val)
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died.bind(scene_path))

func _on_enemy_died(value: int, scene_path: String) -> void:
	enemy_died.emit(value, scene_path)


func _apply_sector_modifiers(enemy: Node, modifiers: Array) -> void:
	for mod in modifiers:
		match mod:
			"shielded":
				if "max_shield" in enemy:
					if enemy.max_shield == 0:
						enemy.max_shield = 1
						if "shield" in enemy:
							enemy.shield = 1
					else:
						var boosted := ceilf(enemy.max_shield * 1.5)
						enemy.max_shield = int(boosted)
						if "shield" in enemy:
							enemy.shield = int(boosted)
			"armored":
				if "damage_reduction" in enemy:
					enemy.damage_reduction = max(enemy.damage_reduction, 0.10)
			"heavily_armored":
				if "damage_reduction" in enemy:
					enemy.damage_reduction = max(enemy.damage_reduction, 0.20)
			"aggressive":
				if enemy.has_node("ShootTimer"):
					var st: Timer = enemy.get_node("ShootTimer")
					st.wait_time = max(0.05, st.wait_time * 0.90)
			"wanted":
				if "bounty_value" in enemy:
					enemy.bounty_value = int(enemy.bounty_value * 1.20)
			"fleeing":
				if "recycle_passes" in enemy:
					enemy.recycle_passes = 0

func _process(_delta: float) -> void:
	if _check_clear:
		if not _live_combatants_present() and not _hazards_present():
			_check_clear = false
			level_cleared.emit()


# True if any "enemies"-group node is alive AND not flagged is_hazard.
# When ignore_recycling is true, also skip enemies reporting is_recycling()
# (used by the wave-ADVANCE gate so a lone recycler doesn't stall the next
# wave). The level-clear gate calls with the default (false) → stays strict.
# Mines / bomblets / asteroids dropped behind a minelayer don't gate
# wave progression (Cody, 2026-05-18 playtest).
func _live_combatants_present(ignore_recycling: bool = false) -> bool:
	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n):
			continue
		if "is_hazard" in n and n.is_hazard:
			continue
		if ignore_recycling and n.has_method("is_recycling") and n.is_recycling():
			continue
		return true
	return false

func _hazards_present() -> bool:
	for n in get_tree().get_nodes_in_group("enemies"):
		if "is_hazard" in n and n.is_hazard:
			return true
	return false

func _ready() -> void:
	if auto_start and level != null:
		start_level()
