extends Area2D
# Test stand-in for the player hull: has a `hull` property + take_damage (what the
# firecore hazard's contact check looks for). Used by test_firecore_hazard.gd.
var hull: int = 10
var taken: int = 0
func take_damage(d: int) -> void:
	hull -= d
	taken += d
