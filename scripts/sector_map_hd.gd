extends Control

# Sector Map HD — identical logic to sector_map_v2.gd, display constants ×4.
# Lives inside a SubViewport sized 1920×1080, so get_viewport_rect() returns
# (0,0,1920,1080) and all pixel geometry is authored at native HD resolution.
#
# Rules / generation logic unchanged from V2 — only display constants differ.

const SectorNode = preload("res://scripts/sector_node.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const BG_TEXTURE = preload("res://graphics/ui/sector_bg.png")
const NODE_STRIP = preload("res://graphics/ui/sector_nodes.png")
const FRAME_BOSS := 0
const FRAME_CURRENT := 1
const FRAME_VALID := 2
const FRAME_OTHER := 3
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

# ---- HD display scale -------------------------------------------------------
# V2 authors geometry at 480×270 / 32px-grid. HD runs inside a 1920×1080
# SubViewport — exactly 4× the V2 internal size — so every pixel constant is
# multiplied by 4. Grid logic (rows, cols, edges) is unchanged.
const DISPLAY_SCALE: float = 4.0

const COLS: int = 14
const ROWS: int = 12
# Base grid constants × 4.
const CELL_X: int = 128   # 32 × 4
const CELL_Y: int = 80    # 20 × 4
const NODE_PX: int = 128  # 32 × 4  (button / hit-area size)
const GRID_X0: int = 64   # 16 × 4
const GRID_Y0: int = 60   # 15 × 4
const C_MIN: int = 1
const C_MAX: int = COLS - 2  # 12
const R_MIN: int = 1
const R_MAX: int = ROWS - 2  # 10
const BOSS_ROW: int = R_MIN
const PRE_BOSS_ROW: int = BOSS_ROW + 1
const ANCHOR_COL: int = 7
const START_POS := Vector2(GRID_X0 + ANCHOR_COL * CELL_X + CELL_X / 2, GRID_Y0 + 11 * CELL_Y + CELL_Y / 2)
const BOSS_POS  := Vector2(GRID_X0 + ANCHOR_COL * CELL_X + CELL_X / 2, GRID_Y0 + 1  * CELL_Y + CELL_Y / 2)
const FILL_ROW_MIN: int = PRE_BOSS_ROW + 1
const FILL_ROW_MAX: int = R_MAX - 1
const EDGE_ROW_REACH: int = 2
const EDGE_COL_REACH: int = 2

const MOD_NORMAL := Color(1, 1, 1, 1)
const MOD_DIM    := Color(1, 1, 1, 0.65)

var nodes: Array = []
var nodes_by_id: Dictionary = {}
var current_id: String = ""
var _pause_layer: CanvasLayer = null
@export var debug_grid: bool = false


func _ready() -> void:
	# Switch to native 1920x1080 for this scene so all rendering is pixel-perfect.
	# _exit_tree() restores the game's normal 480x270 when we leave.
	get_tree().get_root().content_scale_size = Vector2i(1920, 1080)
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


func _exit_tree() -> void:
	get_tree().get_root().content_scale_size = Vector2i(480, 270)


static func cell_center(c: int, r: int) -> Vector2:
	return Vector2(GRID_X0 + c * CELL_X + CELL_X / 2, GRID_Y0 + r * CELL_Y + CELL_Y / 2)


func _install_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.10, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)


# ---- Generation (identical logic to V2 — only positions differ) -------------

