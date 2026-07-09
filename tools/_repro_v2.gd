extends SceneTree
const SCENE := "res://scenes/enemies/factions/corporate/boss_c_director.tscn"
func _init() -> void: process_frame.connect(_run, ConnectFlags.CONNECT_ONE_SHOT)
func _run() -> void:
	var mus = get_root().get_node_or_null("Music"); if mus != null: mus.free()
	var world := Node2D.new(); world.add_to_group("bullet_world"); get_root().add_child(world)
	var player := Area2D.new(); player.add_to_group("player"); player.position = Vector2(240, 210); get_root().add_child(player)
	var ps := load(SCENE) as PackedScene
	var boss = ps.instantiate(); get_root().add_child(boss); boss.start(Vector2(240, 400))
	# skirmish ordered x-trajectory
	var co = boss.play_named_maneuver("cannon_skirmish")
	var xs := []
	while boss._busy:
		await create_timer(0.25).timeout
		if not is_instance_valid(boss): break
		xs.append(int(round(boss.position.x)))
	print("SKIRMISH x over time: ", xs)
	# barrage: await 3 passes, print _barrage_passes each
	for p in 3:
		await boss.play_named_maneuver("missile_barrage")
		print("BARRAGE after pass %d: _barrage_passes=%d" % [p + 1, boss._barrage_passes])
	quit(0)
