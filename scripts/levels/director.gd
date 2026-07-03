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
const ShieldComponentC = preload("res://scripts/enemies/components/shield_component.gd")
const LaneTraffic = preload("res://scripts/systems/lane_traffic.gd")
const LanePathC = preload("res://scripts/enemies/patterns/lane_path.gd")
const FormationShapes = preload("res://scripts/levels/formation_shapes.gd")

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
# Anchor (cruiser) lane-gapping (Roman 2026-06-11): a descending cruiser is held a
# full enemy-length above any cruiser already in its lane OR an adjacent lane, so
# neighbours are clear / fully-passed on arrival instead of globbing. Only enemies
# taller than ANCHOR_MIN_HEIGHT count as cruisers for this gate.
const ANCHOR_MIN_HEIGHT: float = 40.0
const ANCHOR_GAP_PAD: float = 8.0
# GEOMETRIC formation dispatch (conductor readability pass, 2026-06-23): a generator-rolled shape
# (formation_shapes.gd) is performed as a held burst. Rows are PRE-STACKED above the top edge (shared
# formation_shapes.prestack_y / ROW_GAP) so the painted shape descends in intact; members spawn on a
# near-simultaneous stagger so a whole shape lands as one gesture, not a trickle.
const GEOMETRIC_MEMBER_STAGGER: float = 0.03
# Burst-fit ceiling (fairness fix, 2026-07-02): an intentional pre-stacked burst (authored /
# geometric) may exceed the clarity cap so its shape lands intact, but NOT without bound — an
# unclamped raise let a 21-33-member injected wall stack on top of a saturated 36-cap climax
# (conductor review §2.1). The burst-fit cap is raised at most this many slots above max_concurrent,
# and the whole formation is gated to fit under that ceiling BEFORE the first member spawns (so a
# lockstep formation enters coherent instead of shearing mid-spawn while it waits for room).
const BURST_OVERSHOOT: int = 8
# Hard cap on how long a burst waits for cap headroom before spawning anyway — so a held/stuck
# screen (nothing dying) can never deadlock the wave on the pre-gate.
const BURST_HEADROOM_TIMEOUT: float = 6.0
# SWEEP rows (2026-06-27): a directional sweep (left_to_right / right_to_left — the START/MIDDLE
# bulk) used to spawn ONE enemy per spawn_interval on a side-alternating _pick_lane, reading as
# "single enemies trickling in on random lanes". It now enters as ROWS of this many abreast (a
# readable descending line), beat-separated, so the bulk reads as formations while still streaming
# under the concurrency cap. Hazard scatter (random/top_spread) + heavy anchors (center_out) keep
# the one-at-a-time path on purpose. The structured lanes DON'T avoid occupancy the way _pick_lane
# did, so each row is gated on the previous one descending SWEEP_ROW_CLEAR_DEPTH out of the spawn
# zone (capped by SWEEP_ROW_TIMEOUT) — otherwise rows pile up at the top instead of descending apart.
const SWEEP_ROW_SIZE: int = 4
const SWEEP_ROW_CLEAR_DEPTH: float = 36.0
const SWEEP_ROW_TIMEOUT: float = 1.6
# Staggered arrival for LARGE enemies (height >= ANCHOR_MIN_HEIGHT): in a spread formation
# (e.g. lanes 1/3/5) the next lane's enemy does not arrive until the previous one has
# descended ANCHOR_ARRIVAL_DEPTH (≈ half its body in the playfield) — so cruisers like the
# Push trickle in one-at-a-time instead of popping in together (Roman 2026-06-14). Depth-gated
# (robust to movement speed), with a hard timeout so a non-descending unit never blocks a wave.
const ANCHOR_ARRIVAL_DEPTH: float = 32.0
const ARRIVAL_DEPTH_TIMEOUT: float = 2.5
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
# Seeded dispatch RNG — lane / wall-gap / filler placement picks draw from this so a
# same-seed run reproduces PLACEMENT, not just wave content. Seeded per combat node in
# start_score (a stream distinct from the producer's content seed). (Health audit 2026-06-15.)
var _rng := RandomNumberGenerator.new()

# BOSS GATE (Roman 2026-07-01): when a persistent boss registers here (main.gd wires it on the
# battleship level), the director runs DISCRETE waves — it drains the current wave, then awaits ONE
# boss maneuver before starting the next. Null on every other level, so the normal streaming pacing
# (no per-wave clear-gate) is completely untouched.
var boss_gate: Node = null
const BOSS_GATE_DRAIN_TIMEOUT: float = 15.0   # safety cap (s) so a stuck/lingering enemy can't hang the gate

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
	_seed_dispatch_rng()
	# Opening grace: let the player settle after the slide-in before waves come.
	if start_grace > 0.0:
		await get_tree().create_timer(start_grace).timeout
		if not _running:
			return
	_advance_step()

func stop() -> void:
	_running = false
	_check_clear = false


# Seed the dispatch RNG from run_seed + the current node identity so placement (lanes, wall
# gaps, filler picks) reproduces per run+node — a stream distinct from the producer's content
# seed. run_seed 0 (headless tools) stays deterministic. (Health audit 2026-06-15.)
func _seed_dispatch_rng() -> void:
	var run = get_node_or_null("/root/Run")
	var rs: int = int(run.run_seed) if run != null and "run_seed" in run else 0
	var nid: String = String(run.current_node_id) if run != null and "current_node_id" in run else ""
	var sec: int = int(run.sectors_cleared) if run != null and "sectors_cleared" in run else 0
	_rng.seed = (rs * 2654435761) ^ (hash(nid) * 40503) ^ (sec * 100003) ^ 0x9E3779B9


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
				"slot_cap": (int(w.slot_cap) if "slot_cap" in w else -1),
			})
	return out


