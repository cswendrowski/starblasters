extends SceneTree

# Editor load sanity (Roman bug 2026-06-08): the Pattern Eligibility editor must NOT surface
# retired movement keys, even when overlaying a stale user://tuners JSON saved before the pattern
# overhaul. Boots the real editor scene (which runs _load_data against the real save file) and
# asserts every identity + eligible key is a live MOVEMENT_KEY. Also checks the preview builds the
# LITERAL selected key (not the matrix identity).
# NOTE: work runs in _process, not _init — _ready only fires once the loop iterates.
# Run: godot --headless --script res://tools/test_eligibility_editor_load.gd

const RESULT := "res://tools/_editor_load_result.txt"
const SCENE := "res://scenes/dev/pattern_eligibility_editor.tscn"
const EnemyRoster := preload("res://scripts/levels/enemy_roster.gd")

var _frame := 0
var _ed = null

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var ps: PackedScene = load(SCENE)
		if ps == null:
			_write(["FAIL could not load editor scene", "EDITOR LOAD: FAIL"]); return true
		_ed = ps.instantiate()
		root.add_child(_ed)  # _ready -> _load_data (+ overlays the real stale JSON)
		return false
	# Frame 2: _ready has fired; inspect the loaded data.
	var lines: Array = []
	var fails := 0
	var keys: Array = _ed.MOVEMENT_KEYS
	var bad := {}
	for scene in _ed._data.keys():
		var rec: Dictionary = _ed._data[scene]
		var ident: String = str(rec.get("identity", ""))
		if ident != "" and not (ident in keys):
			bad[ident] = true; fails += 1
		for e in rec.get("eligible", []):
			if not (str(e) in keys):
				bad[str(e)] = true; fails += 1
	if not bad.is_empty():
		lines.append("FAIL retired keys still present: " + str(bad.keys()))
	else:
		lines.append("all identities + eligible keys are live (%d enemies)" % _ed._data.size())
	if _ed._data.size() < 20:
		lines.append("FAIL editor loaded too few enemies (%d)" % _ed._data.size()); fails += 1
	# Preview builds the literal key, not the resolved identity.
	var weave = EnemyRoster.make_movement({"movement": "lane_weave"})
	var drift = EnemyRoster.make_movement({"movement": "drift_high"})
	if weave == null or String(weave.get_script().resource_path).get_file() != "lane_path.gd":
		lines.append("FAIL lane_weave preview did not build lane_path"); fails += 1
	if drift == null or String(drift.get_script().resource_path).get_file() != "drift.gd":
		lines.append("FAIL drift_high preview did not build drift"); fails += 1
	lines.append("EDITOR LOAD: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	_write(lines)
	return true

func _write(lines: Array) -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
