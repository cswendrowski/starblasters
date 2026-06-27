extends Object

# Soft separation so same-group hazards COLLIDE but don't MERGE (Roman 2026-06-23). Each hazard, per
# frame, queries its group and accumulates a gentle spring-push away from any neighbour whose body
# overlaps. The push is proportional to the overlap depth (a soft spring, not a hard constraint), so
# bodies can still touch/bump — they just don't stack into one blob.
#
# O(n²) over the group, which is fine for the modest hazard counts (cap ~14, bursts ~24-36). Neighbours
# expose their radius via hazard_radius(); the caller applies the returned vector velocity-style
# (× stiffness × delta) so it's frame-rate independent. Preload-referenced, no class_name.

# Accumulated separation vector (px/s-ish, pre-stiffness) pushing `node` away from overlapping group
# members. `self_radius` is this body's radius; the per-pair push is half the overlap so two bodies
# share the correction. Capped at `max_mag` so a deep multi-body pileup can't fling anything.
static func resolve(node: Node2D, group: String, self_radius: float, max_mag: float = 60.0) -> Vector2:
	var push := Vector2.ZERO
	for other in node.get_tree().get_nodes_in_group(group):
		if other == node or not is_instance_valid(other) or not (other is Node2D):
			continue
		var o := other as Node2D
		var delta: Vector2 = node.global_position - o.global_position
		var d: float = delta.length()
		var other_r: float = o.hazard_radius() if o.has_method("hazard_radius") else self_radius
		var min_d: float = self_radius + other_r
		if d >= min_d:
			continue
		if d < 0.001:
			# Dead-centre overlap — derive a deterministic split from instance ids so the pair never
			# stays stuck on top of each other.
			delta = Vector2(float(int(node.get_instance_id()) % 7 - 3), float(int(o.get_instance_id()) % 5 - 2))
			if delta.length() < 0.001:
				delta = Vector2(1.0, 0.0)
			d = delta.length()
		push += delta.normalized() * ((min_d - d) * 0.5)
	if push.length() > max_mag:
		push = push.normalized() * max_mag
	return push