func _generate_map() -> void:
	nodes.clear()
	nodes_by_id.clear()
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

	var start_node = SectorNode.new()
	start_node.id = "start"
	start_node.node_type = SectorNode.NodeType.START
	start_node.row = R_MAX + 1
	start_node.col = 4
	start_node.pos = START_POS
	nodes.append(start_node)
	nodes_by_id[start_node.id] = start_node

	var boss = SectorNode.new()
	boss.id = "boss"
	boss.node_type = SectorNode.NodeType.BOSS
	boss.row = BOSS_ROW
	boss.col = ANCHOR_COL
	boss.pos = BOSS_POS
	nodes.append(boss)
	nodes_by_id[boss.id] = boss

	var base = SectorNode.new()
	base.id = "preboss_base"
	base.node_type = SectorNode.NodeType.OUTPOST
	base.row = PRE_BOSS_ROW
	base.col = ANCHOR_COL
	base.pos = cell_center(ANCHOR_COL, PRE_BOSS_ROW)
	nodes.append(base)
	nodes_by_id[base.id] = base

	var lane_cols: Array
	if rng.randi() % 2 == 0:
		lane_cols = [2, 7]
	else:
		lane_cols = [2, 5, 8]
	var prev_row_cols: Array = []
	var last_outpost_row: int = -999
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
			if n.node_type == SectorNode.NodeType.OUTPOST and (r - last_outpost_row) < 2:
				n.node_type = SectorNode.NodeType.COMBAT
			if n.node_type == SectorNode.NodeType.OUTPOST:
				last_outpost_row = r
			n.row = r
			n.col = c
			n.pos = cell_center(c, r)
			nodes.append(n)
			nodes_by_id[n.id] = n
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

	_prune_unreachable_row(PRE_BOSS_ROW + 1, base.col)
	for n in nodes:
		if int(n.row) == PRE_BOSS_ROW + 1:
			base.edges_to.append(n.id)
	base.edges_to.append(boss.id)

	for src in nodes:
		if src.node_type == SectorNode.NodeType.BOSS:
			continue
		if src.id == "preboss_base":
			continue
		_build_forward_edges(rng, src)
	_ensure_reachable()
	_repair_dead_ends()
	_strip_backward_edges()
	_save_to_cache()


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
	_strip_backward_edges()


func _strip_backward_edges() -> void:
	for src in nodes:
		var keep: Array = []
		for to_id in src.edges_to:
			if not nodes_by_id.has(to_id):
				continue
			var dst = nodes_by_id[to_id]
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
	var weighted: Array = []
	for n in candidates:
		var col_d: float = abs(float(src.col) - float(n.col))
		var row_d: float = abs(float(src.row) - float(n.row))
		var boss_bonus: float = 6.0 if n.node_type == SectorNode.NodeType.BOSS else 1.0
		var lateral_bonus: float = 2.0 if col_d > 0.0 else 1.0
		var w: float = boss_bonus * lateral_bonus / (row_d * 0.6 + 1.0)
		weighted.append([w, n])
	var picks: int = rng.randi_range(1, 3)
	picks = mini(picks, weighted.size())
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


func _repair_dead_ends() -> void:
	if not nodes_by_id.has("boss"):
		return
	var boss_id: String = nodes_by_id["boss"].id
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
	var orphans: Array = []
	for n in nodes:
		if reach_boss.has(n.id):
			continue
		if n.id == "start":
			continue
		orphans.append(n)
	var strict_row_reach: int = EDGE_ROW_REACH
	var strict_col_reach: int = EDGE_COL_REACH
	var loose_row_reach: int = EDGE_ROW_REACH + 1
	var loose_col_reach: int = EDGE_COL_REACH + 2
	for orphan in orphans:
		var fixed: bool = _try_fix_orphan(orphan, reach_boss, strict_row_reach, strict_col_reach)
		if not fixed:
			fixed = _try_fix_orphan(orphan, reach_boss, loose_row_reach, loose_col_reach)
		if not fixed:
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


func _pick_col_with_spacing(rng: RandomNumberGenerator, used_this_row: Array, prev_row_cols: Array) -> int:
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


func _pick_col_excluding(rng: RandomNumberGenerator, exclude: Array, _legacy_min_gap: int = 1) -> int:
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


