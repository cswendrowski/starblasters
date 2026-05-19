extends Control

# Sector Map V2 — built fresh against the 32px-grid spec + the example
# image Roman provided (2026-05-17). No carryover from the legacy map.
#
# Rules (verbatim from Roman):
#   - 320×400 screen, broken into a 32px grid.
#   - 1-cell margin around the border.
#   - Choice icons are 32px and sit in a single cell.
#   - Start point centered in a bottom 2×2 block (icon still 32px).
#   - Boss node(s) live in the second row from the top, any non-margin col.
#   - There is always a base node before a boss node.
#   - Nodes connect to any node in a row above, never on the same row.
#   - Each non-boss node has 1-3 outgoing edges to a higher row.
#   - No dead-end nodes except bosses.
#   - Available = green, current = yellow, boss = red.
#   - Use the supplied 320x400BG image.
#
# Differs from sector_map.gd by being denser (closer to the example
# image's wing-like clusters) and by using a "lane" bias on edges so
# paths form clear left/right strands rather than diffuse fan-outs.

const SectorNode = preload("res://scripts/sector_node.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const BG_TEXTURE = preload("res://graphics/ui/sector_bg.png")
# Node "dot" background — 4 frames keyed to state (boss / current /
# valid / other). Layered first; the icon overlay draws on top.
const NODE_STRIP = preload("res://graphics/ui/sector_nodes.png")
const FRAME_BOSS := 0
const FRAME_CURRENT := 1
const FRAME_VALID := 2
const FRAME_OTHER := 3
# Node type icon strip — 6 frames in order:
#   0 base / 1 start / 2 battle / 3 boss / 4 hazard / 5 signal.
# Drawn on top of the dot so every node shows both its membership in
# the path state AND its type.
const ICON_STRIP = preload("res://graphics/ui/sector_icons.png")
const ICON_BASE := 0
const ICON_START := 1
const ICON_BATTLE := 2
const ICON_BOSS := 3
const ICON_HAZARD := 4
const ICON_SIGNAL := 5
const COMBAT_SCENE := "res://scenes/main.tscn"
const OUTPOST_SCENE := "res://scenes/outpost.tscn"
const SIGNAL_SCENE := "res://scenes/signal_event.tscn"
const BOSS_SCENE := "res://scenes/main.tscn"
const HAZARD_SCENE := "res://scenes/main.tscn"

# Grid geometry — 320×400 / 32 = 10 × 12.5. Use 12 rows of 32, centered
# vertically with 8px slack so the grid lives at y = 8 … 392.
const COLS: int = 15
const ROWS: int = 12
# 480×270 widescreen rework v2 — 15×12 grid of 16-px cells = 240 × 192,
# centered in viewport (GRID_X0=120, GRID_Y0=39). Cell size matches a
# clean 2:1 downscale of the 32-px dot atlas so pixels stay sharp
# (Cody 2026-05-19 — fixes "unaligned" feel from non-integer scaling).
const CELL: int = 16
const GRID_Y0: int = 39
const GRID_X0: int = 120
const C_MIN: int = 1
const C_MAX: int = COLS - 2  # 13
const R_MIN: int = 1
const R_MAX: int = ROWS - 2  # 10
const BOSS_ROW: int = R_MIN              # 1
const PRE_BOSS_ROW: int = BOSS_ROW + 1   # 2
# Start sits centered on col 7 (the geometric center of 15 cols) at the
# bottom of the playable rows. Boss mirrors above. Single-cell anchors
# now — the 2×2 corner trick was a 320-wide artifact.
const ANCHOR_COL: int = 7
const START_POS := Vector2(GRID_X0 + ANCHOR_COL * CELL + CELL / 2, GRID_Y0 + 11 * CELL + CELL / 2)
const BOSS_POS := Vector2(GRID_X0 + ANCHOR_COL * CELL + CELL / 2, GRID_Y0 + 1 * CELL + CELL / 2)
# Start "covers" rows 10 and 11. Per Roman, no other nodes may share
# those rows; the lowest non-start node is at row 9 (1 up) or row 8
# (2 up). All inner rows above that are open.
const FILL_ROW_MIN: int = PRE_BOSS_ROW + 1  # 3 — first row above pre-boss
const FILL_ROW_MAX: int = R_MAX - 1         # 9 — one row above start
# Edge constraints — connect 1-2 rows up, ≤2 cols away.
const EDGE_ROW_REACH: int = 2
# Edge col reach bumped from 2 to 4 to match the same physical span
# (~64 px) now that CELL halved from 32→16.
const EDGE_COL_REACH: int = 4

# State frame coloring is baked into the sprite strip — no per-state
# modulate needed. Keep these around in case we want to dim visited/far
# nodes further later, but default is to render the sprite as-is.
const MOD_NORMAL := Color(1, 1, 1, 1)
const MOD_DIM    := Color(1, 1, 1, 0.65)

var nodes: Array = []
var nodes_by_id: Dictionary = {}
var current_id: String = ""
var _pause_layer: CanvasLayer = null
# Toggle to draw a 32px grid overlay with (col, row) labels. Useful for
# diagnosing node placement vs the grid spec. Off in shipped builds.
@export var debug_grid: bool = false


func _ready() -> void:
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("sector")
	_install_background()
	_generate_map()
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if run.current_node_id != "" and nodes_by_id.has(run.current_node_id):
			current_id = run.current_node_id
	if current_id == "" and nodes_by_id.has("start"):
		current_id = "start"
	_render()


static func cell_center(c: int, r: int) -> Vector2:
	return Vector2(GRID_X0 + c * CELL + CELL / 2, GRID_Y0 + r * CELL + CELL / 2)


func _install_background() -> void:
	var bg := TextureRect.new()
	bg.texture = BG_TEXTURE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)