# Count of live "enemies"-group bodies on screen — the concurrency-cap measure. Includes
# recyclers AND hazards: mines/asteroids are conducted like enemies now (Roman 2026-06-23) —
# cap-throttled so a field STREAMS at a navigable peak, and their breathers can wait for the
# field to thin (the density ebb). (Was: hazards excluded as uncapped "terrain" in v1 — that
# let asteroid/mine fields pile into an impassable wall.)
# EXCLUDES a gating boss + its parts (Roman 2026-07-01): a persistent boss like the battleship lives in
# "enemies" from wave 1, but the boss + its ~26 turret/laser parts must NOT eat concurrency slots (27 >
# max_concurrent would spin-lock the dispatchers forever → no wave ever spawns). The boss gates clear via
# _live_combatants_present, not this cap.
func _alive_count() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or _is_boss_gate_node(e):
			continue
		n += 1
	return n


# Sum of live enemies' slot footprints — the slot-WEIGHTED density measure (level_structure_redesign_
# 2026-07-01). max_concurrent is now a SLOT cap: a wall of small chaff (weight 1) can pack to it while
# a few cruisers (weight 9) fill it. Hazards weigh 1 (their fields stay count-tuned), so an asteroid
# field's slot sum == its headcount and its existing count-cap is unchanged. Excludes the boss gate,
# like _alive_count.
func _alive_slots() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or _is_boss_gate_node(e):
			continue
		n += (int(e.slot_weight) if "slot_weight" in e else 1)
	return n


# Lane selection for TOP spawns (conductor v2): alternate-anchor — prefer the
# side opposite the previous spawn (Toaplan rhythm, composition guide §3),
# among lanes not currently occupied near the entry band so the stream spreads
# across the 7 lanes and forces player movement.
func _pick_lane(clear_neighbours: bool = false, check_y: float = 0.0, height: float = 0.0) -> int:
	var occupied: Array = _occupied_lanes()
	var candidates: Array = []
	for i in Lanes.COUNT:
		if not occupied.has(i):
			candidates.append(i)
	if candidates.is_empty():
		for i in Lanes.COUNT:
			candidates.append(i)
	# Supremacy Push Gap 2 (Roman 2026-06-11): a big cruiser prefers a lane whose
	# ADJACENT lanes are ALSO clear (full-column check via lane_traffic), so it arrives
	# with its neighbours open instead of being passively vertical-queued behind one.
	if clear_neighbours:
		var win: float = maxf(28.0, height * 0.6)
		var spread: Array = candidates.filter(func(i):
			var here: bool = LaneTraffic.is_lane_free(get_tree(), i, check_y, null, win)
			var left_ok: bool = i == 0 or LaneTraffic.is_lane_free(get_tree(), i - 1, check_y, null, win)
			var right_ok: bool = i == Lanes.COUNT - 1 or LaneTraffic.is_lane_free(get_tree(), i + 1, check_y, null, win)
			return here and left_ok and right_ok)
		if not spread.is_empty():
			candidates = spread
	if _last_lane >= 0:
		var want_high: bool = _last_lane < Lanes.COUNT / 2
		var side: Array = candidates.filter(
			func(i): return (i >= Lanes.COUNT / 2) == want_high)
		if not side.is_empty():
			candidates = side
	var pick: int = candidates[_rng.randi() % candidates.size()]
	_last_lane = pick
	return pick


# Staggered travel-y for the index-th crosser in a dispatch (P2 row choreography):
# spread across CROSSER_STAGGER_BANDS latitudes so consecutive crossers (and
# opposite-direction siblings) ride different heights instead of overlapping.
func _crosser_travel_y(base: float, index: int, step: float = CROSSER_STAGGER_STEP) -> float:
	return base + float(index % CROSSER_STAGGER_BANDS) * step


# Lanes currently holding an enemy/hazard in the top entry band, so a fresh spawn doesn't
# stack onto one — hazards included (2026-06-23) so asteroids spread across lanes on entry.
func _occupied_lanes() -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node2D) or _is_boss_gate_node(e):
			continue
		if e.position.y <= 40.0:
			var ln: int = Lanes.nearest_lane(e.position.x)
			if not out.has(ln):
				out.append(ln)
	return out

# Vertical extent of an enemy from its first RectangleShape2D collision (× scale).
# Used to tell "cruiser" (tall) from chaff and to size the lane-gap.
func _enemy_height(e) -> float:
	var scale_y: float = float(e.display_scale) if (e != null and "display_scale" in e) else 1.0
	var shape := _first_rect_shape(e)
	if shape != null:
		return shape.size.y * scale_y
	return 16.0

func _first_rect_shape(n: Node) -> RectangleShape2D:
	for c in n.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is RectangleShape2D:
			return (c as CollisionShape2D).shape as RectangleShape2D
		var deep := _first_rect_shape(c)
		if deep != null:
			return deep
	return null


