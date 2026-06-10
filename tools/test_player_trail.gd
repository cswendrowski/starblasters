extends Node

# Player engine-trail diagnostic (Roman 2026-06-09): boot combat (ship A, the single-Engine-marker
# hull), move the player so its engine markers travel, and report whether the EngineTrailFx attached,
# found the markers, created its Line2Ds, and accumulated points. Pinpoints why the player trail is
# invisible. Run: godot --headless --path . tools/test_player_trail.tscn --quit-after 120

const RESULT := "res://tools/_player_trail_result.txt"
const TrailScript = preload("res://scripts/effects/engine_trail_fx.gd")
var _t := 0
var _main: Node = null
var _player: Node = null
var _done := false

func _ready() -> void:
	var run = get_node_or_null("/root/Run")
	if run != null:
		run.new_run()   # variant 0 = ship A (single "Engine" marker)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)

func _process(_dt: float) -> void:
	if _done:
		return
	_t += 1
	if _player == null:
		_player = _main.get_node_or_null("Player")
	# Deliberately DO NOT move the player — the drift alone must produce a visible plume.
	if _t < 30:
		return
	_done = true
	var lines: Array = []
	var fails := 0
	if _player == null:
		lines.append("FAIL no player"); fails += 1
		_finish(lines, fails); return
	var markers: Array = _player.find_children("Engine*", "Marker2D", true, false)
	lines.append("markers found: %d %s" % [markers.size(), str(markers.map(func(m): return m.name))])
	if markers.is_empty():
		lines.append("FAIL no Engine* markers found"); fails += 1
	# Locate the EngineTrailFx child on the player.
	var trail = null
	for c in _player.get_children():
		if c.get_script() == TrailScript:
			trail = c
			break
	lines.append("EngineTrailFx attached: %s" % (trail != null))
	if trail == null:
		lines.append("FAIL no EngineTrailFx child"); fails += 1
		_finish(lines, fails); return
	var lns: Array = trail._lines
	lines.append("lines: %d" % lns.size())
	var total_points := 0
	var parents: Array = []
	var max_extent := 0.0
	for ln in lns:
		if ln != null and is_instance_valid(ln):
			total_points += ln.get_point_count()
			var p = ln.get_parent()
			parents.append(p.name if p != null else "<none>")
			# Vertical span of the plume (proves the drift streamed points apart while stationary).
			var ymin: float = INF
			var ymax: float = -INF
			for j in ln.get_point_count():
				var pos: Vector2 = ln.get_point_position(j)
				ymin = minf(ymin, pos.y)
				ymax = maxf(ymax, pos.y)
			if ln.get_point_count() > 0:
				max_extent = maxf(max_extent, ymax - ymin)
		else:
			parents.append("<freed>")
	lines.append("line parents: %s" % str(parents))
	lines.append("total trail points: %d  plume vertical extent: %.1f px" % [total_points, max_extent])
	if lns.is_empty():
		lines.append("FAIL no Line2Ds created"); fails += 1
	elif total_points == 0:
		lines.append("FAIL lines created but no points accumulated"); fails += 1
	elif max_extent < 10.0:
		lines.append("FAIL stationary plume has no vertical extent (drift not working)"); fails += 1
	lines.append("PLAYER TRAIL: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	_finish(lines, fails)

func _finish(lines: Array, _fails: int) -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	get_tree().quit()
