extends SceneTree

# Boot main.tscn, force-fire the player periodically, and log what's
# happening to bullets + enemies. Used to diagnose Cody's "bullets don't
# work, enemies massive" report.

const SCENE := "res://scenes/main.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps: PackedScene = load(SCENE)
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await create_timer(1.5).timeout

	# Find player.
	var player := _find_node_with_method(inst, "fire_primary")
	print("[probe] player=", player, " pos=", (player.global_position if player else "n/a"))
	if player:
		print("[probe] bullet_scene=", player.bullet_scene)
		print("[probe] bullet_damage=", player.bullet_damage, " can_shoot=", player.can_shoot)
		print("[probe] weapon_style=", player.weapon_style, " ammo=", player.ammo)

	# Force-fire 10 times.
	for i in 10:
		if player and player.has_method("fire_primary"):
			player.fire_primary()
		await create_timer(0.15).timeout
		var bullets := get_nodes_in_group("player_bullets")
		var alt_bullets := 0
		for n in root.get_children():
			if n.get_class() == "Area2D" and n != inst:
				alt_bullets += 1
		print("[probe] tick %d  group_bullets=%d  root_areas=%d  enemies=%d" % [
			i, bullets.size(), alt_bullets, get_nodes_in_group("enemies").size()
		])

	# Sample one enemy's scale + position if any present.
	var enemies := get_nodes_in_group("enemies")
	if enemies.size() > 0:
		var e: Node = enemies[0]
		print("[probe] enemy[0] class=", e.get_class(), " scale=", e.scale if "scale" in e else "n/a",
			" global_pos=", e.global_position if "global_position" in e else "n/a")

	inst.queue_free()
	quit()


func _find_node_with_method(n: Node, m: String) -> Node:
	if n.has_method(m):
		return n
	for c in n.get_children():
		var hit := _find_node_with_method(c, m)
		if hit:
			return hit
	return null
