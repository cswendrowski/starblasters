extends SceneTree

# Director boss-gate logic (Roman 2026-07-01): the opt-in discrete-wave gate that the battleship uses.
# Confirms the DRAIN correctly ignores the boss + its parts + hazards (so a maneuver plays over an empty
# field, not blocked by the boss itself), and the gate helpers (_boss_gate_alive / _boss_defeated) track
# a stub boss. The full wave→maneuver→wave ordering is exercised live in-game; here we prove the tricky
# exclusion logic in isolation. Run: godot --headless --path . -s tools/test_battleship_gate.gd

const DirectorScript = preload("res://scripts/levels/director.gd")

var _fails: int = 0


class FakeBoss extends Node2D:
	var defeated: bool = false
	var maneuvers: int = 0
	var waves_seen: Array = []
	var retreated: bool = false
	func is_defeated() -> bool: return defeated
	func play_wave_maneuver(_idx: int = 0) -> void: maneuvers += 1
	func on_wave_started(idx: int) -> void: waves_seen.append(idx)
	func retreat() -> void: retreated = true

class FakeHazard extends Node2D:
	var is_hazard: bool = true


func _init() -> void:
	process_frame.connect(_run, ConnectFlags.CONNECT_ONE_SHOT)


func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  ok: %s" % msg)
	else:
		_fails += 1
		print("  FAIL: %s" % msg)


func _run() -> void:
	var d = DirectorScript.new()
	get_root().add_child(d)

	var boss := FakeBoss.new()
	boss.add_to_group("enemies")
	get_root().add_child(boss)
	d.boss_gate = boss

	# The boss itself is in "enemies" but must NOT count as a wave combatant.
	_ck(not d._wave_combatants_present(), "the boss alone does not block the drain")

	# A boss PART (child of the boss, also in "enemies") is excluded as a descendant.
	var part := Node2D.new()
	part.add_to_group("enemies")
	boss.add_child(part)
	_ck(not d._wave_combatants_present(), "a boss part (descendant) does not block the drain")

	# A HAZARD (dropped firecore etc.) never gates wave progression.
	var hazard := FakeHazard.new()
	hazard.add_to_group("enemies")
	get_root().add_child(hazard)
	_ck(not d._wave_combatants_present(), "a hazard does not block the drain")

	# A real wave enemy DOES block the drain.
	var foe := Node2D.new()
	foe.add_to_group("enemies")
	get_root().add_child(foe)
	_ck(d._wave_combatants_present(), "a real wave enemy blocks the drain")

	# _drain_for_gate returns immediately when only the boss/part/hazard remain.
	foe.free()
	d._running = true
	await d._drain_for_gate()
	_ck(true, "_drain_for_gate returns once the wave has cleared (no hang)")

	# Gate helpers track the stub boss.
	_ck(d._boss_gate_alive(), "boss_gate reported alive")
	_ck(not d._boss_defeated(), "boss not defeated initially")
	boss.defeated = true
	_ck(d._boss_defeated(), "a defeated boss stops the gate from driving it")

	# With no boss_gate set, the gate is inert (normal levels).
	var d2 = DirectorScript.new()
	get_root().add_child(d2)
	_ck(not d2._boss_gate_alive(), "no boss_gate → gate inert (normal levels untouched)")

	print("VERDICT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