# Raise a cruiser's spawn y so it sits at least one full enemy-length above any
# cruiser already in its lane or an adjacent lane — descending later, so neighbours
# never glob. Reads live positions (start() sets them synchronously), so it gates
# both same-dispatch siblings and cruisers lingering from earlier waves.
func _anchor_stagger_y(lane: int, base_y: float, height: float) -> float:
	var gap: float = height + ANCHOR_GAP_PAD
	var sy: float = base_y
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node2D) or _is_boss_gate_node(e):
			continue
		if "is_hazard" in e and e.is_hazard:
			continue
		if _enemy_height(e) < ANCHOR_MIN_HEIGHT:
			continue   # only other cruisers gate us
		if absi(Lanes.nearest_lane(e.position.x) - lane) > 1:
			continue   # same + adjacent lanes only
		sy = minf(sy, e.position.y - gap)
	return sy


func _advance_step() -> void:
	_step_idx += 1
	if _step_idx >= _steps.size():
		# All authored phrases dispatched (the "survive the waves" win). If a live boss is still gating,
		# give it ONE final maneuver over the drained field then have it retreat — it frees itself, so
		# the clear-watch below fires once it's gone. A boss already defeated mid-fight is a no-op.
		if _boss_gate_alive() and not _boss_defeated():
			await _drain_for_gate()
			if _boss_gate_alive() and not _boss_defeated() and boss_gate.has_method("play_wave_maneuver"):
				await boss_gate.play_wave_maneuver(-1)
			if _boss_gate_alive() and not _boss_defeated() and boss_gate.has_method("retreat"):
				boss_gate.retreat()
		_running = false
		_check_clear = true   # all phrases dispatched; watch for clear
		return
	var st: Dictionary = _steps[_step_idx]
	# BOSS GATE (Roman 2026-07-01): before starting a NEW wave (every wave after the first), wait for
	# the current wave to CLEAR, then let the boss play one maneuver — the next wave is held until it
	# finishes. Opt-in via boss_gate; no-op on normal levels.
	if st["is_wave_start"] and int(st["wave_idx"]) >= 1 and _boss_gate_alive():
		await _drain_for_gate()
		if not _running:
			return
		if _boss_gate_alive() and not _boss_defeated() and boss_gate.has_method("play_wave_maneuver"):
			await boss_gate.play_wave_maneuver(int(st["wave_idx"]))
		if not _running:
			return
		# If the player destroyed every part during that maneuver, the fight is WON (the "parts" exit) —
		# stop spawning the remaining waves; the boss's death animation + drain trip the clear-watch.
		if _boss_defeated():
			_running = false
			_check_clear = true
			return
	# Non-blocking banner once per ScoreWave (bridge §1.1): emit and keep going.
	if st["is_wave_start"]:
		# Per-stretch density ramp (level_structure_redesign_2026-07-01): a stretch-opening wave sets
		# the slot cap (16/26/36) for its section. -1 leaves it (hazards / non-stretch content).
		if int(st.get("slot_cap", -1)) >= 0:
			max_concurrent = int(st["slot_cap"])
		wave_started.emit(int(st["wave_idx"]), _wave_total, false, String(st["banner"]))
		# Let a gating boss know a wave began (it enables stage hazards from wave 3 = wave_idx 2).
		if _boss_gate_alive() and boss_gate.has_method("on_wave_started"):
			boss_gate.on_wave_started(int(st["wave_idx"]))
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
	# AUTHORED: an explicit lane layout from the wave pattern editor — each spec is a single
	# enemy pinned to spec.lane, entering at spec.spawn_delay (row * stagger). Spawned at exact
	# lanes in ascending-delay order.
	if ph.shape == &"authored":
		await _dispatch_authored(ph)
		_advance_step()
		return
	# GEOMETRIC: a generator-rolled held shape (vee/chevron/diamond/echelon/columns). The homogeneous
	# count-N spec is exploded across the shape's lane/row grid and burst in pre-stacked rows, so it
	# reads as a formation instead of the random-spread trickle below.
	if FormationShapes.is_geometric(ph.shape):
		await _dispatch_geometric(ph)
		_advance_step()
		return
	# SWEEP: a directional sweep (the START/MIDDLE bulk) enters as readable ROWS abreast instead of
	# one-at-a-time scattered singles — the real fix for the "single enemies on random lanes" trickle
	# (the generator only controls counts; the trickle was this dispatch). Hazard scatter + heavy
	# anchors deliberately skip this.
	if ph.shape == &"left_to_right" or ph.shape == &"right_to_left":
		await _dispatch_sweep_rows(ph)
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
			while _running and _alive_slots() >= max_concurrent:
				await get_tree().create_timer(0.1).timeout
			if not _running:
				return
			var spawned: Node = _spawn_enemy(sp, i)
			i += 1
			# Tandem partner on the same tick (formation 5), mirrored X.
			if sp.formation == 5 and i < sp.count and (i % 2) == 1:
				_spawn_enemy(sp, i)
				i += 1
			# Arrival cadence: a LARGE enemy holds the next lane until it's ~half in
			# (descended ANCHOR_ARRIVAL_DEPTH), so multi-lane cruisers stagger in instead
			# of arriving together. Everything else keeps the spec's spawn_interval.
			if is_instance_valid(spawned) and spawned is Node2D and _enemy_height(spawned) >= ANCHOR_MIN_HEIGHT:
				await _await_arrival_depth(spawned as Node2D)
			else:
				await get_tree().create_timer(maxf(sp.spawn_interval, ANTI_BURST_FLOOR)).timeout
	_advance_step()


