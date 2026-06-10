extends Node

# EM Burst (Roman 2026-06-10) — the EM Torpedo's detonation. A blue-yellow electrical discharge that
# arcs to multiple enemies in a radius:
#   - Strips AND ignores enemy shields (the discharge doesn't care about charge shields).
#   - Chain-detonates enemy ordnance (rockets/missiles) caught in the blast.
#   - Alternate KILL effect: a killed enemy has a 25% chance of a normal explosion and a 75% chance
#     of going inert and drifting into the wreck layer. That split lives in enemy_base.explode()
#     (gated on the "death_style"="wreck" meta this burst sets on lethal hits) so it works for any
#     enemy type and degrades gracefully when no wreck layer exists.
#
# Static entry: EmBurstFx.detonate(tree, world_pos, radius, damage, max_targets, fx_parent).

const ARC_COLOR_CORE := Color(0.85, 0.95, 1.0, 1.0)   # near-white blue core
const ARC_COLOR_BLUE := Color(0.30, 0.55, 1.0, 1.0)
const ARC_COLOR_GOLD := Color(1.0, 0.85, 0.25, 1.0)


# Damage + visual. `fx_parent` is the node the visual parents under (the torpedo's fx container, =
# the combat scene), so the bolts share world coordinates with the enemies.
static func detonate(tree: SceneTree, world_pos: Vector2, radius: float, damage: int, max_targets: int, fx_parent: Node) -> void:
	if tree == null:
		return
	# Gather in-radius enemies, nearest first.
	var hits: Array = []
	for e in tree.get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var d: float = (e as Node2D).global_position.distance_to(world_pos)
		if d > radius:
			continue
		hits.append({"node": e, "dist": d})
	hits.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))

	var struck_positions: Array = []
	var applied: int = 0
	for h in hits:
		if applied >= max_targets:
			break
		var e = h["node"]
		if not is_instance_valid(e):
			continue
		struck_positions.append((e as Node2D).global_position)
		applied += 1
		# Enemy ordnance (rockets/missiles) in the blast detonate. They carry target_group=="player"
		# and live in the "enemies" group; our own torpedo is target_group=="enemies" and NOT in the
		# group, so it's never caught here.
		if "target_group" in e and String(e.get("target_group")) == "player" and e.has_method("explode"):
			e.explode()
			continue
		# Regular enemy: strip shields, then deal damage that bypasses them. Tag lethal hits so the
		# death routes to the wreck-drift presentation.
		if e.has_method("break_shields"):
			e.break_shields()
		if "health" in e and int(e.get("health")) <= damage and e.has_method("set_meta"):
			e.set_meta("death_style", "wreck")
		if e.has_method("take_hit"):
			e.take_hit(damage)

	# Visual: central flash + an arc to each struck enemy. Parent above the backdrop-free combat
	# space so bolts read over the action.
	var parent: Node = fx_parent if (fx_parent != null and is_instance_valid(fx_parent)) else tree.current_scene
	if parent == null:
		parent = tree.root
	var vis := EmBurstVisual.new()
	vis.setup(world_pos, struck_positions, radius)
	parent.add_child(vis)


# ----------------------------------------------------------------------------------------------
# Visual: a short-lived Node2D that draws jagged blue-yellow lightning arcs from the burst center
# to each struck enemy plus a central flash, then fades and frees itself.
class EmBurstVisual extends Node2D:
	var _center: Vector2
	var _targets: Array = []
	var _radius: float = 70.0
	var _life: float = 0.0
	const DURATION := 0.32
	const SEGMENTS := 7
	const JAGGED := 8.0

	func setup(center: Vector2, targets: Array, radius: float) -> void:
		_center = center
		_targets = targets
		_radius = radius
		global_position = Vector2.ZERO   # draw in world coords directly
		z_index = 4

	func _process(delta: float) -> void:
		_life += delta
		queue_redraw()
		if _life >= DURATION:
			queue_free()

	func _draw() -> void:
		var t: float = clampf(_life / DURATION, 0.0, 1.0)
		var fade: float = 1.0 - t
		# Central flash: layered discs, blue out to gold, shrinking bright core.
		var flash_r: float = lerpf(_radius * 0.5, _radius * 0.95, t)
		draw_circle(_center, flash_r, Color(ARC_COLOR_BLUE.r, ARC_COLOR_BLUE.g, ARC_COLOR_BLUE.b, 0.12 * fade))
		draw_circle(_center, flash_r * 0.55, Color(ARC_COLOR_GOLD.r, ARC_COLOR_GOLD.g, ARC_COLOR_GOLD.b, 0.18 * fade))
		draw_circle(_center, lerpf(10.0, 2.0, t), Color(ARC_COLOR_CORE.r, ARC_COLOR_CORE.g, ARC_COLOR_CORE.b, 0.9 * fade))
		# Arcs to each struck enemy.
		for i in _targets.size():
			var tp: Vector2 = _targets[i]
			_draw_bolt(_center, tp, i, fade)

	func _draw_bolt(from: Vector2, to: Vector2, idx: int, fade: float) -> void:
		var pts: PackedVector2Array = PackedVector2Array()
		pts.append(from)
		var dir: Vector2 = to - from
		var perp: Vector2 = Vector2(-dir.y, dir.x).normalized()
		for s in range(1, SEGMENTS):
			var f: float = float(s) / float(SEGMENTS)
			# Deterministic jag (no per-frame random so the bolt doesn't strobe wildly): a couple of
			# sines offset by segment + bolt index + time-phase for a little liveliness.
			var phase: float = float(idx) * 1.7 + _life * 30.0
			var jag: float = sin(f * 9.0 + phase) * JAGGED + sin(f * 23.0 + phase * 1.3) * (JAGGED * 0.4)
			jag *= (1.0 - f)   # taper to a clean hit at the target
			pts.append(from + dir * f + perp * jag)
		pts.append(to)
		# Blue body + gold-white core overlay.
		draw_polyline(pts, Color(ARC_COLOR_BLUE.r, ARC_COLOR_BLUE.g, ARC_COLOR_BLUE.b, 0.85 * fade), 2.4, true)
		draw_polyline(pts, Color(ARC_COLOR_CORE.r, ARC_COLOR_CORE.g, ARC_COLOR_CORE.b, 0.9 * fade), 1.0, true)
		# A small gold spark at the strike point.
		draw_circle(to, 3.0 * fade + 1.0, Color(ARC_COLOR_GOLD.r, ARC_COLOR_GOLD.g, ARC_COLOR_GOLD.b, 0.8 * fade))
