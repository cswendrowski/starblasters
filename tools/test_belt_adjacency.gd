extends SceneTree

# Headless unit check for sector_map_v3._is_belt_adjacent. The function is never
# reached by a normal --quit-after boot (it fires on POI click, behind the gate),
# so this exercises it directly against hand-built row caches.
#
# Run: Godot --headless --script res://tools/test_belt_adjacency.gd

const SMV3 := preload("res://scripts/sector_map_v3.gd")


func _make_poi(id: String, x: float, sub: String) -> Dictionary:
	return {"id": id, "pos": Vector2(x, 64.0), "hazard_subtype": sub, "completed": false, "node_type": 0}


func _init() -> void:
	# Autoloads are attached to root AFTER _init; defer one frame so /root/Run exists.
	_deferred_run.call_deferred()


func _deferred_run() -> void:
	var run := root.get_node_or_null("/root/Run")
	if run == null:
		push_error("[belt_test] Run autoload missing"); quit(1); return

	# Row: [combat, asteroid_field, combat] — index 0 and 2 are ADJACENT to the
	# field at index 1; the field itself is handled by the caller, not this fn.
	var row_adj := {
		"pois": [
			_make_poi("p0", 160.0, ""),
			_make_poi("p1", 240.0, "asteroid_field"),
			_make_poi("p2", 320.0, ""),
		],
		"boss": {"pos": Vector2(448.0, 64.0), "completed": false, "id": "b0"},
	}
	# Row: [combat, minefield, combat] — no belt anywhere -> never adjacent.
	var row_none := {
		"pois": [
			_make_poi("q0", 160.0, ""),
			_make_poi("q1", 240.0, "minefield"),
			_make_poi("q2", 320.0, ""),
		],
		"boss": {"pos": Vector2(448.0, 64.0), "completed": false, "id": "b1"},
	}

	var smv3 := SMV3.new()
	root.add_child(smv3)  # so get_node("/root/Run") inside the fn resolves

	var fails := 0

	run.sector_map_cache = {"rows": [row_adj]}
	# p0 and p2 neighbor the field -> true. p1 is the field itself -> its only
	# neighbors are non-field, so adjacency returns false (caller handles "is").
	fails += _expect("adj p0 (left of field)",  smv3._is_belt_adjacent(row_adj.pois[0], 0), true)
	fails += _expect("adj p2 (right of field)", smv3._is_belt_adjacent(row_adj.pois[2], 0), true)
	fails += _expect("adj p1 (the field)",      smv3._is_belt_adjacent(row_adj.pois[1], 0), false)

	run.sector_map_cache = {"rows": [row_none]}
	fails += _expect("none q0", smv3._is_belt_adjacent(row_none.pois[0], 0), false)
	fails += _expect("none q1", smv3._is_belt_adjacent(row_none.pois[1], 0), false)
	fails += _expect("none q2", smv3._is_belt_adjacent(row_none.pois[2], 0), false)

	# Out-of-range row index -> false, no crash.
	fails += _expect("bad row idx", smv3._is_belt_adjacent(row_adj.pois[0], 99), false)

	if fails == 0:
		print("[belt_test] ALL PASS")
		quit(0)
	else:
		push_error("[belt_test] %d FAILURES" % fails)
		quit(1)


func _expect(label: String, got: bool, want: bool) -> int:
	if got == want:
		print("[belt_test] PASS  %-22s got=%s" % [label, got])
		return 0
	push_error("[belt_test] FAIL  %-22s got=%s want=%s" % [label, got, want])
	return 1
