extends SceneTree

# Driven test for the production bombing-run trigger on the bomber + wing. Spawns the real scenes,
# freezes auto-process, and drives the trigger methods directly so the wiring (external_control gate,
# sequence launch, TailGun pause, finish/resume) is checked deterministically. The sequence mechanics
# themselves are covered by tools/test_bombing_run.gd. Run: godot --headless -s tools/test_bombing_trigger.gd

const BOMBER := preload("res://scenes/enemies/core/enemy_core_bomber.tscn")
const WING := preload("res://scenes/enemies/factions/privateer/enemy_p_m_interceptor.tscn")


class PlayerStub extends Node2D:
	var hits: int = 0
	func take_damage(d: int) -> void:
		hits += d


func _initialize() -> void:
	_run.call_deferred()


func _freeze(n: Node) -> void:
	n.set_process(false)
	n.set_physics_process(false)


func _test_bomber() -> bool:
	var ok := true
	var world := Node2D.new(); root.add_child(world)
	var player := PlayerStub.new(); player.position = Vector2(240.0, 200.0)
	world.add_child(player); player.add_to_group("player")
	await process_frame

	var bomber = BOMBER.instantiate()
	bomber.bombing_run_enabled = true
	world.add_child(bomber)
	bomber.global_position = Vector2(240.0, 90.0)   # settled in the hold band
	await process_frame
	_freeze(bomber)                                  # drive the trigger by hand

	# enemy_core gate: with external_control set, _process must NOT move the enemy.
	bomber.external_control = true
	var held: Vector2 = bomber.global_position
	bomber._process(0.2)
	if bomber.global_position != held:
		print("  FAIL gate: moved under external_control %s->%s" % [held, bomber.global_position]); ok = false
	bomber.external_control = false

	# Trigger a run: a big delta drains the cooldown → launch.
	var tg = bomber.get_node_or_null("TailGun")
	bomber._bomb_cooldown = 0.0
	bomber._tick_bombing_run(1.0)
	if not bomber.external_control:
		print("  FAIL bomber: external_control not set after launch"); ok = false
	if bomber._bomb_seq == null or not is_instance_valid(bomber._bomb_seq):
		print("  FAIL bomber: no sequence launched"); ok = false
	if tg != null and tg.is_processing():
		print("  FAIL bomber: TailGun still processing during run"); ok = false

	# Simulate the sequence finishing → resume.
	var seq = bomber._bomb_seq
	bomber._end_bombing_run()
	if bomber.external_control:
		print("  FAIL bomber: external_control stuck after end"); ok = false
	if bomber._bomb_seq != null:
		print("  FAIL bomber: _bomb_seq not cleared"); ok = false
	if bomber._bomb_cooldown <= 0.0:
		print("  FAIL bomber: cooldown not re-armed"); ok = false
	if tg != null and not tg.is_processing():
		print("  FAIL bomber: TailGun not resumed"); ok = false
	if seq != null and is_instance_valid(seq):
		seq.queue_free()

	print(("  PASS " if ok else "  ---- ") + "bomber trigger")
	world.queue_free(); await process_frame
	return ok


func _test_wing() -> bool:
	var ok := true
	var world := Node2D.new(); root.add_child(world)
	var player := PlayerStub.new(); player.position = Vector2(240.0, 240.0)
	world.add_child(player); player.add_to_group("player")
	await process_frame

	# Default OFF: a vanilla wing must not start a run.
	var w0 = WING.instantiate()
	world.add_child(w0)
	w0.global_position = Vector2(240.0, 150.0)
	await process_frame
	_freeze(w0)
	w0._tick_bombing_run()
	if w0.external_control or w0._bomb_seq != null:
		print("  FAIL wing: ran while disabled"); ok = false

	# Enabled: in-band → launches once, exit mode.
	var w = WING.instantiate()
	w.bombing_run_enabled = true
	world.add_child(w)
	w.global_position = Vector2(240.0, 150.0)   # band_progress ~0.71 (>0.35)
	await process_frame
	_freeze(w)
	w._tick_bombing_run()
	if not w.external_control:
		print("  FAIL wing: external_control not set"); ok = false
	if w._bomb_seq == null or not is_instance_valid(w._bomb_seq):
		print("  FAIL wing: no sequence launched"); ok = false
	if not w._bomb_done:
		print("  FAIL wing: _bomb_done not latched"); ok = false
	# Latched: a second tick must not launch again.
	var seq = w._bomb_seq
	w._tick_bombing_run()
	if w._bomb_seq != seq:
		print("  FAIL wing: relaunched after latch"); ok = false
	# Finish → the wing leaves.
	w._on_bomb_done()
	await process_frame
	if is_instance_valid(w):
		print("  FAIL wing: not freed after run"); ok = false
	if seq != null and is_instance_valid(seq):
		seq.queue_free()

	print(("  PASS " if ok else "  ---- ") + "wing trigger")
	world.queue_free(); await process_frame
	return ok


func _run() -> void:
	var ok := true
	ok = (await _test_bomber()) and ok
	ok = (await _test_wing()) and ok
	print("VERDICT: %s" % ("PASS" if ok else "FAIL"))
	quit()