# ---- Generation ----------------------------------------------------------
#
# Strategy modeled on the example image:
#   - Pick 2 "lane centers" near the left and right edges of the inner
#     area (default cols 2 and 7). Bosses sit at the top of each lane.
#   - Fill each lane with a node in every row from R_MIN+1 to R_MAX,
#     jittering ±1 column so the strands wave rather than running
#     perfectly vertical. This gives the dense wing clusters the
#     example shows.
#   - Edges bias strongly toward the same lane (closer cols), with
#     occasional cross-lane links so the player can flip sides.
#   - Pre-boss row 2 is always an Outpost (the rule "base before boss").
#   - Start anchors the bottom; its outgoing edges reach the lowest
#     nodes in each lane.

func _generate_map() -> void:
	nodes.clear()
	nodes_by_id.clear()
	# Cache check — if we've already generated this map for this run_seed,
	# rebuild from the snapshot instead of re-rolling. The procgen is not
	# fully deterministic across instantiations even with a locked seed
	# (Resource defaults + Godot caching), and Cody's playtest report of
	# "the sector regenerates every time you return" was exactly this.
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if "sector_map_cache" in run and run.sector_map_cache is Dictionary:
			var seed_key: String = str(run.run_seed)
			if run.sector_map_cache.has(seed_key):
				_restore_from_cache(run.sector_map_cache[seed_key])
				return
	var rng := RandomNumberGenerator.new()
	if has_node("/root/Run"):
		rng.seed = get_node("/root/Run").run_seed
	else:
		rng.randomize()

	# Start.
	var start_node = SectorNode.new()
	start_node.id = "start"
	start_node.node_type = SectorNode.NodeType.START
	start_node.row = R_MAX + 1
	start_node.col = 4
	start_node.pos = START_POS
	nodes.append(start_node)
	nodes_by_id[start_node.id] = start_node

	# ONE boss at the top, mirroring the start's bottom 2×2 placement.
	# Centered on the corner between cells (4,0)-(5,0)-(4,1)-(5,1).
	var boss = SectorNode.new()
	boss.id = "boss"
	boss.node_type = SectorNode.NodeType.BOSS
	boss.row = BOSS_ROW
	boss.col = ANCHOR_COL
	boss.pos = BOSS_POS
	nodes.append(boss)
	nodes_by_id[boss.id] = boss

	# Pre-boss base — single Outpost in row 2 directly under the boss
	# centerline. Acts as the funnel: every path to the boss has to pass
	# through this base.
	var base = SectorNode.new()
	base.id = "preboss_base"
	base.node_type = SectorNode.NodeType.OUTPOST
	base.row = PRE_BOSS_ROW
	base.col = ANCHOR_COL
	base.pos = cell_center(ANCHOR_COL, PRE_BOSS_ROW)
	nodes.append(base)
	nodes_by_id[base.id] = base

	# Roll the lane layout for this run: 2 or 3 distinct paths with
	# visible column gaps between them (Roman, 2026-05-17). Each lane
	# is a column center; per-row placements jitter ±1 within their
	# lane to keep the path readable.
	var lane_cols: Array
	if rng.randi() % 2 == 0:
		lane_cols = [2, 7]                          # 2 lanes, gap of 5
	else:
		lane_cols = [2, 5, 8]                       # 3 lanes, gap of 3
	# Free-fill rows 3..9. Each row gets 1..min(4, lanes) nodes,
	# distributed across the lanes. Same-row spacing remains 2-3 col
	# gap; cross-row spacing avoids the column directly below.
	var prev_row_cols: Array = []
	# Track the last row that placed an OUTPOST so we can enforce a 2-row
	# spacing rule (Roman, 2026-05-17: "we should have a rule that bases
	# must be at least 2 nodes apart. I just had a map where the last
	# three nodes before the boss were bases.")
	var last_outpost_row: int = -999
	# Also prefer 2-3 paths visibly — bias the row-fill to use the upper
	# end of the n_in_row range so single-lane rows are rare.
	for r in range(FILL_ROW_MIN, FILL_ROW_MAX + 1):
		var max_nodes: int = mini(4, lane_cols.size())
		var n_in_row: int = rng.randi_range(maxi(1, max_nodes - 1), max_nodes)
		var lanes_this_row: Array = lane_cols.duplicate()
		lanes_this_row.shuffle()
		var used_cols: Array = []
		for i in n_in_row:
			var lane: int = int(lanes_this_row[i % lanes_this_row.size()])
			var c: int = _pick_col_in_lane(rng, lane, used_cols, prev_row_cols)
			if c < 0:
				continue
			used_cols.append(c)
			var n = SectorNode.new()
			n.id = "n_%d_%d" % [r, c]
			n.node_type = _roll_type(rng)
			# Outpost-spacing rule: reroll to COMBAT if we're within 2 rows
			# of the last placed Outpost.
			if n.node_type == SectorNode.NodeType.OUTPOST and (r - last_outpost_row) < 2:
				n.node_type = SectorNode.NodeType.COMBAT
			if n.node_type == SectorNode.NodeType.OUTPOST:
				last_outpost_row = r
			n.row = r
			n.col = c
			n.pos = cell_center(c, r)
			nodes.append(n)
			nodes_by_id[n.id] = n
		# Guarantee at least one node per row.
		if used_cols.is_empty():
			var fallback_c: int = _pick_col_with_spacing(rng, [], [])
			if fallback_c >= 0:
				var n_fb = SectorNode.new()
				n_fb.id = "n_%d_%d" % [r, fallback_c]
				n_fb.node_type = _roll_type(rng)
				n_fb.row = r
				n_fb.col = fallback_c
				n_fb.pos = cell_center(fallback_c, r)
				nodes.append(n_fb)
				nodes_by_id[n_fb.id] = n_fb
				used_cols.append(fallback_c)
		prev_row_cols = used_cols.duplicate()

	# Pre-boss base reach check: it must connect to ALL row-3 nodes.
	# Any row-3 node whose col_d > EDGE_COL_REACH (2) from the base
	# column is unreachable from the base — drop it per Roman's
	# "remove wayward nodes" fallback.
	_prune_unreachable_row(PRE_BOSS_ROW + 1, base.col)
	# Explicitly wire the base → every remaining row-3 node, and
	# base → boss. We do this BEFORE the random edge pass so other
	# sources can still pick the base.
	for n in nodes:
		if int(n.row) == PRE_BOSS_ROW + 1:
			base.edges_to.append(n.id)
	base.edges_to.append(boss.id)

	# ---- Edges. Each non-boss node picks 1-3 outgoing targets in any
	# row strictly above. Pre-boss base's edges are already wired
	# (base → all row-3 + boss); skip its picker pass.
	for src in nodes:
		if src.node_type == SectorNode.NodeType.BOSS:
			continue
		if src.id == "preboss_base":
			continue
		_build_forward_edges(rng, src)
	# Reachability fix-up: any node with zero incoming gets a back-edge
	# added from the closest node below it.
	_ensure_reachable()
	# Dead-end audit: every non-boss, non-start node must have a forward
	# path to the boss. Repair by adding one more edge if possible, or
	# cull the node if no valid candidate exists.
	_repair_dead_ends()
	# Forward-only invariant (Roman 2026-05-19). Safety net — every edge
	# must point UP (smaller row). Same call we use on cache restore.
	_strip_backward_edges()
	# Snapshot the freshly-generated graph into Run.sector_map_cache so
	# any future reload of this scene under the same run_seed restores
	# the identical layout instead of re-rolling.
	_save_to_cache()


