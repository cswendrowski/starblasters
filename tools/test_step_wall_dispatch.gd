extends SceneTree

# P2d.2 conductor step_wall dispatch. Verifies _step_wall_layout (contiguous block,
# on-board offset bounds, dir toward the gap) and that _dispatch_step_wall spawns a
# coordinated row: every member gets step_synced + identical lo/hi/dir, on a
# contiguous block of lanes leaving a gap. (Unison MOTION is covered by
# test_step_wall.) Run: godot --headless --script res://tools/test_step_wall_dispatch.gd

const RESULT := "res://tools/_step_wall_dispatch_result.txt"
const DirectorScript := preload("res://scripts/levels/director.gd")
const WaveSpec := preload("res://scripts/levels/wave_def.gd")
const Phrase := preload("res://scripts/levels/phrase.gd")
const LanePath := preload("res://scripts/enemies/patterns/lane_path.gd")

var _done := false


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var lines: Array = []
	var fails: int = 0

	var world := Node2D.new()
	root.add_child(world)
	var director = DirectorScript.new()
	world.add_child(director)

	# Layout: 5-member row -> 5 contiguous lanes, bounds keep the block on-board.
	var lay: Dictionary = director._step_wall_layout(5)
	var lanes: Array = lay["lanes"]
	if lanes.size() != 5:
		lines.append("FAIL layout size %d != 5" % lanes.size()); fails += 1
	for i in range(1, lanes.size()):
		if int(lanes[i]) != int(lanes[i - 1]) + 1:
			lines.append("FAIL layout lanes not contiguous: %s" % str(lanes)); fails += 1
			break
	if int(lanes[0]) + int(lay["lo"]) < 0:
		lines.append("FAIL layout lo pushes left edge off-board"); fails += 1
	if int(lanes[lanes.size() - 1]) + int(lay["hi"]) > Lanes.COUNT - 1:
		lines.append("FAIL layout hi pushes right edge off-board"); fails += 1
	if absi(int(lay["dir"])) != 1:
		lines.append("FAIL layout dir not +/-1"); fails += 1

	# Dispatch: build a step_wall phrase of 5 STEP enemies and dispatch it.
	var spec := WaveSpec.new()
	spec.enemy_scene = load("res://scenes/enemies/core/enemy_dart.tscn")
	var mv = LanePath.new()
	mv.shape = LanePath.Shape.STEP
	spec.movement_override = mv
	spec.count = 5
	spec.formation = WaveSpec.Formation.STEP_WALL
	var ph = Phrase.new()
	ph.kind = Phrase.Kind.FORMATION
	ph.specs = [spec]
	ph.shape = &"step_wall"
	director._running = true   # dispatch checks _running
	director._dispatch_step_wall(ph)

	var spawned: Array = []
	for e in world.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			spawned.append(e)
	if spawned.size() != 5:
		lines.append("FAIL spawned %d != 5" % spawned.size()); fails += 1

	# All members: step_synced, identical lo/hi/dir; lanes contiguous with a gap.
	var los := {}
	var his := {}
	var dirs := {}
	var occ_lanes := {}
	for e in spawned:
		if not ("movement" in e) or e.movement == null:
			lines.append("FAIL member has no movement"); fails += 1; continue
		if not e.movement.step_synced:
			lines.append("FAIL member not step_synced"); fails += 1
		los[e.movement.step_offset_lo] = true
		his[e.movement.step_offset_hi] = true
		dirs[e.movement.step_start_dir] = true
		occ_lanes[Lanes.nearest_lane(e.position.x)] = true
	if los.size() != 1 or his.size() != 1 or dirs.size() != 1:
		lines.append("FAIL members disagree on sync params (lo=%d hi=%d dir=%d distinct)" % [los.size(), his.size(), dirs.size()]); fails += 1
	if occ_lanes.size() >= Lanes.COUNT:
		lines.append("FAIL step wall left no gap lane (filled all %d)" % Lanes.COUNT); fails += 1

	lines.append("layout lanes=%s lo=%d hi=%d dir=%d ; spawned=%d occupied_lanes=%d" % [
		str(lanes), int(lay["lo"]), int(lay["hi"]), int(lay["dir"]), spawned.size(), occ_lanes.size()])
	lines.append("STEP WALL DISPATCH: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
	return true
