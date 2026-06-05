extends SceneTree

# M5 (Roman 2026-06-04): heavy-beat structure — every combat node ends on a CODA
# (boss-substitute cap); node 2+ also gets a MIDPOINT anchor. Both pull the roster's
# heavy_class pools (anchor=32px, capital=64px). Verifies:
#   cap_for       — 12 shallow -> 16 deep, clamped.
#   coda          — the level ALWAYS finishes on a heavy_class entry.
#   midpoint      — opener (li 0) has exactly ONE heavy beat (the coda); node 2+
#                   (li >= 1) has >= 2 (midpoint + coda).
#   sector ramp   — sector 2 codas reach the capital (64px) pool.
#   no softlock   — build never crashes / drops the cap across a depth sweep.
# Run: godot --headless --script res://tools/test_heavy_beats.gd

const RESULT := "res://tools/_heavy_beats_result.txt"
const WG := preload("res://scripts/levels/wave_generator.gd")
const Roster := preload("res://scripts/levels/enemy_roster.gd")

var _done := false


func _hclass(w) -> String:
	if w == null or w.enemy_scene == null:
		return ""
	var e: Dictionary = Roster.entry_for_scene(w.enemy_scene.resource_path)
	return String(e.get("heavy_class", "")) if not e.is_empty() else ""


func _count_heavy_waves(lvl) -> int:
	var n: int = 0
	for w in lvl.waves:
		if _hclass(w) != "":
			n += 1
	return n


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails: int = 0
	var run = root.get_node_or_null("Run")
	if run != null:
		run.run_seed = 9090

	# --- cap_for ----------------------------------------------------------
	if WG.cap_for(1, 0) != 12:
		lines.append("FAIL cap_for(1,0)=%d expected 12" % WG.cap_for(1, 0)); fails += 1
	if WG.cap_for(9, 9) != 16:
		lines.append("FAIL cap_for deep not clamped to 16"); fails += 1

	# --- coda: every node finishes on a heavy ----------------------------
	# (heavy spec is last, or second-to-last when an escort chaff sub-wave trails it)
	for sd in range(1, 4):
		for li in range(0, 5):
			var lvl = WG.build(sd, li, false)
			var sz: int = lvl.waves.size()
			var tail_heavy: bool = false
			for k in [sz - 1, sz - 2]:
				if k >= 0 and _hclass(lvl.waves[k]) != "":
					tail_heavy = true
			if not tail_heavy:
				lines.append("FAIL (%d,%d) no coda heavy in tail" % [sd, li]); fails += 1

	# --- midpoint presence ------------------------------------------------
	# Opener: only COMMON rolls + the coda heavy -> exactly 1 heavy_class wave.
	var op_heavy: int = _count_heavy_waves(WG.build(1, 0, false))
	if op_heavy != 1:
		lines.append("FAIL opener heavy waves=%d expected 1 (coda only)" % op_heavy); fails += 1
	# Node 2+ in sector 1: midpoint anchor + coda -> at least 2.
	for li in [1, 2, 3]:
		var hw: int = _count_heavy_waves(WG.build(1, li, false))
		if hw < 2:
			lines.append("FAIL (1,%d) heavy waves=%d expected >=2 (midpoint+coda)" % [li, hw]); fails += 1

	# --- sector ramp: capitals appear in sector 2 ------------------------
	var saw_capital: bool = false
	for li in range(0, 4):
		for w in WG.build(2, li, false).waves:
			if _hclass(w) == "capital":
				saw_capital = true
	if not saw_capital:
		lines.append("FAIL no capital (64px) heavy across sector 2 nodes 0-3"); fails += 1

	# --- no softlock sweep + sample report -------------------------------
	for sd in range(1, 4):
		for li in range(0, 6):
			var lvl2 = WG.build(sd, li, false)
			if lvl2 == null or lvl2.waves.is_empty():
				lines.append("FAIL (%d,%d) empty build" % [sd, li]); fails += 1

	# Sample: show the tail heavy of a few nodes for eyeballing.
	for coord in [[1, 0], [1, 2], [2, 1], [3, 3]]:
		var lvl3 = WG.build(coord[0], coord[1], false)
		var sz3: int = lvl3.waves.size()
		var last = lvl3.waves[sz3 - 1]
		var prev = lvl3.waves[sz3 - 2] if sz3 >= 2 else null
		var heavy_w = last if _hclass(last) != "" else prev
		var hc: String = _hclass(heavy_w)
		var nm: String = heavy_w.enemy_scene.resource_path.get_file() if heavy_w and heavy_w.enemy_scene else "?"
		lines.append("(%d,%d) n=%d coda=%s[%s]x%d  heavy_waves=%d" % [
			coord[0], coord[1], sz3, nm, hc, int(heavy_w.count) if heavy_w else 0, _count_heavy_waves(lvl3)])

	lines.append("HEAVY BEATS TEST: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	return true