# Serialize the current `nodes` array (a flat list of SectorNode resources)
# into a plain dict structure that survives autoload state without holding
# Resource references. Stored keyed by str(run_seed) on Run.sector_map_cache.
func _save_to_cache() -> void:
	if not has_node("/root/Run"):
		return
	var run = get_node("/root/Run")
	if not "sector_map_cache" in run:
		return
	var snapshot: Array = []
	for n in nodes:
		snapshot.append({
			"id": n.id,
			"node_type": int(n.node_type),
			"row": int(n.row),
			"col": int(n.col),
			"pos": Vector2(n.pos),
			"edges_to": Array(n.edges_to),
			"planet_idx": int(n.planet_idx),
			"nebula_band": String(n.nebula_band),
			"nebula_tint": Color(n.nebula_tint),
		})
	if not (run.sector_map_cache is Dictionary):
		run.sector_map_cache = {}
	run.sector_map_cache[str(run.run_seed)] = snapshot


func _restore_from_cache(snapshot: Array) -> void:
	for entry in snapshot:
		var n = SectorNode.new()
		n.id = String(entry.get("id", ""))
		n.node_type = int(entry.get("node_type", 0))
		n.row = int(entry.get("row", 0))
		n.col = int(entry.get("col", 0))
		n.pos = Vector2(entry.get("pos", Vector2.ZERO))
		n.edges_to = Array(entry.get("edges_to", []))
		n.planet_idx = int(entry.get("planet_idx", -1))
		n.nebula_band = String(entry.get("nebula_band", ""))
		n.nebula_tint = Color(entry.get("nebula_tint", Color(1, 1, 1, 1)))
		nodes.append(n)
		nodes_by_id[n.id] = n
	# Strip any backward / same-row edges (Roman 2026-05-19). Belt and
	# suspenders — catches stale cache snapshots from older versions that
	# may have had bidirectional edges. Player can only ever move toward
	# the boss (smaller row number); never sideways or back down.
	_strip_backward_edges()


