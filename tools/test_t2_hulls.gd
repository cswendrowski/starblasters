extends SceneTree

# T2 hull migration (2026-06-08): bomber/cruiser/drone_carrier now extend enemy_core with the
# Drift movement pattern. Verify each instantiates, starts on the pattern, descends to its hold,
# and doesn't crash (no legacy-anchor fallback). Bomber's arc-gated tail turret is added in _ready
# (assert present); cruiser turrets / carrier drones are call_deferred so not checked here.
# Run: godot --headless --script res://tools/test_t2_hulls.gd

const RESULT := "res://tools/_t2_hulls_result.txt"
const Roster := preload("res://scripts/levels/enemy_roster.gd")

var _done := false

func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails := 0
	var dt := 1.0 / 60.0

	_check(lines, "bomber", "res://scenes/enemies/core/enemy_bomber.tscn", "drift_mid",
		Vector2(Lanes.lane_center(3), 10.0), 240, 90.0, "TailGun")
	_check(lines, "cruiser", "res://scenes/enemies/core/enemy_cruiser.tscn", "drift_high",
		Vector2(Lanes.lane_center(3), 10.0), 160, 50.0, "")
	_check(lines, "carrier", "res://scenes/enemies/factions/corporate/enemy_drone_carrier.tscn", "drift_high",
		Vector2(Lanes.lane_center(3), 10.0), 160, 50.0, "")

	# accumulate fail count
	for l in lines:
		if "FAIL" in l:
			fails += 1
	lines.append("T2 HULLS: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines))); f.close()
	return true

func _check(lines: Array, name: String, scene_path: String, mv: String, spawn: Vector2,
		ticks: int, hold_y: float, child: String) -> void:
	var ps: PackedScene = load(scene_path)
	if ps == null:
		lines.append("FAIL %s: scene load" % name); return
	var e = ps.instantiate()
	root.add_child(e)
	e.movement = Roster.make_movement({"movement": mv})
	e.start(spawn)
	var dt := 1.0 / 60.0
	for _i in range(ticks):
		if is_instance_valid(e): e._process(dt)
	if not is_instance_valid(e):
		lines.append("FAIL %s: freed unexpectedly" % name); return
	if absf(e.position.y - hold_y) > 18.0:
		lines.append("FAIL %s: did not settle near y=%.0f (y=%.1f)" % [name, hold_y, e.position.y])
	else:
		lines.append("%s settled y=%.1f" % [name, e.position.y])
	if child != "" and e.get_node_or_null(child) == null:
		lines.append("FAIL %s: missing child %s" % [name, child])
	elif child != "":
		lines.append("%s has %s" % [name, child])
