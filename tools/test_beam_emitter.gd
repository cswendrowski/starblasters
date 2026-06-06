extends SceneTree

# M6a.2 step 4: BeamEmitter node. Verifies the FSM (idle->windup->firing->cooldown),
# that damage ONLY lands during FIRING (fairness contract), LOCAL_FORWARD + LOCKED
# aim hit the target, and pierce=false truncates at the nearest target. Run:
#   godot --headless --script res://tools/test_beam_emitter.gd

const RESULT := "res://tools/_beam_emitter_result.txt"
const BeamEmitter := preload("res://scripts/enemies/beam_emitter.gd")
const TargetScript := preload("res://tools/_beam_target.gd")

const DT := 1.0 / 60.0
var _lines: Array = []
var _fails := 0
var _done := false


func _fail(m: String) -> void:
	_lines.append("FAIL " + m); _fails += 1


func _target(pos: Vector2) -> Node2D:
	var n := Node2D.new()
	n.set_script(TargetScript)
	n.position = pos
	root.add_child(n)
	n.add_to_group("player")
	return n


func _emitter(host_pos: Vector2, cfg: Dictionary) -> Node:
	var host := Node2D.new()
	host.position = host_pos
	root.add_child(host)
	var e = BeamEmitter.new()
	e.configure(cfg)
	host.add_child(e)        # _ready -> begin() (autostart)
	return e


func _free_group() -> void:
	for n in root.get_tree().get_nodes_in_group("player"):
		n.free()


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true

	# --- FSM + damage-only-during-FIRING + LOCAL_FORWARD aim ---
	var tgt := _target(Vector2(240, 120))   # directly below the host, in the beam
	var e = _emitter(Vector2(240, 40), {
		"idle_time": 0.1, "windup_time": 0.1, "firing_time": 0.3, "cooldown_time": 0.1,
		"cycle": BeamEmitter.Cycle.LOOP_IDLE, "aim_mode": BeamEmitter.AimMode.LOCAL_FORWARD,
		"forward_local": Vector2(0, 1), "reach": 200.0, "dps": 20.0, "hit_radius": 8.0,
		"emitter_offset": Vector2.ZERO, "target_group": "player",
	})
	var saw_firing := false
	var hits_before_firing := 0
	var phases: Array = []
	for i in 36:   # 0.6s
		e._process(DT)
		if e._phase == BeamEmitter.Phase.FIRING:
			saw_firing = true
		elif not saw_firing:
			hits_before_firing = tgt.hits   # still pre-firing
		phases.append(e._phase)
	if not saw_firing:
		_fail("never reached FIRING")
	if hits_before_firing != 0:
		_fail("took damage before FIRING (%d) — fairness contract broken" % hits_before_firing)
	if tgt.hits <= 0:
		_fail("LOCAL_FORWARD beam dealt no damage during firing")
	_free_group(); e.get_parent().free()

	# --- LOCKED aim: snapshots toward an off-axis target at windup ---
	var tgt2 := _target(Vector2(330, 120))   # down-right of the host
	var e2 = _emitter(Vector2(240, 40), {
		"idle_time": 0.05, "windup_time": 0.1, "firing_time": 0.3, "cooldown_time": 0.1,
		"aim_mode": BeamEmitter.AimMode.LOCKED, "reach": 300.0, "dps": 20.0, "hit_radius": 10.0,
		"emitter_offset": Vector2.ZERO, "target_group": "player",
	})
	for i in 30:
		e2._process(DT)
	if tgt2.hits <= 0:
		_fail("LOCKED aim did not hit the off-axis target (aim snapshot failed)")
	_free_group(); e2.get_parent().free()

	# --- pierce=false truncates at the nearest target ---
	var near := _target(Vector2(240, 90))
	var far := _target(Vector2(240, 160))
	var e3 = _emitter(Vector2(240, 40), {
		"idle_time": 0.05, "windup_time": 0.05, "firing_time": 0.4, "cooldown_time": 0.1,
		"aim_mode": BeamEmitter.AimMode.LOCAL_FORWARD, "forward_local": Vector2(0, 1),
		"reach": 300.0, "dps": 30.0, "hit_radius": 8.0, "pierce": false,
		"emitter_offset": Vector2.ZERO, "target_group": "player",
	})
	for i in 36:
		e3._process(DT)
	if near.hits <= 0:
		_fail("pierce=false: nearest target took no damage")
	if far.hits != 0:
		_fail("pierce=false: far target took damage (%d) — beam should truncate at nearest" % far.hits)
	_free_group(); e3.get_parent().free()

	_lines.append("BEAM EMITTER: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	quit()
	return true