# Drop any edge whose destination is at the same row as the source or
# below it (larger row number = further from boss). Run after generation
# AND after cache restore so the invariant holds regardless of source.
func _strip_backward_edges() -> void:
	for src in nodes:
		var keep: Array = []
		for to_id in src.edges_to:
			if not nodes_by_id.has(to_id):
				continue
			var dst = nodes_by_id[to_id]
			# Strict less-than: dst must be on a row CLOSER to boss.
			if int(dst.row) < int(src.row):
				keep.append(to_id)
		src.edges_to = keep


func _roll_type(rng: RandomNumberGenerator) -> int:
	var roll: int = rng.randi() % 100
	if roll < 60:
		return SectorNode.NodeType.COMBAT
	if roll < 80:
		return SectorNode.NodeType.SIGNAL
	if roll < 92:
		return SectorNode.NodeType.OUTPOST
	return SectorNode.NodeType.HAZARD


func _build_forward_edges(rng: RandomNumberGenerator, src) -> void:
	# Hard filter per Roman 2026-05-17:
	#   - row strictly above (n.row < src.row)
	#   - at most EDGE_ROW_REACH (2) rows up
	#   - at most EDGE_COL_REACH (2) cols away
	#   - bosses only reachable from PRE_BOSS_ROW (col distance still applies)
	var candidates: Array = []
	for n in nodes:
		if n.row >= src.row:
			continue
		if (src.row - n.row) > EDGE_ROW_REACH:
			continue
		if n.node_type == SectorNode.NodeType.START:
			continue
		var col_d: int = int(abs(float(src.col) - float(n.col)))
		if col_d > EDGE_COL_REACH:
			continue
		if n.node_type == SectorNode.NodeType.BOSS and int(src.row) != PRE_BOSS_ROW:
			continue
		candidates.append(n)
	if candidates.is_empty():
		return
	# Score candidates: prefer non-same-column (Roman: "no more than half
	# directly above; prefer left/right"). Closer rows still weighted
	# higher to avoid the graph fanning into long single-row chains.
	var weighted: Array = []
	for n in candidates:
		var col_d: float = abs(float(src.col) - float(n.col))
		var row_d: float = abs(float(src.row) - float(n.row))
		var boss_bonus: float = 6.0 if n.node_type == SectorNode.NodeType.BOSS else 1.0
		# Same-column targets get a base weight; left/right get a multiplier.
		var lateral_bonus: float = 2.0 if col_d > 0.0 else 1.0
		var w: float = boss_bonus * lateral_bonus / (row_d * 0.6 + 1.0)
		weighted.append([w, n])
	# Pick 1-3 edges.
	var picks: int = rng.randi_range(1, 3)
	picks = mini(picks, weighted.size())
	# Track how many same-col edges have been chosen so we can enforce
	# "no more than half directly above" — flooring at floor(picks/2).
	var same_col_cap: int = picks / 2
	var same_col_used: int = 0
	for i in range(picks):
		var total_w: float = 0.0
		for entry in weighted:
			var n = entry[1]
			if src.edges_to.has(n.id):
				continue
			var would_be_same_col: bool = (int(n.col) == int(src.col))
			if would_be_same_col and same_col_used >= same_col_cap:
				continue
			total_w += float(entry[0])
		if total_w <= 0.0:
			break
		var roll: float = rng.randf() * total_w
		for entry in weighted:
			var n2 = entry[1]
			if src.edges_to.has(n2.id):
				continue
			var would_be_same_col2: bool = (int(n2.col) == int(src.col))
			if would_be_same_col2 and same_col_used >= same_col_cap:
				continue
			roll -= float(entry[0])
			if roll <= 0.0:
				src.edges_to.append(n2.id)
				if would_be_same_col2:
					same_col_used += 1
				break