# SWEEP rows: spawn a directional-sweep spec as descending ROWS of SWEEP_ROW_SIZE abreast on spread
# lanes (the gap interleaves between rows), a beat between rows, cap-gated — so the START/MIDDLE bulk
# reads as readable lines instead of one-at-a-time scattered singles. Caller calls _advance_step().
func _dispatch_sweep_rows(ph: Resource) -> void:
	for sp in ph.specs:
		if sp == null:
			continue
		var i: int = 0
		var row_index: int = 0
		while i < sp.count:
			if not _running:
				return
			while _running and _alive_slots() >= max_concurrent:
				await get_tree().create_timer(0.1).timeout
			if not _running:
				return
			# Size this row to the remaining count AND the cap headroom, so a row never overshoots the
			# clarity cap by much. At least 1 so we always make progress.
			var room: int = maxi(1, max_concurrent - _alive_slots())
			var group: int = mini(mini(SWEEP_ROW_SIZE, room), sp.count - i)
			var last_spawned: Node = null
			for ln in _sweep_row_lanes(group, row_index):
				if i >= sp.count:
					break
				last_spawned = _spawn_enemy(sp, i, int(ln))
				i += 1
			row_index += 1
			# Gate the next row on THIS row clearing the spawn zone so rows descend SEPARATED (the
			# structured lanes don't avoid occupancy the way _pick_lane did, so without this they stack).
			if i < sp.count:
				await _await_row_clear(last_spawned, sp.spawn_interval)


# Wait at least `min_beat`, AND until `enemy` has descended SWEEP_ROW_CLEAR_DEPTH (so the row clears
# the spawn zone before the next), capped at SWEEP_ROW_TIMEOUT so a held/dead row can't stall the
# wave. `enemy` may be null/freed — then only `min_beat` applies. Adaptive: fast chaff clear quickly
# (rhythm = the beat), slow chaff wait longer (so they never pile up).
func _await_row_clear(enemy, min_beat: float) -> void:
	var floor_beat: float = maxf(min_beat, ANTI_BURST_FLOOR)
	# is_instance_valid FIRST so it short-circuits before `is Node2D` — `is` THROWS on a freed
	# instance, and the awaited row-lead can be killed mid-sweep before the next row spawns.
	var start_y: float = (enemy.position.y if (is_instance_valid(enemy) and enemy is Node2D) else 0.0)
	var t: float = 0.0
	while _running and t < SWEEP_ROW_TIMEOUT:
		await get_tree().create_timer(0.05).timeout
		t += 0.05
		var cleared: bool = (not is_instance_valid(enemy)) or (not (enemy is Node2D)) \
			or (enemy.position.y - start_y >= SWEEP_ROW_CLEAR_DEPTH)
		if t >= floor_beat and cleared:
			return


# Distinct, spread lane set for a sweep row: evenly spaces `n` lanes across the grid with a half-step
# offset on alternate rows, so successive rows interleave (the gaps shift) into a readable weave.
func _sweep_row_lanes(n: int, row_index: int) -> Array:
	n = clampi(n, 1, Lanes.COUNT)
	var lanes: Array = []
	var step: float = float(Lanes.COUNT) / float(n)
	var off: float = step * 0.5 * float(row_index % 2)
	for k in n:
		var ln: int = clampi(int(floor(off + (float(k) + 0.5) * step)), 0, Lanes.COUNT - 1)
		if not lanes.has(ln):
			lanes.append(ln)
	var p: int = 0   # top up to n distinct lanes if rounding collided
	while lanes.size() < n and p < Lanes.COUNT:
		if not lanes.has(p):
			lanes.append(p)
		p += 1
	return lanes


# Block until `enemy` has descended ANCHOR_ARRIVAL_DEPTH past its spawn Y (≈ half its body
# into the playfield), so the next lane of a multi-lane large formation arrives staggered.
# Depth-gated so it's robust to movement speed; hard timeout so a stalled/non-descending
# unit can never block the wave indefinitely.
func _await_arrival_depth(enemy: Node2D) -> void:
	var start_y: float = enemy.position.y
	var elapsed: float = 0.0
	while _running and is_instance_valid(enemy) and elapsed < ARRIVAL_DEPTH_TIMEOUT:
		if enemy.position.y - start_y >= ANCHOR_ARRIVAL_DEPTH:
			return
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05


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
	var lanes: Array = _pincer_lanes(members.size())
	for idx in members.size():
		if not _running:
			return
		while _running and _alive_slots() >= max_concurrent:
			await get_tree().create_timer(0.1).timeout
		if not _running:
			return
		_spawn_enemy(members[idx], idx, int(lanes[idx]))
		await get_tree().create_timer(0.06).timeout


# AUTHORED: an explicitly laid-out formation (wave pattern editor). Each spec is one enemy pinned
# to spec.lane, entering at spec.spawn_delay (= row * stagger from the editor). Spawn in
# ascending-delay order at exact lanes (lane_override), cap-gated like the other shapes. A spec
# with lane < 0 falls back to _spawn_enemy's algorithmic placement.
func _dispatch_authored(ph: Resource) -> void:
	var specs: Array = []
	for sp in ph.specs:
		if sp != null:
			specs.append(sp)
	if specs.is_empty():
		return
	specs.sort_custom(func(a, b): return float(a.spawn_delay) < float(b.spawn_delay))
	# An authored formation is an EXPLICIT count — the author placed exactly these enemies and
	# expects them all on screen on their authored schedule. The standard max_concurrent gate is a
	# clarity throttle for ALGORITHMIC waves; applying it here partially dropped large formations and
	# staggered same-row enemies that should burst together (Roman 2026-06-17). Raise the gate to fit
	# the whole formation on top of whatever's already alive, so the authored layout lands intact —
	# but CEILED (fairness fix 2026-07-02): the raise never exceeds max_concurrent + BURST_OVERSHOOT,
	# and we wait for that headroom BEFORE the first member so the burst doesn't shear mid-formation
	# on a saturated screen.
	await _await_burst_headroom(specs.size())
	if not _running:
		return
	var authored_cap: int = _burst_cap(specs.size())
	var elapsed: float = 0.0
	for sp in specs:
		if not _running:
			return
		var wait: float = maxf(0.0, float(sp.spawn_delay) - elapsed)
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout
			elapsed += wait
			if not _running:
				return
		while _running and _alive_slots() >= authored_cap:
			await get_tree().create_timer(0.1).timeout
		if not _running:
			return
		_spawn_enemy(sp, 0, int(sp.lane))


