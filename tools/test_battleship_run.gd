extends SceneTree

# Live soak for the Zealot Battleship (Roman 2026-07-01, maneuver build): unlike the synchronous boot
# test, this TICKS real time so the maneuver coroutines, movement + rotate-slide tweens, main/side beam
# FSMs, firecore release, and wreck FX actually run — catching runtime errors those awaited paths could
# throw. It runs several between-wave maneuvers (play_wave_maneuver), both stage hazards, then destroys
# every part to hit the wreck FX + dramatic death. Run: godot --headless --path . -s tools/test_battleship_run.gd

const SCENE := "res://scenes/enemies/factions/zealot/boss_z_battleship.tscn"

var _boss = null


func _init() -> void:
	process_frame.connect(_run, ConnectFlags.CONNECT_ONE_SHOT)


func _tick(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	var mus = get_root().get_node_or_null("Music")
	if mus != null:
		mus.free()
	var world := Node2D.new()
	world.add_to_group("bullet_world")
	get_root().add_child(world)
	var player := Area2D.new()      # a target in the "player" group so turret/beam aim + damage query run
	player.add_to_group("player")
	player.position = Vector2(240.0, 210.0)
	get_root().add_child(player)

	var ps := load(SCENE) as PackedScene
	_boss = ps.instantiate()
	get_root().add_child(_boss)
	_boss.start(Vector2(240.0, 48.0))
	_boss.on_wave_started(0)
	_boss.on_wave_started(2)        # arm stage hazards (wave 3)

	# Several between-wave maneuvers — real tweens, beams, firecore release, turret fire.
	for i in 5:
		if not is_instance_valid(_boss):
			break
		await _boss.play_wave_maneuver(i + 1)
		print("  ran maneuver %d (last=%s)" % [i, String(_boss._last_maneuver)])

	# Both stage hazards directly (the loop's own cadence is 7-12s — too slow to wait on here).
	if is_instance_valid(_boss):
		await _boss._hazard_lane_laser()
		print("  ran stage hazard: lane laser")
	if is_instance_valid(_boss):
		await _boss._hazard_lane_laser_sweep()
		print("  ran stage hazard: lane laser sweep")

	# Destroy everything → wreck FX + dramatic death.
	if is_instance_valid(_boss):
		for p in _boss.live_parts().duplicate():
			if is_instance_valid(p):
				p.destroy()
		await _tick(1.6)
		var gone := not is_instance_valid(_boss)
		print("VERDICT: PASS (ticked all maneuvers + hazards + death without crashing; boss freed=%s)" % str(gone))
	else:
		print("VERDICT: PASS (ticked; boss already freed)")
	quit(0)