# Walk every non-boss node and confirm a forward path reaches the boss.
# Anyone who can't is a dead-end. Try to repair by adding one outgoing
# edge to a reachable higher-row node within rules (row_d ≤ 2, col_d
# ≤ 2). If no valid candidate exists, remove the orphan and clean up
# inbound edges that pointed at it.
func _repair_dead_ends() -> void:
	if not nodes_by_id.has("boss"):
		return
	var boss_id: String = nodes_by_id["boss"].id
	# BFS backwards from boss: which nodes can reach the boss?
	var reach_boss: Dictionary = {boss_id: true}
	var changed: bool = true
	while changed:
		changed = false
		for src in nodes:
			if reach_boss.has(src.id):
				continue
			for to_id in src.edges_to:
				if reach_boss.has(to_id):
					reach_boss[src.id] = true
					changed = true
					break
	# Repair orphans.
	var orphans: Array = []
	for n in nodes:
		if reach_boss.has(n.id):
			continue
		if n.id == "start":
			continue
		orphans.append(n)
	# Roman, 2026-05-17 playtest: "dead-end culling might be over
	# aggressive". Try the strict reach first, then a relaxed pass with
	# wider row/col reach before giving up. Final cull is the same.
	var strict_row_reach: int = EDGE_ROW_REACH
	var strict_col_reach: int = EDGE_COL_REACH
	var loose_row_reach: int = EDGE_ROW_REACH + 1
	var loose_col_reach: int = EDGE_COL_REACH + 2
	for orphan in orphans:
		var fixed: bool = _try_fix_orphan(orphan, reach_boss, strict_row_reach, strict_col_reach)
		if not fixed:
			fixed = _try_fix_orphan(orphan, reach_boss, loose_row_reach, loose_col_reach)
		if not fixed:
			# Cull the orphan and any edges pointing to it.
			nodes.erase(orphan)
			nodes_by_id.erase(orphan.id)
			for n in nodes:
				if n.edges_to.has(orphan.id):
					n.edges_to.erase(orphan.id)


func _try_fix_orphan(orphan, reach_boss: Dictionary, row_reach: int, col_reach: int) -> bool:
	for cand in nodes:
		if not reach_boss.has(cand.id):
			continue
		if cand.row >= orphan.row:
			continue
		if (orphan.row - cand.row) > row_reach:
			continue
		if int(abs(float(cand.col) - float(orphan.col))) > col_reach:
			continue
		if orphan.edges_to.has(cand.id):
			continue
		orphan.edges_to.append(cand.id)
		reach_boss[orphan.id] = true
		return true
	return false


# Drop any node at row `row` whose column is more than EDGE_COL_REACH
# from `anchor_col`. Used after pre-boss base placement to satisfy the
# "base connects to ALL row-below nodes" rule.
func _prune_unreachable_row(row: int, anchor_col: int) -> void:
	var to_remove: Array = []
	for n in nodes:
		if int(n.row) != row:
			continue
		if int(abs(float(n.col) - float(anchor_col))) > EDGE_COL_REACH:
			to_remove.append(n.id)
	for id in to_remove:
		nodes.erase(nodes_by_id[id])
		nodes_by_id.erase(id)