# ---- Render -----------------------------------------------------------------

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
		var btn := TextureButton.new()
		btn.texture_normal = _dot_texture_hd(_frame_for(n, state))
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.custom_minimum_size = Vector2(NODE_PX, NODE_PX)
		btn.size = Vector2(NODE_PX, NODE_PX)
		btn.position = n.pos - Vector2(NODE_PX / 2, NODE_PX / 2)
		btn.modulate = MOD_DIM if state == "visited" else MOD_NORMAL
		btn.disabled = not _is_reachable(n)
		btn.pressed.connect(_on_node_pressed.bind(n))
		var icon_idx: int = _icon_for_type(n.node_type)
		if icon_idx >= 0:
			var icon := TextureRect.new()
			icon.texture = _icon_texture_hd(icon_idx)
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


# HD versions use separate caches (named _hd_*) so they don't collide with
# V2's static caches if both scripts are loaded in the same session.
# Atlas source regions remain 32×32 (image pixels). The NODE_PX button size
# (128 px) handles the 4× upscaling in screen space.
static var _dot_cache_hd: Array = []
static func _dot_texture_hd(idx: int) -> Texture2D:
	if _dot_cache_hd.is_empty():
		_dot_cache_hd.resize(4)
		for i in 4:
			var at := AtlasTexture.new()
			at.atlas = NODE_STRIP
			at.region = Rect2(i * 32, 0, 32, 32)
			_dot_cache_hd[i] = at
	return _dot_cache_hd[clamp(idx, 0, 3)]


static var _icon_cache_hd: Array = []
static func _icon_texture_hd(idx: int) -> Texture2D:
	if _icon_cache_hd.is_empty():
		_icon_cache_hd.resize(6)
		for i in 6:
			var at := AtlasTexture.new()
			at.atlas = ICON_STRIP
			at.region = Rect2(i * 32, 0, 32, 32)
			_icon_cache_hd[i] = at
	return _icon_cache_hd[clamp(idx, 0, 5)]


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
			var width: float = 8.0   # V2: 2.0 × 4
			if src.id == current_id:
				color = Color(0.55, 1.0, 0.50, 0.95)
				width = 12.0          # V2: 3.0 × 4
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
	for r in range(ROWS):
		for c in range(COLS):
			var l := Label.new()
			l.text = "%d,%d" % [c, r]
			l.add_theme_font_override("font", UiTheme.active_font())
			l.add_theme_font_size_override("font_size", 32)   # V2: 8 × 4
			var in_margin: bool = c < C_MIN or c > C_MAX or r < R_MIN or r > R_MAX
			l.add_theme_color_override("font_color",
				Color(0.5, 0.55, 0.7, 0.7) if in_margin
				else Color(1.0, 0.95, 0.55, 1.0))
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
			l.add_theme_constant_override("outline_size", 8)   # V2: 2 × 4
			l.position = Vector2(GRID_X0 + c * CELL_X + 8, GRID_Y0 + r * CELL_Y + 4)  # V2: +2,+1 × 4
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(l)


func _draw_grid_lines(canvas: Node2D) -> void:
	var col_grid: Color = Color(0.30, 0.45, 0.75, 0.55)
	var col_margin: Color = Color(0.85, 0.30, 0.30, 0.55)
	for c in range(COLS + 1):
		var x: float = GRID_X0 + c * CELL_X
		var color: Color = col_margin if (c == C_MIN or c == C_MAX + 1) else col_grid
		canvas.draw_line(Vector2(x, GRID_Y0), Vector2(x, GRID_Y0 + ROWS * CELL_Y), color, 4.0)  # V2: 1.0 × 4
	for r in range(ROWS + 1):
		var y: float = GRID_Y0 + r * CELL_Y
		var color2: Color = col_margin if (r == R_MIN or r == R_MAX + 1) else col_grid
		canvas.draw_line(Vector2(GRID_X0, y), Vector2(GRID_X0 + COLS * CELL_X, y), color2, 4.0)  # V2: 1.0 × 4


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var OptionsOverlay = load("res://scripts/ui/options_overlay.gd")
		OptionsOverlay.open(self)
		get_viewport().set_input_as_handled()
