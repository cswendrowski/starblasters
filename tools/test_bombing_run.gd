extends SceneTree

# Driven test for seq_bombing_run.gd. Builds a minimal world + target + player stubs, pumps the
# sequence deterministically, and asserts telegraph placement, detonation order, AoE damage, the
# shadow, and clean finish. Run: godot --headless -s tools/test_bombing_run.gd
#
# root.add_child only works once the tree is up, so the body is deferred out of _initialize and
# awaits real frames so deferred queue_free()s actually run before the leak check.

const Seq = preload("res://scripts/effects/sequences/seq_bombing_run.gd")
const DT := 0.05
const MAX_TICKS := 500


class PlayerStub extends Node2D:
	var hits: int = 0
	func take_damage(d: int) -> void:
		hits += d


func _initialize() -> void:
	_run.call_deferred()


func _make_target(world: Node2D) -> Node2D:
	var t := Node2D.new()
	t.position = Vector2(240.0, 90.0)
	var spr := Sprite2D.new()
	var ph := PlaceholderTexture2D.new()
	ph.size = Vector2(20, 20)
	spr.texture = ph
	t.add_child(spr)
	world.add_child(t)
	return t


func _telegraphs(world: Node2D) -> Array:
	var out: Array = []
	for c in world.get_children():
		if c is MissileSalvo.TelegraphCircle:
			out.append(c)
	return out


func _shadow_of(world: Node2D) -> Sprite2D:
	for c in world.get_children():
		if c is Sprite2D and absf(c.modulate.a - 0.40) < 0.01:
			return c
	return null


func _run_case(cname: String, pattern: int, direction: int, bpl: int,
		first_bomb: Vector2, last_bomb: Vector2, down: bool) -> bool:
	var world := Node2D.new()
	root.add_child(world)
	var target := _make_target(world)
	var spr: Sprite2D = target.get_child(0)

	var pa := PlayerStub.new(); pa.position = first_bomb; world.add_child(pa); pa.add_to_group("player")
	var pb := PlayerStub.new(); pb.position = last_bomb; world.add_child(pb); pb.add_to_group("player")
	await process_frame   # let the tree + groups register before play()

	var seq = Seq.new()
	world.add_child(seq)
	seq.set_process(false)   # pump manually for determinism
	var finished := [false]
	seq.finished.connect(func(): finished[0] = true)
	seq.play(target, spr, {
		"pattern": float(pattern), "direction": float(direction), "bombs_per_lane": float(bpl),
		"telegraph_time": 1.0, "shadow_speed": 120.0, "ascend_speed": 200.0,
		"aoe_radius": 12.0, "damage": 1.0, "return_mode": 0.0,
	})

	var ok := true
	# (a) telegraph count = lanes × rows, all at valid lane X's.
	var lanes_n: int = ([3, 3, 3, 4])[pattern]
	var teles := _telegraphs(world)
	if teles.size() != lanes_n * bpl:
		print("  FAIL telegraph count: got %d expected %d" % [teles.size(), lanes_n * bpl]); ok = false
	var valid_x := [150.0, 180.0, 210.0, 240.0, 270.0, 300.0, 330.0]
	for tl in teles:
		var matched := false
		for vx in valid_x:
			if absf(tl.global_position.x - vx) < 0.5:
				matched = true; break
		if not matched:
			print("  FAIL telegraph X off-lane: %s" % tl.global_position); ok = false; break

	# Pump; record the tick each player first took damage + watch the shadow move.
	var tick_a := -1
	var tick_b := -1
	var shadow_y0 := 0.0
	var shadow_moved_dir := 0
	var sh0 := _shadow_of(world)
	if sh0 == null:
		print("  FAIL no shadow spawned"); ok = false
	else:
		shadow_y0 = sh0.global_position.y
	for i in MAX_TICKS:
		seq._process(DT)
		var sh := _shadow_of(world)
		if sh != null:
			var dy := sh.global_position.y - shadow_y0
			if absf(dy) > 1.0:
				shadow_moved_dir = 1 if dy > 0.0 else -1
		if pa.hits > 0 and tick_a < 0:
			tick_a = i
		if pb.hits > 0 and tick_b < 0:
			tick_b = i
		if finished[0]:
			break
	await process_frame   # flush deferred queue_free()s from detonation + cleanup
	await process_frame

	# (b) both bomb positions damaged the overlapping player.
	if pa.hits <= 0 or pb.hits <= 0:
		print("  FAIL AoE damage: a=%d b=%d" % [pa.hits, pb.hits]); ok = false
	# (c) first-detonating row hit strictly before the last-detonating row.
	if tick_a < 0 or tick_b < 0 or tick_a >= tick_b:
		print("  FAIL detonation order: tick_a=%d tick_b=%d" % [tick_a, tick_b]); ok = false
	# (d) shadow moved in the sweep direction.
	var want_dir := 1 if down else -1
	if shadow_moved_dir != want_dir:
		print("  FAIL shadow direction: got %d want %d" % [shadow_moved_dir, want_dir]); ok = false
	# (e) finished + telegraphs cleaned up.
	if not finished[0]:
		print("  FAIL never finished"); ok = false
	if _telegraphs(world).size() != 0:
		print("  FAIL telegraphs leaked: %d" % _telegraphs(world).size()); ok = false
	# (f) re-enter put the target back at its hold position, visible.
	if is_instance_valid(target):
		if not target.visible or target.position.distance_to(Vector2(240.0, 90.0)) > 1.5:
			print("  FAIL re-enter pos/vis: vis=%s pos=%s" % [target.visible, target.position]); ok = false

	print(("  PASS " if ok else "  ---- ") + cname)
	world.queue_free()
	await process_frame
	return ok


func _run() -> void:
	var ok := true
	# pattern, direction(0=down), bombs_per_lane, first-detonating bomb, last-detonating bomb
	# rows for bpl=4: 48, 94.67, 141.33, 188 ; bpl=3: 48,118,188 ; bpl=2: 48,188
	ok = (await _run_case("left3 top-down",  0, 0, 4, Vector2(150.0, 48.0),  Vector2(150.0, 188.0), true)) and ok
	ok = (await _run_case("right3 bottom-up", 1, 1, 4, Vector2(330.0, 188.0), Vector2(330.0, 48.0),  false)) and ok
	ok = (await _run_case("middle3 top-down", 2, 0, 3, Vector2(240.0, 48.0),  Vector2(240.0, 188.0), true)) and ok
	ok = (await _run_case("every-other top-down", 3, 0, 2, Vector2(150.0, 48.0), Vector2(330.0, 188.0), true)) and ok
	print("VERDICT: %s" % ("PASS" if ok else "FAIL"))
	quit()
