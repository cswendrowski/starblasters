extends SceneTree

# M6a.2 component producer seam: WaveSpec.components_override flows through
# director._spawn_enemy onto the live enemy (which dupes + fires on_start). Mirrors the
# movement/shoot override path. Run: godot --headless --script res://tools/test_component_seam.gd

const RESULT := "res://tools/_component_seam_result.txt"
const WaveSpec := preload("res://scripts/levels/wave_def.gd")
const DirectorScript := preload("res://scripts/levels/director.gd")
const StraightDown := preload("res://scripts/enemies/patterns/straight_down.gd")
const Probe := preload("res://tools/test_component_probe.gd")

var _world = null
var _frame := 0
var _phase := 0
var _done := false


func _process(_dt: float) -> bool:
	if _done:
		return true
	_frame += 1
	if _phase == 0:
		_world = Node2D.new()
		root.add_child(_world)
		var dir = DirectorScript.new()
		_world.add_child(dir)
		var mv = StraightDown.new()
		mv.speed = 60.0
		var w = WaveSpec.new()
		w.enemy_scene = load("res://scenes/enemies/core/enemy_dart.tscn")
		w.count = 1
		w.movement_override = mv
		w.components_override = [Probe.new()]
		dir._spawn_enemy(w, 0)            # the materializer path
		_phase = 1
		return false
	if _frame < 6:
		return false
	var lines: Array = []
	var fails := 0
	var enemies = get_nodes_in_group("enemies")
	if enemies.is_empty():
		lines.append("FAIL no enemy spawned"); fails += 1
	else:
		var e = enemies[0]
		if not ("_components" in e) or e._components.is_empty():
			lines.append("FAIL components_override didn't reach the enemy"); fails += 1
		elif not e._components[0].started:
			lines.append("FAIL component on_start didn't fire via seam"); fails += 1
		else:
			lines.append("seam ok: component attached + on_start fired")
	lines.append("COMPONENT SEAM: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	_done = true
	quit()
	return true
