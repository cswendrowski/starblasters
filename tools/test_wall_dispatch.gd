extends SceneTree

# WALL dispatch seam (construction §8, dart-trickle fix). Verifies the producer can
# now request a wall through the WaveGen -> ScoreAdapter -> conductor seam:
#   1) ScoreAdapter._shape_id maps the new Formation.WALL/PINCER enum values.
#   2) dart + bomb_drone roster entries are tagged `wall: true`.
#   3) WaveGen._make_wave_spec stamps Formation.WALL onto a wall-tagged single wave
#      (and the tandem roll / random spread no longer stomp it).
# Run: godot --headless --script res://tools/test_wall_dispatch.gd

const RESULT := "res://tools/_wall_dispatch_result.txt"
const WG := preload("res://scripts/levels/wave_generator.gd")
const ScoreAdapter := preload("res://scripts/levels/score_adapter.gd")
const WaveSpec := preload("res://scripts/levels/wave_def.gd")
const Roster := preload("res://scripts/levels/enemy_roster.gd")

var _done := false


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails: int = 0

	# 1) Adapter maps the new enum values.
	var w_wall := WaveSpec.new()
	w_wall.formation = WaveSpec.Formation.WALL
	var w_pincer := WaveSpec.new()
	w_pincer.formation = WaveSpec.Formation.PINCER
	if ScoreAdapter._shape_id(w_wall) != &"wall":
		lines.append("FAIL _shape_id(WALL) != &wall (got %s)" % str(ScoreAdapter._shape_id(w_wall))); fails += 1
	if ScoreAdapter._shape_id(w_pincer) != &"pincer":
		lines.append("FAIL _shape_id(PINCER) != &pincer"); fails += 1

	# 2) Fast chaff tagged wall.
	for path in ["res://scenes/enemies/enemy_dart.tscn", "res://scenes/enemies/enemy_bomb_drone.tscn"]:
		var e: Dictionary = Roster.entry_for_scene(path)
		if e.is_empty() or not bool(e.get("wall", false)):
			lines.append("FAIL %s not tagged wall" % path); fails += 1

	# 3) _make_wave_spec stamps WALL on a wall-tagged wave, robustly across seeds
	#    (the random spread + 25% tandem roll must never win for a wall entry).
	var dart: Dictionary = Roster.entry_for_scene("res://scenes/enemies/enemy_dart.tscn")
	var wall_count: int = 0
	for seed in range(40):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + seed
		# level_index 2 makes the tandem roll eligible — the case that used to stomp.
		var w = WG._make_wave_spec(rng, dart, 1, 2, 1)
		if int(w.formation) == int(WaveSpec.Formation.WALL):
			wall_count += 1
	if wall_count != 40:
		lines.append("FAIL dart wall stamp held only %d/40 seeds" % wall_count); fails += 1

	# Sanity: a non-wall chaff entry (drifter) is NOT forced to wall.
	var drifter: Dictionary = Roster.entry_for_scene("res://scenes/enemies/enemy_drifter.tscn")
	if not drifter.is_empty():
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 7
		var wd = WG._make_wave_spec(rng2, drifter, 1, 2, 1)
		if int(wd.formation) == int(WaveSpec.Formation.WALL):
			lines.append("FAIL drifter (untagged) got WALL formation"); fails += 1

	lines.append("dart wall stamp = %d/40 ; shape map wall/pincer ok=%s" % [
		wall_count, str(ScoreAdapter._shape_id(w_wall) == &"wall" and ScoreAdapter._shape_id(w_pincer) == &"pincer")])
	lines.append("WALL DISPATCH TEST: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	return true
