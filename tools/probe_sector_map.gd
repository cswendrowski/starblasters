extends SceneTree

# Reproduce Cody's "returning to sector map regenerates / progression
# impossible" report. Loads sector_map_v2 with a current_node_id set
# (mimicking the post-combat return), then dumps the node graph + edges
# so we can see if progression is actually broken.

const SECTOR_MAP := "res://scenes/sector_map_v2.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Force a deterministic seed so the report is reproducible.
	if root.has_node("/root/Run"):
		root.get_node("/root/Run").run_seed = 12345
		root.get_node("/root/Run").current_node_id = ""

	# Pass 1 — fresh map. Print start node + its edges.
	print("\n=== PASS 1: fresh load ===")
	var ps: PackedScene = load(SECTOR_MAP)
	var map: Node = ps.instantiate()
	root.add_child(map)
	await create_timer(0.6).timeout
	_dump_state(map)

	# Pass 1b — reload immediately, no state change between. Should be
	# IDENTICAL to pass 1 if generation is deterministic on run_seed alone.
	map.queue_free()
	await create_timer(0.2).timeout
	print("\n=== PASS 1b: reload, no state change ===")
	var map1b: Node = ps.instantiate()
	root.add_child(map1b)
	await create_timer(0.6).timeout
	_dump_state(map1b)
	map1b.queue_free()
	await create_timer(0.2).timeout

	# Re-add pass 1 for the post-combat sim.
	map = ps.instantiate()
	root.add_child(map)
	await create_timer(0.6).timeout

	# Simulate combat node click on one of start's reachable neighbors.
	var target_id: String = ""
	if "nodes_by_id" in map and "current_id" in map:
		var cur = map.nodes_by_id.get(map.current_id, null)
		if cur and cur.edges_to.size() > 0:
			target_id = cur.edges_to[0]
	print("simulating mark_node_visited(", target_id, ")")
	if root.has_node("/root/Run") and target_id != "":
		var run = root.get_node("/root/Run")
		if not run.visited_nodes.has(target_id):
			run.visited_nodes.append(target_id)
		run.current_node_id = target_id

	map.queue_free()
	await create_timer(0.2).timeout

	# Pass 2 — reload after "combat".
	print("\n=== PASS 2: post-combat reload ===")
	var map2: Node = ps.instantiate()
	root.add_child(map2)
	await create_timer(0.6).timeout
	_dump_state(map2)
	map2.queue_free()

	print("\n[probe] done")
	quit()


func _dump_state(map: Node) -> void:
	if not "nodes_by_id" in map:
		print("  no nodes_by_id field")
		return
	if root.has_node("/root/Run"):
		print("  Run.run_seed = ", root.get_node("/root/Run").run_seed)
	print("  current_id = ", map.current_id if "current_id" in map else "?")
	print("  total nodes = ", map.nodes_by_id.size())
	var cur_id: String = map.current_id if "current_id" in map else ""
	if cur_id != "" and map.nodes_by_id.has(cur_id):
		var cur = map.nodes_by_id[cur_id]
		print("  current node edges_to = ", cur.edges_to)
		# Reachable count
		var reachable_count: int = 0
		for n in map.nodes:
			if n.id != cur_id and cur.edges_to.has(n.id):
				reachable_count += 1
		print("  reachable nodes = ", reachable_count)
	# Are all nodes reachable from start via BFS?
	if map.nodes_by_id.has("start"):
		var bfs := []
		var visited := {}
		bfs.append("start")
		visited["start"] = true
		while bfs.size() > 0:
			var cid: String = bfs.pop_front()
			var c = map.nodes_by_id[cid]
			for eid in c.edges_to:
				if not visited.has(eid):
					visited[eid] = true
					bfs.append(eid)
		print("  reachable-from-start total = ", visited.size(), " / ", map.nodes_by_id.size())
