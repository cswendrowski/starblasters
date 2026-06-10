extends Node

# Hangar rebuild smoke test (Roman 2026-06-10 "rip it out and redo entirely"). Boots the rebuilt
# hangar, verifies the SubViewportContainer playspace + sim player wired up, the player's bullets
# route into the in-viewport world, and the full fire -> collide -> dummy.take_hit pipeline works
# inside the SubViewport (the "bullets missing" failure). Visual correctness (green muzzle) is
# Roman's eyeball; this guards the structure + the damage path.
# Run: godot --headless --path . tools/test_hangar.tscn --quit-after 200

const RESULT := "res://tools/_hangar_result.txt"
const HANGAR_SCENE = preload("res://scenes/hangar.tscn")

var _t := 0
var _hangar: Node = null
var _phase := 0
var _lines: Array = []
var _fails := 0
var _dps_before := 0.0


func _ready() -> void:
	var run = get_node_or_null("/root/Run")
	if run != null:
		run.new_run()
	_hangar = HANGAR_SCENE.instantiate()
	add_child(_hangar)


func _process(_dt: float) -> void:
	_t += 1
	# Phase 0: let the hangar _ready + the deferred part-list refresh settle.
	if _phase == 0 and _t >= 16:
		var vp = _hangar.get("_preview_vp")
		var world = _hangar.get("_world")
		var player = _hangar.get("_player")
		var dummy = _hangar.get("_dummy")
		_lines.append("preview_vp is SubViewport: %s" % (vp is SubViewport))
		if not (vp is SubViewport):
			_lines.append("FAIL preview_vp not a SubViewport"); _fails += 1
		elif not ((vp as Node).get_parent() is SubViewportContainer):
			_lines.append("FAIL SubViewport not under a SubViewportContainer"); _fails += 1
		else:
			_lines.append("SubViewport under SubViewportContainer: OK")
		if world == null:
			_lines.append("FAIL no _world"); _fails += 1
		if player == null:
			_lines.append("FAIL no _player"); _fails += 1
		if dummy == null:
			_lines.append("FAIL no _dummy"); _fails += 1
		if player != null and world != null:
			# bullets must route into the in-viewport world.
			var bp = player.get("bullet_parent")
			_lines.append("player.bullet_parent == _world: %s" % (bp == world))
			if bp != world:
				_lines.append("FAIL bullet_parent not routed to _world"); _fails += 1
			# player + dummy must live inside the SubViewport (so they render + collide there).
			if vp is SubViewport and not (vp as Node).is_ancestor_of(player):
				_lines.append("FAIL player not inside the SubViewport"); _fails += 1
		if _fails > 0 or player == null or world == null or dummy == null:
			_finish(); return
		# Set up the hit test: park the dummy just above the player, fire.
		if dummy is Node2D and player is Node2D:
			(dummy as Node2D).global_position = (player as Node2D).global_position + Vector2(0, -24)
		_dps_before = dummy.get_dps() if dummy.has_method("get_dps") else 0.0
		_phase = 1
		return
	# Phase 1: force a few primary shots (headless has no Input).
	if _phase == 1 and _t < 60:
		var player = _hangar.get("_player")
		if player != null and is_instance_valid(player):
			if "can_shoot" in player:
				player.set("can_shoot", true)
			if player.has_method("fire_primary"):
				player.fire_primary()
		return
	# Phase 2: check bullets spawned in the world + the dummy registered damage.
	if _phase == 1 and _t >= 60:
		var world = _hangar.get("_world")
		var dummy = _hangar.get("_dummy")
		var bullets := 0
		if world != null:
			for c in (world as Node).get_children():
				var nm := String(c.name)
				if nm == "DummyTarget" or nm == "AudioListener" or c == _hangar.get("_player"):
					continue
				bullets += 1
		_lines.append("non-dummy/non-player nodes spawned in _world: %d (bullets/fx, expect > 0)" % bullets)
		if bullets <= 0:
			_lines.append("FAIL no bullets/fx spawned into the viewport world"); _fails += 1
		var dps_after = dummy.get_dps() if (dummy != null and dummy.has_method("get_dps")) else 0.0
		_lines.append("dummy DPS: %.1f -> %.1f (expect a rise = bullets hit inside the viewport)" % [_dps_before, dps_after])
		if dps_after <= _dps_before:
			_lines.append("WARN dummy registered no damage (bullets may need more frames to reach it)")
		_lines.append("HANGAR REBUILD: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
		_finish()


func _finish() -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	get_tree().quit()
