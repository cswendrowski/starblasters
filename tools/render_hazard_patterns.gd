extends SceneTree

# Render the authored HAZARD patterns (asteroid/mine-pinned, by CONTENT not tag) as ASCII lane×row
# grids so the navigable channels/gaps can be studied. Row 0 = leads (bottom, enters first).
#   godot --path . --headless -s tools/render_hazard_patterns.gd

const SAVE_PATH := "user://tuners/wave_patterns.json"
const COUNT := 7   # lanes

func _initialize() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var lib = JSON.parse_string(f.get_as_text())
	f.close()
	for p in lib:
		var pls: Array = p.get("placements", [])
		if pls.is_empty():
			continue
		var kind := _hazard_kind(pls)
		if kind == "":
			continue   # not hazard-pinned — skip (general combat pattern)
		_render(str(p.get("name", "?")), str(p.get("faction", "?")), kind, pls)
	quit()

func _hazard_kind(pls: Array) -> String:
	for pl in pls:
		var e: String = String(pl.get("enemy", "")).to_lower()
		if e.contains("asteroid"):
			return "asteroid"
		if e.contains("mine") or e.contains("bomblet"):
			return "mine"
	return ""

func _render(nm: String, fac: String, kind: String, pls: Array) -> void:
	var max_row := 0
	var occupied := {}
	for pl in pls:
		var lane := int(pl.get("lane", 0))
		var row := int(pl.get("row", 0))
		max_row = maxi(max_row, row)
		occupied["%d,%d" % [lane, row]] = true
	print("\n=== %-20s [%s]  faction=%s  n=%d  rows=%d ===" % [nm, kind, fac, pls.size(), max_row + 1])
	for r in range(max_row, -1, -1):
		var line := ""
		for lane in COUNT:
			line += "#" if occupied.has("%d,%d" % [lane, r]) else "·"
		print("   ", line, "   row %d" % r)