# GEOMETRIC: perform a generator-rolled held shape (formation_shapes.gd). The phrase's specs are
# homogeneous (one enemy type, count each); we explode the TOTAL across the shape's lane/row cells,
# PRE-STACK each row above the top edge (bottom row leads, higher rows trail one shared ROW_GAP up)
# and burst them so the shape paints in as it descends — the same technique as _dispatch_authored.
# Members are one enemy type → identical chassis speed → the shape holds without an explicit
# lockstep clamp (that clamp matters only for MIXED-speed formations, which the authored path and
# any future escort/native-mixed path own via formation_shapes.lock_to_slowest).
func _dispatch_geometric(ph: Resource) -> void:
	var base: Resource = null
	var total: int = 0
	for sp in ph.specs:
		if sp == null:
			continue
		if base == null:
			base = sp
		total += int(sp.count)
	if base == null or total <= 0:
		return
	var cells: Array = FormationShapes.placements(ph.shape, total)
	if cells.is_empty():
		return
	# Tallest row sets the pre-stack height (row 0 enters at the edge; each row up adds a gap).
	var max_row: int = 0
	for c in cells:
		max_row = maxi(max_row, int(c.y))
	# Explode into count-1 sub-specs, each pinned to its cell's lane + pre-stacked spawn_y. Duplicate
	# the base spec so per-spawn fields (lane/spawn_y) don't stomp the shared spec; movement_override
	# and the other Resource refs ride through shared, exactly as a single count-N wave already shares
	# them across its members (no new per-instance state — see _spawn_enemy's per-instance dups).
	var specs: Array = []
	for c in cells:
		var s: Resource = base.duplicate()
		s.count = 1
		s.lane = clampi(int(c.x), 0, Lanes.COUNT - 1)
		# Shared pre-stack row math (formation_shapes.prestack_y): row == max_row enters at the top edge,
		# each row up trails one ROW_GAP higher (dedup, conductor review §3).
		s.spawn_y = FormationShapes.prestack_y(int(c.y), max_row)
		specs.append(s)
	# An explicit shape is an intentional burst (like authored): raise the gate to fit the whole
	# formation on top of whatever's already alive so the clarity cap can't partially drop it —
	# CEILED to max_concurrent + BURST_OVERSHOOT, with a whole-formation pre-gate, so it can't stack
	# an unbounded wall on a saturated screen (fairness fix 2026-07-02; see _dispatch_authored).
	await _await_burst_headroom(specs.size())
	if not _running:
		return
	var cap: int = _burst_cap(specs.size())
	for s in specs:
		if not _running:
			return
		while _running and _alive_slots() >= cap:
			await get_tree().create_timer(0.1).timeout
		if not _running:
			return
		_spawn_enemy(s, 0, int(s.lane))
		await get_tree().create_timer(GEOMETRIC_MEMBER_STAGGER).timeout


# Ceiled burst-fit cap for an intentional pre-stacked formation of `member_count`: fit it on top of
# whatever's alive (est. up to 4 slots/member so same-row bursts aren't throttled), but never raise
# more than BURST_OVERSHOOT above the clarity cap. Always >= max_concurrent so a burst is never
# throttled BELOW the normal streaming rate.
func _burst_cap(member_count: int) -> int:
	var want: int = _alive_slots() + member_count * 4
	return maxi(max_concurrent, mini(want, max_concurrent + BURST_OVERSHOOT))


# Gate a burst until the WHOLE formation fits under the ceiling (max_concurrent + BURST_OVERSHOOT),
# so a pre-stacked / lockstep formation enters coherent instead of shearing while it stalls
# mid-spawn on a saturated screen. `member_count` is used as the slot estimate (authored members are
# overwhelmingly 1-slot smalls; mediums under-estimate slightly and eat into the overshoot budget).
# A formation too big to ever fit (target < 0 — dev-forced walls on a low cap) waits for the screen
# to drain as far as it will, then the timeout releases it and it streams under _burst_cap.
# Hard-timeout either way so a held/stuck screen can't deadlock the wave.
func _await_burst_headroom(member_count: int) -> void:
	var ceiling: int = max_concurrent + BURST_OVERSHOOT
	# Room for the whole formation: alive must drop far enough that alive + member_count <= ceiling.
	var target: int = ceiling - member_count
	var elapsed: float = 0.0
	while _running and _alive_slots() > target and elapsed < BURST_HEADROOM_TIMEOUT:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1


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
		while _running and _alive_slots() >= max_concurrent:
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
# NOTE (review): DEV-ONLY live — only the Lane Visualizer emits Formation.STEP_WALL;
# wave_generator caps forced formations at PINCER, so production never reaches this path
# yet. The synced-STEP machinery (lane_path STEP group + _synced_offset) is ready for a
# producer to author step walls when wanted.
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
	while _running and _alive_slots() >= max_concurrent:
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
	var left_block: bool = _rng.randf() < 0.5
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
	# Seeded shuffle off the dispatch RNG (reproducible placement); shared impl (dedup, review §3).
	FormationShapes.fisher_yates(pool, _rng)
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


