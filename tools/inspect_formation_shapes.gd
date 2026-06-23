extends SceneTree

# Dump formation_shapes.gd placements as ASCII grids so the geometry can be eyeballed and lane/row
# validity checked (conductor readability pass, 2026-06-23).
#   godot --path . --headless -s tools/inspect_formation_shapes.gd

const FormationShapes = preload("res://scripts/levels/formation_shapes.gd")
const Lanes = preload("res://scripts/systems/lanes.gd")

func _initialize() -> void:
	for shape in FormationShapes.SHAPES:
		for count in [6, 9, 12]:
			_dump(shape, count)
	print("VERDICT: shapes dumped")
	quit()

func _dump(shape: StringName, count: int) -> void:
	var cells: Array = FormationShapes.placements(shape, count)
	var max_row: int = 0
	var bad: int = 0
	for c in cells:
		max_row = maxi(max_row, int(c.y))
		if int(c.x) < 0 or int(c.x) >= Lanes.COUNT:
			bad += 1
	print("\n=== %s  count=%d  -> %d cells, %d rows%s ===" % [
		shape, count, cells.size(), max_row + 1,
		("  [%d OFF-GRID!]" % bad) if bad > 0 else ""])
	# Render top row (highest, trails) down to row 0 (leads, bottom) — as it appears on screen.
	for r in range(max_row, -1, -1):
		var line: String = ""
		for lane in Lanes.COUNT:
			line += "#" if _has(cells, lane, r) else "."
		print("  ", line)

func _has(cells: Array, lane: int, row: int) -> bool:
	for c in cells:
		if int(c.x) == lane and int(c.y) == row:
			return true
	return false