# Pick a column inside a specific lane (lane_col ± 1), honoring the
# same-row and cross-row spacing rules. Returns -1 if nothing fits.
func _pick_col_in_lane(rng: RandomNumberGenerator, lane_col: int, used_this_row: Array, prev_row_cols: Array) -> int:
	var candidates: Array = []
	for delta in [0, -1, 1]:
		var c: int = clampi(lane_col + delta, C_MIN, C_MAX)
		if used_this_row.has(c):
			continue
		if prev_row_cols.has(c):
			continue
		var ok: bool = true
		for ec in used_this_row:
			var d: int = abs(int(ec) - c)
			if d < 2:
				ok = false
				break
		if ok:
			candidates.append(c)
	if candidates.is_empty():
		return -1
	return candidates[rng.randi() % candidates.size()]


# Spacing-aware column picker.
#   - Same-row: prefer col_d 2-3 between picks (1-2 empty cells between).
#   - Cross-row: avoid the same column as a node directly below (row_d=1).
# Falls back gracefully when no col satisfies the strict spec.
func _pick_col_with_spacing(rng: RandomNumberGenerator, used_this_row: Array, prev_row_cols: Array) -> int:
	# Strict pass — honors both same-row gap and cross-row alignment.
	var strict: Array = []
	for c in range(C_MIN, C_MAX + 1):
		if prev_row_cols.has(c):
			continue
		var ok: bool = true
		for ec in used_this_row:
			var d: int = abs(int(ec) - c)
			if d < 2 or d > 3:
				ok = false
				break
		if ok:
			strict.append(c)
	if not strict.is_empty():
		return strict[rng.randi() % strict.size()]
	# Relaxed pass — drop the cross-row check (still honor min same-row gap).
	var relaxed: Array = []
	for c in range(C_MIN, C_MAX + 1):
		var ok2: bool = true
		for ec in used_this_row:
			if abs(int(ec) - c) < 2:
				ok2 = false
				break
		if ok2:
			relaxed.append(c)
	if not relaxed.is_empty():
		return relaxed[rng.randi() % relaxed.size()]
	return -1


# Legacy alias for the original picker — kept so the boss/preboss code
# above still compiles. Not called from the fill loop anymore.
# Pick a column for a same-row node honoring Roman's spacing rule
# (2026-05-17): "prefer at least 1 cell between nodes, up to 2". That
# translates to a column-distance of 2 or 3 between any pair of picks
# in the same row. We do a strict pass first; if no cols fit, fall back
# to "at least 1 cell" (col_d ≥ 2), then to any unused col.
func _pick_col_excluding(rng: RandomNumberGenerator, exclude: Array, _legacy_min_gap: int = 1) -> int:
	# Strict pass — every existing pick must be 2 or 3 cols away.
	var strict: Array = []
	for c in range(C_MIN, C_MAX + 1):
		var ok: bool = true
		for ec in exclude:
			var d: int = abs(int(ec) - c)
			if d < 2 or d > 3:
				ok = false
				break
		if ok:
			strict.append(c)
	if not strict.is_empty():
		return strict[rng.randi() % strict.size()]
	# Relaxed pass — require ≥1 cell between (col_d ≥ 2). The upper
	# bound is dropped, since strict failed.
	var relaxed: Array = []
	for c in range(C_MIN, C_MAX + 1):
		var ok2: bool = true
		for ec in exclude:
			if abs(int(ec) - c) < 2:
				ok2 = false
				break
		if ok2:
			relaxed.append(c)
	if not relaxed.is_empty():
		return relaxed[rng.randi() % relaxed.size()]
	# Last resort — any unused column.
	var pool: Array = []
	for c in range(C_MIN, C_MAX + 1):
		if not exclude.has(c):
			pool.append(c)
	if pool.is_empty():
		return -1
	return pool[rng.randi() % pool.size()]


func _ensure_reachable() -> void:
	var incoming: Dictionary = {nodes_by_id["start"].id: true}
	for src in nodes:
		for to_id in src.edges_to:
			incoming[to_id] = true
	for n in nodes:
		if n.node_type == SectorNode.NodeType.START:
			continue
		if incoming.has(n.id):
			continue
		# Find closest node below this one (highest row index strictly
		# above … sorry, "below" in display = larger row index).
		var best = null
		var best_d: float = INF
		for src in nodes:
			if src.row <= n.row:
				continue
			if src.node_type == SectorNode.NodeType.BOSS:
				continue
			if src.edges_to.size() >= 3:
				continue
			var col_d: float = abs(float(src.col) - float(n.col))
			var row_d: float = float(src.row - n.row)
			var d: float = col_d + row_d * 0.5
			if d < best_d:
				best_d = d
				best = src
		if best != null:
			best.edges_to.append(n.id)
			incoming[n.id] = true


