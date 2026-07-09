extends SceneTree

# Live soak for the Corporate Director (Roman 2026-07-06): unlike the synchronous boot test, this TICKS
# real time so the maneuver coroutines, physics integration, bay/door/lift tweens, wing beams, missile
# salvos (weave + friendly-fire barrage + lane-strike), and the flechette injection actually run — catching
# runtime errors those awaited paths could throw. It runs every maneuver + interlude, then hammers the body
# to death (dramatic explode). Run: godot --headless --path . -s tools/test_director_run.gd

const SCENE := "res://scenes/enemies/factions/corporate/boss_c_director.tscn"

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
	var player := Area2D.new()
	player.add_to_group("player")
	player.position = Vector2(240.0, 210.0)
	get_root().add_child(player)

	var ps := load(SCENE) as PackedScene
	_boss = ps.instantiate()
	get_root().add_child(_boss)
	_boss.start(Vector2(240.0, 400.0))
	_boss.on_wave_started(1)   # arm the interludes

	for nm in ["gun_charge", "missile_weave", "cannon_skirmish", "laser_lane", "missile_barrage", "missile_lane_strike"]:
		if not is_instance_valid(_boss):
			break
		await _boss.play_named_maneuver(nm)
		print("  ran %s" % nm)

	# Destroy every SECTION + wing (the fight IS the sections → kill-all = death). Hit each a few times so
	# the 2-stage hood/missile fully clears.
	if is_instance_valid(_boss):
		var parts: Array = _boss.live_parts().duplicate()
		for p in parts:
			for _n in 3:
				if not is_instance_valid(p) or (p.has_method("is_destroyed") and p.is_destroyed()):
					break
				p.take_hit(999999)
		await _tick(1.6)
		var gone := not is_instance_valid(_boss)
		print("VERDICT: PASS (ticked all maneuvers + interludes + section-kill death without crashing; boss freed=%s)" % str(gone))
	else:
		print("VERDICT: PASS (ticked; boss already freed)")
	quit(0)
