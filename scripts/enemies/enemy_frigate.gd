extends "res://scripts/enemy_core.gd"

# Frigate — tough burst-gunner workhorse. Movement is driven by the
# `slow_advance` pattern Resource (assigned by the wave generator): a slow
# descent to hold_y, then station-keep with a gentle sine drift in X.
#
# This bespoke script adds ONLY mutual separation so multiple frigates don't
# clump/overlap into a single bullet-stack (Roman playtest, 2026-05-29).
#
# Why the push is re-applied every frame instead of nudged once:
# enemy_core._process does `position += compute_step(...)`, and slow_advance
# returns `target_x - position.x` for the X component — i.e. it SNAPS X to its
# drift target each frame. A one-shot nudge applied after super._process is
# erased on the next tick. So we recompute the separation push fresh every
# frame and re-add it after super, producing a stable steady-state offset
# proportional to how crowded the frigate is. X-only: hold-Y is the whole
# point of the formation, and a persistent Y push (Y step is 0 once holding)
# would slowly drag frigates off their band.

const SEPARATION_RADIUS := 40.0   # px; start pushing apart inside this gap
const PUSH_STRENGTH      := 55.0  # px/sec lateral repulsion per crowded sibling
const SEP_MAX            := 30.0  # px; cap so the offset can't run away
const SEP_DECAY          := 18.0  # px/sec relax toward 0 when uncrowded
const SEP_SIDE_MARGIN    := 14.0  # mirror enemy_core._clamp_to_sides inset

# Persistent lateral separation offset. Lives in a member (not in `position`)
# because slow_advance SNAPS position.x to its drift target every frame —
# anything written straight into position.x is erased on the next tick. By
# keeping the offset here and re-adding the FULL value after super._process,
# the spacing survives the snap and accumulates until siblings clear the
# radius, then decays back to 0 when the frigate is alone.
var _sep_x: float = 0.0


func _process(delta: float) -> void:
	super._process(delta)
	# Only the pattern-driven path needs separation, and only while alive.
	if _pattern == null or _cycling or _dying:
		return
	var safe_delta: float = min(delta, 1.0 / 30.0)
	_separate_from_siblings(safe_delta)


# Accumulate an X-only repulsion offset from any other frigate within
# SEPARATION_RADIUS, then re-apply the full offset after super's position
# snap. Re-clamps to the playfield band so the push can't shove a frigate
# into the side gutter. Sibling counts are tiny (base_count 3), so the linear
# group scan is cheap.
func _separate_from_siblings(delta: float) -> void:
	var push_x: float = 0.0
	var my_script: Script = get_script()
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self:
			continue
		if not is_instance_valid(node):
			continue
		# Only repel other frigates — this is in-formation spacing, not a
		# general obstacle avoidance.
		if node.get_script() != my_script:
			continue
		var other: Node2D = node as Node2D
		if other == null:
			continue
		var dx: float = global_position.x - other.global_position.x
		var dy: float = global_position.y - other.global_position.y
		var dist: float = sqrt(dx * dx + dy * dy)
		if dist < SEPARATION_RADIUS and dist > 0.001:
			# Falloff: full strength when overlapping, zero at the radius edge.
			var falloff: float = 1.0 - (dist / SEPARATION_RADIUS)
			# Push along X (sign of the X separation; if perfectly stacked
			# vertically, nudge deterministically right so they still split).
			var dir: float = signf(dx) if absf(dx) > 0.001 else 1.0
			push_x += dir * falloff

	if push_x != 0.0:
		_sep_x += push_x * PUSH_STRENGTH * delta
		_sep_x = clampf(_sep_x, -SEP_MAX, SEP_MAX)
	else:
		# Relax back toward center when no longer crowded.
		_sep_x = move_toward(_sep_x, 0.0, SEP_DECAY * delta)

	if _sep_x == 0.0:
		return
	position.x += _sep_x
	# Keep inside the playfield band (mirrors enemy_core._clamp_to_sides).
	if position.x < Playfield.X_MIN + SEP_SIDE_MARGIN:
		position.x = Playfield.X_MIN + SEP_SIDE_MARGIN
	elif position.x > Playfield.X_MAX - SEP_SIDE_MARGIN:
		position.x = Playfield.X_MAX - SEP_SIDE_MARGIN