# ---- Render --------------------------------------------------------------

func _render() -> void:
	var graph := Control.new()
	graph.name = "Graph"
	graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(graph)
	if debug_grid:
		_draw_debug_grid(graph)
	var edges := Node2D.new()
	edges.name = "Edges"
	graph.add_child(edges)
	edges.draw.connect(_draw_edges.bind(edges))
	edges.queue_redraw()
	for n in nodes:
		var state := _state_of(n)
		# Dot background — state-colored (red/yellow/green/dark-blue).
		var btn := TextureButton.new()
		btn.texture_normal = _dot_texture(_frame_for(n, state))
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.custom_minimum_size = Vector2(CELL, CELL)
		btn.size = Vector2(CELL, CELL)
		btn.position = n.pos - Vector2(CELL / 2, CELL / 2)
		btn.modulate = MOD_DIM if state == "visited" else MOD_NORMAL
		btn.disabled = not _is_reachable(n)
		btn.pressed.connect(_on_node_pressed.bind(n))
		# Icon overlay — type-shaped (base/start/battle/boss/hazard/signal).
		# Sits on top of the dot, ignores mouse so the underlying button
		# still receives clicks. Per Roman, 2026-05-17: icons render at
		# 50% opacity by default, bumped to 80% when the node is an
		# active choice (state == "reachable") so the player can spot
		# their options.
		var icon_idx: int = _icon_for_type(n.node_type)
		if icon_idx >= 0:
			var icon := TextureRect.new()
			icon.texture = _icon_texture(icon_idx)
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.modulate = Color(1, 1, 1, 0.8 if state == "reachable" else 0.5)
			btn.add_child(icon)
		if state == "reachable":
			var tw := btn.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
			tw.tween_property(btn, "modulate:a", 0.7, 0.7)
			tw.tween_property(btn, "modulate:a", 1.0, 0.7)
		graph.add_child(btn)


# Frame index per node + state. Per Roman's spec:
#   - Boss = frame 0 (red) regardless of state.
#   - Current player position = frame 1 (yellow).
#   - Reachable from current = frame 2 (green).
#   - Everything else (visited, far, not-yet-reachable) = frame 3 (dark).
func _frame_for(n, state: String) -> int:
	if n.node_type == SectorNode.NodeType.BOSS:
		return FRAME_BOSS
	match state:
		"current":
			return FRAME_CURRENT
		"reachable":
			return FRAME_VALID
		_:
			return FRAME_OTHER


# Build (or fetch from cache) the 32×32 dot sub-region for the requested
# frame index. Caches at first call so we don't allocate per node.
static var _dot_cache: Array = []
static func _dot_texture(idx: int) -> Texture2D:
	if _dot_cache.is_empty():
		_dot_cache.resize(4)
		for i in 4:
			var at := AtlasTexture.new()
			at.atlas = NODE_STRIP
			at.region = Rect2(i * 32, 0, 32, 32)
			_dot_cache[i] = at
	return _dot_cache[clamp(idx, 0, 3)]


static var _icon_cache: Array = []
static func _icon_texture(idx: int) -> Texture2D:
	if _icon_cache.is_empty():
		_icon_cache.resize(6)
		for i in 6:
			var at := AtlasTexture.new()
			at.atlas = ICON_STRIP
			at.region = Rect2(i * 32, 0, 32, 32)
			_icon_cache[i] = at
	return _icon_cache[clamp(idx, 0, 5)]


# Type → icon frame mapping.
func _icon_for_type(node_type: int) -> int:
	match node_type:
		SectorNode.NodeType.OUTPOST: return ICON_BASE
		SectorNode.NodeType.START:   return ICON_START
		SectorNode.NodeType.COMBAT:  return ICON_BATTLE
		SectorNode.NodeType.BOSS:    return ICON_BOSS
		SectorNode.NodeType.HAZARD:  return ICON_HAZARD
		SectorNode.NodeType.SIGNAL:  return ICON_SIGNAL
	return -1


func _state_of(n) -> String:
	if n.id == current_id:
		return "current"
	if _is_reachable(n):
		return "reachable"
	if _is_visited(n):
		return "visited"
	return "far"


func _is_reachable(n) -> bool:
	if n.id == current_id:
		return false
	if current_id == "" or not nodes_by_id.has(current_id):
		return false
	var cur = nodes_by_id[current_id]
	return cur.edges_to.has(n.id)


func _is_visited(n) -> bool:
	if not has_node("/root/Run"):
		return false
	return get_node("/root/Run").visited_nodes.has(n.id)


