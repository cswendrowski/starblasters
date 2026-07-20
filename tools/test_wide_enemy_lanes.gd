extends SceneTree

# Wide-enemy edge-lane containment (2026-07-18). Cruisers + Harriers are ~64-78px WIDE; in an edge
# lane a naive lane-center spawn puts half the hull off the playfield band. This spawns both through
# the REAL WaveDirector._spawn_enemy into EVERY lane (lane_override) and asserts the measured hull
# edges stay inside [Playfield.X_MIN, X_MAX]. Also checks the natural TOP path avoids the edge lanes.
#   godot --headless --script res://tools/test_wide_enemy_lanes.gd

const DirectorScript := preload("res://scripts/levels/director.gd")
const WaveSpec := preload("res://scripts/levels/wave_def.gd")
const Playfield := preload("res://scripts/systems/playfield.gd")
const Lanes := preload("res://scripts/systems/lanes.gd")

const WIDE := {
	"Cruiser (multi-part)": "res://scenes/enemies/core/enemy_cruiser.tscn",
	"Harrier": "res://scenes/enemies/factions/privateer/enemy_p_l_harrier.tscn",
}

var _done := false


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var fails: int = 0
	var world := Node2D.new()
	root.add_child(world)
	var director = DirectorScript.new()
	world.add_child(director)

	for label in WIDE:
		var scene_path: String = WIDE[label]
		# Measure the composite half-width once from a bare probe.
		var probe = load(scene_path).instantiate()
		var hw: float = director._enemy_half_width(probe)
		probe.free()
		print("%s: composite half-width = %.1f px (full ~%.0f)" % [label, hw, hw * 2.0])

		# Spawn into every lane and assert hull edges stay in-band.
		for lane in Lanes.COUNT:
			var spec := WaveSpec.new()
			spec.enemy_scene = load(scene_path)
			spec.count = 1
			spec.spawn_y = 20.0
			var enemy = director._spawn_enemy(spec, 0, lane)
			if enemy == null:
				print("  FAIL lane %d: null spawn" % lane)
				fails += 1
				continue
			var x: float = enemy.position.x
			var left: float = x - hw
			var right: float = x + hw
			var ok: bool = left >= Playfield.X_MIN - 0.01 and right <= Playfield.X_MAX + 0.01
			if not ok:
				fails += 1
			print("  lane %d: center=%.1f x=%.1f edges=[%.1f, %.1f]  %s" % [
				lane, Lanes.lane_center(lane), x, left, right, ("OK" if ok else "OFF-BAND")])
			enemy.free()

	print("wide-enemy lane containment: %d failures" % fails)
	print("VERDICT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit()
	return true
