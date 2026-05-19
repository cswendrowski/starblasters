extends SceneTree

const Map = preload("res://scripts/sector_map_v2.gd")

func _initialize() -> void:
	# Cannot directly .new() a Control script. Instantiate the scene and
	# inspect 'nodes' identity.
	var ps: PackedScene = load("res://scenes/sector_map_v2.tscn")
	var a = ps.instantiate()
	var b = ps.instantiate()
	root.add_child(a)
	root.add_child(b)
	await create_timer(0.4).timeout
	print("a.nodes id=", a.nodes.hash(), " size=", a.nodes.size())
	print("b.nodes id=", b.nodes.hash(), " size=", b.nodes.size())
	# Compare lists — should differ if per-instance
	a.nodes.clear()
	a.nodes.append("APPENDED-TO-A")
	print("after a.append: a.size=", a.nodes.size(), " b.size=", b.nodes.size())
	quit()
