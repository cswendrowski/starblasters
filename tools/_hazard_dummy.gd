extends Node2D
# Test stand-in: a node that reports as a hazard (is_hazard == true) so LaneTraffic
# occupancy queries skip it. Used by test_lane_traffic.gd.
var is_hazard: bool = true
