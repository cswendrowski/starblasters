extends SceneTree

# Cannon Bay deploy-sequence check (Roman 2026-07-28) — scripts/enemies/core/cannon_bay.gd.
#
# Walks a live instance through CLOSED -> COVER -> RAISE -> READY and asserts the two gates open at
# the right moments: it must not be shootable while closed or while the doors run, must become
# shootable partway through the raise, and must not fire until the raise finishes. Also checks the
# scene's authored start pose is respected rather than overwritten, and that the per-shot hook is
# wired without exploding.
#
# Run: godot --path . --headless -s res://tools/test_cannon_bay.gd

const SCENE := "res://scenes/enemies/ground/b_t_cannon_bay.tscn"
const Roster = preload("res://scripts/levels/enemy_roster.gd")

var _fails: int = 0


func _ok(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		print("  FAIL  ", label)
		_fails += 1


func _init() -> void:
	print("=== cannon bay deploy ===")
	var ps := load(SCENE) as PackedScene
	if ps == null:
		print("  FAIL  scene does not load")
		_finish()
		return

	# --- authored start pose survives into the instance -------------------
	var probe := ps.instantiate()
	var cannon := probe.get_node_or_null("Cannon") as Node2D
	_ok(cannon != null, "scene has a Cannon group")
	if cannon != null:
		_ok(not cannon.visible, "Cannon starts hidden (authored)")
		_ok(cannon.position.y > 0.0, "Cannon starts offset (authored y=%.1f)" % cannon.position.y)
		_ok(cannon.scale.x < 1.0, "Cannon starts scaled down (authored %.2f)" % cannon.scale.x)
	var authored_scale: float = cannon.scale.x if cannon != null else -1.0
	for n in ["Cover", "Cannon/Tower/Barrel/Muzzle1", "Cannon/Tower/Barrel/FlareL",
			"Cannon/Tower/Barrel/FlareR", "Cannon/Tower/Barrel/Ejection"]:
		_ok(probe.get_node_or_null(n) != null, "scene has %s" % n)
	var cover := probe.get_node_or_null("Cover") as Sprite2D
	_ok(cover != null and cover.hframes == 7, "Cover is a 7-frame strip (hframes=%d)"
		% (cover.hframes if cover != null else -1))
	probe.free()

	# --- roster registration (weapon + HP come from here, not the scene) --
	var entry: Dictionary = Roster.entry_for_scene(SCENE)
	_ok(not entry.is_empty(), "registered in enemy_roster")
	if not entry.is_empty():
		var mounts: Array = entry.get("mounts", [])
		_ok(mounts.size() >= 1, "roster carries a mount (weapon)")
		var hp: int = int(Roster.compose_stats(entry).get("max_health", 0))
		_ok(hp > 1, "roster HP composes above 1 (got %d)" % hp)

	# --- live deploy walk -------------------------------------------------
	var bay := ps.instantiate()
	root.add_child(bay)
	await process_frame
	await process_frame

	_ok(not bay.take_hit(1), "CLOSED: not shootable")
	_ok(not bay._on_playfield(), "CLOSED: holds fire")
	if authored_scale > 0.0 and bay.get_node_or_null("Cannon") != null:
		var live_scale: float = (bay.get_node("Cannon") as Node2D).scale.x
		_ok(is_equal_approx(live_scale, authored_scale),
			"authored scale respected, not overwritten (%.2f)" % live_scale)

	# Mid-doors: the cover strip is stepping, still no damage.
	await _wait(bay.DEPLOY_START_DELAY + bay.COVER_FRAME_TIME * 3.0)
	_ok(not bay.take_hit(1), "COVER: not shootable while doors open")
	_ok(not bay._on_playfield(), "COVER: holds fire")

	# Past the halfway point of the raise: damage opens, firing still shut.
	var raise_total: float = bay.RAISE_GROW_TIME + bay.RAISE_SLIDE_TIME
	await _wait(bay.COVER_FRAME_TIME * 5.0 + raise_total * bay.RAISE_VULNERABLE_FRAC + 0.05)
	_ok(bay._vulnerable, "RAISE halfway: shootable")
	_ok(not bay._on_playfield(), "RAISE halfway: still holds fire")

	# Fully deployed.
	await _wait(raise_total)
	_ok(bay._phase == bay.Phase.READY, "reaches READY")
	var c2 := bay.get_node_or_null("Cannon") as Node2D
	if c2 != null:
		_ok(c2.visible, "READY: Cannon visible")
		_ok(is_equal_approx(c2.modulate.a, 1.0), "READY: faded in (a=%.2f)" % c2.modulate.a)
		_ok(is_equal_approx(c2.scale.x, 1.0), "READY: grew to 1.0 (%.2f)" % c2.scale.x)
		_ok(absf(c2.position.y) < 0.01, "READY: offset reduced to 0 (y=%.2f)" % c2.position.y)

	# Per-shot hook: must not error, and must leave the barrel back home after the recoil.
	var barrel := bay.get_node_or_null("Cannon/Tower/Barrel") as Node2D
	var home: Vector2 = barrel.position if barrel != null else Vector2.ZERO
	bay.on_mount_fired(Vector2.UP, barrel.global_position if barrel != null else Vector2.ZERO)
	await process_frame
	_ok(barrel != null and not barrel.position.is_equal_approx(home), "recoil kicks the barrel back")
	await _wait(bay.RECOIL_OUT_TIME + bay.RECOIL_IN_TIME + 0.1)
	_ok(barrel != null and barrel.position.is_equal_approx(home), "barrel slides home after recoil")

	bay.queue_free()
	_finish()


func _wait(seconds: float) -> void:
	await root.get_tree().create_timer(maxf(0.01, seconds), false).timeout


func _finish() -> void:
	print("VERDICT: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
