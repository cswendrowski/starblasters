extends Node

# Firecore regression repro (Roman 2026-06-10: "Firecores no longer move, and can't be killed").
# Boots combat, spawns a firecore hazard BOTH ways — directly, and through the real zealot
# faction-overlay EmitterComponent death path — then ticks and asserts each one drifts down and
# dies to take_hit. Run: godot --headless --path . tools/test_firecore_repro.tscn --quit-after 240

const RESULT := "res://tools/_firecore_repro_result.txt"
var _t := 0
var _main: Node = null
var _direct: Node = null
var _via_emitter: Node = null
var _y0_direct := 0.0
var _y0_emitter := 0.0
var _host: Node = null
var _phase := 0

func _ready() -> void:
	var run = get_node_or_null("/root/Run")
	if run != null:
		run.new_run()
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)

func _process(_dt: float) -> void:
	_t += 1
	if _phase == 0 and _t >= 8:
		# Direct spawn.
		_direct = load("res://scenes/enemies/factions/zealot/firecore_hazard.tscn").instantiate()
		_main.add_child(_direct)
		_direct.start(Vector2(200, 100))
		_y0_direct = _direct.position.y
		# Real path: a host enemy with the zealot faction overlay (chance forced to 1.0), killed.
		var Factions = load("res://scripts/levels/factions.gd")
		_host = load("res://scenes/enemies/core/enemy_bomb_drone.tscn").instantiate()
		var comps: Array = Factions.build_components(Factions.Id.ZEALOT)
		for c in comps:
			if "chance" in c:
				c.chance = 1.0   # force the drop
		_host.components = comps
		_main.add_child(_host)
		if _host is Node2D:
			(_host as Node2D).position = Vector2(280, 120)
		_phase = 1
		return
	if _phase == 1 and _t >= 12:
		_host.explode()   # death -> overlay emitter drops a firecore at the host position
		_phase = 2
		return
	if _phase == 2 and _t >= 16:
		# Find the emitter-dropped firecore (the one that isn't _direct).
		for n in get_tree().get_nodes_in_group("enemies"):
			if n != _direct and is_instance_valid(n) and String(n.scene_file_path).contains("firecore_hazard"):
				_via_emitter = n
				_y0_emitter = n.position.y
		_phase = 3
		return
	if _phase == 3 and _t >= 40:
		var lines: Array = []
		var fails := 0
		# --- movement ---
		if _direct == null or not is_instance_valid(_direct):
			lines.append("FAIL direct firecore vanished early"); fails += 1
		else:
			var dy: float = _direct.position.y - _y0_direct
			lines.append("direct: drifted %.1f px (expect > 0)" % dy)
			if dy <= 0.5:
				lines.append("FAIL direct firecore not moving"); fails += 1
		if _via_emitter == null:
			lines.append("FAIL no firecore spawned via the zealot overlay emitter"); fails += 1
		elif is_instance_valid(_via_emitter):
			var dy2: float = _via_emitter.position.y - _y0_emitter
			lines.append("via-emitter: drifted %.1f px (expect > 0), parent=%s" % [dy2, _via_emitter.get_parent().name])
			if dy2 <= 0.5:
				lines.append("FAIL emitter-spawned firecore not moving"); fails += 1
		# --- killability ---
		if _direct != null and is_instance_valid(_direct):
			var killed = _direct.take_hit(99)
			lines.append("direct take_hit(99) -> %s  _dying=%s" % [str(killed), str(_direct.get("_dying"))])
			if _direct.get("_dying") != true:
				lines.append("FAIL direct firecore can't be killed"); fails += 1
		if _via_emitter != null and is_instance_valid(_via_emitter):
			_via_emitter.take_hit(99)
			lines.append("via-emitter take_hit(99) -> _dying=%s" % str(_via_emitter.get("_dying")))
			if _via_emitter.get("_dying") != true:
				lines.append("FAIL emitter-spawned firecore can't be killed"); fails += 1
		lines.append("FIRECORE REPRO: " + ("PASS (no repro)" if fails == 0 else "REPRODUCED (%d failures)" % fails))
		var f := FileAccess.open(RESULT, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(PackedStringArray(lines)))
			f.close()
		get_tree().quit()
