extends SceneTree

# Focused check for the recycling-ghost depth pin (RecycleController._sink_ghost/_raise_ghost,
# Roman 2026-07-28). A recycling ship must render BEHIND the ground plane it flies back over, and
# must land back on its EXACT pre-cycle depth afterwards — including enemies that pin z absolutely
# (ground structures) rather than relatively.
#
# Run: godot --path . --headless -s res://tools/test_recycle_ghost_depth.gd

const Recycle = preload("res://scripts/effects/recycle_controller.gd")

var _fails: int = 0


func _ok(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		print("  FAIL  ", label)
		_fails += 1


func _init() -> void:
	print("=== recycle ghost depth ===")

	# 1. A default relative-z enemy sinks below the deepest station layer and round-trips.
	var a := Node2D.new()
	a.z_index = 0
	a.z_as_relative = true
	Recycle._sink_ghost(a)
	_ok(a.z_index == Recycle.GHOST_Z, "relative enemy sinks to GHOST_Z (%d)" % a.z_index)
	_ok(a.z_as_relative == false, "pinned absolutely while cycling")
	_ok(a.z_index < -16, "clears the station stack floor (-16)")
	_ok(a.z_index < -8, "clears the stronghold rock (-8)")
	_ok(a.z_index < -1, "clears loose asteroid-POI rocks (-1)")
	Recycle._raise_ghost(a)
	_ok(a.z_index == 0 and a.z_as_relative == true, "round-trips to z 0 / relative")
	a.free()

	# 2. An enemy that already pins z ABSOLUTELY restores both fields, not just z_index.
	var b := Node2D.new()
	b.z_index = -5
	b.z_as_relative = false
	Recycle._sink_ghost(b)
	_ok(b.z_index == Recycle.GHOST_Z, "absolute-z enemy sinks too")
	Recycle._raise_ghost(b)
	_ok(b.z_index == -5 and b.z_as_relative == false, "round-trips to z -5 / absolute")
	b.free()

	# 3. Idempotent sink: a double call must not overwrite the stash with the ghost value (which
	#    would strand the enemy at GHOST_Z forever after restore).
	var c := Node2D.new()
	c.z_index = 3
	c.z_as_relative = true
	Recycle._sink_ghost(c)
	Recycle._sink_ghost(c)
	Recycle._raise_ghost(c)
	_ok(c.z_index == 3 and c.z_as_relative == true, "double-sink still round-trips to z 3")
	c.free()

	# 4. Raise without a prior sink is a no-op, not a crash / bogus write.
	var d := Node2D.new()
	d.z_index = 7
	Recycle._raise_ghost(d)
	_ok(d.z_index == 7, "raise without sink leaves z untouched")
	_ok(not d.has_meta("_recycle_depth"), "no depth meta left behind")
	d.free()

	print("VERDICT: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
