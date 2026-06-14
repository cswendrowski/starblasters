extends Object

# Referenced via preload (const LaneTraffic = preload(...)), not a global class_name:
# a brand-new class_name isn't registered in headless --script runs until the class
# cache regenerates, and lane_path.gd needs it at parse time. Preload is the
# codebase convention for pattern/util dependencies (see enemy_roster).

# Runtime lane-occupancy queries for lane-CHANGING movement patterns (P2 row
# choreography). A lane-changer (Shifter / Drifter) calls is_lane_free before
# committing to a target lane so two enemies don't merge into the same column at the
# same height. Pure on-demand scan of the "enemies" group — there is NO reservation
# state to maintain or leak; occupancy is read from live positions each query.
#
# Lane detection mirrors the director (_occupied_lanes): nearest_lane(position.x).
# Enemies are parented at the world origin so position == global_position.

# Vertical window (px) around the query Y within which another enemy in `lane`
# counts as blocking — roughly one enemy height + margin.
const DEFAULT_Y_WINDOW: float = 28.0


# True if no OTHER non-hazard enemy occupies `lane` within y_window of `y`.
static func is_lane_free(tree: SceneTree, lane: int, y: float, exclude: Object = null, y_window: float = DEFAULT_Y_WINDOW) -> bool:
	if tree == null:
		return true
	for e in tree.get_nodes_in_group("enemies"):
		if e == exclude or not is_instance_valid(e) or not (e is Node2D):
			continue
		if "is_hazard" in e and e.is_hazard:
			continue
		if Lanes.nearest_lane(e.position.x) == lane and absf(e.position.y - y) < y_window:
			return false
	return true


# The adjacent lane in `dir` (+1 right / -1 left) if it exists AND is free; else -1.
static func free_adjacent(tree: SceneTree, from_lane: int, dir: int, y: float, exclude: Object = null, y_window: float = DEFAULT_Y_WINDOW) -> int:
	var target: int = from_lane + dir
	if target < 0 or target >= Lanes.COUNT:
		return -1
	if is_lane_free(tree, target, y, exclude, y_window):
		return target
	return -1
