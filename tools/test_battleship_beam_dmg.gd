extends SceneTree

# Isolates the side-laser beam DAMAGE pipeline: a target in the "player" group with take_damage()
# is placed directly on the beam line; we activate the laser, tick past its windup into FIRING, and
# assert the target took damage. Confirms whether "beams deal no damage" is a pipeline bug or just
# geometry/hit-radius. Run: godot --headless --path . -s tools/test_battleship_beam_dmg.gd

const SIDELASER := "res://scenes/enemies/factions/zealot/boss_z_battleship_sidelaser.tscn"


class FakePlayer extends Area2D:
	var hits: int = 0
	func take_damage(d: int) -> void:
		hits += d


func _init() -> void:
	process_frame.connect(_run, ConnectFlags.CONNECT_ONE_SHOT)


func _tick(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	var mus = get_root().get_node_or_null("Music")
	if mus != null:
		mus.free()
	var laser = load(SIDELASER).instantiate()
	get_root().add_child(laser)
	laser.rotation = 0.0                       # side laser fires toward its "Beam" marker (-5,0) → -X (left)
	laser.position = Vector2(240.0, 40.0)
	var p := FakePlayer.new()
	p.add_to_group("player")
	p.position = Vector2(150.0, 40.0)          # squarely on the leftward beam line
	get_root().add_child(p)

	laser.set_active(true)                     # begin: idle(0.3) → windup(1.0) → FIRING(2.0)
	await _tick(3.0)
	print("player hits after 3s of an active side laser: %d" % p.hits)
	print("VERDICT: %s" % ("PASS" if p.hits > 0 else "FAIL (beam dealt no damage)"))
	quit(0 if p.hits > 0 else 1)
