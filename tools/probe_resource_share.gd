extends SceneTree

const SectorNode = preload("res://scripts/sector_node.gd")

func _initialize() -> void:
	var a = SectorNode.new()
	var b = SectorNode.new()
	print("a.edges_to is b.edges_to? ", a.edges_to == b.edges_to, " (id-match: ", a.edges_to.get_typed_class_name(), ")")
	a.edges_to.append("FROM_A")
	print("after a.append: a=", a.edges_to, " b=", b.edges_to)
	quit()
