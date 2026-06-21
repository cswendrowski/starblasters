extends SceneTree

# P2a crosser height-stagger. Spawns a stream of crossers (side_traverse movement)
# through the real WaveDirector._spawn_enemy and confirms they DON'T all ride the
# same latitude — successive crossers settle at staggered travel_y (which the
# pattern writes to position.y in on_start). Run:
#   godot --headless --script res://tools/test_crosser_stagger.gd

const RESULT := "res://tools/_crosser_stagger_result.txt"
const DirectorScript := preload("res://scripts/levels/director.gd")
const WaveSpec := preload("res://scripts/levels/wave_def.gd")
const SideTraverse := preload("res://scripts/enemies/patterns/side_traverse.gd")

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
	world.add_child(director)   # director.get_parent() == world == spawn parent

	# A crosser spec: dart hull (enemy_core) driven by side_traverse.
	var spec := WaveSpec.new()
	spec.enemy_scene = load("res://scenes/enemies/core/enemy_core_s_dart.tscn")
	var mv = SideTraverse.new()
	mv.direction = 1
	spec.movement_override = mv
	spec.count = 8
	spec.spawn_y = 0.0
	spec.formation = 0   # TOP — the path crossers actually take in production

	# Helper unit check: distinct bands, consecutive differ, stays in upper band.
	var ys_helper: Array = []
	for i in 8:
		ys_helper.append(director._crosser_travel_y(80.0, i))
	var distinct := {}
	for y in ys_helper:
		distinct[y] = true
	if distinct.size() < director.CROSSER_STAGGER_BANDS:
		lines.append("FAIL helper produced %d distinct bands, want >= %d" % [distinct.size(), director.CROSSER_STAGGER_BANDS]); fails += 1
	for i in range(1, 8):
		if is_equal_approx(ys_helper[i], ys_helper[i - 1]):
			lines.append("FAIL helper: consecutive crossers %d/%d share y=%.1f" % [i - 1, i, ys_helper[i]]); fails += 1
			break
	for y in ys_helper:
		if y < 60.0 or y > 200.0:
			lines.append("FAIL helper: travel_y %.1f out of upper band" % y); fails += 1
			break

	# Integration: spawn 8 through the director, read the settled latitudes.
	for i in 8:
		director._spawn_enemy(spec, i)
	var ys: Array = []
	for e in world.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			ys.append(e.position.y)
	if ys.size() != 8:
		lines.append("FAIL expected 8 crossers spawned, got %d" % ys.size()); fails += 1
	var ys_distinct := {}
	for y in ys:
		ys_distinct[snappedf(y, 0.5)] = true
	if ys_distinct.size() < director.CROSSER_STAGGER_BANDS:
		lines.append("FAIL spawned crossers ride only %d latitudes, want >= %d (all same = no stagger)" % [ys_distinct.size(), director.CROSSER_STAGGER_BANDS]); fails += 1

	lines.append("helper ys=%s ; spawned distinct latitudes=%d" % [str(ys_helper), ys_distinct.size()])
	lines.append("CROSSER STAGGER: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	quit()
	return true
