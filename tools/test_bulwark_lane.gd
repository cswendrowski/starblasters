extends SceneTree

# Bulwark on-lane migration (2026-06-08): the Bulwark now extends enemy_core and moves via the
# shared Drift pattern instead of bespoke inertial thrust. Verify it instantiates, starts on the
# pattern, descends to the hold height (~90), and holds there — no crash, no legacy-anchor
# fallback (the scene has no MoveTimer/ShootTimer).
# Work runs on the first _process frame (so add_child has fired _ready), then ticks the node
# manually and quits the same frame.
# Run: godot --headless --script res://tools/test_bulwark_lane.gd

const RESULT := "res://tools/_bulwark_lane_result.txt"
const SCENE := "res://scenes/enemies/factions/corporate/enemy_bulwark.tscn"

var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails := 0
	var ps: PackedScene = load(SCENE)
	if ps == null:
		_write(["FAIL could not load bulwark scene", "BULWARK LANE: FAIL"]); return true
	var b = ps.instantiate()
	root.add_child(b)            # fires _ready (default Drift, shield, turret)
	if b.has_method("start"):
		b.start(Vector2(Lanes.lane_center(3), 20.0))
	# Tick the node's own _process manually for ~3.5s of frames.
	var dt := 1.0 / 60.0
	for _i in range(210):
		if is_instance_valid(b):
			b._process(dt)
	if not ("movement" in b):
		lines.append("FAIL bulwark has no 'movement' slot (not enemy_core)"); fails += 1
	if b.movement == null:
		lines.append("FAIL default movement not assigned"); fails += 1
	else:
		lines.append("movement = %s" % String(b.movement.get_script().resource_path).get_file())
	var y: float = b.position.y
	if abs(y - 90.0) > 12.0:
		lines.append("FAIL did not settle near hold y=90 (y=%.1f)" % y); fails += 1
	else:
		lines.append("settled y=%.1f (target 90)" % y)
	if b.get_node_or_null("Turret") == null:
		lines.append("FAIL turret child missing"); fails += 1
	if b.components.is_empty():
		lines.append("FAIL shield component missing"); fails += 1
	lines.append("BULWARK LANE: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	_write(lines)
	return true

func _write(lines: Array) -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
