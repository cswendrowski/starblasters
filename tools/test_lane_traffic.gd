extends SceneTree

# P2c.1 LaneTraffic occupancy queries. Places dummy enemies in known lanes and
# verifies is_lane_free / free_adjacent read occupancy correctly (lane match +
# vertical window + exclude + hazard skip). Run:
#   godot --headless --script res://tools/test_lane_traffic.gd

const RESULT := "res://tools/_lane_traffic_result.txt"
const LaneTraffic := preload("res://scripts/systems/lane_traffic.gd")

var _done := false


func _enemy(lane: int, y: float, hazard: bool = false) -> Node2D:
	var n := Node2D.new()
	n.position = Vector2(Lanes.lane_center(lane), y)
	if hazard:
		n.set_meta("dummy", true)
	root.add_child(n)
	n.add_to_group("enemies")
	return n


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails: int = 0

	var occ2 := _enemy(2, 100.0)
	_enemy(4, 100.0)

	# occupied lane @ same height -> not free
	if LaneTraffic.is_lane_free(self, 2, 100.0):
		lines.append("FAIL lane 2 @100 reported free (occupied)"); fails += 1
	# empty lane -> free
	if not LaneTraffic.is_lane_free(self, 3, 100.0):
		lines.append("FAIL lane 3 @100 reported occupied (empty)"); fails += 1
	# same lane, far in Y -> free (outside window)
	if not LaneTraffic.is_lane_free(self, 2, 200.0):
		lines.append("FAIL lane 2 @200 reported occupied (occupant @100 is 100px away)"); fails += 1
	# exclude the occupant -> free
	if not LaneTraffic.is_lane_free(self, 2, 100.0, occ2):
		lines.append("FAIL lane 2 @100 not free when occupant excluded"); fails += 1

	# free_adjacent
	if LaneTraffic.free_adjacent(self, 1, 1, 100.0) != -1:  # lane 2 occupied
		lines.append("FAIL free_adjacent(1,+1) should be -1 (lane2 occupied)"); fails += 1
	if LaneTraffic.free_adjacent(self, 5, 1, 100.0) != 6:   # lane 6 empty
		lines.append("FAIL free_adjacent(5,+1) should be 6"); fails += 1
	if LaneTraffic.free_adjacent(self, 0, -1, 100.0) != -1: # off the edge
		lines.append("FAIL free_adjacent(0,-1) should be -1 (edge)"); fails += 1

	# hazard occupant is ignored. Add a hazard-flagged node in lane 3.
	var haz := Node2D.new()
	haz.position = Vector2(Lanes.lane_center(3), 100.0)
	# emulate an is_hazard property via a tiny script-less stand-in: use a CharacterBody?
	# Simplest: a Node2D won't have is_hazard, so it would NOT be skipped. Use a
	# dedicated dummy with the property instead.
	haz.add_to_group("enemies")
	root.add_child(haz)
	haz.set_script(preload("res://tools/_hazard_dummy.gd"))
	if not LaneTraffic.is_lane_free(self, 3, 100.0):
		lines.append("FAIL lane 3 with a HAZARD occupant should still be free (hazards ignored)"); fails += 1

	lines.append("LANE TRAFFIC: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
	return true