# Lane layout for a pincer formation of n members: alternate inward from both edges
# (0, 6, 1, 5, 2, 4, 3 ...), wrapping if n exceeds the lane count. (Wall + spread
# formations have their own dispatch paths — _dispatch_wall / the default spread — so
# this is only ever called for pincer.)
func _pincer_lanes(n: int) -> Array:
	var out: Array = []
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
		while _running and _alive_slots() >= max_concurrent:
			await get_tree().create_timer(0.1).timeout
			elapsed += 0.1
		if not _running:
			return
		var sp: Resource = ph.pool[_rng.randi() % ph.pool.size()]
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


func _spawn_enemy(wave: Resource, index: int, lane_override: int = -1, step_sync: Dictionary = {}) -> Node:
	if wave.enemy_scene == null:
		push_warning("WaveDirector: spec has no enemy_scene")
		return null
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
	# Hazard drift mode (asteroid/mine/firecore) — set before add_child so the hazard's _ready builds
	# the LateralDrift in the right mode. Guarded `in` check: non-hazard enemies have no drift_mode.
	if "drift_mode" in wave and String(wave.drift_mode) != "" and "drift_mode" in enemy:
		enemy.drift_mode = String(wave.drift_mode)
	if wave.movement_override != null and "movement" in enemy:
		enemy.movement = wave.movement_override
	if wave.shoot_pattern_override != null and "shoot_pattern" in enemy:
		enemy.shoot_pattern = wave.shoot_pattern_override
	# Behavior components (m6 §3): set before add_child so enemy_base._ready dupes them.
	if not wave.components_override.is_empty() and "components" in enemy:
		enemy.components = wave.components_override
	# Firing mounts: set before add_child so enemy_base._attach_mounts realizes them in _ready.
	if "mounts_override" in wave and not wave.mounts_override.is_empty() and "mounts" in enemy:
		enemy.mounts = wave.mounts_override
	# Crosser height-stagger (P2 row choreography): a horizontal crosser (its
	# movement has a `travel_y`) rides a per-index latitude so a stream doesn't
	# overlap. Duplicate first so siblings don't share the mutated resource (the
	# formation-4 direction dup below preserves this via duplicate()).
	if "movement" in enemy and enemy.movement != null and "travel_y" in enemy.movement:
		var mv_cross: Resource = enemy.movement.duplicate()
		# Large anchor-class crossers (cruisers, ~63px) need a height-aware latitude gap
		# so two horizontally-crossing cruisers don't ride 26px-apart bands and overlap
		# (Roman 2026-06-11 push-glob fix — the descent variant already gets this via
		# _anchor_stagger_y; this closes the side_traverse gap). Chaff keeps the tight 26px.
		var cross_step: float = CROSSER_STAGGER_STEP
		var h_cross: float = _enemy_height(enemy)
		if h_cross >= ANCHOR_MIN_HEIGHT:
			cross_step = h_cross + ANCHOR_GAP_PAD
		# Depth axis (locomotion refactor 2026-06-19): a resolved enemy/formation depth sets the
		# CROSS latitude — the per-index stagger then spreads around it so a row crosses at the
		# chosen depth without overlapping. No depth → the pattern's own travel_y default.
		var base_ty: float = mv_cross.travel_y
		if "depth_override" in wave and wave.depth_override >= 0.0:
			base_ty = Zones.y_for_progress(wave.depth_override)
		mv_cross.travel_y = _crosser_travel_y(base_ty, index, cross_step)
		enemy.movement = mv_cross
	# STEP_WALL (P2d): stamp the shared synced-STEP params so the row steps in unison.
	# Duplicate per instance; the anchor lane comes from lane_override.
	if not step_sync.is_empty() and "movement" in enemy and enemy.movement != null \
			and "step_synced" in enemy.movement:
		var mv_sync: Resource = enemy.movement.duplicate()
		# Force the synced-step branch. The dispatch previously stamped step_synced/offsets but
		# never the shape, so a real step_wall wave kept the entry's own shape (WEAVE/HOOK/…) and
		# the synced-step locomotion never engaged — only hand-built Shape.STEP resources worked.
		mv_sync.shape = LanePathC.Shape.STEP
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
	# wave.shield_charges is applied below as a ShieldComponent (after the faction overlay),
	# not the retired simple max_shield (shield_unification_2026-06-08.md).
	if wave.recycle_passes >= -1 and "recycle_passes" in enemy:
		enemy.recycle_passes = wave.recycle_passes
	# Locomotion (locomotion refactor 2026-06-19): apply the resolved chassis stats to the
	# instance (movement patterns read these for SCALE). Guarded `in` checks so hazards without
	# the stat block skip. depth_override (formation or roster default) sets the enemy default.
	# (The +5%/sector locomotion ramp was dropped 2026-06-23 with the single-sector switch.)
	if wave.move_speed > 0.0 and "move_speed" in enemy:
		enemy.move_speed = wave.move_speed
	if wave.weight > 0.0 and "weight" in enemy:
		enemy.weight = wave.weight
	if wave.turn_rate > 0.0 and "turn_rate" in enemy:
		enemy.turn_rate = wave.turn_rate
	if wave.accel > 0.0 and "accel" in enemy:
		enemy.accel = wave.accel
	if wave.depth_override >= 0.0 and "depth_bp" in enemy:
		enemy.depth_bp = wave.depth_override
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
			# Faction projectile-appearance facet (2026-06-20): stamp the level faction on EVERY
			# spawn (universals included — the whole point) so family-tagged bullets resolve to
			# this faction's styled variant at fire time (shoot_pattern._spawn_bullet).
			enemy.set_meta("faction_skin", pf)
			# Apply the LEVEL faction; FactionsC.apply only overlays units whose home IS that
			# faction (Roman 2026-06-08), so bonuses never leak onto universals / other-faction
			# units in the level. (Dropped the privateer-interloper re-theme — it re-themed
			# arbitrary spawns, which contradicts faction-scoped bonuses.)
			FactionsC.apply(pf, enemy)
		# Faction livery (2026-06-20): recolor the enemy's Livery layer to the LEVEL faction.
		# Unlike apply(), this is NOT home-gated — every unit with a "Livery" node wears the
		# level's colors (Roman's runtime auto-detect decision). pf < 0 hides the layer.
		FactionsC.apply_livery(pf, enemy)
		# Faction tail-glow (2026-06-21): tint a "TailGunGlow" layer to the faction's bullet color
		# (privateer lime-green, corpo purple-pink…). pf < 0 leaves the baked glow.
		FactionsC.apply_tailglow(pf, enemy)
	else:
		# No faction context (hazard node / dev launch) — hide the Livery layer so it doesn't
		# render an untinted overlay on the body.
		FactionsC.apply_livery(-1, enemy)
	# Data-driven shields (shield_unification_2026-06-08.md): roster "shielded" tag +
	# sector "shielded" modifier both produce a ShieldComponent. Done AFTER the faction
	# overlay so a sector boost lands on an existing corporate component instead of
	# stacking a parallel shield. Before add_child so _init_components dups it.
	_resolve_shields(enemy, wave, _run)
	# Compute spawn x based on formation. Spawn x is confined to the
	# playfield band (Playfield.X_MIN..X_MAX), not the full viewport,
	# so the side gutters stay clear.
	# Lanes are the spawn-anchor grid (scripts/lanes.gd). A lane_override (from a
	# shaped formation) forces a specific lane; otherwise TOP formations (0-3) use
	# alternate-anchor selection and SIDE (4)/TANDEM (5) keep bespoke placement.
	var x := 0.0
	var pos: Vector2
	if lane_override >= 0:
		var lane_x: float = Lanes.lane_center(lane_override)
		if "spawn_x_offset" in wave:
			lane_x += wave.spawn_x_offset   # sub-lane offset (Formation Builder sub-grid); 0 default
		pos = Vector2(lane_x, wave.spawn_y)
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
				# Cruisers (tall anchors) don't glob: pick a lane whose neighbours are
				# clear (Gap 2), then hold this one a full enemy-length above any cruiser
				# already in its lane or an adjacent lane (Gap 1 / _anchor_stagger_y).
				var h: float = _enemy_height(enemy)
				var is_cruiser: bool = h >= ANCHOR_MIN_HEIGHT
				var lane: int = _pick_lane(is_cruiser, wave.spawn_y, h)
				var sy: float = wave.spawn_y
				if is_cruiser:
					sy = _anchor_stagger_y(lane, sy, h)
				pos = Vector2(Lanes.lane_center(lane), sy)
	# Formation Builder lateral-direction override: force which way a side-aware
	# movement runs (or randomize per spawn). Only patterns exposing `direction` or
	# `mirrored` respond; others are untouched. Layers over any SIDE_ALTERNATING dup.
	if "direction_override" in wave and wave.direction_override != 0:
		var dir: int = wave.direction_override
		if dir == 2:
			dir = 1 if _rng.randf() < 0.5 else -1
		_apply_direction(enemy, dir)
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
	return enemy