func _draw_edges(canvas: Node2D) -> void:
	for src in nodes:
		for to_id in src.edges_to:
			if not nodes_by_id.has(to_id):
				continue
			var dst = nodes_by_id[to_id]
			var color: Color = Color(0.45, 0.55, 0.65, 0.42)
			var width: float = 2.0
			if src.id == current_id:
				color = Color(0.55, 1.0, 0.50, 0.95)
				width = 3.0
			elif _is_visited(src) and _is_visited(dst):
				color = Color(0.40, 0.45, 0.55, 0.45)
			canvas.draw_line(src.pos, dst.pos, color, width)


func _on_node_pressed(n) -> void:
	if not _is_reachable(n):
		return
	var effective_type: int = n.node_type
	if n.node_type == SectorNode.NodeType.SIGNAL:
		var roll: int = randi() % 100
		if roll < 10:
			effective_type = SectorNode.NodeType.HAZARD
		elif roll < 20:
			effective_type = SectorNode.NodeType.COMBAT
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.mark_node_visited(n.id)
		run.current_node_type = effective_type
		run.current_stellar = {
			"planet_idx": n.planet_idx,
			"nebula_band": n.nebula_band,
			"nebula_tint": n.nebula_tint,
		}
		if effective_type == SectorNode.NodeType.HAZARD:
			run.current_hazard_subtype = "minefield" if randi() % 2 == 0 else "asteroid_field"
	match effective_type:
		SectorNode.NodeType.COMBAT:
			SceneTransition.change_scene(get_tree(), COMBAT_SCENE)
		SectorNode.NodeType.OUTPOST:
			SceneTransition.change_scene(get_tree(), OUTPOST_SCENE)
		SectorNode.NodeType.SIGNAL:
			SceneTransition.change_scene(get_tree(), SIGNAL_SCENE)
		SectorNode.NodeType.BOSS:
			SceneTransition.change_scene(get_tree(), BOSS_SCENE)
		SectorNode.NodeType.HAZARD:
			SceneTransition.change_scene(get_tree(), HAZARD_SCENE)


func _draw_debug_grid(parent: Control) -> void:
	var line_layer := Node2D.new()
	line_layer.name = "DebugGrid"
	parent.add_child(line_layer)
	line_layer.draw.connect(_draw_grid_lines.bind(line_layer))
	line_layer.queue_redraw()
	# Cell labels — one Label per cell showing "c,r". Margin cells use a
	# dimmer color so the inner playable area pops.
	for r in range(ROWS):
		for c in range(COLS):
			var l := Label.new()
			l.text = "%d,%d" % [c, r]
			l.add_theme_font_override("font", UiTheme.active_font())
			l.add_theme_font_size_override("font_size", 8)
			var in_margin: bool = c < C_MIN or c > C_MAX or r < R_MIN or r > R_MAX
			l.add_theme_color_override("font_color",
				Color(0.5, 0.55, 0.7, 0.7) if in_margin
				else Color(1.0, 0.95, 0.55, 1.0))
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
			l.add_theme_constant_override("outline_size", 2)
			l.position = Vector2(GRID_X0 + c * CELL + 2, GRID_Y0 + r * CELL + 1)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(l)


func _draw_grid_lines(canvas: Node2D) -> void:
	var col_grid: Color = Color(0.30, 0.45, 0.75, 0.55)
	var col_margin: Color = Color(0.85, 0.30, 0.30, 0.55)
	# Vertical lines.
	for c in range(COLS + 1):
		var x: float = GRID_X0 + c * CELL
		var color: Color = col_margin if (c == C_MIN or c == C_MAX + 1) else col_grid
		canvas.draw_line(Vector2(x, GRID_Y0), Vector2(x, GRID_Y0 + ROWS * CELL), color, 1.0)
	# Horizontal lines.
	for r in range(ROWS + 1):
		var y: float = GRID_Y0 + r * CELL
		var color2: Color = col_margin if (r == R_MIN or r == R_MAX + 1) else col_grid
		canvas.draw_line(Vector2(GRID_X0, y), Vector2(GRID_X0 + COLS * CELL, y), color2, 1.0)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# Roman, 2026-05-17: Esc on the sector map shouldn't end the run.
		# Open the options overlay instead so the player can adjust audio /
		# fonts / etc and continue.
		var OptionsOverlay = load("res://scripts/ui/options_overlay.gd")
		OptionsOverlay.open(self)
		get_viewport().set_input_as_handled()
