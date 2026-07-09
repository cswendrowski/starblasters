extends Node

# Mount system attach test (Roman 2026-06-16). Run as a SCENE so autoloads load (enemy_core.start
# needs them): godot --path . --headless res://tools/test_mounts.tscn
# Builds one enemy carrying one of each MountSpec kind (via the production dict path
# EnemyRoster.make_mount_specs) and asserts MountBuilder realized each: a turret node under the
# Turret marker, a BeamEmitter child, and two MountComponents (gun + launcher) in _components.

const Roster = preload("res://scripts/levels/enemy_roster.gd")
const MountComponentC = preload("res://scripts/enemies/mounts/mount_component.gd")
const EnemyTurretScript = preload("res://scripts/enemies/enemy_turret.gd")
const BeamEmitterC = preload("res://scripts/enemies/beam_emitter.gd")
const ENEMY := "res://scenes/enemies/factions/zealot/enemy_z_s_manta.tscn"   # a generic enemy_core


func _ready() -> void:
	var inst := (load(ENEMY) as PackedScene).instantiate()
	for nm in ["Turret1", "Muzzle1", "Launch1", "Beam1"]:
		var mk := Marker2D.new()
		mk.name = nm
		inst.add_child(mk)
	inst.mounts = Roster.make_mount_specs([
		{"kind": "turret", "marker": "Turret*", "payload": Roster.BV_Basic},
		{"kind": "gun", "marker": "Muzzle*", "payload": Roster.BV_Basic, "aim": "straight_down"},
		{"kind": "launcher", "marker": "Launch*", "payload_scene": "res://scenes/projectiles/projectile_ball.tscn"},
		{"kind": "beam", "marker": "Beam1", "beam_config": {"reach": 120.0, "dps": 2.0}},
	])
	add_child(inst)
	if inst.has_method("start"):
		inst.start(Vector2(240, 60))
	await get_tree().process_frame
	await get_tree().process_frame

	var turrets := _find(inst, EnemyTurretScript)
	var beams := _find(inst, BeamEmitterC)
	var mount_comps: int = 0
	for c in inst._components:
		if c.get_script() == MountComponentC:
			mount_comps += 1
	var tm := inst.get_node_or_null("Turret1")
	var turret_under_marker: bool = tm != null and _find(tm, EnemyTurretScript).size() == 1

	print(">> turret nodes: ", turrets.size(), " (expect 1)")
	print(">> turret under Turret1 marker: ", turret_under_marker, " (expect true)")
	print(">> beam nodes: ", beams.size(), " (expect 1)")
	print(">> mount components (gun+launcher): ", mount_comps, " (expect 2)")
	var ok: bool = turrets.size() == 1 and turret_under_marker and beams.size() == 1 and mount_comps == 2
	print(">> RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit()


func _find(node: Node, scr: Script) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c.get_script() == scr:
			out.append(c)
		out.append_array(_find(c, scr))
	return out