func _on_enemy_died(value: int, scene_path: String) -> void:
	enemy_died.emit(value, scene_path)


# Apply an absolute lateral direction (+1 right / -1 left) to whatever side knob the
# movement exposes. `direction` (side_traverse/side_cut/side_pingpong) maps directly;
# `mirrored` (lane_path HOOK/STEP/WEAVE) flips relative to the authored side — right =
# authored, left = mirror. Duplicates the resource so siblings don't share state.
# No-op for movements with neither knob.
func _apply_direction(enemy, dir: int) -> void:
	if not ("movement" in enemy) or enemy.movement == null:
		return
	var mv = enemy.movement
	if "direction" in mv:
		var d = mv.duplicate()
		d.direction = dir
		enemy.movement = d
	elif "mirrored" in mv:
		var d = mv.duplicate()
		d.mirrored = dir < 0
		enemy.movement = d


func _apply_sector_modifiers(enemy: Node, modifiers: Array) -> void:
	for mod in modifiers:
		match mod:
			"shielded":
				# Handled in _resolve_shields() (after the faction overlay) so the boost
				# lands on an existing ShieldComponent instead of stacking a parallel one
				# (shield_unification_2026-06-08.md). No-op here.
				pass
			"armored":
				if "damage_reduction" in enemy:
					enemy.damage_reduction = max(enemy.damage_reduction, 0.10)
			"heavily_armored":
				if "damage_reduction" in enemy:
					enemy.damage_reduction = max(enemy.damage_reduction, 0.20)
			"aggressive":
				# Faster fire AND faster projectiles (M6b weapon scaling). Scale the
				# SINGLE-SOURCED fire_interval (review P1): tweaking $ShootTimer.wait_time
				# was a no-op — enemy_core re-arms wait_time from fire_interval on every
				# shot, clobbering it.
				if "fire_interval_min" in enemy:
					enemy.fire_interval_min *= 0.85
				if "fire_interval_max" in enemy:
					enemy.fire_interval_max *= 0.85
				if "bullet_speed_mult" in enemy:
					enemy.bullet_speed_mult *= 1.15
			"armed":
				# Heavier, slightly faster shots (M6b weapon scaling).
				if "bullet_damage_mult" in enemy:
					enemy.bullet_damage_mult *= 1.3
				if "bullet_speed_mult" in enemy:
					enemy.bullet_speed_mult *= 1.1
			"wanted":
				if "bounty_value" in enemy:
					enemy.bounty_value = int(enemy.bounty_value * 1.20)
			"fleeing":
				if "recycle_passes" in enemy:
					enemy.recycle_passes = 0


# Attach/boost a ShieldComponent for data-driven shields (shield_unification_2026-06-08.md).
# Runs after the faction overlay + sector modifiers, before add_child (so _init_components
# dups the result). Both sources BOOST an existing CHARGE component (e.g. corporate) when
# present rather than stacking a parallel shield; chaff/sector shields never regenerate.
func _resolve_shields(enemy: Node, wave, run) -> void:
	if not ("components" in enemy and enemy.components is Array):
		return
	# faction_shield_exempt = "no generic shield, period" (c_dart wants none; bulwark/sapper
	# author their OWN shield in _ready, which isn't in `components` yet here — so a data-driven
	# add would STACK a parallel ring rather than boost it = "doubled up shields", Roman 2026-06-11).
	if ("faction_shield_exempt" in enemy) and enemy.faction_shield_exempt:
		return
	var charge = _find_charge_shield(enemy)
	# Roster "shielded" tag (wave.shield_charges).
	if wave.shield_charges > 0:
		if charge != null:
			charge.capacity = maxi(charge.capacity, wave.shield_charges)
		else:
			charge = ShieldComponentC.new()
			charge.mode = ShieldComponentC.Mode.CHARGE
			charge.capacity = wave.shield_charges
			charge.regen_interval = 0.0   # chaff shields don't regenerate
			# Reassign (not append) — @export Array defaults are shared across instances.
			enemy.components = enemy.components + [charge]
	# Sector "shielded" modifier → +1 charge on the (possibly just-added) component.
	if run != null and "sector_modifiers" in run and run.sector_modifiers.has("shielded"):
		if charge != null:
			charge.capacity += 1
		else:
			var sc = ShieldComponentC.new()
			sc.mode = ShieldComponentC.Mode.CHARGE
			sc.capacity = 1
			sc.regen_interval = 0.0
			enemy.components = enemy.components + [sc]


# First CHARGE-mode ShieldComponent in the enemy's authored components (pre-dup), or null.
func _find_charge_shield(enemy):
	for c in enemy.components:
		if c != null and c is ShieldComponentC and c.mode == ShieldComponentC.Mode.CHARGE:
			return c
	return null


func _process(_delta: float) -> void:
	if _check_clear:
		if not _live_combatants_present() and not _hazards_present():
			_check_clear = false
			level_cleared.emit()


# True if any "enemies"-group node is alive AND not flagged is_hazard.
# Mines / bomblets / asteroids dropped behind a minelayer don't gate
# wave progression (Cody, 2026-05-18 playtest).
func _live_combatants_present() -> bool:
	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n):
			continue
		if "is_hazard" in n and n.is_hazard:
			continue
		return true
	return false

func _hazards_present() -> bool:
	for n in get_tree().get_nodes_in_group("enemies"):
		if "is_hazard" in n and n.is_hazard:
			return true
	return false


# ---- Boss gate (opt-in discrete waves; see boss_gate) --------------------

func _boss_gate_alive() -> bool:
	return boss_gate != null and is_instance_valid(boss_gate)


# True if `e` is the gating boss or one of its parts — such nodes live in "enemies" but must be excluded
# from wave concurrency/placement math (they aren't wave chaff competing for slots or lanes).
func _is_boss_gate_node(e: Node) -> bool:
	return _boss_gate_alive() and (e == boss_gate or boss_gate.is_ancestor_of(e))


# True once the boss has begun its death/retreat (it reports is_defeated) — the gate stops driving it.
func _boss_defeated() -> bool:
	return _boss_gate_alive() and boss_gate.has_method("is_defeated") and boss_gate.is_defeated()


# True while any WAVE combatant is still alive — a non-hazard "enemies" node that is neither the boss
# nor one of its parts (the boss + its turrets/lasers are in "enemies" too, but must NOT gate its own
# maneuver). Hazards (dropped firecores etc.) never gate, matching _live_combatants_present.
func _wave_combatants_present() -> bool:
	for n in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(n):
			continue
		if "is_hazard" in n and n.is_hazard:
			continue
		if _is_boss_gate_node(n):
			continue
		return true
	return false


# Await until the current wave's combatants have cleared, so the boss plays its between-wave maneuver
# over an empty field. Bounded by BOSS_GATE_DRAIN_TIMEOUT so a stuck/lingering enemy can't hang it.
func _drain_for_gate() -> void:
	var guard: float = 0.0
	while _running and _wave_combatants_present() and guard < BOSS_GATE_DRAIN_TIMEOUT:
		await get_tree().create_timer(0.1).timeout
		guard += 0.1

func _ready() -> void:
	if auto_start and level != null:
		start_level()
